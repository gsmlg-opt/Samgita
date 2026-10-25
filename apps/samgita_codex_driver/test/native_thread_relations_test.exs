defmodule SamgitaCodexDriver.NativeThreadRelationsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/thread_relation_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @missing "00000000-0000-0000-0000-000000000000"

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{"multi_agent_version" => "v1"})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  test "real native spawn edges distinguish direct children and recursive descendants across restart",
       ctx do
    pid = start(ctx)
    unrelated = complete(ctx, pid, "OWNED_RELATION_UNRELATED")
    root = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    before_turn = System.system_time(:millisecond)

    turn =
      TurnFixture.start_turn(pid, root, [%{"type" => "text", "text" => "OWNED_RELATION_ROOT"}])

    events = TurnFixture.finish_turn(pid, root, turn)
    after_turn = System.system_time(:millisecond)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 11
    a = spawned_id(requests, "relation-spawn-a")
    b = spawned_id(requests, "relation-spawn-b")
    g = spawned_id(requests, "relation-spawn-g")
    assert MapSet.size(MapSet.new([root, a, b, g, unrelated])) == 5
    assert_spawn_event(events, "relation-spawn-a", root, a, "OWNED_RELATION_CHILD_A")
    assert_spawn_event(events, "relation-spawn-b", root, b, "OWNED_RELATION_CHILD_B")

    expected_waits =
      for {call_id, child, message} <- [
            {"relation-wait-a", a, "Owned relation a done"},
            {"relation-wait-b", b, "Owned relation b done"}
          ] do
        wait_entry(events, root, turn, call_id, child, message, before_turn, after_turn)
      end

    # The full read is only the producer/store barrier. Wait payloads above are
    # prescribed independently from the fixed child responses and native IDs.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => root, "includeTurns" => true})["thread"][
               "turns"
             ]

    wait_query = %{
      "threadId" => root,
      "turnId" => turn,
      "itemIds" => ["relation-wait-b", "relation-wait-a"]
    }

    assert_wait_selection(pid, wait_query, expected_waits)
    assert ModelFixture.requests(ctx.fixture) == requests
    parents = %{a => {root, 1}, b => {root, 1}, g => {a, 2}}
    direct = %{"parentThreadId" => root}
    recursive = %{"ancestorThreadId" => root}

    assert_ids(list(pid, direct), [b, a])
    assert_ids(list(pid, recursive), [b, g, a])
    assert_ids(list(pid, %{"parentThreadId" => a}), [g])
    assert_ids(list(pid, %{"ancestorThreadId" => a}), [g])

    for selector <- [direct, recursive] do
      for row <- list(pid, selector)["data"] do
        {parent, depth} = Map.fetch!(parents, row["id"])
        assert row["parentThreadId"] == parent
        assert row["modelProvider"] == "fixture"
        assert row["cwd"] == ctx.fixture.workspace
        assert %{"subAgent" => %{"thread_spawn" => source}} = row["source"]
        assert source["parent_thread_id"] == parent
        assert source["depth"] == depth
        assert row["forkedFromId"] == nil
      end
    end

    for selector <- [direct, recursive] do
      for direction <- ["asc", "desc"] do
        expected = if selector == direct, do: [a, b], else: [a, g, b]
        expected = if direction == "asc", do: expected, else: Enum.reverse(expected)
        assert pages(pid, Map.put(selector, "sortDirection", direction)) == expected
      end
    end

    # Omitted sources on a relation query include the real spawned source. An
    # explicit empty filter restores interactive sources, excluding all children.
    for selector <- [direct, recursive] do
      expected = if selector == direct, do: [b, a], else: [b, g, a]

      for kinds <- [nil, ["subAgent"], ["subAgentThreadSpawn"]] do
        assert_ids(list(pid, Map.put(selector, "sourceKinds", kinds)), expected)
      end

      assert_ids(list(pid, Map.put(selector, "sourceKinds", [])), [])
      assert_ids(list(pid, Map.put(selector, "sourceKinds", ["vscode"])), [])
      assert_ids(list(pid, Map.put(selector, "modelProviders", ["owned-absent"])), [])
    end

    assert_ids(list(pid, %{"parentThreadId" => g}), [])
    assert_ids(list(pid, %{"ancestorThreadId" => g}), [])
    assert_ids(list(pid, %{"parentThreadId" => unrelated}), [])
    assert_ids(list(pid, %{"ancestorThreadId" => @missing}), [])
    assert_ids(list(pid, %{"parentThreadId" => nil}), [root, unrelated])
    assert_ids(list(pid, %{"ancestorThreadId" => nil}), [root, unrelated])

    assert_ids(list(pid, Map.merge(recursive, %{"limit" => 2, "excludedThreadIds" => [b]})), [
      g,
      a
    ])

    baseline = durable(list(pid, recursive))
    native_pid = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native_pid}")
    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_pid
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    # First content operation in the distinct native process is selective.
    assert_wait_selection(cold, wait_query, expected_waits)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert durable(list(cold, recursive)) == baseline
    assert_ids(list(cold, direct), [b, a])
    assert pages(cold, Map.put(recursive, "sortDirection", "asc")) == [a, g, b]
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == requests
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(cold)
  end

  test "invalid relation selectors and disabled experimental negotiation create no native work",
       ctx do
    pid = start(ctx)

    for {key, prefix} <- [
          {"parentThreadId", "invalid parent thread id:"},
          {"ancestorThreadId", "invalid ancestor thread id:"}
        ] do
      error = upstream_error(pid, "thread/list", %{key => "not-a-thread-id"})
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], prefix)
      error = upstream_error(pid, "thread/list", %{key => 17}, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
    end

    assert upstream_error(pid, "thread/list", %{
             "parentThreadId" => @missing,
             "ancestorThreadId" => @missing
           }) == %{
             "code" => -32_600,
             "message" => "parentThreadId and ancestorThreadId are mutually exclusive"
           }

    assert :ok = Session.close(pid)
    stable = start(ctx, false)

    for key <- ["parentThreadId", "ancestorThreadId"] do
      error = upstream_error(stable, "thread/list", %{key => @missing}, validation: :wire)
      assert error["code"] == -32_600
      assert error["message"] =~ "thread/list.#{key} requires experimentalApi capability"
    end

    assert call(stable, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp complete(ctx, pid, text) do
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    TurnFixture.finish_turn(pid, id, turn)
    id
  end

  defp wait_entry(events, root, turn, call_id, child, message, before_turn, after_turn) do
    expected = %{
      "id" => call_id,
      "type" => "collabAgentToolCall",
      "tool" => "wait",
      "status" => "completed",
      "senderThreadId" => root,
      "receiverThreadIds" => [child],
      "prompt" => nil,
      "model" => nil,
      "reasoningEffort" => nil,
      "agentsStates" => %{child => %{"status" => "completed", "message" => message}}
    }

    params = fn method ->
      for event <- events,
          event.wire["method"] == method,
          event.wire["params"]["item"]["id"] == call_id,
          do: event.wire["params"]
    end

    assert [started] = params.("item/started")
    assert [completed] = params.("item/completed")
    assert started["threadId"] == root and started["turnId"] == turn
    started_at = Map.fetch!(started, "startedAtMs")
    completed_at = Map.fetch!(completed, "completedAtMs")
    assert is_integer(started_at) and is_integer(completed_at)
    assert before_turn <= started_at and started_at <= completed_at and completed_at <= after_turn

    assert completed === %{
             "threadId" => root,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completed_at
           }

    %{
      "turnId" => turn,
      "item" => expected,
      "startedAtMs" => started_at,
      "completedAtMs" => completed_at
    }
  end

  defp assert_wait_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === %{"data" => expected}

    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => [
                 "owned-absent-wait",
                 "relation-wait-b",
                 "relation-wait-a",
                 "relation-wait-a"
               ]
           }) === %{"data" => expected}

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-wait"]}) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-turn"}) ===
             %{"data" => []}

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
  end

  defp spawned_id(requests, call_id) do
    outputs =
      for request <- requests,
          item <- request["input"],
          item["type"] == "function_call_output" and item["call_id"] == call_id,
          do: JSON.decode!(item["output"])

    assert [value] = Enum.uniq(outputs)
    assert is_binary(value["agent_id"])
    value["agent_id"]
  end

  defp assert_spawn_event(events, id, parent, child, prompt) do
    item = TurnFixture.notification(events, "item/completed", &(&1["item"]["id"] == id))
    assert item["threadId"] == parent

    assert %{
             "id" => ^id,
             "type" => "collabAgentToolCall",
             "tool" => "spawnAgent",
             "status" => "completed",
             "senderThreadId" => ^parent,
             "receiverThreadIds" => [^child],
             "prompt" => ^prompt
           } = item["item"]
  end

  defp pages(pid, params) do
    pages(pid, Map.put(params, "limit", 1), [], MapSet.new())
  end

  defp pages(pid, params, acc, seen) do
    page = list(pid, params)
    rows = Enum.map(page["data"], & &1["id"])
    assert length(rows) <= 1
    assert length(acc) + length(rows) <= 3
    assert MapSet.disjoint?(MapSet.new(rows), MapSet.new(acc))

    case Map.fetch!(page, "nextCursor") do
      nil ->
        acc ++ rows

      cursor ->
        assert is_binary(cursor)
        assert rows != []
        refute MapSet.member?(seen, cursor)
        pages(pid, Map.put(params, "cursor", cursor), acc ++ rows, MapSet.put(seen, cursor))
    end
  end

  defp list(pid, extra),
    do:
      call(
        pid,
        "thread/list",
        Map.merge(
          %{"sortKey" => "created_at", "limit" => 100, "useStateDbOnly" => true},
          extra
        )
      )

  defp assert_ids(page, expected) do
    assert Enum.map(page["data"], & &1["id"]) == expected
    assert Map.fetch!(page, "nextCursor") == nil
  end

  defp durable(page),
    do:
      Enum.map(
        page["data"],
        &Map.take(
          &1,
          ["id", "parentThreadId", "forkedFromId", "source", "cwd", "modelProvider", "createdAt"]
        )
      )

  defp start(ctx, experimental \\ true) do
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
               %{"name" => "samgita_owned_relations", "version" => "0.1.0"},
               %{"experimentalApi" => experimental}
             )

    pid
  end
end
