defmodule SamgitaCodexDriver.NativePersistedMcpVariantsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, thread: 3, start_turn: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @scripts Path.expand("../../../scripts/codex", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @call_id "interaction-call-1"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert binary_hash(binary) == @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-result-variants-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")

    System.put_env(
      "CODEX_MODEL_FIXTURE_SCRIPT",
      Path.join(@scripts, "mcp_result_variants_fixture.py")
    )

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # LIFO cleanup closes the native group/stdio peer, provider, then scratch root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    assert ModelFixture.requests(fixture) == []
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture, scenario: tags[:scenario]}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  @tag scenario: "structured_success"
  test "non-null MCP structured content and metadata survive the first cold selective read",
       ctx do
    run_variant(
      ctx,
      "completed",
      %{
        "content" => [%{"type" => "text", "text" => "Owned MCP structured success λ"}],
        "structuredContent" => %{"ok" => true, "count" => 3, "labels" => ["blue", "λ"]},
        "_meta" => %{
          "fixture/result" => %{"variant" => "structured_success", "sequence" => 1},
          "fixture/opaque" => ["λ", nil, 17]
        }
      },
      false
    )
  end

  @tag scenario: "tool_error"
  test "actual MCP isError gives a failed result with metadata through first cold history", ctx do
    run_variant(
      ctx,
      "failed",
      %{
        "content" => [%{"type" => "text", "text" => "Owned MCP tool failure λ"}],
        "structuredContent" => %{"ok" => false, "reason" => "owned-declined", "codes" => [7, 9]},
        "_meta" => %{
          "fixture/result" => %{"variant" => "tool_error", "sequence" => 1},
          "fixture/opaque" => ["λ", nil, 17]
        }
      },
      true
    )
  end

  defp run_variant(ctx, status, result, is_error) do
    pid = start(ctx)
    native_pid = assert_native(pid)
    id = thread(ctx, pid, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    before_ms = System.system_time(:millisecond)

    turn =
      start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned MCP result variant only"},
        %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
      ])

    events = collect(pid, turn, [], System.monotonic_time(:millisecond) + 15_000)
    after_ms = System.system_time(:millisecond)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert Session.interaction_outcomes(pid) == []
    assert_idle(pid)
    started = mcp_notification(events, "item/started")
    completed = mcp_notification(events, "item/completed")
    started_at_ms = Map.fetch!(started, "startedAtMs")
    completed_at_ms = Map.fetch!(completed, "completedAtMs")
    duration_ms = Map.fetch!(completed["item"], "durationMs")
    assert is_integer(started_at_ms) and is_integer(completed_at_ms)
    assert before_ms <= started_at_ms and started_at_ms <= completed_at_ms
    assert completed_at_ms <= after_ms
    assert is_integer(duration_ms) and duration_ms >= 0
    assert duration_ms <= after_ms - before_ms + 1

    # Only generated timing comes from the observed item. Every semantic field
    # is an independent literal in the test, separate from the peer implementation.
    expected = %{
      "id" => @call_id,
      "type" => "mcpToolCall",
      "server" => "fixture",
      "tool" => "confirm",
      "arguments" => %{},
      "status" => status,
      "readOnlyHint" => true,
      "appContext" => nil,
      "mcpAppUi" => nil,
      "pluginId" => nil,
      "error" => nil,
      "durationMs" => duration_ms,
      "result" => result
    }

    expected_started =
      Map.merge(expected, %{"status" => "inProgress", "durationMs" => nil, "result" => nil})

    assert started === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected_started,
             "startedAtMs" => started_at_ms
           }

    assert completed === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completed_at_ms
           }

    requests = assert_provider(ctx, result)
    rows = journal(ctx)
    peer_pid = assert_peer(ctx, rows, native_pid, result, is_error)

    effects = fn ->
      assert ModelFixture.requests(ctx.fixture) === requests
      assert journal(ctx) === rows
      assert File.ls!(ctx.fixture.workspace) == []
    end

    effects.()

    # Producer/store barrier is allowed only on the warm process.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [@call_id]}

    expected_direct = %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => expected,
          "startedAtMs" => started_at_ms,
          "completedAtMs" => completed_at_ms
        }
      ]
    }

    warm = call(pid, "thread/items/read", query)
    assert warm === expected_direct
    assert_selection(pid, query, expected_direct)
    effects.()
    close_owned(pid)
    assert_gone(native_pid)
    assert_gone(peer_pid)
    effects.()

    cold = start(ctx)
    refute cold == pid
    cold_native_pid = assert_native(cold)
    refute cold_native_pid == native_pid
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    effects.()

    # The first content read in this genuinely new native process is selective
    # history. No resume, thread/read hydration, new turn or execution is allowed.
    persisted = call(cold, "thread/items/read", query)
    assert persisted === expected_direct
    assert persisted === warm
    assert_selection(cold, query, expected_direct)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    effects.()
    assert_idle(cold)
    close_owned(cold)
    assert_gone(cold_native_pid)
    assert_gone(peer_pid)
    effects.()
  end

  defp assert_provider(ctx, expected_result) do
    assert [first, continued] = requests = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"
    assert outputs(first) == []
    assert [output] = outputs(continued)
    assert output["call_id"] == @call_id

    # The pin deliberately selects structuredContent for the model-facing
    # continuation; the item still retains the independent text content/_meta.
    assert is_binary(output["output"])
    assert [header, encoded] = String.split(output["output"], "\nOutput:\n", parts: 2)
    assert Regex.match?(~r/^Wall time: [0-9]+\.[0-9]{4} seconds$/, header)
    assert JSON.decode!(encoded) === expected_result["structuredContent"]
    requests
  end

  defp outputs(request),
    do: Enum.filter(request["input"], &(&1["type"] == "function_call_output"))

  defp assert_peer(ctx, rows, native_pid, result, is_error) do
    assert [peer] = for(%{"peer_started" => peer} <- rows, do: peer)
    peer_pid = peer["pid"]
    assert is_integer(peer_pid) and peer_pid > 0 and peer_pid != native_pid
    assert is_integer(peer["parent_pid"]) and peer["parent_pid"] > 0
    assert peer["variant"] == ctx.scenario
    assert File.dir?("/proc/#{peer_pid}")
    assert descendant?(peer_pid, native_pid, 16)
    assert File.read!("/proc/#{peer_pid}/cmdline") =~ "mcp_result_variants_fixture.py"

    assert [initialize] = messages(rows, "in", "initialize")
    assert initialize["params"]["protocolVersion"] == "2025-06-18"
    assert messages(rows, "in", "server/discover") == []
    assert [_] = messages(rows, "in", "tools/list")
    assert [call] = messages(rows, "in", "tools/call")
    assert call["params"]["name"] == "confirm"
    assert call["params"]["arguments"] === %{}

    assert [reply] =
             for(
               %{"direction" => "out", "message" => message} <- rows,
               message["id"] == call["id"],
               do: message
             )

    assert reply === %{
             "jsonrpc" => "2.0",
             "id" => call["id"],
             "result" => Map.put(result, "isError", is_error)
           }

    assert [%{"effect" => "tool-call-observed", "variant" => ctx.scenario, "sequence" => 1}] ===
             Enum.filter(rows, &Map.has_key?(&1, "effect"))

    peer_pid
  end

  defp descendant?(_pid, _ancestor, 0), do: false
  defp descendant?(pid, pid, _remaining), do: true

  defp descendant?(pid, ancestor, remaining) when pid > 1 do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} ->
        [_, parent] = Regex.run(~r/^\d+ \(.*\) \S+ (\d+) /, stat)
        descendant?(String.to_integer(parent), ancestor, remaining - 1)

      {:error, :enoent} ->
        false
    end
  end

  defp descendant?(_pid, _ancestor, _remaining), do: false

  defp messages(rows, direction, method) do
    for %{"direction" => ^direction, "message" => %{"method" => ^method} = message} <- rows,
        do: message
  end

  defp journal(ctx) do
    ctx.fixture.codex_home
    |> Path.join("mcp-result-variants.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end

  defp mcp_notification(events, method) do
    assert [params] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["id"] == @call_id,
               do: event.wire["params"]
             )

    params
  end

  defp assert_selection(pid, query, expected) do
    assert call(
             pid,
             "thread/items/read",
             Map.put(query, "itemIds", [@call_id, @call_id, "owned-absent-item"])
           ) === expected

    assert call(pid, "thread/items/read", Map.put(query, "itemIds", ["owned-absent-item"])) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", Map.put(query, "turnId", "owned-absent-turn")) ===
             %{"data" => []}
  end

  defp collect(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)

    refute Enum.any?(incoming, &(&1.kind == :server_request)),
           "Unexpected native interaction; the owned MCP peer requires no approval"

    events = events ++ incoming

    if notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, turn, events, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected MCP variant event gap")
      after
        remaining -> flunk("MCP variant deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_native(pid) do
    native_pid = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native_pid) and native_pid > 0
    assert binary_hash("/proc/#{native_pid}/exe") == @binary_sha256
    native_pid
  end

  defp binary_hash(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp assert_gone(native_pid, remaining \\ 100) do
    if File.exists?("/proc/#{native_pid}") do
      assert remaining > 0, "Owned process #{native_pid} survived session cleanup"
      Process.sleep(10)
      assert_gone(native_pid, remaining - 1)
    else
      :ok
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_persisted_mcp_variants", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
  end
end
