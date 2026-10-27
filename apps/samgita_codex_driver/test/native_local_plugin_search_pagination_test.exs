defmodule SamgitaCodexDriver.NativeLocalPluginSearchPaginationTest do
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
  @market "owned-pagination-local"
  @query "  OWNED PAGINATION MARKER!!!  "
  @keyword "owned pagination marker"
  @rows (for index <- 1..18 do
           suffix = String.pad_leading(Integer.to_string(index), 2, "0")
           {"owned-page-#{suffix}", "Owned local candidate #{suffix}", [@keyword]}
         end)

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
        {:ok, next} -> record_sent(next, encoded)
        other -> other
      end
    end

    defp record_sent(state, encoded) do
      case record(state, :out, encoded) do
        :ok -> {:ok, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} -> record_received(next, events)
        other -> other
      end
    end

    defp record_received(state, events) do
      case record_events(state, events) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
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

      if selected?(direction, wire),
        do: Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire)),
        else: :ok
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
    catalog = catalog(Path.join(catalogs, "personal"))
    expected = Map.new(@rows, &{candidate_id(&1), candidate(catalog, &1)})
    assert map_size(expected) == 18

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
      catalog: catalog,
      expected: expected,
      inputs: inputs,
      original_tree: source_tree(catalogs),
      capture: capture
    })
  end

  test "local plugin first pages retain all matches across cursor and remote-limit defaults",
       ctx do
    warm = start(ctx)

    for {extra, expected} <- warm_cases(ctx) do
      search(ctx, warm.pid, extra, expected)
      assert_sources(ctx)
    end

    with_held_marketplace(ctx, fn -> search(ctx, warm.pid, %{}, %{}) end)
    search(ctx, warm.pid, %{}, ctx.expected)
    assert_retained(ctx, warm.pid)
    close(warm)
    assert_sources(ctx)

    cold = start(ctx)
    assert cold.native != warm.native
    search(ctx, cold.pid, %{}, ctx.expected)
    search(ctx, cold.pid, %{"cursor" => ""}, %{})
    search(ctx, cold.pid, %{"cursor" => nil}, ctx.expected)
    assert_retained(ctx, cold.pid)
    close(cold)
    assert_sources(ctx)
    assert_inventory(ctx)
  end

  # Requested limits belong to the native remote query. Eighteen matching
  # local rows distinguish their behavior from that remote default of sixteen.
  defp warm_cases(ctx) do
    [
      {%{}, ctx.expected},
      {%{"cursor" => nil}, ctx.expected},
      {%{"limit" => nil}, ctx.expected},
      {%{"limit" => 0}, ctx.expected},
      {%{"limit" => 1}, ctx.expected},
      {%{"limit" => 17}, ctx.expected},
      {%{"limit" => 1001}, ctx.expected},
      {%{"cursor" => ""}, %{}},
      {%{"cursor" => "owned-next"}, %{}}
    ]
  end

  defp catalog(root) do
    File.mkdir_p!(Path.join(root, ".git"))
    marketplace = Path.join(root, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace))

    plugins =
      for {name, _display, _keywords} <- Enum.reverse(@rows),
          do: %{"name" => name, "source" => %{"source" => "local", "path" => "./plugins/#{name}"}}

    File.write!(marketplace, JSON.encode!(%{"name" => @market, "plugins" => plugins}), [
      :exclusive
    ])

    for {name, display, keywords} <- @rows do
      path = Path.join(root, "plugins/#{name}/.codex-plugin/plugin.json")
      File.mkdir_p!(Path.dirname(path))

      File.write!(
        path,
        JSON.encode!(%{
          "name" => name,
          "description" => "Owned inert local pagination metadata",
          "keywords" => keywords,
          "interface" => %{"displayName" => display}
        }),
        [:exclusive]
      )
    end

    %{root: root, marketplace: marketplace}
  end

  defp candidate_id({name, _display, _keywords}), do: "#{name}@#{@market}"

  defp candidate(catalog, {name, display, keywords} = row) do
    %{
      "marketplaceName" => @market,
      "marketplacePath" => catalog.marketplace,
      "plugin" => %{
        "id" => candidate_id(row),
        "name" => name,
        "keywords" => keywords,
        "source" => %{"type" => "local", "path" => Path.join(catalog.root, "plugins/#{name}")},
        "interface" => %{"displayName" => display}
      }
    }
  end

  defp ordinary_candidate(row) do
    assert Map.keys(row) |> Enum.sort() == ["marketplaceName", "marketplacePath", "plugin"]
    plugin = Map.fetch!(row, "plugin")

    %{
      "marketplaceName" => Map.fetch!(row, "marketplaceName"),
      "marketplacePath" => Map.fetch!(row, "marketplacePath"),
      "plugin" => %{
        "id" => Map.fetch!(plugin, "id"),
        "name" => Map.fetch!(plugin, "name"),
        "keywords" => Map.fetch!(plugin, "keywords"),
        "source" => Map.fetch!(plugin, "source"),
        "interface" => Map.take(Map.fetch!(plugin, "interface"), ["displayName"])
      }
    }
  end

  defp search(ctx, pid, extra, expected) do
    params =
      Map.merge(
        %{"searchTerm" => @query, "scope" => "personal", "cwds" => [ctx.catalog.root]},
        extra
      )

    result = call(ctx, pid, "plugin/search", params)
    assert Map.keys(result) |> Enum.sort() == ["data", "nextCursor"]
    assert Map.fetch!(result, "nextCursor") === nil
    rows = Map.fetch!(result, "data")
    assert length(rows) == map_size(expected)
    candidates = Enum.map(rows, &ordinary_candidate/1)
    ids = Enum.map(candidates, &get_in(&1, ["plugin", "id"]))
    assert length(Enum.uniq(ids)) == length(ids)

    # All authored matches have the same native keyword rank. Compare the
    # complete ordinary projection by identity, without inventing a tie order.
    assert Map.new(Enum.zip(ids, candidates)) === expected
  end

  defp with_held_marketplace(ctx, action) do
    held = Path.join(ctx.root, "held-pagination-marketplace.json")
    marketplace = ctx.catalog.marketplace
    assert :ok = File.rename(marketplace, held)

    try do
      relative = Path.relative_to(marketplace, ctx.catalogs)
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
      assert :ok = File.rename(held, marketplace)
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
    info = %{"name" => "owned_local_plugin_search_pagination", "version" => "0.1.0"}
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
    assert Enum.all?(events, &(&1.kind == :notification))
    assert {:ok, []} = Session.drain(pid, 256)

    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil,
             buffered_events: 0
           } = Session.status(pid)

    assert_sources(ctx)
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    expected =
      ["initialize", "server/diagnostics"] ++
        List.duplicate("plugin/search", 11) ++
        ["thread/loaded/list", "initialize", "server/diagnostics"] ++
        List.duplicate("plugin/search", 3) ++ ["thread/loaded/list"]

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    assert length(ledger.in) == 20
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 20
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_sources(ctx) do
    assert_inputs(ctx.inputs)
    assert source_tree(ctx.catalogs) === ctx.original_tree
    assert File.ls!(ctx.fixture.workspace) == []
    refute File.exists?(Path.join(ctx.root, "held-pagination-marketplace.json"))
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
    do: "owned-local-plugin-search-pagination-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
