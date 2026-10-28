defmodule SamgitaCodexDriver.NativeOrdinaryAppsThreadContextTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_catalog_metadata_fixture.py", __DIR__)
  @script_sha "cd21e46bca341400798105d77707b3768f9a00ecde3025afe787df7be8c3cbd6"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schemas %{
    "v2/AppsListParams.json" =>
      "e880d0c24811118a2d3c2c7f0569a14aae5b12a31b0efe56809ccca8bbd85802",
    "v2/AppsListResponse.json" =>
      "5811fda68d6274decfc11744ad72bbe93e601d8514549e94f361ba3131d1adeb"
  }
  @fields ~w(id name)
  @expected [
    %{"id" => "catalog-alpha", "name" => "Owned Catalog Alpha λ"},
    %{"id" => "catalog-beta", "name" => "Owned Catalog Beta β"},
    %{"id" => "catalog-gamma", "name" => "Owned Catalog Gamma γ"}
  ]
  @ids [-1, "-1"]

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
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, state) do
      case record(state, :in, encoded) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end

    defp record_event(_, :ok, _), do: {:cont, :ok}

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)

      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 512 and size <= limit and ledger.bytes + size <= 2_097_152 do
          frame = %{direction: direction, encoded: encoded, wire: wire}
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
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-apps-thread-context-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-catalog-metadata")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    paths = [
      @script,
      @base,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "models.json"),
      fixture.requests,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
      | Enum.map(Map.keys(@schemas), &schema_path/1)
    ]

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native app list accepts its real loaded thread and explicit null without changing descriptive cache content",
       ctx do
    native = start(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    # No thread/global feature override, policy mutation or turn is requested.
    started =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    thread = Map.fetch!(started["thread"], "id")
    assert is_binary(thread) and byte_size(thread) > 0 and byte_size(thread) <= 128
    assert started["cwd"] === ctx.fixture.workspace

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert_controls(ctx)

    assert_list(ctx, native.pid, thread, Enum.at(@ids, 0))
    assert_directory(ctx)
    assert_thread_started(ctx, thread)

    # This is an explicit null on the same method, not app/read's other schema.
    assert_list(ctx, native.pid, nil, Enum.at(@ids, 1))
    assert_directory(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert_controls(ctx)
    assert_idle(native.pid)
    close(native)
    assert_controls(ctx)
    assert_inventory(ctx, thread)
    close_provider(ctx)
    assert_controls(ctx)
    assert_directory(ctx)
  end

  defp assert_list(ctx, pid, thread, id) do
    thread_node = schema("v2/AppsListParams.json")["properties"]["threadId"]
    assert :ok = Schema.validate(thread_node, thread, max_depth: 8)
    first_incoming = length(frames(ctx, :in))
    result = call(ctx, pid, "app/list", %{"threadId" => thread, "limit" => 100}, id)
    assert Map.fetch!(result, "nextCursor") === nil
    assert project(Map.fetch!(result, "data")) === @expected
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    updates = Enum.filter(events, &(&1.wire["method"] === "app/list/updated"))
    originals = frames(ctx, :in) |> Enum.drop(first_incoming)
    original_updates = Enum.filter(originals, &(&1.wire["method"] === "app/list/updated"))
    assert [update] = updates
    assert [original] = original_updates
    assert original.wire === update.wire
    assert JSON.decode!(original.encoded) === update.wire
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 64)
    assert decoded === update.wire
    assert is_integer(decoded["emittedAtMs"]) and decoded["emittedAtMs"] > 0
    assert project(decoded["params"]["data"]) === @expected
    assert_no_work(events)
    assert_controls(ctx)
  end

  defp project(apps) do
    properties = schema("v2/AppsListResponse.json")["definitions"]["AppInfo"]["properties"]

    Enum.map(apps, fn app ->
      # Keep the mixed AppInfo array opaque except these descriptive scalars.
      Map.new(@fields, fn name ->
        value = Map.fetch!(app, name)
        assert :ok = Schema.validate(properties[name], value, max_depth: 8)
        {name, value}
      end)
    end)
  end

  defp assert_thread_started(ctx, thread) do
    assert [original] =
             Enum.filter(frames(ctx, :in), &(&1.wire["method"] === "thread/started"))

    assert original.wire["params"]["thread"]["id"] === thread
    assert JSON.decode!(original.encoded) === original.wire
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 64)
    assert decoded === original.wire
  end

  defp assert_directory(ctx) do
    assert rows(ctx, "directory") === [
             %{
               "event" => "directory",
               "sequence" => 1,
               "path" => "/backend-api/connectors/directory/list",
               "query" => %{"external_logos" => ["true"]}
             },
             %{
               "event" => "directory",
               "sequence" => 2,
               "path" => "/backend-api/connectors/directory/list",
               "query" => %{"external_logos" => ["true"], "token" => ["owned catalog β"]}
             }
           ]

    methods = Enum.map(rows(ctx, "mcp"), & &1["method"])
    assert "initialize" in methods and "tools/list" in methods
    assert length(methods) <= 32
    assert Enum.all?(methods, &(&1 in ~w(initialize notifications/initialized tools/list ping)))
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp rows(ctx, kind) do
    journal =
      snapshot(Path.join(ctx.root, "ordinary-catalog-metadata-journal.json")).bytes
      |> JSON.decode!()

    assert length(journal["events"]) <= 256
    Enum.filter(journal["events"], &(&1["event"] === kind))
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_apps_thread_context", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params, id \\ request_id()) do
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(ctx, thread) do
    outgoing = frames(ctx, :out)

    expected =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/start thread/loaded/list app/list app/list thread/loaded/list)

    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    lists = Enum.filter(outgoing, &(&1.wire["method"] === "app/list"))
    assert Enum.map(lists, & &1.wire["id"]) === @ids

    assert Enum.map(lists, & &1.wire["params"]) === [
             %{"threadId" => thread, "limit" => 100},
             %{"threadId" => nil, "limit" => 100}
           ]

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 8 and length(Enum.uniq(ids)) === 8
    assert length(replies) === 8
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
    assert Enum.count(frames(ctx, :in), &(&1.wire["method"] === "app/list/updated")) === 2
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert_no_work(events)
    assert {:ok, []} = Session.drain(pid, 256)
  end

  defp assert_no_work(events) do
    refute Enum.any?(events, &(&1.kind === :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )
  end

  defp close(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    assert [%{"pid" => native}] = rows(ctx, "fixture_started")
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    refute File.exists?("/proc/#{native}")
    assert [%{"pid" => ^native}] = rows(ctx, "fixture_closed")
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 2_097_152
    bytes = File.read!(path)
    assert byte_size(bytes) <= 2_097_152
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id,
    do: "owned-apps-thread-context-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
