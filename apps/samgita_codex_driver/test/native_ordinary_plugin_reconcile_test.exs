defmodule SamgitaCodexDriver.NativeOrdinaryPluginReconcileTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_plugin_reconcile_fixture.py", __DIR__)
  @script_sha "45ddc9bf6a80c2f0de23569a444e35d3420d6801df44ed20329d1ddbade5fa05"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @remote "plugins~Plugin_owned_ordinary"
  @plugin "owned-ordinary@openai-curated-remote"
  @marker "Owned ordinary reconcile marker λ🙂\n"
  @skill "---\nname: notes\ndescription: Owned ordinary notes\n---\nOwned skill text β🙂\n"
  @reason "Owned ordinary cache reconciliation λ🙂"
  @ids [-1, "-1", 1, "1", "owned-reconcile-empty-λ🙂"]
  @empty %{
    "changedPlugins" => [],
    "failedRemotePluginIds" => [],
    "failedMaterializationRemotePluginIds" => []
  }
  @changed %{
    "changedPlugins" => [
      %{
        "id" => @plugin,
        "hasSkills" => true,
        "hasApps" => false,
        "hasHooks" => false,
        "hasMcps" => false
      }
    ],
    "failedRemotePluginIds" => [],
    "failedMaterializationRemotePluginIds" => []
  }
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/PluginReconcileParams.json" =>
      "91dfe0967326b876e50ddf8d896c6c516440c43a36b08efd4746c0bd770882dc",
    "v2/PluginReconcileResponse.json" =>
      "ba2a8e317c9098beed39d4decc433d9dc29ba0c8164e8d4c229481b9243c5ec8"
  }

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

        if length(ledger.frames) < 256 and size <= limit and ledger.bytes + size <= 2_097_152 do
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

    assert is_binary(System.find_executable("openssl")),
           "BLOCKED_ENV: owned listener setup needs OpenSSL"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-reconcile-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-plugin-reconcile")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    config = Path.join(fixture.codex_home, "config.toml")
    disabled = File.read!(config)
    assert length(:binary.matches(disabled, "\nplugins = false\n")) === 1
    enabled = String.replace(disabled, "\nplugins = false\n", "\nplugins = true\n", global: false)
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    paths = [
      @script,
      @base,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json") | Enum.map(Map.keys(@schemas), &schema_path/1)
    ]

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

  test "ordinary native reconciliation materializes one skills bundle and preserves cache across a cold process",
       ctx do
    warm = start(ctx)
    set_plugins(ctx, true)
    assert reconcile(ctx, warm.pid, Enum.at(@ids, 0)) === @changed
    cached = assert_bundle(ctx)
    assert_fetches(ctx, [true])
    assert_controls(ctx, true)

    assert reconcile(ctx, warm.pid, Enum.at(@ids, 1)) === @empty
    assert assert_bundle(ctx) === cached
    assert_fetches(ctx, [true, true])
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    close(warm)
    prefix = Agent.get(ctx.capture, & &1.frames)
    assert_controls(ctx, true)

    set_plugins(ctx, false)
    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    set_plugins(ctx, true)
    assert reconcile(ctx, cold.pid, Enum.at(@ids, 2)) === @empty
    assert assert_bundle(ctx) === cached
    assert_fetches(ctx, [true, true, true])

    write_state(ctx, false)
    assert reconcile(ctx, cold.pid, Enum.at(@ids, 3)) === @changed
    refute File.exists?(plugin_root(ctx))
    assert_fetches(ctx, [true, true, true, false])
    assert reconcile(ctx, cold.pid, Enum.at(@ids, 4)) === @empty
    refute File.exists?(plugin_root(ctx))
    assert_fetches(ctx, [true, true, true, false, false])
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    close(cold)
    frames = Agent.get(ctx.capture, & &1.frames)
    assert Enum.take(frames, length(prefix)) === prefix
    assert_inventory(frames)
    assert_controls(ctx, true)
    close_provider(ctx)
    assert_controls(ctx, true)
  end

  defp reconcile(ctx, pid, id) do
    params = %{"reason" => @reason}
    assert :ok = Schema.validate(schema("v2/PluginReconcileParams.json"), params, max_depth: 8)
    result = call(ctx, pid, "plugin/reconcile", params, id)
    assert :ok = Schema.validate(schema("v2/PluginReconcileResponse.json"), result, max_depth: 16)
    result
  end

  defp assert_request(wire) do
    document = schema("ClientRequest.json")
    owner = Enum.at(Map.fetch!(document, "oneOf"), 75)

    assert owner === %{
             "properties" => %{
               "id" => %{"$ref" => "#/definitions/RequestId"},
               "method" => %{
                 "enum" => ["plugin/reconcile"],
                 "title" => "Plugin/reconcileRequestMethod",
                 "type" => "string"
               },
               "params" => %{"$ref" => "#/definitions/PluginReconcileParams"}
             },
             "required" => ["id", "method", "params"],
             "title" => "Plugin/reconcileRequest",
             "type" => "object"
           }

    selected =
      Map.put(
        owner,
        "definitions",
        Map.take(document["definitions"], ["RequestId", "PluginReconcileParams"])
      )

    assert :ok = Schema.validate(selected, wire, max_depth: 16)
  end

  defp assert_bundle(ctx) do
    version = Path.join(plugin_root(ctx), "1.0.0")
    manifest = Path.join(version, ".codex-plugin/plugin.json")
    marker = Path.join(version, "marker.txt")
    skill = Path.join(version, "skills/notes/SKILL.md")
    identity = Path.join(plugin_root(ctx), ".codex-remote-plugin-install.json")
    for path <- [manifest, marker, skill, identity], do: assert(File.regular?(path))

    assert JSON.decode!(File.read!(manifest)) === %{
             "name" => "owned-ordinary",
             "version" => "1.0.0"
           }

    assert File.read!(marker) === @marker
    assert File.read!(skill) === @skill
    assert JSON.decode!(File.read!(identity))["remote_plugin_id"] === @remote
    Map.new([manifest, marker, skill, identity], &{&1, snapshot(&1)})
  end

  defp plugin_root(ctx),
    do: Path.join(ctx.fixture.codex_home, "plugins/cache/openai-curated-remote/owned-ordinary")

  defp assert_fetches(ctx, states) do
    expected =
      Enum.with_index(states, 1)
      |> Enum.map(fn {present, sequence} ->
        %{
          "event" => "installed",
          "sequence" => sequence,
          "path" => "/backend-api/ps/plugins/installed",
          "query" => %{"limit" => ["200"], "includeDownloadUrls" => ["true"]},
          "present" => present
        }
      end)

    assert rows(ctx, "installed") === expected

    assert [
             %{
               "event" => "bundle",
               "sequence" => 1,
               "path" => "/bundles/ordinary-v1",
               "size" => size,
               "sha256" => digest
             }
           ] = rows(ctx, "bundle")

    assert is_integer(size) and size > 0 and size <= 131_072
    assert is_binary(digest) and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest)
  end

  defp set_plugins(ctx, enabled) do
    before = if enabled, do: ctx.disabled, else: ctx.enabled
    after_value = if enabled, do: ctx.enabled, else: ctx.disabled
    assert File.read!(ctx.config) === before
    path = ctx.config <> ".ordinary-pending"
    File.write!(path, after_value, [:exclusive])
    File.rename!(path, ctx.config)
    assert File.read!(ctx.config) === after_value
  end

  defp write_state(ctx, present) do
    path = Path.join(ctx.root, "ordinary-reconcile-state.json")
    pending = path <> ".pending"
    File.write!(pending, JSON.encode!(%{"present" => present}), [:exclusive])
    File.rename!(pending, path)
  end

  defp assert_controls(ctx, enabled) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === if(enabled, do: ctx.enabled, else: ctx.disabled)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp rows(ctx, kind) do
    journal =
      snapshot(Path.join(ctx.root, "ordinary-reconcile-journal.json")).bytes |> JSON.decode!()

    assert length(journal["events"]) <= 128
    Enum.filter(journal["events"], &(&1["event"] === kind))
  end

  defp start(ctx) do
    assert File.read!(ctx.config) === ctx.disabled
    # Unlike ordinary_args, leave plugin enablement to this owned TOML gate.
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
               max_event_bytes: 2_097_152,
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
                      "CODEX_CA_CERTIFICATE" =>
                        Path.join(ctx.root, "ordinary-reconcile-tls/ca.pem"),
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_plugin_reconcile", "version" => "0.1.0"}
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
    assert_empty_loaded(ctx, pid)
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp call(ctx, pid, method, params, id \\ request_id()) do
    wire = %{"id" => id, "method" => method, "params" => params}
    if method === "plugin/reconcile", do: assert_request(wire)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    frames = Agent.get(ctx.capture, & &1.frames)
    assert [sent, received] = Enum.filter(frames, &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(frames) do
    outgoing = Enum.filter(frames, &(&1.direction === :out))

    expected =
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/reconcile plugin/reconcile thread/loaded/list initialize initialized server/diagnostics thread/loaded/list plugin/reconcile plugin/reconcile plugin/reconcile thread/loaded/list)

    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    reconciles = Enum.filter(outgoing, &(&1.wire["method"] === "plugin/reconcile"))
    assert Enum.map(reconciles, & &1.wire["id"]) === @ids
    assert Enum.map(reconciles, & &1.wire["params"]) === List.duplicate(%{"reason" => @reason}, 5)
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 13 and length(Enum.uniq(ids)) === 13
    assert length(replies) === 13
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    refute Enum.any?(events, &(&1.kind === :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert {:ok, []} = Session.drain(pid, 128)
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

  defp request_id, do: "owned-reconcile-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
