defmodule SamgitaCodexDriver.NativePluginSearchSourcesTest do
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
  @market "owned-personal-source-descriptors"
  @declared_a [
    {"owned-source-git",
     %{
       "source" => "git-subdir",
       "url" => "  https://catalog.example.invalid/source-a.git  ",
       "path" => "  ./plugins/alpha  ",
       "ref" => "  owned-ref-a  ",
       "sha" => "  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  "
     }},
    {"owned-source-npm",
     %{
       "source" => "npm",
       "package" => "  @fixture/ordinary-search  ",
       "version" => "  ^1.2.0  ",
       "registry" => "  https://registry.example.invalid/  "
     }}
  ]
  @declared_b [
    {"owned-source-git",
     %{"source" => "url", "url" => "https://catalog.example.invalid/source-b.git"}},
    {"owned-source-npm", %{"source" => "npm", "package" => "fixture-ordinary-search-alt"}}
  ]
  # Complete independent native source oracles. These are not computed by
  # normalizing declarations or reading an observed native response.
  @expected_a [
    {"owned-source-git",
     %{
       "type" => "git",
       "url" => "https://catalog.example.invalid/source-a.git",
       "path" => "plugins/alpha",
       "refName" => "owned-ref-a",
       "sha" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
     }},
    {"owned-source-npm",
     %{
       "type" => "npm",
       "package" => "@fixture/ordinary-search",
       "version" => "^1.2.0",
       "registry" => "https://registry.example.invalid/"
     }}
  ]
  @expected_b [
    {"owned-source-git",
     %{
       "type" => "git",
       "url" => "https://catalog.example.invalid/source-b.git",
       "path" => nil,
       "refName" => nil,
       "sha" => nil
     }},
    {"owned-source-npm",
     %{
       "type" => "npm",
       "package" => "fixture-ordinary-search-alt",
       "version" => nil,
       "registry" => nil
     }}
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
      case JSON.decode(encoded) do
        {:ok, wire} ->
          if selected?(direction, wire),
            do: Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire)),
            else: :ok

        {:error, _} ->
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
        next =
          ledger
          |> Map.put(direction, entries ++ [%{encoded: encoded, wire: wire}])
          |> Map.put(:bytes, ledger.bytes + size)

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

    catalog = Path.join(ctx.root, "owned-source-catalog λ")
    File.mkdir_p!(Path.join(catalog, ".git"))
    marketplace = Path.join(catalog, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace))
    original = marketplace_bytes(@declared_a)
    File.write!(marketplace, original, [:exclusive])
    held = Path.join(ctx.root, "held-source-descriptors-marketplace.json")

    on_exit(fn ->
      replace_file!(marketplace, original)
      File.rm(held)
    end)

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
      catalog: catalog,
      marketplace: marketplace,
      original: original,
      held: held,
      inputs: inputs,
      original_tree: source_tree(catalog),
      capture: capture
    })
  end

  test "native plugin search preserves declared Git and npm descriptors across source changes",
       ctx do
    warm = start(ctx)
    assert_unloaded(ctx, warm.pid)
    search_twice(ctx, warm.pid, @expected_a, ctx.original_tree)

    try do
      changed = marketplace_bytes(@declared_b)
      replace_file!(ctx.marketplace, changed)
      search_twice(ctx, warm.pid, @expected_b, marketplace_tree(ctx, changed))
    after
      replace_file!(ctx.marketplace, ctx.original)
    end

    search_twice(ctx, warm.pid, @expected_a, ctx.original_tree)

    with_held_marketplace(ctx, fn tree ->
      absent = Enum.map(@expected_a, fn {name, _source} -> {name, :absent} end)
      search_twice(ctx, warm.pid, absent, tree)
    end)

    search_twice(ctx, warm.pid, @expected_a, ctx.original_tree)
    assert_unloaded(ctx, warm.pid)
    assert_quiet(ctx, warm.pid, ctx.original_tree)
    close(warm)
    assert_sources(ctx, ctx.original_tree)

    cold = start(ctx)
    assert cold.native != warm.native
    assert_unloaded(ctx, cold.pid)
    search_twice(ctx, cold.pid, @expected_a, ctx.original_tree)
    assert_unloaded(ctx, cold.pid)
    assert_quiet(ctx, cold.pid, ctx.original_tree)
    close(cold)
    assert_sources(ctx, ctx.original_tree)
    assert_inventory(ctx)
  end

  defp marketplace_bytes(declarations) do
    JSON.encode!(%{
      "name" => @market,
      "plugins" =>
        Enum.map(declarations, fn {name, source} -> %{"name" => name, "source" => source} end)
    })
  end

  defp marketplace_tree(ctx, contents) do
    relative = Path.relative_to(ctx.marketplace, ctx.catalog)

    %{
      ctx.original_tree
      | files: Map.put(ctx.original_tree.files, relative, saved_bytes(contents))
    }
  end

  defp search_twice(ctx, pid, sources, tree) do
    for {name, source} <- sources, _ <- 1..2 do
      assert_sources(ctx, tree)

      result =
        call(ctx, pid, "plugin/search", %{
          "searchTerm" => name,
          "scope" => "personal",
          "cwds" => [ctx.catalog]
        })

      assert Map.keys(result) |> Enum.sort() == ["data", "nextCursor"]
      assert Map.fetch!(result, "nextCursor") === nil
      assert ordinary_result(result) === expected_result(ctx, name, source)
      assert_quiet(ctx, pid, tree)
    end
  end

  defp ordinary_result(result) do
    %{
      "data" =>
        Enum.map(Map.fetch!(result, "data"), fn row ->
          assert Map.keys(row) |> Enum.sort() == ["marketplaceName", "marketplacePath", "plugin"]

          %{
            "marketplaceName" => Map.fetch!(row, "marketplaceName"),
            "marketplacePath" => Map.fetch!(row, "marketplacePath"),
            "plugin" => Map.take(Map.fetch!(row, "plugin"), ["id", "name", "source"])
          }
        end),
      "nextCursor" => Map.fetch!(result, "nextCursor")
    }
  end

  defp expected_result(_ctx, _name, :absent), do: %{"data" => [], "nextCursor" => nil}

  defp expected_result(ctx, name, source) do
    %{
      "data" => [
        %{
          "marketplaceName" => @market,
          "marketplacePath" => ctx.marketplace,
          "plugin" => %{"id" => "#{name}@#{@market}", "name" => name, "source" => source}
        }
      ],
      "nextCursor" => nil
    }
  end

  defp with_held_marketplace(ctx, action) do
    assert :ok = File.rename(ctx.marketplace, ctx.held)

    try do
      relative = Path.relative_to(ctx.marketplace, ctx.catalog)

      tree = %{
        entries: List.delete(ctx.original_tree.entries, relative),
        files: Map.delete(ctx.original_tree.files, relative)
      }

      assert snapshot(ctx.held) === saved_bytes(ctx.original)
      action.(tree)
      assert snapshot(ctx.held) === saved_bytes(ctx.original)
      assert_sources(ctx, tree)
    after
      assert :ok = File.rename(ctx.held, ctx.marketplace)
    end
  end

  defp replace_file!(path, contents) do
    temporary = path <> ".owned-plugin-sources-#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, contents, [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp start(ctx) do
    assert_sources(ctx, ctx.original_tree)

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
    # Preserve query-time local discovery after the supported startup helper
    # restores the owned configuration; no permanent plugins=false override.
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
    info = %{"name" => "owned_plugin_search_sources", "version" => "0.1.0"}
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

    case Session.request_native(pid, wire, timeout_ms: 5_000) do
      {:ok, %{"id" => ^id, "result" => result} = response} ->
        assert_exchange(ctx, wire, response)
        result

      other ->
        flunk("Native #{method} did not succeed: #{inspect(upstream_summary(other))}")
    end
  end

  defp upstream_summary({:error, %SamgitaProtocolCodex.Error{wire: wire}}) when is_map(wire),
    do: wire |> Map.get("error", %{}) |> Map.take(["code", "message"])

  defp upstream_summary(_reply), do: :unexpected_reply

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

  defp assert_unloaded(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
  end

  defp assert_quiet(ctx, pid, tree) do
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert Session.uncertain_operations(pid) == []
    assert Session.interaction_outcomes(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or method == "error" or
               String.starts_with?(method, "thread/") or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/") or String.starts_with?(method, "hook/") or
               String.starts_with?(method, "plugin/")
           end)

    assert_sources(ctx, tree)
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    expected =
      ["initialize", "server/diagnostics", "thread/loaded/list"] ++
        List.duplicate("plugin/search", 20) ++
        ["thread/loaded/list", "initialize", "server/diagnostics", "thread/loaded/list"] ++
        List.duplicate("plugin/search", 4) ++ ["thread/loaded/list"]

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    assert length(ledger.in) == 32
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 32
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_sources(ctx, tree) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert source_tree(ctx.catalog) === tree
    assert File.ls!(ctx.fixture.workspace) == []
    assert ModelFixture.requests(ctx.fixture) == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) == []
    if tree === ctx.original_tree, do: refute(File.exists?(ctx.held))
  end

  defp source_tree(root) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 16
    for path <- paths, do: assert(File.lstat!(path).type in [:regular, :directory])

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
    saved_bytes(File.read!(path))
  end

  defp saved_bytes(bytes) do
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id,
    do: "owned-plugin-search-sources-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
