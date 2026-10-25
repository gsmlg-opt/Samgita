defmodule SamgitaCodexDriver.NativeSubagentActivityTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("support/native_subagent_activity_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @spawn "owned-v39-spawn-activity"
  @wait "owned-v39-wait-activity"
  @child_path "/root/activity_child"
  @root_marker "OWNED_ACTIVITY_ROOT_V39"
  @child_marker "OWNED_ACTIVITY_CHILD_V39"

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

    TurnFixture.configure_model(ctx, %{
      "multi_agent_version" => "v2",
      "supported_reasoning_levels" => [
        %{"effort" => "medium", "description" => "Owned synthetic medium effort"}
      ],
      "default_reasoning_level" => "medium"
    })

    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  test "native v2 Started and Completed activity preserves exact items across first cold selection",
       ctx do
    pid = start(ctx)
    warm_instance = Session.status(pid).instance_id
    %{connection: warm_connection} = :sys.get_state(pid)
    root = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    assert File.ls!(ctx.fixture.workspace) == []
    assert ModelFixture.requests(ctx.fixture) == []
    before_turn = System.system_time(:millisecond)

    turn =
      TurnFixture.start_turn(
        pid,
        root,
        [%{"type" => "text", "text" => @root_marker}],
        %{"effort" => "medium"}
      )

    events = TurnFixture.finish_turn(pid, root, turn)
    after_turn = System.system_time(:millisecond)
    requests = ModelFixture.requests(ctx.fixture)
    assert_provider(ctx, requests)
    assert_idle(pid)
    assert File.ls!(ctx.fixture.workspace) == []

    # Independent native management/history responses resolve generated identities.
    # Neither activity.agentThreadId nor activity.id supplies its own expectation.
    page =
      call(pid, "thread/list", %{
        "parentThreadId" => root,
        "sortKey" => "created_at",
        "limit" => 100,
        "useStateDbOnly" => true
      })

    assert [child] = page["data"]
    assert page["nextCursor"] == nil
    child_id = child["id"]
    assert is_binary(child_id) and byte_size(child_id) > 0 and child_id != root
    assert child["parentThreadId"] == root
    assert child["forkedFromId"] == nil
    assert child["cwd"] == ctx.fixture.workspace
    assert child["modelProvider"] == "fixture"

    assert %{"subAgent" => %{"thread_spawn" => source}} = child["source"]
    assert source["parent_thread_id"] == root
    assert source["depth"] == 1
    assert source["agent_path"] == @child_path

    child_history = call(pid, "thread/read", %{"threadId" => child_id, "includeTurns" => true})
    assert child_history["thread"]["id"] == child_id
    assert [%{"id" => child_turn, "status" => "completed"}] = child_history["thread"]["turns"]
    assert is_binary(child_turn) and byte_size(child_turn) > 0

    expected_started = %{
      "type" => "subAgentActivity",
      "id" => @spawn,
      "kind" => "started",
      "agentThreadId" => child_id,
      "agentPath" => @child_path,
      "model" => "mock-model",
      "reasoningEffort" => "medium"
    }

    expected_completed = %{
      "type" => "subAgentActivity",
      "id" => "subagent-completed-" <> child_turn,
      "kind" => "completed",
      "agentThreadId" => child_id,
      "agentPath" => @child_path,
      "model" => nil,
      "reasoningEffort" => nil
    }

    activities =
      Enum.filter(events, fn event ->
        get_in(event.wire, ["params", "item", "type"]) == "subAgentActivity"
      end)

    assert Enum.map(activities, &{&1.wire["method"], &1.wire["params"]["item"]["kind"]}) ==
             [
               {"item/started", "started"},
               {"item/completed", "started"},
               {"item/started", "completed"},
               {"item/completed", "completed"}
             ]

    expected =
      for item <- [expected_started, expected_completed] do
        activity_entry(events, root, turn, item, before_turn, after_turn)
      end

    root_completed =
      Enum.find_index(events, fn event ->
        event.wire["method"] == "turn/completed" and
          event.wire["params"]["threadId"] == root and
          event.wire["params"]["turn"]["id"] == turn
      end)

    last_activity = Enum.find_index(events, &(&1 == List.last(activities)))
    assert is_integer(root_completed) and is_integer(last_activity)
    assert last_activity < root_completed

    # This full read is a producer/store barrier, never the expected-item oracle.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => root, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{
      "threadId" => root,
      "turnId" => turn,
      "itemIds" => [expected_completed["id"], @spawn]
    }

    assert_selection(pid, query, expected)
    assert_provider(ctx, requests)
    assert File.ls!(ctx.fixture.workspace) == []
    warm_native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(warm_native) and warm_native > 0
    assert :ok = StdioSessionFixture.close(pid, warm_connection)
    refute File.exists?("/proc/#{warm_native}")

    cold = start(ctx)
    %{connection: cold_connection} = :sys.get_state(cold)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(cold_native) and cold_native > 0 and cold_native != warm_native
    refute Session.status(cold).instance_id == warm_instance
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # First content operation in this distinct native process is selective.
    assert_selection(cold, query, expected)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert {:ok, remaining} = Session.drain(cold)

    refute Enum.any?(remaining, fn event ->
             event.kind == :server_request or
               event.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ]
           end)

    assert_provider(ctx, requests)
    assert File.ls!(ctx.fixture.workspace) == []
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    refute File.exists?("/proc/#{cold_native}")
    assert ModelFixture.requests(ctx.fixture) == requests
  end

  defp activity_entry(events, root, turn, expected, before_turn, after_turn) do
    params = fn method ->
      for event <- events,
          event.wire["method"] == method,
          get_in(event.wire, ["params", "item", "id"]) == expected["id"],
          do: event.wire["params"]
    end

    assert [started] = params.("item/started")
    assert [completed] = params.("item/completed")
    started_at = Map.fetch!(started, "startedAtMs")
    completed_at = Map.fetch!(completed, "completedAtMs")
    assert is_integer(started_at) and is_integer(completed_at)
    assert before_turn <= started_at and started_at <= completed_at and completed_at <= after_turn

    assert started === %{
             "threadId" => root,
             "turnId" => turn,
             "item" => expected,
             "startedAtMs" => started_at
           }

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

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === %{"data" => expected}

    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => ["owned-absent-activity", @spawn, @spawn, hd(query["itemIds"])]
           }) === %{"data" => expected}

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-activity"]}) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-turn"}) ===
             %{"data" => []}

    assert_idle(pid)
  end

  defp assert_provider(ctx, expected_requests) do
    requests = ModelFixture.requests(ctx.fixture)
    assert requests === expected_requests
    assert length(requests) == 4

    observed = ctx.root |> Path.join("activity-observed.json") |> File.read!() |> JSON.decode!()

    assert observed === %{
             "root_requests" => 3,
             "child_requests" => 1,
             "responses" => ["spawn", "wait", "child_final", "root_final"],
             "errors" => []
           }

    for request <- requests do
      assert request["model"] == "mock-model"
      assert request["reasoning"]["effort"] == "medium"
    end

    root_requests =
      Enum.filter(requests, fn request ->
        Enum.any?(request["input"], fn item ->
          item["role"] == "user" and
            Enum.any?(Map.get(item, "content", []), &(&1["text"] == @root_marker))
        end)
      end)

    assert length(root_requests) == 3
    assert [child_request] = requests -- root_requests

    assert [message] =
             Enum.filter(child_request["input"], fn item ->
               item["type"] == "agent_message" and item["author"] == "/root" and
                 item["recipient"] == @child_path
             end)

    assert message["content"] === [
             %{
               "type" => "input_text",
               "text" =>
                 "Message Type: NEW_TASK\nTask name: /root/activity_child\nSender: /root\nPayload:\n" <>
                   @child_marker
             }
           ]

    outputs =
      for request <- root_requests,
          item <- request["input"],
          item["type"] == "function_call_output",
          do: {item["call_id"], JSON.decode!(item["output"])}

    assert Enum.uniq(outputs) |> Enum.sort() ==
             Enum.sort([
               {@spawn, %{"task_name" => @child_path}},
               {@wait, %{"message" => "Wait completed.", "timed_out" => false}}
             ])
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert Session.interaction_outcomes(pid) == []
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "samgita_owned_activity", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
