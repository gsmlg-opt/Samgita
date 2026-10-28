defmodule SamgitaCodexDriver.NativeEnvironmentConnectionEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand(
            "../../../scripts/codex/ordinary_environment_connection_fixture.py",
            __DIR__
          )
  @script_sha "239f96ea487ae43eac710a9ddf40e7240abd462bcdc3cfb511552a48108d087c"
  @schema Path.expand(
            "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/ServerNotification.json",
            __DIR__
          )
  @schema_sha "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1"
  @environment "owned-environment-λ"
  @connected "thread/environment/connected"
  @disconnected "thread/environment/disconnected"
  @selected [@connected, @disconnected]

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    schema_bytes = File.read!(@schema)
    assert hash(schema_bytes) === @schema_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: python3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-environment-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)

    on_exit(fn ->
      if not File.exists?(Path.join(root, "journal.json")), do: File.rm_rf!(root)
    end)

    %{root: root, binary: Path.expand(binary), python: python, schema: JSON.decode!(schema_bytes)}
  end

  test "original connected and disconnected envelopes follow the selected native environment",
       ctx do
    {pid, connection} = start(ctx)
    [started] = entries(ctx, "native_started")
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert native === started["pid"]

    for process <- [started["pid"], started["executorPid"]] do
      assert hash(File.read!("/proc/#{process}/exe")) === @binary_sha
    end

    # This file supplies synthetic runtime connection setup only.
    setup = JSON.decode!(File.read!(Path.join(ctx.root, "connection-setup.json")))

    assert call(pid, "environment/add", %{
             "environmentId" => @environment,
             "execServerUrl" => setup["execServerUrl"],
             "authBearerToken" => setup["authBearerToken"],
             "connectTimeoutMs" => 15_000
           }) === %{}

    assert call(pid, "environment/status", %{"environmentId" => @environment}) === %{
             "status" => "pending"
           }

    await(fn -> length(entries(ctx, "proxy_held")) === 1 end, now() + 5_000)

    attached = thread(ctx, pid, [%{"environmentId" => @environment, "cwd" => executor_cwd(ctx)}])
    detached = thread(ctx, pid, [])
    refute attached === detached
    events = drain(pid)
    assert selected(events) === []
    assert entries(ctx, "original_notification") === []
    assert length(entries(ctx, "proxy_held")) === 1
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)

    connected_lower = System.system_time(:millisecond)
    release = control(ctx, 1, "release_executor_connection")
    events = collect(pid, events, @connected, now() + 10_000)
    connected_upper = System.system_time(:millisecond)

    assert [up] = selected(events)
    assert_envelope(ctx, up, @connected, attached, generation, connected_lower, connected_upper)
    info = call(pid, "environment/info", %{"environmentId" => @environment})
    assert Map.fetch!(info, "cwd") === "file://" <> executor_cwd(ctx)

    assert call(pid, "environment/status", %{"environmentId" => @environment}) === %{
             "status" => "ready"
           }

    disconnected_lower = System.system_time(:millisecond)
    stopped = control(ctx, 2, "stop_executor")
    events = collect(pid, events, @disconnected, now() + 10_000)
    disconnected_upper = System.system_time(:millisecond)
    assert [^up, down] = selected(events)

    assert_envelope(
      ctx,
      down,
      @disconnected,
      attached,
      generation,
      disconnected_lower,
      disconnected_upper
    )

    observations = disconnected_status(pid, [], now() + 5_000)
    assert Map.fetch!(List.last(observations), "status") === "disconnected"
    assert is_binary(List.last(observations)["error"])
    assert byte_size(List.last(observations)["error"]) > 0

    loaded = call(pid, "thread/loaded/list", %{})
    assert Enum.sort(Map.fetch!(loaded, "data")) === Enum.sort([attached, detached])
    assert Map.fetch!(loaded, "nextCursor") === nil

    for {id, environments} <- [
          {attached,
           [
             %{
               "environmentId" => @environment,
               "cwd" => executor_cwd(ctx),
               "runtimeWorkspaceRoots" => [executor_cwd(ctx)]
             }
           ]},
          {detached, []}
        ] do
      saved = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]
      assert Map.fetch!(saved, "id") === id
      assert Map.fetch!(saved, "turns") === []
      assert Map.fetch!(saved, "environments") === environments
    end

    events = events ++ drain(pid)
    assert selected(events) === [up, down]
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    originals = assert_originals(ctx, [up, down])
    [original_up, original_down] = originals

    assert original_up["monoNs"] >= started_control(ctx, release)["monoNs"]
    assert original_down["monoNs"] >= started_control(ctx, stopped)["monoNs"]
    assert original_up["captureId"] < original_down["captureId"]
    refute Enum.any?(selected(events), &(&1.wire["params"]["threadId"] == detached))
    assert_issued_inventory(ctx, length(observations))
    assert entries(ctx, "provider_request") === []
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@schema)) === @schema_sha

    _ = control(ctx, 3, "close")
    assert_closed(ctx)
    StdioSessionFixture.close(pid, connection)
    assert Port.info(connection.port) === nil
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert assert_originals(ctx, [up, down]) === originals
  end

  defp start(ctx) do
    for name <- ["home", "app", "tmp"] do
      File.mkdir_p!(Path.join(ctx.root, name))
    end

    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {SamgitaCodexDriver.Transport.Stdio,
                  [
                    executable: ctx.python,
                    args: ["-u", @script, "--root", ctx.root, "--codex", ctx.binary],
                    cwd: ctx.root,
                    inherit_env: [],
                    env: %{
                      "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                      "CODEX_HOME" => Path.join(ctx.root, "app"),
                      "HOME" => Path.join(ctx.root, "home"),
                      "TMPDIR" => Path.join(ctx.root, "tmp")
                    },
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      try do
        ensure_closed(ctx)
      after
        StdioSessionFixture.close(pid, connection)
      end

      assert_closed(ctx)
      assert Port.info(connection.port) === nil
      assert :atomics.get(connection.owner.completion, 1) === 1
      File.rm_rf!(ctx.root)
    end)

    await(fn -> length(entries(ctx, "native_started")) === 1 end, now() + 10_000)

    assert {:ok, %{"result" => _}} =
             Session.initialize(
               pid,
               %{"name" => "owned_environment_connection", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    {pid, connection}
  end

  defp thread(ctx, pid, environments) do
    response =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "ephemeral" => false,
        "environments" => environments
      })

    thread = Map.fetch!(response, "thread")
    id = Map.fetch!(thread, "id")
    assert is_binary(id) and id != ""
    assert Map.fetch!(thread, "turns") === []
    id
  end

  defp assert_envelope(ctx, event, method, thread, generation, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === generation

    assert event.wire === %{
             "method" => method,
             "params" => %{"threadId" => thread, "environmentId" => @environment},
             "emittedAtMs" => emitted
           }

    assert :ok = Schema.validate(ctx.schema, event.wire, max_depth: 32)
  end

  defp assert_originals(ctx, events) do
    originals = entries(ctx, "original_notification")
    assert Enum.map(originals, & &1["method"]) === @selected
    assert Enum.map(originals, &JSON.decode!(&1["encoded"])) === Enum.map(events, & &1.wire)

    for {original, event} <- Enum.zip(originals, events) do
      assert byte_size(original["encoded"]) <= 65_536
      assert {:ok, decoded} = Wire.decode(original["encoded"], max_depth: 32)
      assert decoded === event.wire
    end

    rows = journal(ctx)
    ids = Enum.map(rows, & &1["captureId"])
    assert ids === Enum.to_list(1..length(rows))
    assert Enum.map(rows, & &1["monoNs"]) === Enum.sort(Enum.map(rows, & &1["monoNs"]))
    assert length(rows) <= 160
    assert Enum.sum(Enum.map(originals, &byte_size(&1["encoded"]))) <= 524_288
    originals
  end

  defp assert_issued_inventory(ctx, disconnected_observations) do
    methods = Enum.map(entries(ctx, "native_input"), & &1["method"])

    assert Enum.all?(methods, fn method ->
             method in ~w(initialize initialized server/diagnostics environment/add
                          environment/status thread/start environment/info thread/loaded/list thread/read)
           end)

    assert Enum.count(methods, &(&1 == "initialize")) === 1
    assert Enum.count(methods, &(&1 == "initialized")) === 1
    assert Enum.count(methods, &(&1 == "environment/add")) === 1
    assert Enum.count(methods, &(&1 == "thread/start")) === 2
    assert Enum.count(methods, &(&1 == "environment/info")) === 1
    assert Enum.count(methods, &(&1 == "environment/status")) === 2 + disconnected_observations
    refute Enum.any?(methods, &(&1 == "turn/start"))
    assert Enum.count(methods, &(&1 == "thread/read")) === 2

    assert Enum.filter(entries(ctx, "native_output"), &(&1["method"] in @selected))
           |> Enum.map(& &1["method"]) === @selected
  end

  defp disconnected_status(pid, observations, deadline) do
    assert length(observations) < 16 and now() < deadline,
           "Native disconnected status observation bound"

    status = call(pid, "environment/status", %{"environmentId" => @environment})
    observations = observations ++ [status]

    if status["status"] == "disconnected" do
      observations
    else
      Process.sleep(20)
      disconnected_status(pid, observations, deadline)
    end
  end

  defp selected(events), do: Enum.filter(events, &(&1.wire["method"] in @selected))

  defp drain(pid) do
    assert {:ok, batch} = Session.drain(pid, 64)
    assert length(batch) <= 64
    assert Enum.sum(Enum.map(batch, &byte_size(JSON.encode!(&1.wire)))) <= 524_288
    batch
  end

  defp collect(pid, events, method, deadline) do
    events = events ++ drain(pid)
    assert length(events) <= 96
    assert length(selected(events)) <= 2

    if Enum.any?(events, &(&1.wire["method"] == method)) do
      events
    else
      assert now() < deadline, "Native environment notification deadline"
      Process.sleep(10)
      collect(pid, events, method, deadline)
    end
  end

  defp call(pid, method, params) do
    id = "owned-environment-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

    result
  end

  defp control(ctx, sequence, action) do
    identity = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    write_control(ctx, %{"id" => identity, "sequence" => sequence, "action" => action})

    await(
      fn -> Enum.find(entries(ctx, "control_completed"), &(&1["id"] == identity)) end,
      now() + 15_000
    )
  end

  defp write_control(ctx, control) do
    pending = Path.join(ctx.root, "control.pending")
    File.write!(pending, JSON.encode!(control))
    File.rename!(pending, Path.join(ctx.root, "control.json"))
  end

  defp started_control(ctx, completed) do
    [started] = Enum.filter(entries(ctx, "control_started"), &(&1["id"] == completed["id"]))
    started
  end

  defp ensure_closed(ctx) do
    if entries(ctx, "owner_closed") === [] do
      controls = entries(ctx, "control_started")

      unless Enum.any?(controls, &(&1["action"] == "close")) do
        request_close(ctx, controls)
      end

      await(fn -> entries(ctx, "owner_closed") !== [] end, now() + 15_000)
    end
  end

  defp request_close(ctx, controls) do
    next = if controls == [], do: 1, else: List.last(controls)["sequence"] + 1
    identity = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    write_control(ctx, %{"id" => identity, "sequence" => next, "action" => "close"})
  end

  defp assert_closed(ctx) do
    await(fn -> entries(ctx, "owner_closed") !== [] end, now() + 5_000)
    assert entries(ctx, "fixture_error") === []

    assert [%{"failed" => false}] =
             Enum.map(entries(ctx, "owner_closed"), &Map.take(&1, ["failed"]))

    assert [resources] = entries(ctx, "resources_closed")
    assert resources["childrenReaped"] === true
    assert resources["liveWorkers"] === 0
    assert resources["liveSockets"] === 0
    assert resources["providerRequests"] === 0
    assert entries(ctx, "provider_request") === []

    assert Enum.sort(Enum.map(entries(ctx, "owned_process_exit"), & &1["name"])) ===
             ~w(app executor)

    [started] = entries(ctx, "native_started")

    await(
      fn ->
        Enum.all?(
          [started["pid"], started["executorPid"], started["controllerPid"]],
          fn process ->
            not File.exists?("/proc/#{process}")
          end
        )
      end,
      now() + 5_000
    )
  end

  defp journal(ctx) do
    path = Path.join(ctx.root, "journal.json")
    if File.exists?(path), do: JSON.decode!(File.read!(path))["events"], else: []
  end

  defp entries(ctx, event), do: Enum.filter(journal(ctx), &(&1["event"] == event))

  defp await(fun, deadline) do
    case fun.() do
      result when result not in [false, nil] ->
        result

      _ ->
        assert now() < deadline, "Owned environment lifecycle deadline"
        Process.sleep(10)
        await(fun, deadline)
    end
  end

  defp executor_cwd(ctx), do: Path.join(ctx.root, "executor-workspace")
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
