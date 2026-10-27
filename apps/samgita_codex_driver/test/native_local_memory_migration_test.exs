defmodule SamgitaCodexDriver.NativeLocalMemoryMigrationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  # Literal EXTENSION_INSTRUCTIONS from pinned external-agent-migration/src/memory_import.rs.
  @instructions_sha "d4ad3f79866e712d390783953470d9d00686ef72fbaddcb8d6706e1753a349e7"
  @memory_a "Owned project A memory λ.\n"
  @topic_a "Owned nested project A evidence.\n"
  @memory_b "Owned project B memory remains at its source.\n"
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
  external_agent_memory_import = true
  memories = false
  shell_snapshot = false
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
        {:ok, next} ->
          case record(next.capture, :out, encoded) do
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

    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 96 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [%{direction: direction, encoded: encoded} | ledger.records]
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
    git = System.find_executable("git") || flunk("BLOCKED_ENV: local Git required")
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python required")

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-memory-migration-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    ownership = :atomics.new(1, [])

    on_exit(fn ->
      assert :atomics.get(ownership, 1) === 0
      File.rm_rf!(root)
    end)

    home = Path.join(root, "home")
    codex = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    cwd_a = Path.join(root, "project-a-cwd")
    cwd_b = Path.join(root, "project-b-cwd")

    for path <- [home, codex, workspace, cwd_a, cwd_b, Path.join(root, "tmp")],
        do: File.mkdir_p!(path)

    source = Path.join(home, ".claude/projects")

    sources = %{
      Path.join(source, "project-a/memory/MEMORY.md") => @memory_a,
      Path.join(source, "project-a/memory/nested/topic.md") => @topic_a,
      Path.join(source, "project-b/memory/MEMORY.md") => @memory_b,
      Path.join(source, "project-a/session.jsonl") => session_source(cwd_a),
      Path.join(source, "project-b/session.jsonl") => session_source(cwd_b),
      Path.join(codex, "config.toml") => @base
    }

    for {path, bytes} <- sources do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
    end

    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    %{
      binary: Path.expand(binary),
      root: root,
      home: home,
      codex: codex,
      workspace: workspace,
      cwd_a: cwd_a,
      git: git,
      python: python,
      sources: sources,
      ownership: ownership,
      capture: capture
    }
  end

  test "native selected memory migration copies scoped evidence and queues without execution across repeat and cold recovery",
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
             "items" => [expected_item(ctx, ["project-a", "project-b"])],
             "connectors" => []
           }

    refute File.exists?(resources(ctx))
    [original] = detected["items"]
    selected = put_in(original, ["details", "memory"], ["project-a"])
    assert selected === expected_item(ctx, ["project-a"])
    first = run_import(ctx, warm.pid, "import-selected", selected)
    assert_destinations(ctx)
    first_db = database(ctx)
    first_queue = assert_database(first_db, [first])
    assert_watermark(first_queue, first)
    assert_remaining(ctx, warm.pid, "detect-remaining")
    first_history = histories(ctx, warm.pid, "warm-history", [first])

    # Explicit reimport is a new history record and another SQL watermark, never execution.
    second = run_import(ctx, warm.pid, "import-repeat", selected)
    refute second["importId"] === first["importId"]
    assert_destinations(ctx)
    second_db = database(ctx)
    second_queue = assert_database(second_db, [first, second])
    {lower, upper} = second["timeBounds"]

    assert second_queue["input_watermark"] >=
             max(div(lower, 1000), first_queue["input_watermark"] + 1)

    assert second_queue["input_watermark"] <=
             max(div(upper, 1000), first_queue["input_watermark"] + 1)

    history = histories(ctx, warm.pid, "repeat-history", [first, second])

    assert Enum.find(history["data"], &(&1["importId"] === first["importId"])) ===
             hd(first_history["data"])

    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, "cold")
    refute cold.native === warm.native
    assert histories(ctx, cold.pid, "cold-history", [first, second]) === history
    assert_remaining(ctx, cold.pid, "detect-cold")
    assert database(ctx) === second_db
    assert_destinations(ctx)
    assert_idle(cold.pid)
    close(cold)
    assert_inventory(ctx)
  end

  defp session_source(cwd) do
    JSON.encode!(%{
      "type" => "user",
      "cwd" => cwd,
      "timestamp" => "2026-07-13T00:00:00Z",
      "message" => %{"content" => "Owned inert scope evidence."}
    }) <> "\n"
  end

  defp expected_item(ctx, projects) do
    %{
      "itemType" => "MEMORY",
      "cwd" => nil,
      "description" =>
        "Import memory files from #{ctx.home}/.claude/projects to #{resources(ctx)}",
      "details" => Map.put(@empty_details, "memory", projects)
    }
  end

  defp assert_remaining(ctx, pid, id) do
    assert request(ctx, pid, id, "externalAgentConfig/detect", @detect) ===
             %{"items" => [expected_item(ctx, ["project-b"])], "connectors" => []}

    assert_sources(ctx)
  end

  defp success(ctx) do
    %{
      "itemType" => "MEMORY",
      "cwd" => nil,
      "source" => "project-a",
      "target" => resources(ctx),
      "title" => nil
    }
  end

  defp run_import(ctx, pid, request_id, item) do
    lower = System.system_time(:millisecond)

    response =
      request(ctx, pid, request_id, "externalAgentConfig/import", %{"migrationItems" => [item]})

    assert %{"importId" => id} = response
    assert Map.keys(response) === ["importId"]
    assert id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    events = collect_completion(pid, id, [], now() + 5_000)
    upper = System.system_time(:millisecond)
    selected = Enum.filter(events, &(&1.wire["params"]["importId"] === id))

    originals =
      Enum.filter(records(ctx), &(&1.direction === :in and &1.wire["params"]["importId"] === id))

    assert Enum.map(selected, & &1.wire) === Enum.map(originals, & &1.wire)
    results = [%{"itemType" => "MEMORY", "successes" => [success(ctx)], "failures" => []}]

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
      "successes" => [success(ctx)],
      "failures" => [],
      "timeBounds" => {lower, upper}
    }
  end

  defp histories(ctx, pid, id, prescribed) do
    response = request(ctx, pid, id, "externalAgentConfig/import/readHistories", nil)
    assert Map.keys(response) |> Enum.sort() === ["connectors", "data"]
    assert response["connectors"] === []
    rows = response["data"]
    assert length(rows) === length(prescribed)

    for expected <- prescribed do
      assert [row] = Enum.filter(rows, &(&1["importId"] === expected["importId"]))
      {lower, upper} = expected["timeBounds"]
      completed = row["completedAtMs"]
      assert is_integer(completed) and lower <= completed and completed <= upper
      assert row === expected |> Map.delete("timeBounds") |> Map.put("completedAtMs", completed)
    end

    assert rows === Enum.sort_by(rows, &{-&1["completedAtMs"], &1["importId"]})
    response
  end

  defp assert_destinations(ctx) do
    target = Path.join(resources(ctx), "project-a")
    assert bounded_file(Path.join(target, "MEMORY.md")) === @memory_a
    assert bounded_file(Path.join(target, "nested/topic.md")) === @topic_a
    assert bounded_file(Path.join(target, "scope.json")) === JSON.encode!(%{"cwd" => ctx.cwd_a})
    assert Enum.sort(File.ls!(target)) === ["MEMORY.md", "nested", "scope.json"]
    assert File.ls!(Path.join(target, "nested")) === ["topic.md"]
    assert File.ls!(resources(ctx)) === ["project-a"]
    instructions = bounded_file(Path.join(Path.dirname(resources(ctx)), "instructions.md"))
    assert byte_size(instructions) === 3163
    assert hash(instructions) === @instructions_sha
    assert_sources(ctx)
  end

  defp database(ctx) do
    # Read only selected native tables with bounded rows; never modify queue state.
    reader = """
    import json, pathlib, sqlite3, sys
    def rows(name, query):
        uri = (pathlib.Path(sys.argv[1]) / name).resolve().as_uri() + '?mode=ro'
        with sqlite3.connect(uri, uri=True, timeout=1) as db:
            db.row_factory = sqlite3.Row
            return [dict(row) for row in db.execute(query).fetchall()]
    # This pin stores memory jobs separately from general import history.
    jobs = rows('memories_1.sqlite', 'SELECT kind, job_key, status, worker_id, ownership_token, started_at, finished_at, lease_until, retry_at, retry_remaining, last_error, input_watermark, last_success_watermark FROM jobs LIMIT 3')
    history = rows('state_5.sqlite', 'SELECT import_id, provider_id, completed_at_ms, successes, failures FROM external_agent_config_imports ORDER BY import_id LIMIT 4')
    print(json.dumps({'jobs': jobs, 'history': history}))
    """

    {encoded, status} =
      System.cmd(ctx.python, ["-B", "-c", reader, ctx.codex], stderr_to_stdout: true)

    assert status === 0, "Owned native SQLite inspection failed: #{encoded}"
    assert byte_size(encoded) <= 16_384
    JSON.decode!(encoded)
  end

  defp assert_database(database, imports) do
    assert [queue] = database["jobs"]

    assert Map.delete(queue, "input_watermark") === %{
             "kind" => "memory_consolidate_global",
             "job_key" => "global",
             "status" => "pending",
             "worker_id" => nil,
             "ownership_token" => nil,
             "started_at" => nil,
             "finished_at" => nil,
             "lease_until" => nil,
             "retry_at" => nil,
             "retry_remaining" => 3,
             "last_error" => nil,
             "last_success_watermark" => 0
           }

    rows = database["history"]
    assert length(rows) === length(imports)

    for expected <- imports do
      assert [row] = Enum.filter(rows, &(&1["import_id"] === expected["importId"]))
      {lower, upper} = expected["timeBounds"]

      assert is_integer(row["completed_at_ms"]) and lower <= row["completed_at_ms"] and
               row["completed_at_ms"] <= upper

      assert row["provider_id"] === nil
      assert JSON.decode!(row["failures"]) === []
      # The native SQLite record uses snake_case independently of public DTOs.
      [wire] = expected["successes"]

      assert JSON.decode!(row["successes"]) === [
               %{
                 "item_type" => "MEMORY",
                 "cwd" => nil,
                 "source" => "project-a",
                 "target" => wire["target"],
                 "title" => nil
               }
             ]
    end

    queue
  end

  defp assert_watermark(queue, imported) do
    {lower, upper} = imported["timeBounds"]
    assert is_integer(queue["input_watermark"])

    assert div(lower, 1000) <= queue["input_watermark"] and
             queue["input_watermark"] <= div(upper, 1000)
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
                      "PATH" => Path.dirname(ctx.git) <> ":/usr/bin:/bin",
                      "GIT_CONFIG_NOSYSTEM" => "1",
                      "GIT_CONFIG_GLOBAL" => "/dev/null",
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
    info = %{"name" => "owned_local_memory_migration", "version" => "0.1.0"}
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
        flunk("Owned local memory import completion deadline")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Owned local memory import event gap")
        after
          10 -> :ok
        end

        collect_completion(pid, id, events, deadline)
    end
  end

  defp assert_idle(pid) do
    assert {:ok, events} = Session.drain(pid, 32)

    refute Enum.any?(events, fn event ->
             event.kind in [:server_request, :unsupported_server_request] or
               event.wire["method"] === "error"
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
             {"import-repeat", "externalAgentConfig/import"},
             {"repeat-history", "externalAgentConfig/import/readHistories"},
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

  defp resources(ctx),
    do: Path.join(ctx.codex, "memories/extensions/external_agent_import/resources")

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
