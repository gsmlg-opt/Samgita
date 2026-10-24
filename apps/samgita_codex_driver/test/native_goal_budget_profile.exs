defmodule SamgitaCodexDriver.NativeGoalBudgetProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_goal_budget_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @objective "Owned synthetic continuation accounting; preserve the objective until the token budget stops work."
  @first "Owned synthetic first goal turn recorded."
  @final "Owned synthetic budget run stopped with the objective retained."
  @call_id "owned-active-goal-read-1"

  setup tags do
    scenario = tags[:scenario] || "budget"
    request_budget = if scenario == "quota", do: 1, else: 3
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-gb-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary), "--scenario", scenario],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{
      root: root,
      owner: owner,
      socket: Path.join(root, "native.sock"),
      request_budget: request_budget
    }

    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]
    assert [ready] = journal(ctx, "bem-journal.json", "goal_provider_ready")
    assert ready["request_budget"] == request_budget and ready["source_provider_requests"] == 0
    assert ready["request_auth"] == "none"

    assert ready["output"] ==
             if(scenario == "quota",
               do: "http429_insufficient_quota",
               else: "fixed_assistant_get_goal_assistant"
             )

    config = File.read!(Path.join(root, "codex/config.toml"))

    for setting <- [
          "goals = true",
          "max_goal_token_budget = 20",
          "requires_openai_auth = false",
          "supports_websockets = false",
          "request_max_retries = 0",
          "stream_max_retries = 0",
          "enable_request_compression = false",
          "shell_tool = false",
          "unified_exec = false",
          "shell_snapshot = false",
          "plugins = false",
          "apps = false",
          "hooks = false",
          "[analytics]\nenabled = false",
          "cli_auth_credentials_store = \"file\""
        ] do
      assert config =~ setting
    end

    refute config =~ "experimental_bearer_token"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    ctx
  end

  test "native goal schedules two turns, accounts cached tokens and cold-restores a budget stop",
       ctx do
    pid = connect(ctx)

    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert_uuid(id)
    assert call(pid, "thread/goal/get", %{"threadId" => id}) == %{"goal" => nil}
    assert json(ctx, "requests.json") == []
    timing = %{wall: System.system_time(:second), mono: System.monotonic_time(:millisecond)}

    # This single user mutation is the only execution trigger. No client turn/start,
    # tool response, interrupt, or budgetLimited write occurs anywhere in this profile.
    assert %{"goal" => initial} =
             call(pid, "thread/goal/set", %{
               "threadId" => id,
               "objective" => @objective,
               "status" => "active",
               "tokenBudget" => 20,
               "origin" => "user"
             })

    assert_goal(initial, id, "active", 0, initial["createdAt"], timing, 0)
    assert initial["timeUsedSeconds"] == 0

    execution = collect(pid, &finished?/1)
    [first_turn, second_turn] = assert_lifecycle(execution, id)
    assert_goal_notices(execution, id, initial, first_turn, second_turn, timing)
    assert_provider(ctx, id, first_turn, second_turn, initial, timing)

    assert %{"goal" => final} = call(pid, "thread/goal/get", %{"threadId" => id})
    assert_goal(final, id, "budgetLimited", 21, initial["createdAt"], timing, 1)

    assert Enum.any?(
             notices(execution, "thread/goal/updated"),
             &(&1 == %{
                 "threadId" => id,
                 "turnId" => second_turn,
                 "goal" => final
               })
           )

    history = turns(pid, id)
    assert_history(history, first_turn, second_turn)
    assert_idle(pid, id)
    assert_quiet(ctx, pid)

    cold = restart(ctx, pid)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert call(cold, "thread/goal/get", %{"threadId" => id}) == %{"goal" => final}
    assert turns(cold, id) == history
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_quiet(ctx, cold)

    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert call(cold, "thread/goal/get", %{"threadId" => id}) == %{"goal" => final}
    assert turns(cold, id) == history
    assert_idle(cold, id)
    assert_quiet(ctx, cold)
    finish(ctx, cold)
  end

  @tag scenario: "quota"
  test "native quota failure stops an active goal and cold resume cannot retry it", ctx do
    pid = connect(ctx)

    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert_uuid(id)
    assert call(pid, "thread/goal/get", %{"threadId" => id}) == %{"goal" => nil}
    assert json(ctx, "goal-attempts.json") == 0
    assert json(ctx, "requests.json") == []
    assert json(ctx, "goal-http.json") == []
    timing = %{wall: System.system_time(:second), mono: System.monotonic_time(:millisecond)}

    assert %{"goal" => initial} =
             call(pid, "thread/goal/set", %{
               "threadId" => id,
               "objective" => @objective,
               "status" => "active",
               "tokenBudget" => 20,
               "origin" => "user"
             })

    assert_goal(initial, id, "active", 0, initial["createdAt"], timing, 0)

    events =
      collect(pid, fn seen ->
        length(notices(seen, "turn/completed")) == 1 and
          Enum.any?(
            notices(seen, "thread/goal/updated"),
            &(&1["goal"]["status"] == "usageLimited")
          )
      end)

    turn = assert_quota_lifecycle(events, id)
    assert %{"goal" => final} = call(pid, "thread/goal/get", %{"threadId" => id})
    assert_goal(final, id, "usageLimited", 0, initial["createdAt"], timing, 0)
    updates = notices(events, "thread/goal/updated")
    assert %{"threadId" => id, "turnId" => nil, "goal" => initial} in updates
    assert %{"threadId" => id, "turnId" => turn, "goal" => final} in updates
    assert hd(updates) == %{"threadId" => id, "turnId" => nil, "goal" => initial}
    assert List.last(updates) == %{"threadId" => id, "turnId" => turn, "goal" => final}

    assert Enum.map(updates, & &1["goal"]["status"]) ==
             List.duplicate("active", length(updates) - 1) ++ ["usageLimited"]

    for update <- updates do
      assert Enum.sort(Map.keys(update)) == ~w(goal threadId turnId)
      assert update["threadId"] == id and update["turnId"] in [nil, turn]
      assert update["goal"]["status"] in ["active", "usageLimited"]

      assert_goal(
        update["goal"],
        id,
        update["goal"]["status"],
        0,
        initial["createdAt"],
        timing,
        0
      )
    end

    for [previous, current] <- Enum.chunk_every(updates, 2, 1, :discard),
        key <- ~w(tokensUsed timeUsedSeconds updatedAt) do
      assert current["goal"][key] >= previous["goal"][key]
    end

    assert_quota_provider(ctx, id, turn)
    history = turns(pid, id)
    assert_quota_history(history, turn)
    assert_thread_status(pid, id, %{"type" => "systemError"})
    assert_quiet(ctx, pid, {final, turn})

    cold = restart(ctx, pid)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert call(cold, "thread/goal/get", %{"threadId" => id}) == %{"goal" => final}
    assert_goal(final, id, "usageLimited", 0, initial["createdAt"], timing, 0)
    assert turns(cold, id) == history
    assert_quota_history(turns(cold, id), turn)
    assert_quiet(ctx, cold, {final, turn})
    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert call(cold, "thread/goal/get", %{"threadId" => id}) == %{"goal" => final}
    assert_quota_history(turns(cold, id), turn)
    assert turns(cold, id) == history
    assert_idle(cold, id)
    assert_quiet(ctx, cold, {final, turn})
    finish(ctx, cold)
  end

  defp quota_error do
    %{
      "message" => "Quota exceeded. Check your plan and billing details.",
      "codexErrorInfo" => "usageLimitExceeded",
      "additionalDetails" => nil,
      "misalignment" => nil
    }
  end

  defp assert_quota_lifecycle(events, id) do
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert [started] = notices(events, "turn/started")
    assert started["threadId"] == id
    turn = started["turn"]["id"]
    assert_uuid(turn)

    assert notices(events, "error") == [
             %{"threadId" => id, "turnId" => turn, "error" => quota_error(), "willRetry" => false}
           ]

    assert [ended] = notices(events, "turn/completed")
    assert ended["threadId"] == id and ended["turn"]["id"] == turn
    assert ended["turn"]["status"] == "failed" and ended["turn"]["error"] == quota_error()

    for method <- ["item/started", "item/completed", "item/agentMessage/delta"],
        do: assert(notices(events, method) == [])

    turn
  end

  defp assert_quota_history(history, turn) do
    assert [stored] = history
    assert stored["id"] == turn and stored["status"] == "failed"
    assert stored["error"] == quota_error() and stored["items"] == []
  end

  defp assert_quota_provider(ctx, id, turn) do
    await(fn ->
      case json(ctx, "goal-http.json") do
        [record] -> record["responded"]
        _ -> false
      end
    end)

    assert [request] = json(ctx, "requests.json")
    assert [record] = json(ctx, "goal-http.json")
    assert record["index"] == 1 and record["path"] == "/v1/responses"
    assert record["status"] == 429 and record["requestAuth"] == "none"
    assert record["metadata"]["thread_id"] == id and record["metadata"]["turn_id"] == turn
    assert record["metadata"]["turn_trigger"] == "goal"
    raw = Base.decode64!(record["rawBodyBase64"])
    assert hash(raw) == record["rawBodySHA256"] and JSON.decode!(raw) == request
    response = Base.decode64!(record["rawResponseBase64"])
    assert hash(response) == record["rawResponseSHA256"]

    assert JSON.decode!(response) == %{
             "error" => %{
               "code" => "insufficient_quota",
               "message" => "Owned synthetic goal quota."
             }
           }

    joined =
      request["input"]
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.map_join("\n", &Map.get(&1, "text", ""))

    assert joined =~ @objective
    assert joined =~ "- Tokens used: 0\n- Token budget: 20\n- Tokens remaining: 20"
    refute Enum.any?(request["input"], &(&1["type"] in ["function_call", "function_call_output"]))
  end

  defp assert_goal(goal, id, status, tokens, created, timing, minimum_seconds) do
    assert Enum.sort(Map.keys(goal)) == Enum.sort(~w(threadId objective status tokenBudget
      tokensUsed timeUsedSeconds createdAt updatedAt))
    assert goal["threadId"] == id and goal["objective"] == @objective
    assert goal["status"] == status and goal["tokenBudget"] == 20 and goal["tokensUsed"] == tokens
    assert_goal_clock(goal, created, timing, minimum_seconds)
  end

  defp assert_goal_clock(goal, created, timing, minimum_seconds) do
    for key <- ~w(tokenBudget tokensUsed timeUsedSeconds createdAt updatedAt),
        do: assert(is_integer(Map.fetch!(goal, key)))

    assert is_integer(created) and created > 0 and goal["createdAt"] == created
    assert created >= timing.wall and created <= System.system_time(:second)
    assert goal["updatedAt"] >= created and goal["updatedAt"] <= System.system_time(:second)
    upper = div(System.monotonic_time(:millisecond) - timing.mono, 1_000) + 1
    assert goal["timeUsedSeconds"] >= minimum_seconds and goal["timeUsedSeconds"] <= upper
  end

  defp assert_lifecycle(execution, id) do
    refute Enum.any?(execution, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    assert [first, second] = notices(execution, "turn/started")
    turn_ids = Enum.map([first, second], & &1["turn"]["id"])
    assert [one, two] = turn_ids
    assert one != two
    for turn <- turn_ids, do: assert_uuid(turn)
    for notice <- [first, second], do: assert(notice["threadId"] == id)
    completions = notices(execution, "turn/completed")
    assert Enum.map(completions, & &1["turn"]["id"]) == turn_ids

    for notice <- completions do
      assert notice["threadId"] == id
      assert notice["turn"]["status"] == "completed"
      assert Map.fetch!(notice["turn"], "error") == nil
    end

    for {turn, index} <- Enum.with_index(turn_ids, 1),
        do: assert_assistant(execution, id, turn, index)

    for method <- ["item/started", "item/completed"] do
      assert length(
               Enum.filter(notices(execution, method), &(&1["item"]["type"] == "agentMessage"))
             ) == 2
    end

    turn_ids
  end

  defp assert_assistant(execution, id, turn, index) do
    selected = fn method ->
      Enum.filter(
        notices(execution, method),
        &(&1["turnId"] == turn and &1["item"]["type"] == "agentMessage")
      )
    end

    assert [began] = selected.("item/started")
    assert [ended] = selected.("item/completed")

    for notice <- [began, ended] do
      assert notice["threadId"] == id and notice["turnId"] == turn
      assert notice["item"] == assistant(index)
    end

    started = Map.fetch!(began, "startedAtMs")
    completed = Map.fetch!(ended, "completedAtMs")
    assert is_integer(started) and started > 0
    assert is_integer(completed) and completed >= started
  end

  defp assistant(index) do
    %{
      "type" => "agentMessage",
      "id" => "owned-active-goal-progress-#{index}",
      "text" => if(index == 1, do: @first, else: @final),
      "delivery" => nil,
      "memoryCitation" => nil,
      "phase" => nil,
      "questions" => nil
    }
  end

  defp assert_goal_notices(execution, id, initial, first, second, timing) do
    updates = notices(execution, "thread/goal/updated")
    assert %{"threadId" => id, "turnId" => nil, "goal" => initial} in updates
    assert Enum.any?(updates, &(&1["turnId"] == first and &1["goal"]["tokensUsed"] == 9))

    assert Enum.any?(
             updates,
             &(&1["turnId"] == second and &1["goal"]["status"] == "budgetLimited")
           )

    for update <- updates do
      assert Enum.sort(Map.keys(update)) == ~w(goal threadId turnId)
      assert update["threadId"] == id and update["turnId"] in [nil, first, second]
      goal = update["goal"]

      assert {goal["status"], goal["tokensUsed"]} in [
               {"active", 0},
               {"active", 9},
               {"budgetLimited", 21}
             ]

      minimum = if goal["tokensUsed"] > 0, do: 1, else: 0

      assert_goal(
        goal,
        id,
        goal["status"],
        goal["tokensUsed"],
        initial["createdAt"],
        timing,
        minimum
      )
    end
  end

  defp assert_provider(ctx, id, first, second, initial, timing) do
    await(fn ->
      length(json(ctx, "goal-http.json")) == 3 and
        Enum.all?(json(ctx, "goal-http.json"), & &1["responded"])
    end)

    requests = json(ctx, "requests.json")
    records = json(ctx, "goal-http.json")
    assert length(requests) == 3 and length(records) == 3
    assert json(ctx, "goal-attempts.json") == ctx.request_budget

    for {record, index} <- Enum.with_index(records, 1) do
      raw = Base.decode64!(record["rawBodyBase64"])
      assert byte_size(raw) > 0 and byte_size(raw) <= 4_194_304
      assert hash(raw) == record["rawBodySHA256"]
      assert JSON.decode!(raw) == Enum.at(requests, index - 1)
      assert record["index"] == index and record["path"] == "/v1/responses"
      assert record["requestAuth"] == "none" and record["responded"]
      assert record["metadata"]["thread_id"] == id
      assert record["metadata"]["turn_id"] == Enum.at([first, second, second], index - 1)
      assert record["metadata"]["turn_trigger"] == "goal"
      assert_response(record, index)
    end

    assert hd(records)["delayElapsedSeconds"] >= 1.25
    assert hd(records)["delayElapsedSeconds"] < 3
    assert Enum.map(tl(records), & &1["delayElapsedSeconds"]) == [0.0, 0.0]
    assert_tool_output(List.last(requests), id, initial, timing)
    # Independent oracle: total wire tokens 26, cache hits 5, goal net 21.
    assert Enum.sum(Enum.map(1..3, &usage(&1)["total_tokens"])) == 26
    assert Enum.sum(Enum.map(1..3, &usage(&1)["input_tokens_details"]["cached_tokens"])) == 5
    assert 7 - 3 + 5 == 9 and 11 - 2 + 3 == 12 and 9 + 0 + 12 == 21
  end

  defp assert_response(record, index) do
    raw = Base.decode64!(record["rawResponseBase64"])
    assert hash(raw) == record["rawResponseSHA256"]

    actual =
      for block <- String.split(raw, "\n\n", trim: true) do
        assert [event_line, data_line] = String.split(block, "\n")
        assert "event: " <> event = event_line
        assert "data: " <> data = data_line
        {event, JSON.decode!(data)}
      end

    identity = "owned-active-goal-response-#{index}"

    assert actual == [
             {"response.created",
              %{"type" => "response.created", "response" => %{"id" => identity}}},
             {"response.output_item.done",
              %{"type" => "response.output_item.done", "item" => response_item(index)}},
             {"response.completed",
              %{
                "type" => "response.completed",
                "response" => %{"id" => identity, "usage" => usage(index)}
              }}
           ]
  end

  defp response_item(2),
    do: %{
      "type" => "function_call",
      "name" => "get_goal",
      "call_id" => @call_id,
      "arguments" => "{}"
    }

  defp response_item(index),
    do: %{
      "type" => "message",
      "role" => "assistant",
      "id" => "owned-active-goal-progress-#{if index == 1, do: 1, else: 2}",
      "content" => [
        %{"type" => "output_text", "text" => if(index == 1, do: @first, else: @final)}
      ]
    }

  defp usage(index) do
    {incoming, cached, outgoing} = Enum.at([{7, 3, 5}, {0, 0, 0}, {11, 2, 3}], index - 1)

    %{
      "input_tokens" => incoming,
      "input_tokens_details" => %{"cached_tokens" => cached, "cache_write_tokens" => 0},
      "output_tokens" => outgoing,
      "output_tokens_details" => %{"reasoning_tokens" => 0},
      "total_tokens" => incoming + outgoing
    }
  end

  defp assert_tool_output(request, id, initial, timing) do
    assert [call] = Enum.filter(request["input"], &(&1["type"] == "function_call"))
    assert call["name"] == "get_goal" and call["call_id"] == @call_id
    assert Map.get(call, "namespace") == nil and JSON.decode!(call["arguments"]) == %{}
    assert [output] = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == @call_id and is_binary(output["output"])
    result = JSON.decode!(output["output"])
    assert Enum.sort(Map.keys(result)) == ~w(completionBudgetReport goal remainingTokens)
    assert result["remainingTokens"] == 11 and Map.fetch!(result, "completionBudgetReport") == nil
    assert_goal(Map.fetch!(result, "goal"), id, "active", 9, initial["createdAt"], timing, 1)
  end

  defp assert_history(history, first, second) do
    assert Enum.map(history, & &1["id"]) == [first, second]

    for {turn, index} <- Enum.with_index(history, 1) do
      assert turn["status"] == "completed" and Map.fetch!(turn, "error") == nil
      selected = Enum.filter(turn["items"], &(&1["type"] == "agentMessage"))
      assert selected == [assistant(index)]

      refute Enum.any?(
               turn["items"],
               &(&1["type"] in [
                   "commandExecution",
                   "fileChange",
                   "dynamicToolCall",
                   "mcpToolCall",
                   "webSearch",
                   "imageGeneration"
                 ])
             )
    end
  end

  defp assert_idle(pid, id) do
    assert_thread_status(pid, id, %{"type" => "idle"})
  end

  defp assert_thread_status(pid, id, status) do
    await(fn ->
      call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]["status"] ==
        status
    end)
  end

  defp assert_quiet(ctx, pid, expected_goal \\ nil) do
    control(ctx, "barrier")
    observe_quiet(ctx, pid, System.monotonic_time(:millisecond) + 1_000, expected_goal)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "goal-attempts.json") == ctx.request_budget
    assert length(json(ctx, "requests.json")) == ctx.request_budget
    assert length(json(ctx, "goal-http.json")) == ctx.request_budget
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert journal(ctx, "realtime-journal.json", "handshake") == []
    assert journal(ctx, "realtime-journal.json", "native_frame") == []
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp observe_quiet(ctx, pid, deadline, expected_goal) do
    assert {:ok, batch} = Session.drain(pid)

    refute Enum.any?(
             batch,
             &(&1.kind == :server_request or
                 &1.wire["method"] in ["error", "turn/started", "turn/completed"])
           )

    if expected_goal do
      {goal, turn} = expected_goal
      refute Enum.any?(batch, &(&1.wire["method"] == "thread/goal/cleared"))

      for update <- notices(batch, "thread/goal/updated") do
        assert update in [
                 %{"threadId" => goal["threadId"], "turnId" => nil, "goal" => goal},
                 %{"threadId" => goal["threadId"], "turnId" => turn, "goal" => goal}
               ]
      end
    end

    assert json(ctx, "goal-attempts.json") == ctx.request_budget

    if System.monotonic_time(:millisecond) < deadline do
      receive do
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native goal observation gap")
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        20 -> :ok
      end

      observe_quiet(ctx, pid, deadline, expected_goal)
    end
  end

  defp turns(pid, id) do
    result =
      call(pid, "thread/turns/list", %{
        "threadId" => id,
        "limit" => 100,
        "sortDirection" => "asc",
        "itemsView" => "full"
      })

    assert Map.fetch!(result, "nextCursor") == nil
    Map.fetch!(result, "data")
  end

  defp connect(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport: {UnixSocket, [socket_path: ctx.socket]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(pid, %{"name" => "samgita_goal_budget", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    pid
  end

  defp restart(ctx, pid) do
    instance = Session.status(pid).instance_id
    native = json(ctx, "state.json")["native_pid"]
    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}")
    control(ctx, "restart")
    refute File.exists?("/proc/#{native}")
    refute json(ctx, "state.json")["native_pid"] == native
    cold = connect(ctx)
    refute Session.status(cold).instance_id == instance
    cold
  end

  defp finish(ctx, pid) do
    assert :ok = Session.close(pid)
    control(ctx, "close")
    assert length(journal(ctx, "bem-journal.json", "fixture_closed")) == 1

    for native <- json(ctx, "state.json")["native_pids"],
        do: refute(File.exists?("/proc/#{native}"))
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: assert_process_reaped(pid)

      assert journal(ctx, "bem-journal.json", "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned goal budget evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-goal-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))

    await(fn ->
      Enum.find(journal(ctx, "bem-journal.json", "control_done"), &(&1["id"] == id))
    end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline, "Owned native goal event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native goal event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp finished?(execution),
    do:
      length(notices(execution, "turn/completed")) == 2 and
        Enum.any?(
          notices(execution, "thread/goal/updated"),
          &(&1["goal"]["status"] == "budgetLimited")
        )

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned native goal fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp notices(execution, method),
    do: for(event <- execution, event.wire["method"] == method, do: event.wire["params"])

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp journal(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
