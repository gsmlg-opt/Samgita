defmodule SamgitaCodexDriver.NativeLocalPluginMigrationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @base """
  check_for_update_on_startup = false
  [memories]
  generate_memories = false
  use_memories = false
  [analytics]
  enabled = false
  [otel]
  exporter = "none"
  trace_exporter = "none"
  metrics_exporter = "none"
  [features]
  apps = false
  plugins = false
  remote_plugin = false
  recommended_plugins = false
  memories = false
  shell_snapshot = false
  [desktop]
  ordinary_migration_marker = "kept"
  """
  @empty_details %{
    "plugins" => [],
    "skills" => [],
    "sessions" => [],
    "mcpServers" => [],
    "hooks" => [],
    "subagents" => [],
    "commands" => []
  }
  @market "owned-migration-market"
  @plugin_a "owned-alpha"
  @plugin_b "owned-beta"
  @version "2.4.1"
  @detect %{"includeHome" => true, "maxSessionAgeDays" => 0, "maxSessions" => 0}

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
      case record(state.capture, :out, encoded) do
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
      case Enum.reduce_while(events, :ok, &record_event(&1, &2, state.capture)) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Keep original framed payloads before Session decoding, including notices.
    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 96 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
          entry = %{direction: direction, encoded: encoded}

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

    assert hash(File.read!(binary)) === @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-migration-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    ownership = :atomics.new(1, [])

    on_exit(fn ->
      assert :atomics.get(ownership, 1) === 0
      File.rm_rf!(root)
    end)

    home = Path.join(root, "home")
    codex = Path.join(root, "codex")
    market = Path.join(home, ".claude/local-market")

    for directory <- [home, codex, Path.join(root, "workspace"), Path.join(root, "tmp")],
        do: File.mkdir_p!(directory)

    settings = %{
      "enabledPlugins" => %{"#{@plugin_a}@#{@market}" => true, "#{@plugin_b}@#{@market}" => true},
      "extraKnownMarketplaces" => %{@market => %{"source" => "directory", "path" => market}}
    }

    marketplace = %{
      "name" => @market,
      "plugins" => [
        %{"name" => @plugin_a, "source" => "./plugins/#{@plugin_a}"},
        %{"name" => @plugin_b, "source" => "./plugins/#{@plugin_b}"}
      ]
    }

    sources =
      %{
        Path.join(home, ".claude/settings.json") => JSON.encode!(settings),
        Path.join(market, ".claude-plugin/marketplace.json") => JSON.encode!(marketplace)
      }
      |> Map.merge(plugin_files(market, @plugin_a, "A"))
      |> Map.merge(plugin_files(market, @plugin_b, "B"))

    for {path, bytes} <- sources do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
    end

    config_path = Path.join(codex, "config.toml")
    File.write!(config_path, @base, [:exclusive])
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    %{
      binary: Path.expand(binary),
      root: root,
      home: home,
      codex: codex,
      workspace: Path.join(root, "workspace"),
      config_path: config_path,
      market: market,
      sources: sources,
      ownership: ownership,
      capture: capture
    }
  end

  test "native local plugin migration installs only the selected name and retains the remaining candidate cold",
       ctx do
    warm = start(ctx, "warm")

    assert request(
             ctx,
             warm.pid,
             "initial-history",
             "externalAgentConfig/import/readHistories",
             nil
           ) ===
             %{"data" => [], "connectors" => []}

    detected = request(ctx, warm.pid, "detect-both", "externalAgentConfig/detect", @detect)

    assert detected === %{
             "items" => [expected_item(ctx, [@plugin_a, @plugin_b])],
             "connectors" => []
           }

    assert File.read!(ctx.config_path) === @base
    refute File.exists?(Path.join(ctx.codex, "plugins/cache/#{@market}"))

    # These names drive the pinned installation loop. Preserve every other field
    # of the actual detected item while deliberately selecting A alone.
    [original] = detected["items"]

    selected =
      put_in(original, ["details", "plugins"], [
        %{"marketplaceName" => @market, "pluginNames" => [@plugin_a]}
      ])

    assert selected === expected_item(ctx, [@plugin_a])
    history_row = run_import(ctx, warm.pid, selected)
    saved = assert_destinations(ctx)

    assert request(ctx, warm.pid, "detect-remaining", "externalAgentConfig/detect", @detect) ===
             %{"items" => [expected_item(ctx, [@plugin_b])], "connectors" => []}

    history = histories(ctx, warm.pid, "warm-history", history_row)
    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, "cold")
    refute cold.native === warm.native
    assert histories(ctx, cold.pid, "cold-history", history_row) === history

    assert request(ctx, cold.pid, "detect-cold", "externalAgentConfig/detect", @detect) ===
             %{"items" => [expected_item(ctx, [@plugin_b])], "connectors" => []}

    assert assert_destinations(ctx) === saved
    assert_sources(ctx)
    assert_idle(cold.pid)
    close(cold)
    assert_inventory(ctx)
  end

  defp plugin_files(market, name, label) do
    %{
      Path.join(market, "plugins/#{name}/.codex-plugin/plugin.json") =>
        JSON.encode!(%{
          "name" => name,
          "version" => @version,
          "description" => "Owned inert plugin #{label}"
        }),
      Path.join(market, "plugins/#{name}/skills/owned-#{label}/SKILL.md") =>
        "---\nname: owned-#{String.downcase(label)}-skill\ndescription: Owned inert migration #{label}\n---\nOwned fixture metadata #{label} λ.\n"
    }
  end

  defp expected_item(ctx, names) do
    %{
      "itemType" => "PLUGINS",
      "description" => "Migrate enabled plugins from #{ctx.home}/.claude/settings.json",
      "cwd" => nil,
      "details" =>
        Map.put(@empty_details, "plugins", [
          %{"marketplaceName" => @market, "pluginNames" => names}
        ])
    }
  end

  defp run_import(ctx, pid, item) do
    lower = System.system_time(:millisecond)

    response =
      request(ctx, pid, "import-selected", "externalAgentConfig/import", %{
        "migrationItems" => [item]
      })

    assert %{"importId" => id} = response
    assert id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    events = collect_completion(pid, id, [], now() + 5_000)
    upper = System.system_time(:millisecond)
    selected = Enum.filter(events, &(&1.wire["params"]["importId"] === id))

    originals =
      Enum.filter(records(ctx), &(&1.direction === :in and &1.wire["params"]["importId"] === id))

    assert Enum.map(selected, & &1.wire) === Enum.map(originals, & &1.wire)

    success = %{
      "itemType" => "PLUGINS",
      "cwd" => nil,
      "source" => "#{@plugin_a}@#{@market}",
      "target" => "#{@plugin_a}@#{@market}",
      "title" => nil
    }

    results = [%{"itemType" => "PLUGINS", "successes" => [success], "failures" => []}]

    assert Enum.map(selected, &{&1.wire["method"], &1.wire["params"]}) === [
             {"externalAgentConfig/import/progress",
              %{"importId" => id, "itemTypeResults" => results}},
             {"externalAgentConfig/import/completed",
              %{"importId" => id, "itemTypeResults" => results}}
           ]

    assert Enum.all?(selected, &(&1.kind === :notification))
    assert_sources(ctx)

    %{
      "importId" => id,
      "providerId" => nil,
      "successes" => [success],
      "failures" => [],
      "timeBounds" => {lower, upper}
    }
  end

  defp histories(ctx, pid, id, prescribed) do
    response = request(ctx, pid, id, "externalAgentConfig/import/readHistories", nil)
    assert %{"data" => [row], "connectors" => []} = response
    {lower, upper} = prescribed["timeBounds"]
    completed = Map.fetch!(row, "completedAtMs")
    assert is_integer(completed) and lower <= completed and completed <= upper
    expected = prescribed |> Map.delete("timeBounds") |> Map.put("completedAtMs", completed)
    assert row === expected
    response
  end

  defp assert_destinations(ctx) do
    config_bytes = bounded_file(ctx.config_path)
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3.11+ required")

    reader = """
    import json, sys, tomllib
    with open(sys.argv[1], "rb") as source:
        print(json.dumps(tomllib.load(source), ensure_ascii=False))
    """

    {encoded, status} =
      System.cmd(python, ["-B", "-c", reader, ctx.config_path], stderr_to_stdout: true)

    assert status === 0, "Owned destination TOML parsing failed: #{encoded}"
    assert byte_size(encoded) <= 32_768
    config = JSON.decode!(encoded)
    assert config["plugins"] === %{"#{@plugin_a}@#{@market}" => %{"enabled" => true}}
    assert config["features"]["plugins"] === false
    assert config["desktop"] === %{"ordinary_migration_marker" => "kept"}

    assert Map.take(config["marketplaces"][@market], ["source", "source_type"]) ===
             %{"source" => ctx.market, "source_type" => "local"}

    installed = Path.join(ctx.codex, "plugins/cache/#{@market}/#{@plugin_a}/#{@version}")

    expected_files = %{
      Path.join(installed, ".codex-plugin/plugin.json") =>
        JSON.encode!(%{
          "name" => @plugin_a,
          "version" => @version,
          "description" => "Owned inert plugin A"
        }),
      Path.join(installed, "skills/owned-A/SKILL.md") =>
        "---\nname: owned-a-skill\ndescription: Owned inert migration A\n---\nOwned fixture metadata A λ.\n"
    }

    for {path, expected} <- expected_files, do: assert(bounded_file(path) === expected)
    assert Enum.sort(File.ls!(Path.join(ctx.codex, "plugins/cache/#{@market}"))) === [@plugin_a]
    assert File.ls!(Path.join(ctx.codex, "plugins/cache/#{@market}/#{@plugin_a}")) === [@version]
    refute File.exists?(Path.join(ctx.codex, "plugins/cache/#{@market}/#{@plugin_b}"))
    assert_sources(ctx)
    Map.put(expected_files, ctx.config_path, config_bytes)
  end

  defp start(ctx, label) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 32,
               max_event_bytes: 131_072,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.home,
                      "CODEX_HOME" => ctx.codex,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(2, [])
    :atomics.add(ctx.ownership, 1, 1)
    on_exit(fn -> cleanup(ctx, pid, connection, identity) end)
    id = label <> "-initialize"
    info = %{"name" => "owned_local_plugin_migration", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native =
      request(ctx, pid, label <> "-diagnostics", "server/diagnostics", %{})["process"]["id"]

    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    assert_sources(ctx)
    %{pid: pid, connection: connection, identity: identity, native: native, ctx: ctx}
  end

  defp request(ctx, pid, id, method, params) do
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent, received] = Enum.filter(records(ctx), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and sent.encoded === JSON.encode!(wire)
    assert sent.wire === wire
    assert received.direction === :in and received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp records(ctx) do
    ctx.capture
    |> Agent.get(&Enum.reverse(&1.records))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp collect_completion(pid, id, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 32)
    events = events ++ incoming
    assert length(events) <= 32
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 131_072
    refute Enum.any?(events, &(&1.kind in [:server_request, :unsupported_server_request]))

    cond do
      Enum.any?(
        events,
        &(&1.wire["method"] === "externalAgentConfig/import/completed" and
              &1.wire["params"]["importId"] === id)
      ) ->
        events

      now() >= deadline ->
        flunk("Owned local plugin import completion deadline")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Owned local plugin import event gap")
        after
          10 -> :ok
        end

        collect_completion(pid, id, events, deadline)
    end
  end

  defp assert_idle(pid) do
    assert {:ok, events} = Session.drain(pid, 32)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""
             event.kind in [:server_request, :unsupported_server_request] or method === "error"
           end)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp assert_inventory(ctx) do
    outbound = Enum.filter(records(ctx), &(&1.direction === :out and Map.has_key?(&1.wire, "id")))

    assert Enum.map(outbound, &{&1.wire["id"], &1.wire["method"]}) === [
             {"warm-initialize", "initialize"},
             {"warm-diagnostics", "server/diagnostics"},
             {"initial-history", "externalAgentConfig/import/readHistories"},
             {"detect-both", "externalAgentConfig/detect"},
             {"import-selected", "externalAgentConfig/import"},
             {"detect-remaining", "externalAgentConfig/detect"},
             {"warm-history", "externalAgentConfig/import/readHistories"},
             {"cold-initialize", "initialize"},
             {"cold-diagnostics", "server/diagnostics"},
             {"cold-history", "externalAgentConfig/import/readHistories"},
             {"detect-cold", "externalAgentConfig/detect"}
           ]

    refute Enum.any?(records(ctx), fn record ->
             method = record.wire["method"] || ""

             String.starts_with?(method, "thread/") or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_sources(ctx)
  end

  defp assert_sources(ctx) do
    for {path, expected} <- ctx.sources, do: assert(bounded_file(path) === expected)
    assert File.ls!(ctx.workspace) === []
  end

  defp bounded_file(path) do
    assert File.stat!(path).size <= 16_384
    File.read!(path)
  end

  defp close(session), do: cleanup(session.ctx, session.pid, session.connection, session.identity)

  defp cleanup(ctx, pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
    assert_sources(ctx)

    if :atomics.compare_exchange(identity, 2, 0, 1) === :ok,
      do: :atomics.sub(ctx.ownership, 1, 1)
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
