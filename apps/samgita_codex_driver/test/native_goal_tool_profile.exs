defmodule SamgitaCodexDriver.NativeGoalToolProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_goal_tool_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @a "Owned synthetic goal A: observe rejection without replacement."
  @b "Owned synthetic goal B: observe a fresh accounting baseline."
  @input "Explicitly create goal A with token budget 100: #{@a} Then deliberately attempt the rejected replacement A probe. Complete A after observing rejection. Explicitly create replacement goal B with token budget 200: #{@b} Then deliberately attempt the rejected replacement B probe and complete B after observing rejection. Report the native structured usage. This authorizes only these synthetic goal tools, no commands or external work."
  @final "Synthetic goal A completed using 9 of 100 tokens; replacement goal B completed using 12 of 200 tokens."
  @error "cannot create a new goal because this thread has an unfinished goal; complete the existing goal first"
  @report "Goal achieved. Report final usage from this tool result's structured goal fields. If `goal.tokenBudget` is present, include token usage from `goal.tokensUsed` and `goal.tokenBudget`. If `goal.timeUsedSeconds` is greater than 0, summarize elapsed time in a concise, human-friendly form appropriate to the response language."
  @calls [
    {"create_goal", "owned-goal-create-a", %{"objective" => @a, "token_budget" => 100}},
    {"create_goal", "owned-goal-reject-a",
     %{"objective" => "Rejected replacement A must never become the goal.", "token_budget" => 99}},
    {"update_goal", "owned-goal-complete-a", %{"status" => "complete"}},
    {"create_goal", "owned-goal-create-b", %{"objective" => @b, "token_budget" => 200}},
    {"create_goal", "owned-goal-reject-b",
     %{"objective" => "Rejected replacement B must never become the goal.", "token_budget" => 199}},
    {"update_goal", "owned-goal-complete-b", %{"status" => "complete"}}
  ]

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-gt-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
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

    ctx = %{root: root, owner: owner, socket: Path.join(root, "native.sock")}
    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]
    assert [ready] = journal(ctx, "bem-journal.json", "goal_tool_provider_ready")
    assert ready["request_budget"] == 7 and ready["source_provider_requests"] == 0
    assert ready["request_auth"] == "none"
    assert ready["output"] == "fixed_create_reject_complete_replace_reject_complete_final"
    assert_config(ctx)
    ctx
  end

  test "stock create/complete/replacement preserve independent budgets and cold durable state",
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

    # The sole execution trigger. No client goal mutation, tool response,
    # interrupt, retry or hidden state update occurs anywhere in this profile.
    turn =
      call(pid, "turn/start", %{
        "threadId" => id,
        "turnTrigger" => "user",
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert_uuid(turn)
    execution = collect(pid, &finished?/1)
    assert_lifecycle(execution, id, turn)
    goals = assert_provider(ctx, id, turn, timing)
    assert_goal_notices(execution, id, turn, goals, timing)
    assert %{"goal" => final} = call(pid, "thread/goal/get", %{"threadId" => id})
    assert_goal(final, id, :b, "complete", 12, timing)
    assert final == goals.b_complete
    history = turns(pid, id)
    assert_history(history, turn)
    assert_idle(pid, id)
    assert_quiet(ctx, pid, id, turn, final, timing)

    cold = restart(ctx, pid)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_retained(cold, id, turn, final, history, timing)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_quiet(ctx, cold, id, turn, final, timing)
    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert_retained(cold, id, turn, final, history, timing)
    assert_idle(cold, id)
    assert_quiet(ctx, cold, id, turn, final, timing)
    finish(ctx, cold)
  end

  defp assert_config(ctx) do
    config = File.read!(Path.join(ctx.root, "codex/config.toml"))

    for setting <- [
          "goals = true",
          "max_goal_token_budget = 200",
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
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp assert_goal(goal, id, key, status, tokens, timing) do
    assert Enum.sort(Map.keys(goal)) == Enum.sort(~w(threadId objective status tokenBudget
      tokensUsed timeUsedSeconds createdAt updatedAt))
    assert goal["threadId"] == id
    assert goal["objective"] == objective(key)
    assert goal["status"] == status
    assert goal["tokenBudget"] == budget(key) and goal["tokensUsed"] == tokens
    assert_clock(goal, timing)
  end

  defp assert_clock(goal, timing) do
    for key <- ~w(tokenBudget tokensUsed timeUsedSeconds createdAt updatedAt),
        do: assert(is_integer(Map.fetch!(goal, key)))

    assert goal["createdAt"] >= timing.wall and goal["createdAt"] <= System.system_time(:second)
    assert goal["updatedAt"] >= goal["createdAt"]
    assert goal["updatedAt"] <= System.system_time(:second)
    upper = div(System.monotonic_time(:millisecond) - timing.mono, 1_000) + 1
    assert goal["timeUsedSeconds"] >= 0 and goal["timeUsedSeconds"] <= upper
  end

  defp assert_creation_window(goal, records, key) do
    index = if key == :a, do: 0, else: 3
    lower = trunc(Enum.at(records, index)["responseWall"])
    upper = trunc(Enum.at(records, index + 1)["arrivalWall"])
    assert goal["createdAt"] >= lower and goal["createdAt"] <= upper
  end

  defp assert_completion_window(goal, records, key) do
    index = if key == :a, do: 2, else: 5
    lower = trunc(Enum.at(records, index)["responseWall"])
    upper = trunc(Enum.at(records, index + 1)["arrivalWall"])
    assert goal["updatedAt"] >= lower and goal["updatedAt"] <= upper
  end

  defp assert_lifecycle(execution, id, turn) do
    assert_no_interaction(execution)
    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn}}] = notices(execution, "turn/started")
    assert [complete] = notices(execution, "turn/completed")
    assert complete["threadId"] == id and complete["turn"]["id"] == turn
    assert complete["turn"]["status"] == "completed"
    assert Map.fetch!(complete["turn"], "error") == nil

    for method <- ["item/started", "item/completed"] do
      items = notices(execution, method)
      assert Enum.map(items, & &1["item"]["type"]) == ["userMessage", "agentMessage"]

      for notice <- items do
        assert notice["threadId"] == id and notice["turnId"] == turn
      end

      assert_user(hd(items)["item"])
      assert List.last(items)["item"] == assistant()
    end

    [started] =
      Enum.filter(notices(execution, "item/started"), &(&1["item"]["type"] == "agentMessage"))

    [ended] =
      Enum.filter(notices(execution, "item/completed"), &(&1["item"]["type"] == "agentMessage"))

    assert is_integer(started["startedAtMs"]) and started["startedAtMs"] > 0
    assert is_integer(ended["completedAtMs"]) and ended["completedAtMs"] >= started["startedAtMs"]
  end

  defp assert_user(item) do
    assert_uuid(item["id"])

    assert item == %{
             "type" => "userMessage",
             "id" => item["id"],
             "clientId" => nil,
             "content" => [%{"type" => "text", "text" => @input, "text_elements" => []}]
           }
  end

  defp assistant do
    %{
      "type" => "agentMessage",
      "id" => "owned-goal-final-1",
      "text" => @final,
      "delivery" => nil,
      "memoryCitation" => nil,
      "phase" => nil,
      "questions" => nil
    }
  end

  defp assert_provider(ctx, id, turn, timing) do
    await(fn ->
      length(json(ctx, "goal-http.json")) == 7 and
        Enum.all?(json(ctx, "goal-http.json"), & &1["responded"])
    end)

    requests = json(ctx, "requests.json")
    records = json(ctx, "goal-http.json")
    assert length(requests) == 7 and length(records) == 7
    assert json(ctx, "goal-attempts.json") == 7

    for {record, index} <- Enum.with_index(records, 1) do
      assert_http_record(record, index, Enum.at(requests, index - 1), id, turn)
      assert_response(record, index)
      assert_replayed_calls(Enum.at(requests, index - 1), index, id, records, timing)
    end

    assert Enum.sum(Enum.map(1..7, &usage(&1)["total_tokens"])) == 26
    assert Enum.sum(Enum.map(1..7, &usage(&1)["input_tokens_details"]["cached_tokens"])) == 5
    final = List.last(requests)

    goals = %{
      a_created: tool_goal(final, 1),
      a_complete: tool_goal(final, 3),
      b_created: tool_goal(final, 4),
      b_complete: tool_goal(final, 6)
    }

    assert goals.a_created["createdAt"] == goals.a_complete["createdAt"]
    assert goals.b_created["createdAt"] == goals.b_complete["createdAt"]
    assert goals.b_created["createdAt"] >= goals.a_created["createdAt"]
    assert goals.a_created["timeUsedSeconds"] == 0 and goals.b_created["timeUsedSeconds"] == 0
    goals
  end

  defp assert_http_record(record, index, request, id, turn) do
    raw = Base.decode64!(record["rawBodyBase64"])
    assert byte_size(raw) > 0 and byte_size(raw) <= 4_194_304
    assert hash(raw) == record["rawBodySHA256"]
    assert JSON.decode!(raw) == request
    assert record["index"] == index and record["path"] == "/v1/responses"
    assert record["requestAuth"] == "none" and record["responded"]
    assert record["metadata"]["thread_id"] == id and record["metadata"]["turn_id"] == turn
    assert record["metadata"]["turn_trigger"] == "user"
    assert request["model"] == "mock-model"
    assert @input in input_texts(request)

    refute Enum.any?(
             request["input"],
             &(&1["type"] in ["custom_tool_call", "custom_tool_call_output"])
           )
  end

  defp assert_response(record, index) do
    raw = Base.decode64!(record["rawResponseBase64"])
    assert hash(raw) == record["rawResponseSHA256"]

    actual =
      for block <- String.split(raw, "\n\n", trim: true) do
        assert ["event: " <> event, "data: " <> data] = String.split(block, "\n")
        {event, JSON.decode!(data)}
      end

    identity = "owned-goal-tool-response-#{index}"

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

  defp response_item(7),
    do: %{
      "type" => "message",
      "role" => "assistant",
      "id" => "owned-goal-final-1",
      "content" => [%{"type" => "output_text", "text" => @final}]
    }

  defp response_item(index) do
    {name, call_id, arguments} = Enum.at(@calls, index - 1)

    %{
      "type" => "function_call",
      "name" => name,
      "call_id" => call_id,
      "arguments" => JSON.encode!(arguments)
    }
  end

  defp usage(index) do
    {incoming, cached, outgoing} = Map.get(%{2 => {7, 3, 5}, 5 => {11, 2, 3}}, index, {0, 0, 0})

    %{
      "input_tokens" => incoming,
      "input_tokens_details" => %{"cached_tokens" => cached, "cache_write_tokens" => 0},
      "output_tokens" => outgoing,
      "output_tokens_details" => %{"reasoning_tokens" => 0},
      "total_tokens" => incoming + outgoing
    }
  end

  defp assert_replayed_calls(request, index, id, records, timing) do
    calls = Enum.filter(request["input"], &(&1["type"] == "function_call"))
    outputs = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))
    assert length(calls) == index - 1 and length(outputs) == index - 1

    Enum.reduce(Enum.with_index(Enum.zip(calls, outputs), 1), -1, fn {{call, output}, ordinal},
                                                                     previous ->
      {name, call_id, arguments} = Enum.at(@calls, ordinal - 1)
      assert call["name"] == name and call["call_id"] == call_id
      assert Map.get(call, "namespace") == nil and JSON.decode!(call["arguments"]) == arguments
      assert output["call_id"] == call_id and is_binary(output["output"])
      call_position = Enum.find_index(request["input"], &(&1 == call))
      output_position = Enum.find_index(request["input"], &(&1 == output))
      assert previous < call_position and call_position < output_position
      assert_tool_result(output["output"], ordinal, id, records, timing)
      output_position
    end)
  end

  defp assert_tool_result(output, ordinal, _id, _records, _timing) when ordinal in [2, 5],
    do: assert(output == @error)

  defp assert_tool_result(output, ordinal, id, records, timing) do
    {key, status, tokens, remaining, report} = result_expectation(ordinal)
    result = JSON.decode!(output)
    assert Enum.sort(Map.keys(result)) == ~w(completionBudgetReport goal remainingTokens)
    assert is_integer(result["remainingTokens"]) and result["remainingTokens"] == remaining
    assert Map.fetch!(result, "completionBudgetReport") == report
    goal = Map.fetch!(result, "goal")
    assert_goal(goal, id, key, status, tokens, timing)
    assert_creation_window(goal, records, key)
    if status == "active", do: assert(goal["timeUsedSeconds"] == 0)
    if status == "complete", do: assert_completion_window(goal, records, key)
  end

  defp result_expectation(1), do: {:a, "active", 0, 100, nil}
  defp result_expectation(3), do: {:a, "complete", 9, 91, @report}
  defp result_expectation(4), do: {:b, "active", 0, 200, nil}
  defp result_expectation(6), do: {:b, "complete", 12, 188, @report}

  defp tool_goal(request, ordinal) do
    {_name, id, _arguments} = Enum.at(@calls, ordinal - 1)

    [output] =
      Enum.filter(
        request["input"],
        &(&1["type"] == "function_call_output" and &1["call_id"] == id)
      )

    JSON.decode!(output["output"])["goal"]
  end

  defp assert_goal_notices(execution, id, turn, goals, timing) do
    updates = notices(execution, "thread/goal/updated")

    for goal <- [goals.a_created, goals.a_complete, goals.b_created, goals.b_complete],
        do: assert(%{"threadId" => id, "turnId" => turn, "goal" => goal} in updates)

    Enum.reduce(updates, {-1, %{}}, fn update, {phase, previous} ->
      assert Enum.sort(Map.keys(update)) == ~w(goal threadId turnId)
      assert update["threadId"] == id and update["turnId"] == turn
      goal = update["goal"]
      {key, current_phase, tokens} = notification_expectation(goal)
      assert current_phase >= phase
      assert_goal(goal, id, key, goal["status"], tokens, timing)
      created = if key == :a, do: goals.a_created, else: goals.b_created
      assert goal["createdAt"] == created["createdAt"]
      if last = previous[key], do: assert_progress_order(last, goal)
      {current_phase, Map.put(previous, key, goal)}
    end)
  end

  defp notification_expectation(%{
         "objective" => @a,
         "status" => "active",
         "tokensUsed" => tokens
       })
       when tokens in [0, 9],
       do: {:a, 0, tokens}

  defp notification_expectation(%{"objective" => @a, "status" => "complete", "tokensUsed" => 9}),
    do: {:a, 1, 9}

  defp notification_expectation(%{
         "objective" => @b,
         "status" => "active",
         "tokensUsed" => tokens
       })
       when tokens in [0, 12],
       do: {:b, 2, tokens}

  defp notification_expectation(%{"objective" => @b, "status" => "complete", "tokensUsed" => 12}),
    do: {:b, 3, 12}

  defp notification_expectation(_), do: flunk("Unapproved goal update/identity/status/usage")

  defp assert_progress_order(previous, current) do
    for field <- ~w(tokensUsed timeUsedSeconds updatedAt),
        do: assert(current[field] >= previous[field])
  end

  defp assert_history(history, turn) do
    assert [entry] = history
    assert entry["id"] == turn and entry["status"] == "completed"
    assert Map.fetch!(entry, "error") == nil
    assert [user, message] = entry["items"]
    assert_user(user)
    assert message == assistant()
  end

  defp assert_retained(pid, id, turn, final, history, timing) do
    assert %{"goal" => retained} = call(pid, "thread/goal/get", %{"threadId" => id})
    assert_goal(retained, id, :b, "complete", 12, timing)
    assert retained == final
    retained_history = turns(pid, id)
    assert_history(retained_history, turn)
    assert retained_history == history
  end

  defp assert_quiet(ctx, pid, id, turn, final, timing) do
    control(ctx, "barrier")
    observe_quiet(ctx, pid, id, turn, final, timing, System.monotonic_time(:millisecond) + 1_000)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "goal-attempts.json") == 7
    assert length(json(ctx, "requests.json")) == 7 and length(json(ctx, "goal-http.json")) == 7
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert journal(ctx, "realtime-journal.json", "handshake") == []
    assert journal(ctx, "realtime-journal.json", "native_frame") == []
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp observe_quiet(ctx, pid, id, turn, final, timing, deadline) do
    assert {:ok, batch} = Session.drain(pid)
    assert_no_interaction(batch)
    assert notices(batch, "turn/started") == [] and notices(batch, "turn/completed") == []

    for update <- notices(batch, "thread/goal/updated") do
      assert Enum.sort(Map.keys(update)) == ~w(goal threadId turnId)
      assert update["threadId"] == id and update["turnId"] in [nil, turn]
      assert_goal(update["goal"], id, :b, "complete", 12, timing)
      assert update["goal"] == final
    end

    assert json(ctx, "goal-attempts.json") == 7

    if System.monotonic_time(:millisecond) < deadline do
      receive do
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native goal observation gap")
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        20 -> :ok
      end

      observe_quiet(ctx, pid, id, turn, final, timing, deadline)
    end
  end

  defp assert_no_interaction(execution),
    do:
      refute(Enum.any?(execution, &(&1.kind == :server_request or &1.wire["method"] == "error")))

  defp assert_idle(pid, id) do
    await(fn ->
      call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]["status"] ==
        %{"type" => "idle"}
    end)
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
             Session.initialize(pid, %{"name" => "samgita_goal_tools", "version" => "0.1.0"}, %{
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
          do: await_process_exit(pid)

      assert journal(ctx, "bem-journal.json", "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned goal tool evidence retained: #{ctx.root}")
  end

  defp await_process_exit(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-goal-tool-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))

    await(fn ->
      Enum.find(journal(ctx, "bem-journal.json", "control_done"), &(&1["id"] == id))
    end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    assert_no_interaction(batch)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned native goal-tool event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native goal-tool event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp finished?(execution),
    do:
      length(notices(execution, "turn/completed")) == 1 and
        Enum.any?(
          notices(execution, "thread/goal/updated"),
          &(&1["goal"]["objective"] == @b and
              &1["goal"]["status"] == "complete" and &1["goal"]["tokensUsed"] == 12)
        )

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned native goal-tool fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp input_texts(request),
    do:
      for(
        item <- request["input"],
        part <- Map.get(item, "content", []),
        part["type"] in ["input_text", "output_text"],
        do: part["text"]
      )

  defp objective(:a), do: @a
  defp objective(:b), do: @b
  defp budget(:a), do: 100
  defp budget(:b), do: 200

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp journal(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
