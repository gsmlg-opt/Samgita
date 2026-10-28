defmodule SamgitaCodexDriver.NativeOrdinaryMarketplaceRemoveTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @configured ~w(owned-config-only owned-combined owned-cold owned-retained)
  @snapshots ~w(owned-snapshot-only owned-combined owned-cold owned-retained)
  @warm_names ~w(owned-config-only owned-snapshot-only owned-combined)

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
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 128, else: 768
      message_limit = if direction == :out, do: 4096, else: 131_072
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 4_194_304 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@provider)) === @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) === @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    base =
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"

    sources =
      Map.new(@configured, fn name ->
        path = Path.join([ctx.root, "marketplace-sources", name])
        write_marketplace(path, name)
        {name, path}
      end)

    fragments =
      Map.new(@configured, fn name ->
        {name,
         "\n[marketplaces.#{name}]\nsource_type = \"local\"\nsource = #{JSON.encode!(sources[name])}\n"}
      end)

    File.write!(config, base <> Enum.map_join(@configured, &fragments[&1]))
    installed = Path.join(ctx.fixture.codex_home, ".tmp/marketplaces")
    for name <- @snapshots, do: write_marketplace(Path.join(installed, name), name)

    paths = [
      @provider,
      __ENV__.file,
      Path.join(ctx.fixture.codex_home, "turn-models.json"),
      ctx.fixture.requests,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex"),
      schema_path("ClientRequest.json"),
      schema_path("v2/MarketplaceRemoveParams.json"),
      schema_path("v2/MarketplaceRemoveResponse.json")
    ]

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    Map.merge(ctx, %{
      capture: capture,
      config: config,
      base: base,
      fragments: fragments,
      installed: installed,
      sources: Map.new(sources, fn {_name, path} -> {path, tree_snapshot(path)} end),
      roots:
        Map.new(@snapshots, fn name -> {name, tree_snapshot(Path.join(installed, name))} end),
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    })
  end

  test "ordinary native marketplace removal changes only selected config and snapshots across cold recovery",
       ctx do
    warm = start(ctx)
    assert_state(ctx, [], warm.pid)

    for {name, id} <- Enum.zip(@warm_names, [-535_710, 535_710, "owned-remove-λ🙂"]) do
      expected_root = if name in @snapshots, do: Path.join(ctx.installed, name), else: nil

      assert remove(ctx, warm.pid, name, id) === %{
               "marketplaceName" => name,
               "installedRoot" => expected_root
             }

      removed = Enum.take(@warm_names, Enum.find_index(@warm_names, &(&1 === name)) + 1)
      assert_state(ctx, removed, warm.pid)
    end

    close(warm)
    assert_state(ctx, @warm_names)
    warm_capture = Agent.get(ctx.capture, & &1)
    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    # The first content query of the fresh process observes no loaded work and
    # leaves the preserved cold candidate byte-identical before explicit removal.
    assert_state(ctx, @warm_names, cold.pid)

    assert remove(ctx, cold.pid, "owned-cold", "owned-remove-cold-雪🙂") === %{
             "marketplaceName" => "owned-cold",
             "installedRoot" => Path.join(ctx.installed, "owned-cold")
           }

    removed = @warm_names ++ ["owned-cold"]
    assert_state(ctx, removed, cold.pid)
    close(cold)
    assert_state(ctx, removed)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    close_provider(ctx)
    assert_state(ctx, removed)
  end

  defp write_marketplace(path, name) do
    File.mkdir_p!(Path.join(path, ".agents/plugins"))

    File.write!(
      Path.join(path, ".agents/plugins/marketplace.json"),
      JSON.encode!(%{"name" => name, "plugins" => []})
    )

    File.write!(Path.join(path, "sentinel.txt"), "Owned marketplace #{name} λ🙂\n")
  end

  defp remove(ctx, pid, name, id) do
    params = %{"marketplaceName" => name}
    assert :ok = Schema.validate(schema("v2/MarketplaceRemoveParams.json"), params, max_depth: 64)
    result = call(ctx, pid, "marketplace/remove", params, id)

    assert :ok =
             Schema.validate(schema("v2/MarketplaceRemoveResponse.json"), result, max_depth: 64)

    result
  end

  defp assert_state(ctx, removed, pid \\ nil) do
    assert_persistence(ctx, removed)
    if pid, do: assert_idle(ctx, pid)
    assert_persistence(ctx, removed)
  end

  defp assert_persistence(ctx, removed) do
    current = snapshot(ctx.config).bytes
    assert String.starts_with?(current, ctx.base)

    for name <- @configured do
      if name in removed,
        do: refute(String.contains?(current, "[marketplaces.#{name}]")),
        else: assert(String.contains?(current, ctx.fragments[name]))
    end

    for name <- @snapshots do
      root = Path.join(ctx.installed, name)

      if name in removed,
        do: refute(File.exists?(root)),
        else: assert(tree_snapshot(root) === ctx.roots[name])
    end

    refute File.exists?(Path.join(ctx.installed, "owned-config-only"))
    refute String.contains?(current, "[marketplaces.owned-snapshot-only]")
    for {path, original} <- ctx.sources, do: assert(tree_snapshot(path) === original)
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp assert_idle(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind === :server_request or method === "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)

    assert {:ok, []} = Session.drain(pid, 256)
  end

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
                      "CODEX_APP_SERVER_CHATGPT_BASE_URL" => ctx.fixture.url,
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_marketplace_remove", "version" => "0.1.0"}
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
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp call(ctx, pid, method, params, id \\ request_id()) do
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)

    assert {:ok, %{"id" => actual_id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert actual_id === id
    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
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
    assert {:os_pid, native} = Port.info(ctx.fixture.port, :os_pid)
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    refute File.exists?("/proc/#{native}")
  end

  defp assert_inventory(ledger) do
    warm =
      ~w(initialize initialized server/diagnostics thread/loaded/list marketplace/remove thread/loaded/list marketplace/remove thread/loaded/list marketplace/remove thread/loaded/list)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list marketplace/remove thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 14 and length(Enum.uniq(ids)) === 14
    assert length(replies) === 14
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
    remove_frames = Enum.filter(requests, &(&1.wire["method"] === "marketplace/remove"))

    assert Enum.map(remove_frames, & &1.wire["id"]) === [
             -535_710,
             535_710,
             "owned-remove-λ🙂",
             "owned-remove-cold-雪🙂"
           ]

    assert Enum.map(remove_frames, & &1.wire["params"]) ===
             Enum.map(@warm_names ++ ["owned-cold"], &%{"marketplaceName" => &1})
  end

  defp tree_snapshot(root) do
    assert File.dir?(root)
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 32

    contents =
      Map.new(Enum.filter(paths, &File.regular?/1), &{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.reduce(contents, 0, fn {_path, saved}, size -> size + byte_size(saved.bytes) end) <=
             1_048_576

    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: contents}
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
    do: "owned-marketplace-remove-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
