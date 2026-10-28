defmodule SamgitaCodexDriver.NativeOrdinaryInstalledThreadContextTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_installed_apps_fixture.py", __DIR__)
  @script_sha "e20306dd396d517a2f4f9bf75356052c442490b15f39c75d98a9e714ab19a706"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema_shas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/AppsInstalledParams.json" =>
      "c2027510d5d041c2205349036f9c2bea10b20df309de5330beab9de8a9e50bdb",
    "v2/AppsInstalledResponse.json" =>
      "d8ef8dd14dcba8aaaaaf2b0b80db90d66edf8f4ff422589b844ae2b0edcb46d4"
  }
  @thread_node_sha "22649c82b922402200147e8ee7d966cb548fcffa2852cd9e2f6e7d1fa1da8ad5"
  @thread_node_bytes """
  {
    "description": "Optional loaded thread id used to evaluate effective app configuration.",
    "type": [
      "string",
      "null"
    ]
  }
  """
  @missing "00000000-0000-4000-8000-000000000000"
  @one [
    %{"id" => "owned-installed-alpha", "runtimeName" => "Owned Alpha λ🙂"},
    %{"id" => "owned-installed-beta", "runtimeName" => nil}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 64 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}
          {:ok, %{frames: ledger.frames ++ [frame], bytes: ledger.bytes + size}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    for {name, sha} <- @schema_shas, do: assert(hash(File.read!(schema_path(name))) === sha)
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    root = Path.join(System.tmp_dir!(), "owned-installed-thread-context-#{suffix}")
    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-installed-thread-context")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)
    provider_ctx = %{root: root, fixture: fixture, resources: resources}
    on_exit(fn -> assert :ok = close_provider(provider_ctx) end)
    cwd = Path.join(root, "loaded-thread-cwd")
    File.mkdir!(cwd)
    # Fixed owned setup precedes immutable snapshots. Keep the distinct cwd
    # without asking native thread/start to materialize a new workspace entry.
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(config, "\n[projects.#{JSON.encode!(cwd)}]\ntrust_level = \"trusted\"\n", [
      :append
    ])

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      fixture: fixture,
      cwd: cwd,
      resources: resources,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    paths =
      [
        @script,
        @base,
        fixture.requests,
        Path.join(fixture.codex_home, "config.toml"),
        Path.join(fixture.codex_home, "models.json"),
        Path.join(root, "ordinary-installed-apps-inputs.json")
      ] ++
        Enum.map(Map.keys(@schema_shas), &schema_path/1)

    Map.put(ctx, :inputs, Map.new(paths, &{&1, snapshot(&1)}))
  end

  test "ordinary installed thread context uses a loaded native thread and preserves explicit null",
       ctx do
    native = start(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) ===
             %{"data" => [], "nextCursor" => nil}

    assert installed(
             ctx,
             native.pid,
             %{"threadId" => nil, "forceRefresh" => false},
             "installed-before-thread"
           ) === []

    assert_discovery(ctx, 0)

    started =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.cwd,
        "ephemeral" => true,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    thread = started["thread"]["id"]
    assert is_binary(thread) and byte_size(thread) > 0 and thread != @missing

    assert Map.take(started, ~w(cwd model modelProvider)) ===
             %{"cwd" => ctx.cwd, "model" => "mock-model", "modelProvider" => "fixture"}

    # This is the native causal barrier. rmcp_client publishes the startup
    # catalog before returning the ManagedClient; only then can Ready be emitted.
    # Neither thread/start success nor the peer's response-sent journal suffices.
    await(
      fn ->
        Enum.any?(frames(ctx, :in), fn frame ->
          frame.wire["method"] === "mcpServer/startupStatus/updated" and
            Map.take(frame.wire["params"], ~w(threadId name status)) ===
              %{"threadId" => thread, "name" => "codex_apps", "status" => "ready"}
        end)
      end,
      now() + 5_000
    )

    assert call(ctx, native.pid, "thread/loaded/list", %{}) ===
             %{"data" => [thread], "nextCursor" => nil}

    read = call(ctx, native.pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})

    assert Map.take(read["thread"], ~w(id cwd ephemeral modelProvider turns)) ===
             %{
               "id" => thread,
               "cwd" => ctx.cwd,
               "ephemeral" => true,
               "modelProvider" => "fixture",
               "turns" => []
             }

    assert_discovery(ctx, 1)

    assert installed(ctx, native.pid, %{"threadId" => thread, "forceRefresh" => false}, 3319) ===
             @one

    assert installed(ctx, native.pid, %{"threadId" => nil, "forceRefresh" => false}, "3319") ===
             @one

    # Ordinary absent-state control: ignoring/dropping threadId would return
    # the populated global snapshot rather than this exact pinned lookup error.
    missing_wire = %{
      "id" => "installed-missing-thread",
      "method" => "app/installed",
      "params" => %{"threadId" => @missing, "forceRefresh" => false}
    }

    assert {:error, %SamgitaProtocolCodex.Error{code: :upstream_error, wire: reply}} =
             Session.request_native(native.pid, missing_wire, timeout_ms: 5_000)

    assert %{"id" => "installed-missing-thread", "error" => error} = reply
    assert error === %{"code" => -32_600, "message" => "thread not found: " <> @missing}
    assert_exchange(ctx, missing_wire, reply)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) ===
             %{"data" => [thread], "nextCursor" => nil}

    assert_discovery(ctx, 1)
    assert_controls(ctx)
    assert_inventory(ctx, thread)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert :ok = close_native(native)
    assert :ok = close_provider(ctx)
    assert_controls(ctx)
    assert_discovery(ctx, 1)
  end

  defp installed(ctx, pid, params, id) do
    result = call(ctx, pid, %{"id" => id, "method" => "app/installed", "params" => params})
    document = schema("v2/AppsInstalledResponse.json")
    properties = document["definitions"]["InstalledApp"]["properties"]
    # Other native computed outcome fields remain opaque. Only descriptive
    # identity/runtime-name projections are validated or asserted here.
    assert is_list(result["apps"]) and length(result["apps"]) <= 2

    Enum.map(result["apps"], fn app ->
      for key <- ~w(id runtimeName) do
        assert :ok =
                 Schema.validate(
                   with_definitions(document, properties[key]),
                   Map.fetch!(app, key)
                 )
      end

      Map.take(app, ~w(id runtimeName))
    end)
  end

  defp start(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
      "-c",
      "features.recommended_plugins=false",
      "app-server",
      "--listen",
      "stdio://"
    ]

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    :atomics.put(ctx.resources, 2, 1)
    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      :atomics.put(ctx.resources, 2, 2)
    end)

    id = request_id()
    info = %{"name" => "owned_ordinary_installed_thread_context", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = reply} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, reply)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, resources: ctx.resources}
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = reply} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, reply)
    result
  end

  defp assert_exchange(ctx, wire, reply) do
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === reply
    assert {:ok, decoded_sent} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_sent === wire
    assert {:ok, decoded_reply} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_reply === reply

    if wire["method"] === "app/installed" do
      root = schema("ClientRequest.json")
      variant = Enum.fetch!(root["oneOf"], 85)
      assert variant["properties"]["method"]["enum"] === ["app/installed"]
      assert :ok = Schema.validate(with_definitions(root, variant), decoded_sent, max_depth: 32)
      document = schema("v2/AppsInstalledParams.json")
      node = Map.fetch!(document["properties"], "threadId")
      assert hash(@thread_node_bytes) === @thread_node_sha
      assert JSON.decode!(@thread_node_bytes) === node
      assert Map.has_key?(decoded_sent["params"], "threadId")
      assert Map.fetch!(decoded_sent["params"], "forceRefresh") === false

      assert :ok =
               Schema.validate(
                 with_definitions(document, node),
                 decoded_sent["params"]["threadId"]
               )

      assert :ok = Schema.validate(document, decoded_sent["params"], max_depth: 16)
    end
  end

  defp assert_inventory(ctx, thread) do
    await(
      fn -> Enum.count(frames(ctx, :in), &Map.has_key?(&1.wire, "method")) === 4 end,
      now() + 5_000
    )

    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list app/installed thread/start thread/loaded/list thread/read app/installed app/installed app/installed thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    responses = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 11 and length(responses) === 11
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 11
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)
    assert Enum.count(responses, &Map.has_key?(&1.wire, "error")) === 1
    notifications = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "method"))
    methods = Enum.frequencies_by(notifications, & &1.wire["method"])

    assert methods === %{
             "remoteControl/status/changed" => 1,
             "thread/started" => 1,
             "mcpServer/startupStatus/updated" => 2
           }

    startup =
      Enum.filter(notifications, &(&1.wire["method"] === "mcpServer/startupStatus/updated"))

    assert Enum.map(startup, &Map.take(&1.wire["params"], ~w(threadId name status))) === [
             %{"threadId" => thread, "name" => "codex_apps", "status" => "starting"},
             %{"threadId" => thread, "name" => "codex_apps", "status" => "ready"}
           ]

    for frame <- notifications do
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire
    end
  end

  defp assert_discovery(ctx, count) do
    assert length(rows(ctx, "mcp_initialize")) === count
    assert length(rows(ctx, "mcp_initialized")) === count
    tools = rows(ctx, "tools_list")
    assert length(tools) === count
    assert rows(ctx, "directory") === []

    if count === 1 do
      assert [%{"sequence" => 1, "generation" => 1} = row] = tools
      assert JSON.decode!(row["raw_request"]) === row["request"]
      assert row["request"]["method"] === "tools/list"

      assert Enum.map(row["result"]["tools"], &Map.take(&1, ~w(name _meta))) === [
               %{
                 "name" => "owned_alpha_lookup",
                 "_meta" => %{
                   "connector_id" => "owned-installed-alpha",
                   "connector_name" => "  Owned Alpha λ🙂  "
                 }
               },
               %{
                 "name" => "owned_alpha_notes",
                 "_meta" => %{
                   "connector_id" => "owned-installed-alpha",
                   "connector_name" => "  Owned Alpha λ🙂  "
                 }
               },
               %{
                 "name" => "owned_beta_lookup",
                 "_meta" => %{"connector_id" => "owned-installed-beta"}
               }
             ]

      await(fn -> length(rows(ctx, "tools_list_response_sent")) === 1 end, now() + 5_000)

      assert [%{"sequence" => 1, "raw" => raw, "sha256" => sha}] =
               rows(ctx, "tools_list_response_sent")

      assert hash(raw) === sha

      assert JSON.decode!(raw) === %{
               "jsonrpc" => "2.0",
               "id" => row["request"]["id"],
               "result" => row["result"]
             }
    else
      assert rows(ctx, "tools_list_response_sent") === []
    end
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === [] and File.ls!(ctx.cwd) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "generation_changed") === []
    assert rows(ctx, "unexpected_http") === [] and rows(ctx, "unexpected_mcp") === []
    assert rows(ctx, "fixture_error") === []
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
    :atomics.put(native.resources, 2, 2)
    :ok
  end

  defp close_provider(ctx) do
    try do
      if rows(ctx, "fixture_closed") === [] do
        path = Path.join(ctx.root, "ordinary-installed-apps-control.json")
        refute File.exists?(path)
        File.write!(path, JSON.encode!(%{"action" => "close"}), [:exclusive])
        await(fn -> rows(ctx, "fixture_closed") != [] end, now() + 5_000)
      end
    after
      assert :ok = ModelFixture.close(ctx.fixture)
    end

    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    assert [%{"pid" => helper}] = rows(ctx, "fixture_started")
    assert [%{"pid" => ^helper}] = rows(ctx, "fixture_closed")
    await(fn -> not File.exists?("/proc/#{helper}") end, now() + 5_000)
    :atomics.put(ctx.resources, 1, 2)
    :ok
  end

  defp rows(ctx, event) do
    path = Path.join(ctx.root, "ordinary-installed-apps-journal.json")

    if File.exists?(path) do
      events = snapshot(path).bytes |> JSON.decode!() |> Map.fetch!("events")
      assert length(events) <= 64
      Enum.filter(events, &(&1["event"] === event))
    else
      []
    end
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp with_definitions(document, node),
    do: Map.put(node, "definitions", Map.get(document, "definitions", %{}))

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      Path.expand(
        "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/" <> name,
        __DIR__
      )

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp await(predicate, until) do
    unless predicate.() do
      assert now() < until, "ordinary installed thread-context observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, until)
    end
  end

  defp request_id,
    do: "ordinary-installed-thread-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
