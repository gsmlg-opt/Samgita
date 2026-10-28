defmodule SamgitaCodexDriver.NativeOrdinaryPluginShareListTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_plugin_share_list_fixture.py", __DIR__)
  @script_sha "e2ed540e49f974006da8048234d89a04e51b79f2a92c521a441753aca96af093"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema_hashes %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "ServerNotification.json" =>
      "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1",
    "v2/PluginShareListParams.json" =>
      "0d71280d2a655ffc26375044ec1693203848614f99fdb4563e0cb5a4ee40122b",
    "v2/PluginShareListResponse.json" =>
      "d349a496947956fd5f4d125b8348faa2ef0c91daf7f3cd74ae0616f55c8e328b"
  }
  @null_node_sha "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb"
  @remote "plugins~Plugin_owned_ordinary_list_4883"
  @name "owned-ordinary-list"
  @version "4.8.83"
  @display "Owned ordinary remote list λ🙂"
  @description "Owned list-only description β🙂"
  @list_id "owned-share-list-4883"

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
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
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

    for {name, expected} <- @schema_hashes,
        do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-share-list-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-plugin-share-list")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    config = Path.join(fixture.codex_home, "config.toml")
    disabled = File.read!(config)
    fragment = "\nplugins = false\n"
    assert length(:binary.matches(disabled, fragment)) === 1
    enabled = String.replace(disabled, fragment, "\nplugins = true\n", global: false)
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    paths =
      [@script, @base, fixture.requests, Path.join(fixture.codex_home, "models.json")] ++
        Enum.map(Map.keys(@schema_hashes), &schema_path/1)

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      config: config,
      disabled: disabled,
      enabled: enabled,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native share list emits present null for an unmapped remote plugin without local work",
       ctx do
    assert_controls(ctx, ctx.disabled)
    native = start(ctx)
    assert_empty_loaded(ctx, native.pid)
    assert rows(ctx, "created_page") === []
    assert rows(ctx, "installed_page") === []
    assert_controls(ctx, ctx.disabled)

    # Latest config is refreshed by the list handler. Avoid unrelated startup
    # installed-plugin refresh; this is fixed ordinary feature setup, not a gate test.
    pending = ctx.config <> ".ordinary-pending"
    File.write!(pending, ctx.enabled, [:exclusive])
    File.rename!(pending, ctx.config)
    wire = %{"id" => @list_id, "method" => "plugin/share/list", "params" => %{}}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 32)
    assert :ok = Schema.validate(schema("v2/PluginShareListParams.json"), wire["params"])
    result = call(ctx, native.pid, wire)
    document = schema("v2/PluginShareListResponse.json")
    assert :ok = Schema.validate(document, result, max_depth: 64)
    assert Enum.sort(Map.keys(result)) === ["data"]
    assert [item] = Map.fetch!(result, "data")

    node =
      document
      |> Map.fetch!("definitions")
      |> Map.fetch!("PluginShareListItem")
      |> Map.fetch!("properties")
      |> Map.fetch!("localPluginPath")
      |> Map.fetch!("anyOf")
      |> Enum.at(1)

    assert node === %{"type" => "null"}

    canonical_node = """
    {
      "type": "null"
    }
    """

    assert JSON.decode!(canonical_node) === node
    assert hash(canonical_node) === @null_node_sha
    assert Map.has_key?(item, "localPluginPath")
    assert Map.fetch!(item, "localPluginPath") === nil
    assert :ok = Schema.validate(node, Map.fetch!(item, "localPluginPath"))
    plugin = Map.fetch!(item, "plugin")
    assert Map.fetch!(plugin, "remotePluginId") === @remote
    assert Map.fetch!(plugin, "name") === @name
    assert Map.fetch!(plugin, "version") === @version
    interface = Map.fetch!(plugin, "interface")
    assert Map.fetch!(interface, "displayName") === @display
    assert Map.fetch!(interface, "shortDescription") === @description
    assert_reads(ctx)
    assert_empty_loaded(ctx, native.pid)
    assert_controls(ctx, ctx.enabled)
    assert_idle(native.pid)
    close_native(native)
    assert_inventory(ctx)
    assert_controls(ctx, ctx.enabled)
    close_provider(ctx)
    assert_reads(ctx)
    assert_controls(ctx, ctx.enabled)
  end

  defp assert_reads(ctx) do
    assert rows(ctx, "created_page") === [
             %{
               "event" => "created_page",
               "path" => "/backend-api/ps/plugins/workspace/created",
               "query" => %{"limit" => ["200"]},
               "remote_plugin_id" => @remote,
               "name" => @name,
               "version" => @version,
               "display_name" => @display,
               "description" => @description,
               "count" => 1
             }
           ]

    assert rows(ctx, "installed_page") === [
             %{
               "event" => "installed_page",
               "path" => "/backend-api/ps/plugins/installed",
               "query" => %{"scope" => ["WORKSPACE"]},
               "count" => 0
             }
           ]

    reads = Enum.filter(journal(ctx), &(&1["event"] in ~w(created_page installed_page)))
    assert Enum.map(reads, & &1["event"]) === ~w(created_page installed_page)
  end

  defp assert_controls(ctx, config) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === config
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []

    refute File.exists?(
             Path.join(ctx.fixture.codex_home, ".tmp/plugin-share-local-paths-v1.json")
           )

    for relative <- ~w(plugins/cache cache/remote_plugin_catalog) do
      files =
        Path.join(ctx.fixture.codex_home, relative)
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: true)
        |> Enum.filter(&File.regular?/1)

      assert files === []
    end

    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []

    assert Enum.all?(
             journal(ctx),
             &(&1["event"] in ~w(fixture_started fixture_closed startup_read created_page installed_page))
           )
  end

  defp start(ctx) do
    assert File.read!(ctx.config) === ctx.disabled

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

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_plugin_share_list", "version" => "1"}
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

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

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
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
    assert :ok = Schema.validate_request(wire["method"], wire["params"], experimental: true)
    assert :ok = Schema.validate_result(:server_response, wire["method"], response["result"])
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list plugin/share/list thread/loaded/list)

    assert [list] = Enum.filter(outgoing, &(&1.wire["method"] === "plugin/share/list"))
    assert list.wire === %{"id" => @list_id, "method" => "plugin/share/list", "params" => %{}}
    document = schema("ClientRequest.json")
    variants = Map.fetch!(document, "oneOf")

    selected =
      Enum.filter(
        variants,
        &(get_in(&1, ["properties", "method", "enum"]) === ["plugin/share/list"])
      )

    assert [variant] = selected
    assert variant === Enum.at(variants, 80)
    node = variant |> Map.fetch!("properties") |> Map.fetch!("id")
    assert node === %{"$ref" => "#/definitions/RequestId"}
    id_contract = Map.put(node, "definitions", Map.fetch!(document, "definitions"))
    assert :ok = Schema.validate(id_contract, Map.fetch!(list.wire, "id"), max_depth: 8)
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    incoming = frames(ctx, :in)
    responses = Enum.filter(incoming, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 5 and length(Enum.uniq(ids)) === 5
    assert length(responses) === 5
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)
    notifications = Enum.reject(incoming, &Map.has_key?(&1.wire, "id"))

    # Startup can send normal configWarning notifications. Current native
    # notifications always carry emittedAtMs; neither absence nor a fixed count
    # is assumed. Original bytes and the full ordinary envelope are validated.
    for frame <- notifications do
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
      emitted = Map.fetch!(frame.wire, "emittedAtMs")
      assert is_integer(emitted) and emitted > 0
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire
      assert :ok = Schema.validate(schema("ServerNotification.json"), frame.wire, max_depth: 64)
      method = Map.fetch!(frame.wire, "method")

      assert :ok =
               Schema.validate_notification(
                 :server_notification,
                 method,
                 Map.fetch!(frame.wire, "params"),
                 experimental: true
               )

      refute String.starts_with?(method, ["thread/", "turn/", "item/"])
    end
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert {:ok, []} = Session.drain(pid, 128)
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp journal(ctx) do
    bytes = snapshot(Path.join(ctx.root, "ordinary-share-list-journal.json")).bytes
    assert byte_size(bytes) <= 131_072
    events = JSON.decode!(bytes) |> Map.fetch!("events")
    assert length(events) <= 64
    events
  end

  defp rows(ctx, kind), do: Enum.filter(journal(ctx), &(&1["event"] === kind))

  defp close_native(native) do
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
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: schema_path(name) |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-share-list-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
