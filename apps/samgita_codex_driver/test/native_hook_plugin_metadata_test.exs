defmodule SamgitaCodexDriver.NativeHookPluginMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @market "owned-hook-metadata"
  @plugin "owned-hook-provenance"
  @plugin_id "owned-hook-provenance@owned-hook-metadata"
  @command "owned-plugin-hook-descriptor"
  @status_message "Owned inert PreCompact metadata"
  @ordinary_fields ~w(key eventName handlerType command async matcher timeoutSec statusMessage additionalContextLimit sourcePath source pluginId displayOrder)

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
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 65_536

        if ledger.count < 96 and size <= limit and ledger.bytes + size <= 1_048_576 do
          entry = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
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

    assert hash(File.read!(binary)) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-hook-plugin-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    workspace = Path.join(root, "workspace")
    File.mkdir!(Path.join(workspace, ".git"))
    config = Path.join(root, "codex/config.toml")

    # Ordinary local metadata features; no hook trigger or executable is created.
    # Keep the exact local-plugin initialization fragment used by the shared helper.
    File.write!(config, """
    check_for_update_on_startup = false
    [memories]
    generate_memories = false
    use_memories = false

    [features]
    plugins = true
    remote_plugin = false
    plugin_sharing = false
    hooks = true
    apps = false
    memories = false
    shell_snapshot = false
    """)

    marketplace = Path.join(workspace, ".agents/plugins/marketplace.json")
    plugin_root = Path.join(workspace, @plugin)
    manifest = Path.join(plugin_root, ".codex-plugin/plugin.json")
    hook_source = Path.join(plugin_root, "hooks/hooks.json")

    inputs = %{
      marketplace =>
        JSON.encode!(%{
          "name" => @market,
          "plugins" => [
            %{"name" => @plugin, "source" => %{"source" => "local", "path" => "./#{@plugin}"}}
          ]
        }),
      manifest =>
        JSON.encode!(%{"name" => @plugin, "description" => "Owned inert hook metadata"}),
      hook_source =>
        JSON.encode!(%{
          "hooks" => %{
            "PreCompact" => [
              %{
                "hooks" => [
                  %{
                    "type" => "command",
                    "command" => @command,
                    "timeout" => 7,
                    "async" => false,
                    "statusMessage" => @status_message,
                    "additionalContextLimit" => 73
                  }
                ]
              }
            ]
          }
        })
    }

    for {path, bytes} <- inputs do
      assert byte_size(bytes) <= 4096
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
    end

    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    cache_base = Path.join([root, "codex/plugins/cache", @market, @plugin])

    %{
      binary: Path.expand(binary),
      root: root,
      workspace: workspace,
      config: config,
      marketplace: marketplace,
      inputs: inputs,
      capture: capture,
      cache_base: cache_base,
      cached_manifest: Path.join(cache_base, "local/.codex-plugin/plugin.json"),
      cached_hook: Path.join(cache_base, "local/hooks/hooks.json"),
      manifest: manifest,
      hook_source: hook_source
    }
  end

  test "actual installed plugin provenance survives a cold native replacement and disappears on uninstall",
       ctx do
    assert_inputs(ctx)
    refute File.exists?(ctx.cache_base)
    warm = start(ctx)
    assert catalog(ctx, warm.pid) === empty_catalog(ctx)

    # Correlate the actual install reply, without inspecting unrelated metadata.
    install = call(ctx, warm.pid, "plugin/install", install_params(ctx))
    assert is_map(install)
    assert_cache(ctx)
    installed_config = config_bytes(ctx)
    assert_installed(ctx, warm.pid)
    assert_installed(ctx, warm.pid)
    assert config_bytes(ctx) === installed_config
    assert_quiet(ctx, warm.pid)
    close(warm)

    cold = start(ctx)
    refute cold.native == warm.native
    assert config_bytes(ctx) === installed_config
    assert_cache(ctx)
    assert_installed(ctx, cold.pid)
    assert config_bytes(ctx) === installed_config

    assert call(ctx, cold.pid, "plugin/uninstall", %{"pluginId" => @plugin_id}) === %{}
    refute File.exists?(ctx.cache_base)
    assert catalog(ctx, cold.pid) === empty_catalog(ctx)
    assert_inputs(ctx)
    assert_quiet(ctx, cold.pid)
    close(cold)
    assert_inventory(ctx)
  end

  defp install_params(ctx),
    do: %{"marketplacePath" => ctx.marketplace, "pluginName" => @plugin}

  defp catalog(ctx, pid), do: call(ctx, pid, "hooks/list", %{"cwds" => [ctx.workspace]})

  defp empty_catalog(ctx),
    do: %{"data" => [%{"cwd" => ctx.workspace, "hooks" => [], "warnings" => [], "errors" => []}]}

  defp assert_installed(ctx, pid) do
    before = config_bytes(ctx)
    result = catalog(ctx, pid)
    assert Map.keys(result) === ["data"]
    assert [entry] = Map.fetch!(result, "data")
    assert Enum.sort(Map.keys(entry)) === ["cwd", "errors", "hooks", "warnings"]

    # PreCompact cannot emit additional context: preserve the native warning
    # and its normalization instead of accepting the unsupported input value.
    warnings = [
      "ignoring additionalContextLimit for PreCompact hook in #{ctx.cached_hook}: " <>
        "this event cannot emit additionalContext"
    ]

    assert Map.take(entry, ~w(cwd errors warnings)) ===
             %{"cwd" => ctx.workspace, "errors" => [], "warnings" => warnings}

    assert [hook] = Map.fetch!(entry, "hooks")

    # Exact ordinary provenance only. Other native metadata remains in original
    # captured bytes and is intentionally outside this functional assertion.
    assert Map.take(hook, @ordinary_fields) === %{
             "key" => @plugin_id <> ":hooks/hooks.json:pre_compact:0:0",
             "eventName" => "preCompact",
             "handlerType" => "command",
             "command" => @command,
             "async" => false,
             "matcher" => nil,
             "timeoutSec" => 7,
             "statusMessage" => @status_message,
             "additionalContextLimit" => nil,
             "sourcePath" => ctx.cached_hook,
             "source" => "plugin",
             "pluginId" => @plugin_id,
             "displayOrder" => 0
           }

    assert config_bytes(ctx) === before
    assert_cache(ctx)
  end

  defp start(ctx) do
    session =
      NativeLaunchFixture.local_plugins_after_initialize(ctx.config, fn ->
        assert {:ok, pid} =
                 Session.start_link(
                   max_events: 64,
                   max_event_bytes: 262_144,
                   max_message_bytes: 65_536,
                   transport:
                     {CaptureStdio,
                      [
                        capture: ctx.capture,
                        executable: ctx.binary,
                        args: [
                          "-c",
                          ~s(approval_policy="never"),
                          "-c",
                          ~s(sandbox_mode="danger-full-access"),
                          "-c",
                          "features.recommended_plugins=false",
                          "app-server",
                          "--listen",
                          "stdio://"
                        ],
                        cwd: ctx.workspace,
                        inherit_env: [],
                        max_message_bytes: 65_536,
                        env: %{
                          "HOME" => Path.join(ctx.root, "home"),
                          "CODEX_HOME" => Path.join(ctx.root, "codex"),
                          "TMPDIR" => Path.join(ctx.root, "tmp"),
                          "PATH" => "/usr/bin:/bin",
                          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                          "NO_COLOR" => "1",
                          "RUST_LOG" => "off"
                        }
                      ]}
                 )

        %{connection: connection} = :sys.get_state(pid)
        identity = :atomics.new(1, [])
        on_exit(fn -> cleanup(pid, connection, identity) end)
        id = request_id()
        info = %{"name" => "owned_hook_plugin_metadata", "version" => "0.1.0"}
        capabilities = %{"experimentalApi" => true}

        wire = %{
          "id" => id,
          "method" => "initialize",
          "params" => %{"clientInfo" => info, "capabilities" => capabilities}
        }

        assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
                 Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

        assert_exchange(ctx, wire, response)
        %{pid: pid, connection: connection, identity: identity}
      end)

    native = call(ctx, session.pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(session.identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    Map.put(session, :native, native)
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    selected =
      ctx.capture
      |> Agent.get(&Enum.reverse(&1.records))
      |> Enum.filter(&(&1.wire["id"] === wire["id"]))

    assert [sent, received] = selected
    assert sent.direction === :out
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.direction === :in
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_cache(ctx) do
    assert File.read!(ctx.cached_manifest) === Map.fetch!(ctx.inputs, ctx.manifest)
    assert File.read!(ctx.cached_hook) === Map.fetch!(ctx.inputs, ctx.hook_source)
    assert_inputs(ctx)
  end

  defp assert_inputs(ctx) do
    assert map_size(ctx.inputs) === 3

    for {path, bytes} <- ctx.inputs do
      assert File.stat!(path).size <= 4096
      assert File.read!(path) === bytes
    end

    source_files =
      ctx.workspace
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    assert source_files === Enum.sort(Map.keys(ctx.inputs))
    config_bytes(ctx)
  end

  defp config_bytes(ctx) do
    assert File.stat!(ctx.config).size <= 8192
    bytes = File.read!(ctx.config)
    assert byte_size(bytes) <= 8192
    bytes
  end

  defp assert_quiet(ctx, pid) do
    assert {:ok, events} = Session.drain(pid, 64)
    assert length(events) <= 64
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 262_144

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Session.interaction_outcomes(pid) === []

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or
               method == "error" or String.starts_with?(method, "thread/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)

    assert_inputs(ctx)
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)
    records = Enum.reverse(ledger.records)

    requests =
      Enum.filter(records, &(&1.direction == :out and Map.has_key?(&1.wire, "id")))

    assert Enum.map(requests, & &1.wire["method"]) === [
             "initialize",
             "server/diagnostics",
             "hooks/list",
             "plugin/install",
             "hooks/list",
             "hooks/list",
             "initialize",
             "server/diagnostics",
             "hooks/list",
             "plugin/uninstall",
             "hooks/list"
           ]

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 11

    replies =
      Enum.filter(records, fn record ->
        record.direction == :in and Map.has_key?(record.wire, "id") and
          not Map.has_key?(record.wire, "method")
      end)

    assert length(replies) === 11
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)

    notifications =
      Enum.filter(records, &(&1.direction == :out and not Map.has_key?(&1.wire, "id")))

    assert Enum.map(notifications, & &1.wire) === [
             %{"method" => "initialized"},
             %{"method" => "initialized"}
           ]

    assert ledger.count === length(records)
    assert ledger.count <= 96
    assert ledger.bytes === Enum.reduce(records, 0, &(byte_size(&1.encoded) + &2))
    assert ledger.bytes <= 1_048_576
    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp close(session), do: cleanup(session.pid, session.connection, session.identity)

  defp cleanup(pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id,
    do: "owned-hook-plugin-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
