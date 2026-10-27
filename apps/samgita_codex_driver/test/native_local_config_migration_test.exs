defmodule SamgitaCodexDriver.NativeLocalConfigMigrationTest do
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
        "owned-local-migration-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    ownership = :atomics.new(1, [])

    on_exit(fn ->
      assert :atomics.get(ownership, 1) === 0
      File.rm_rf!(root)
    end)

    for directory <- ~w(home home/.claude home/.claude/hooks codex workspace tmp),
        do: File.mkdir_p!(Path.join(root, directory))

    marker = Path.join(root, "unexpected-command-invocation")
    inert = "#!/bin/sh\nprintf 'unexpected invocation\\n' >> '#{marker}'\nexit 0\n"
    home = Path.join(root, "home")
    codex = Path.join(root, "codex")
    mcp_script = Path.join(home, "mcp-inert.sh")
    hook_script = Path.join(home, ".claude/hooks/local-check.sh")

    servers = %{
      "owned_alpha" => %{"command" => "/bin/sh", "args" => [mcp_script, "alpha"]},
      "owned_beta" => %{"command" => "/bin/sh", "args" => [mcp_script, "beta"]}
    }

    settings = %{
      "hooks" => %{
        "PreCompact" => [
          %{
            "hooks" => [
              %{
                "type" => "command",
                "command" => "/bin/sh .claude/hooks/local-check.sh",
                "timeoutSec" => 5,
                "statusMessage" => "Owned compact λ"
              }
            ]
          }
        ],
        "Stop" => [
          %{
            "hooks" => [
              %{"type" => "command", "command" => "/bin/sh .claude/hooks/local-check.sh"}
            ]
          }
        ]
      }
    }

    sources = %{
      mcp_script => inert,
      hook_script => inert,
      Path.join(home, ".mcp.json") => JSON.encode!(%{"mcpServers" => servers}),
      Path.join(home, ".claude/settings.json") => JSON.encode!(settings)
    }

    for {path, body} <- sources, do: File.write!(path, body, [:exclusive])
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
      marker: marker,
      mcp_script: mcp_script,
      hook_script: hook_script,
      sources: sources,
      ownership: ownership,
      capture: capture
    }
  end

  test "native local hook and MCP configuration imports persist named results and record empty repeats",
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

    detected = request(ctx, warm.pid, "detect-first", "externalAgentConfig/detect", @detect)
    assert detected === %{"items" => expected_items(ctx), "connectors" => []}
    items = Map.fetch!(detected, "items")

    assert File.read!(ctx.config_path) === @base
    refute File.exists?(Path.join(ctx.codex, "hooks.json"))
    assert_sources(ctx)
    expected_results = expected_results()
    first = run_import(ctx, warm.pid, "first", items, expected_results)
    saved = assert_destinations(ctx)

    assert request(ctx, warm.pid, "detect-after", "externalAgentConfig/detect", @detect) ===
             %{"items" => [], "connectors" => []}

    # Source-pinned no-op semantics: original items still produce two empty
    # groups and a NEW durable import/history record, not zero import activity.
    empty = for type <- ["MCP_SERVER_CONFIG", "HOOKS"], do: result(type, [])
    repeated = run_import(ctx, warm.pid, "repeat", items, empty)
    refute repeated["importId"] === first["importId"]
    assert assert_destinations(ctx) === saved
    history = histories(ctx, warm.pid, "warm-history", [first, repeated])
    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, "cold")
    refute cold.native === warm.native
    assert histories(ctx, cold.pid, "cold-history", [first, repeated]) === history

    assert request(ctx, cold.pid, "detect-cold", "externalAgentConfig/detect", @detect) ===
             %{"items" => [], "connectors" => []}

    assert assert_destinations(ctx) === saved
    assert_sources(ctx)
    assert_idle(cold.pid)
    close(cold)
    assert_inventory(ctx)
  end

  defp expected_items(ctx) do
    [
      %{
        "itemType" => "MCP_SERVER_CONFIG",
        "description" => "Migrate MCP servers from #{ctx.home} into #{ctx.config_path}",
        "cwd" => nil,
        "details" =>
          Map.put(@empty_details, "mcpServers", [
            %{"name" => "owned_alpha"},
            %{"name" => "owned_beta"}
          ])
      },
      %{
        "itemType" => "HOOKS",
        "description" => "Migrate hooks from #{ctx.home}/.claude to #{ctx.codex}/hooks.json",
        "cwd" => nil,
        "details" =>
          Map.put(@empty_details, "hooks", [%{"name" => "PreCompact"}, %{"name" => "Stop"}])
      }
    ]
  end

  defp expected_results do
    [
      result("MCP_SERVER_CONFIG", [
        success("MCP_SERVER_CONFIG", "owned_alpha"),
        success("MCP_SERVER_CONFIG", "owned_beta")
      ]),
      result("HOOKS", [success("HOOKS", "PreCompact"), success("HOOKS", "Stop")])
    ]
  end

  defp result(type, successes),
    do: %{"itemType" => type, "successes" => successes, "failures" => []}

  defp success(type, name),
    do: %{"itemType" => type, "cwd" => nil, "source" => name, "target" => name, "title" => nil}

  defp run_import(ctx, pid, label, items, expected) do
    lower = System.system_time(:millisecond)
    params = %{"migrationItems" => items}
    response = request(ctx, pid, "import-" <> label, "externalAgentConfig/import", params)
    assert %{"importId" => id} = response
    assert id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    events = collect_completion(pid, id, [], now() + 5_000)
    upper = System.system_time(:millisecond)
    selected = Enum.filter(events, &(&1.wire["params"]["importId"] === id))

    originals =
      Enum.filter(records(ctx), &(&1.direction === :in and &1.wire["params"]["importId"] === id))

    assert Enum.map(selected, & &1.wire) === Enum.map(originals, & &1.wire)

    expected_notices = [
      {"externalAgentConfig/import/progress",
       %{"importId" => id, "itemTypeResults" => [Enum.at(expected, 0)]}},
      {"externalAgentConfig/import/progress",
       %{"importId" => id, "itemTypeResults" => [Enum.at(expected, 1)]}},
      {"externalAgentConfig/import/completed", %{"importId" => id, "itemTypeResults" => expected}}
    ]

    assert Enum.map(selected, &{&1.wire["method"], &1.wire["params"]}) === expected_notices
    assert Enum.all?(selected, &(&1.kind === :notification))
    assert_sources(ctx)

    %{
      "importId" => id,
      "providerId" => nil,
      "successes" => Enum.flat_map(expected, & &1["successes"]),
      "failures" => [],
      "timeBounds" => {lower, upper}
    }
  end

  defp histories(ctx, pid, id, expected) do
    response = request(ctx, pid, id, "externalAgentConfig/import/readHistories", nil)
    assert %{"data" => rows, "connectors" => []} = response
    assert length(rows) === length(expected)

    for prescribed <- expected do
      assert [row] = Enum.filter(rows, &(&1["importId"] === prescribed["importId"]))
      {lower, upper} = prescribed["timeBounds"]
      completed = Map.fetch!(row, "completedAtMs")
      assert is_integer(completed) and lower <= completed and completed <= upper
      expected_row = prescribed |> Map.delete("timeBounds") |> Map.put("completedAtMs", completed)
      assert row === expected_row
    end

    response
  end

  defp assert_destinations(ctx) do
    config = bounded_file(ctx.config_path)
    assert config =~ "ordinary_migration_marker = \"kept\""
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3.11+ required")

    # Native writes pretty TOML with multiline arrays, not one JSON value per
    # line. Parse the complete real file with the standard TOML implementation.
    reader = """
    import json, sys, tomllib
    with open(sys.argv[1], "rb") as source:
        print(json.dumps(tomllib.load(source), ensure_ascii=False))
    """

    {encoded, status} =
      System.cmd(python, ["-B", "-c", reader, ctx.config_path], stderr_to_stdout: true)

    assert status === 0, "Owned destination TOML parsing failed: #{encoded}"

    assert JSON.decode!(encoded)["mcp_servers"] === %{
             "owned_alpha" => %{"command" => "/bin/sh", "args" => [ctx.mcp_script, "alpha"]},
             "owned_beta" => %{"command" => "/bin/sh", "args" => [ctx.mcp_script, "beta"]}
           }

    hooks_path = Path.join(ctx.codex, "hooks.json")
    hooks = bounded_file(hooks_path)
    rewritten = "/bin/sh '#{ctx.codex}/hooks/local-check.sh'"

    assert JSON.decode!(hooks) === %{
             "hooks" => %{
               "PreCompact" => [
                 %{
                   "hooks" => [
                     %{
                       "type" => "command",
                       "command" => rewritten,
                       "timeout" => 5,
                       "statusMessage" => "Owned compact λ"
                     }
                   ]
                 }
               ],
               "Stop" => [%{"hooks" => [%{"type" => "command", "command" => rewritten}]}]
             }
           }

    copied_path = Path.join(ctx.codex, "hooks/local-check.sh")
    copied = bounded_file(copied_path)
    assert copied === Map.fetch!(ctx.sources, ctx.hook_script)
    assert_sources(ctx)
    %{ctx.config_path => config, hooks_path => hooks, copied_path => copied}
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
    info = %{"name" => "owned_local_config_migration", "version" => "0.1.0"}
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
        flunk("Owned local config import completion deadline")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Owned local config import event gap")
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
             {"detect-first", "externalAgentConfig/detect"},
             {"import-first", "externalAgentConfig/import"},
             {"detect-after", "externalAgentConfig/detect"},
             {"import-repeat", "externalAgentConfig/import"},
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
    refute File.exists?(ctx.marker)
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
