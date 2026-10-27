defmodule SamgitaCodexDriver.NativePluginSearchScopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @query "  ORBIT!!!  "
  @global [
    {"global-visible", "ORBIT", []},
    {"orbit-global-prefix", "Independent global prefix", []}
  ]
  @personal [
    {"orbit", "Independent personal exact", []},
    {"personal-keyword", "Independent personal keyword", ["orbit"]}
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

      if selected?(direction, wire) do
        Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
      else
        :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 32 and size <= limit and ledger.bytes + size <= 1_048_576 do
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
    assert hash(File.read!(@provider)) == @provider_sha
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

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nplugins = true\nremote_plugin = false\nplugin_sharing = false\napps = false\nshell_snapshot = false\nmemories = false\n"
    )

    catalogs = Path.join(ctx.root, "catalogs")
    global = catalog(Path.join(catalogs, "global"), "codex-official", @global)
    personal = catalog(Path.join(catalogs, "personal"), "owned-personal-orbit", @personal)

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    Map.merge(ctx, %{
      config: config,
      catalogs: catalogs,
      global: global,
      personal: personal,
      inputs: inputs,
      original_tree: source_tree(catalogs),
      capture: capture
    })
  end

  test "local global and personal discovery follows held and restored source catalogs", ctx do
    warm = start(ctx)
    original = matrix(ctx, warm.pid, true, true)
    assert_sources(ctx)

    with_held(ctx, ctx.global, fn -> matrix(ctx, warm.pid, false, true) end)
    assert matrix(ctx, warm.pid, true, true) === original
    assert_sources(ctx)

    with_held(ctx, ctx.personal, fn -> matrix(ctx, warm.pid, true, false) end)
    assert matrix(ctx, warm.pid, true, true) === original
    assert_retained(ctx, warm.pid)
    close(warm)
    assert_sources(ctx)

    cold = start(ctx)
    assert cold.native != warm.native
    assert matrix(ctx, cold.pid, true, true) === original
    assert_retained(ctx, cold.pid)
    close(cold)
    assert_sources(ctx)
    assert_inventory(ctx)
  end

  defp catalog(root, name, rows) do
    File.mkdir_p!(Path.join(root, ".git"))
    marketplace = Path.join(root, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace))

    plugins =
      for {plugin, _display, _keywords} <- Enum.reverse(rows) do
        %{"name" => plugin, "source" => %{"source" => "local", "path" => "./plugins/#{plugin}"}}
      end

    File.write!(marketplace, JSON.encode!(%{"name" => name, "plugins" => plugins}), [:exclusive])

    for {plugin, display, keywords} <- rows do
      path = Path.join(root, "plugins/#{plugin}/.codex-plugin/plugin.json")
      File.mkdir_p!(Path.dirname(path))

      File.write!(
        path,
        JSON.encode!(%{
          "name" => plugin,
          "description" => "Owned inert catalog metadata",
          "keywords" => keywords,
          "interface" => %{"displayName" => display}
        }),
        [:exclusive]
      )
    end

    %{root: root, name: name, marketplace: marketplace}
  end

  defp matrix(ctx, pid, global_present, personal_present) do
    global = if global_present, do: Enum.map(@global, &candidate(ctx.global, &1)), else: []

    personal =
      if personal_present, do: Enum.map(@personal, &candidate(ctx.personal, &1)), else: []

    union = ranked_union(global, personal)

    for {scope, expected} <- [{"global", global}, {"personal", personal}, {:omitted, union}],
        into: %{} do
      params = %{"searchTerm" => @query, "cwds" => [ctx.global.root, ctx.personal.root]}
      params = if scope == :omitted, do: params, else: Map.put(params, "scope", scope)
      result = call(ctx, pid, "plugin/search", params)
      assert Map.keys(result) |> Enum.sort() == ["data", "nextCursor"]
      assert Map.fetch!(result, "nextCursor") === nil

      # Keep the complete native result and wire capture. This independent
      # candidate projection concerns catalog identity/content, not activation.
      observed = Enum.map(Map.fetch!(result, "data"), &ordinary_candidate/1)
      assert observed === expected
      {scope, result}
    end
  end

  defp ranked_union([global_exact, global_prefix], [personal_exact, personal_keyword]),
    do: [global_exact, personal_exact, global_prefix, personal_keyword]

  defp ranked_union([], personal), do: personal
  defp ranked_union(global, []), do: global

  defp candidate(catalog, {name, display, keywords}) do
    %{
      "marketplaceName" => catalog.name,
      "marketplacePath" => catalog.marketplace,
      "plugin" => %{
        "id" => "#{name}@#{catalog.name}",
        "name" => name,
        "keywords" => keywords,
        "source" => %{"type" => "local", "path" => Path.join(catalog.root, "plugins/#{name}")},
        "interface" => %{"displayName" => display}
      }
    }
  end

  defp ordinary_candidate(row) do
    plugin = Map.fetch!(row, "plugin")

    %{
      "marketplaceName" => Map.fetch!(row, "marketplaceName"),
      "marketplacePath" => Map.fetch!(row, "marketplacePath"),
      "plugin" =>
        plugin
        |> Map.take(["id", "name", "keywords", "source"])
        |> Map.put("interface", Map.take(Map.fetch!(plugin, "interface"), ["displayName"]))
    }
  end

  defp with_held(ctx, catalog, action) do
    held = Path.join(ctx.root, "held-#{catalog.name}-marketplace.json")
    assert :ok = File.rename(catalog.marketplace, held)

    try do
      relative = Path.relative_to(catalog.marketplace, ctx.catalogs)
      original = Map.fetch!(ctx.original_tree.files, relative)
      assert snapshot(held) === original

      expected = %{
        entries: List.delete(ctx.original_tree.entries, relative),
        files: Map.delete(ctx.original_tree.files, relative)
      }

      assert source_tree(ctx.catalogs) === expected
      action.()
      assert source_tree(ctx.catalogs) === expected
      assert snapshot(held) === original
      assert_inputs(ctx.inputs)
    after
      assert :ok = File.rename(held, catalog.marketplace)
    end
  end

  defp start(ctx) do
    session =
      NativeLaunchFixture.local_plugins_after_initialize(ctx.config, fn ->
        start_initialized(ctx)
      end)

    native = call(ctx, session.pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    Map.put(session, :native, native)
  end

  defp start_initialized(ctx) do
    # Keep the existing local-catalog launch pattern: a CLI plugins=false
    # override would prevent query-time discovery after config restoration.
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
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_plugin_search_scope", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    %{pid: pid, connection: connection}
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
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] == wire["id"]))
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() == ["id", "result"]
  end

  defp assert_retained(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert {:ok, []} = Session.drain(pid, 256)

    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil, buffered_events: 0} =
             Session.status(pid)

    assert_sources(ctx)
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    assert File.exists?("/proc/#{session.native}") == false
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    expected =
      ["initialize", "server/diagnostics"] ++
        List.duplicate("plugin/search", 15) ++
        ["thread/loaded/list", "initialize", "server/diagnostics"] ++
        List.duplicate("plugin/search", 3) ++ ["thread/loaded/list"]

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    assert length(ledger.in) == 24
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 24
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_sources(ctx) do
    assert_inputs(ctx.inputs)
    assert source_tree(ctx.catalogs) === ctx.original_tree
    assert File.ls!(ctx.fixture.workspace) == []
    assert Path.wildcard(Path.join(ctx.root, "held-*-marketplace.json")) == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) == []
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp source_tree(root) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 64

    files =
      paths
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.reduce(files, 0, fn {_path, saved}, size -> size + byte_size(saved.bytes) end) <=
             1_048_576

    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: files}
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id,
    do: "owned-plugin-search-scope-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
