defmodule SamgitaCodexDriver.NativeGoalTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_thread "00000000-0000-4000-8000-000000000000"

  setup tags do
    context = TurnFixture.setup(tags)
    enabled = !tags[:disabled]
    config = Path.join(context.fixture.codex_home, "config.toml")
    File.write!(config, "\n[features]\ngoals = #{enabled}\n", [:append])
    context
  end

  @tag disabled: true
  test "goals feature rejects every native operation without an experimental requirement", ctx do
    pid = start(ctx, experimental: false)
    id = thread(ctx, pid)

    for {method, params} <- [
          {"thread/goal/get", %{"threadId" => id}},
          {"thread/goal/set", paused(id, "Never executed")},
          {"thread/goal/clear", %{"threadId" => id, "origin" => "user"}}
        ] do
      assert upstream_error(pid, method, params) == %{
               "code" => -32_600,
               "message" => "goals feature is disabled"
             }
    end

    assert_no_execution(ctx, pid)
  end

  test "paused goals preserve nullable budget and status updates without starting work", ctx do
    # Goal RPCs are stable. A native status is not Samgita Task acceptance.
    pid = start(ctx, experimental: false)
    id = thread(ctx, pid)
    assert get_goal(pid, id) == nil

    first = set_goal(pid, Map.put(paused(id, "  Synthetic objective λ  "), "tokenBudget", 100))
    assert first["objective"] == "Synthetic objective λ"
    assert first["status"] == "paused"
    assert first["tokenBudget"] == 100
    assert first["tokensUsed"] == 0
    assert first["timeUsedSeconds"] == 0
    assert first["threadId"] == id
    assert is_integer(first["createdAt"]) and first["createdAt"] > 0
    assert first["updatedAt"] >= first["createdAt"]
    assert get_goal(pid, id) == first
    assert_goal_event(pid, "thread/goal/updated", id, first)

    kept = set_goal(pid, %{"threadId" => id, "objective" => nil, "status" => nil})
    assert Map.drop(kept, ["updatedAt"]) == Map.drop(first, ["updatedAt"])
    cleared_budget = set_goal(pid, %{"threadId" => id, "tokenBudget" => nil})
    assert cleared_budget["tokenBudget"] == nil
    assert cleared_budget["createdAt"] == first["createdAt"]

    for status <- ["blocked", "usageLimited", "budgetLimited", "complete", "paused"] do
      updated = set_goal(pid, %{"threadId" => id, "status" => status, "origin" => "automatic"})
      assert updated["status"] == status
      assert updated["objective"] == first["objective"]
      assert updated["tokensUsed"] == 0
      assert get_goal(pid, id) == updated
    end

    assert call(pid, "thread/goal/clear", %{"threadId" => id}) == %{"cleared" => true}
    assert get_goal(pid, id) == nil
    assert_goal_event(pid, "thread/goal/cleared", id, nil)

    assert call(pid, "thread/goal/clear", %{"threadId" => id, "origin" => nil}) ==
             %{"cleared" => false}

    assert_no_execution(ctx, pid)
  end

  test "objective and budget limits reject mutations while preserving the previous goal", ctx do
    config = Path.join(ctx.fixture.codex_home, "config.toml")
    File.write!(config, "\n[goals]\nmax_goal_token_budget = 100\n", [:append])
    pid = start(ctx)
    id = thread(ctx, pid)

    assert upstream_error(pid, "thread/goal/set", %{"threadId" => id, "status" => "paused"}) ==
             %{
               "code" => -32_600,
               "message" => "cannot update goal for thread #{id}: no goal exists"
             }

    # The upstream boundary counts Unicode scalars, not UTF8 bytes or UTF16 units.
    objective = String.duplicate("λ🙂", 2_000)
    goal = set_goal(pid, paused(id, objective))
    assert goal["objective"] == objective
    assert goal["tokenBudget"] == 100
    changed = set_goal(pid, %{"threadId" => id, "tokenBudget" => 50})
    assert changed["tokenBudget"] == 50
    reset = set_goal(pid, %{"threadId" => id, "tokenBudget" => nil})
    assert reset["tokenBudget"] == 100

    for {extra, message} <- [
          {%{"objective" => " \n\t"}, "goal objective must not be empty"},
          {%{"objective" => objective <> "λ"}, "goal objective must be at most 4000 characters"},
          {%{"tokenBudget" => 0}, "goal budgets must be positive when provided"},
          {%{"tokenBudget" => -1}, "goal budgets must be positive when provided"},
          {%{"tokenBudget" => 101},
           "goal token budget 101 exceeds the maximum allowed goal token budget of 100"}
        ] do
      assert upstream_error(pid, "thread/goal/set", Map.put(extra, "threadId", id)) == %{
               "code" => -32_600,
               "message" => message
             }

      assert get_goal(pid, id) == reset
    end

    ephemeral = thread(ctx, pid, %{"ephemeral" => true})

    for {thread_id, message} <- [
          {ephemeral, "ephemeral thread does not support goals: #{ephemeral}"},
          {@missing_thread, "thread not found: #{@missing_thread}"}
        ] do
      for {method, extra} <- [
            {"thread/goal/get", %{}},
            {"thread/goal/set", %{"objective" => "Rejected", "status" => "paused"}},
            {"thread/goal/clear", %{}}
          ] do
        assert upstream_error(pid, method, Map.put(extra, "threadId", thread_id)) == %{
                 "code" => -32_600,
                 "message" => message
               }
      end
    end

    assert_no_execution(ctx, pid)
  end

  for cold <- [false, true] do
    @tag cold: cold
    test "explicit user provenance survives goal edits and clear, cold=#{cold}", ctx do
      pid = start(ctx)
      id = thread(ctx, pid)
      automatic = "Automatically generated goal without user authorization."
      original = set_goal(pid, Map.put(paused(id, automatic), "origin", "automatic"))
      assert ModelFixture.requests(ctx.fixture) == []

      pid =
        if ctx.cold do
          assert :ok = Session.close(pid)
          restarted = start(ctx)
          # Read/mutate the durable goal before loading the thread runtime.
          assert get_goal(restarted, id) == original
          restarted
        else
          pid
        end

      for {origin, objective} <- [
            {:absent, "Missing provenance must not authorize this objective."},
            {nil, "Null provenance must not authorize this objective."},
            {"user", "Send the synthetic approved report."},
            {"user", "Draft the synthetic report without sending it."}
          ] do
        params = paused(id, objective)
        params = if origin == :absent, do: params, else: Map.put(params, "origin", origin)
        assert set_goal(pid, params)["objective"] == objective
      end

      assert call(pid, "thread/goal/clear", %{"threadId" => id, "origin" => "user"}) ==
               %{"cleared" => true}

      assert get_goal(pid, id) == nil
      assert ModelFixture.requests(ctx.fixture) == []
      assert :ok = Session.close(pid)
      resumed = start(ctx)
      assert call(resumed, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
      assert get_goal(resumed, id) == nil
      assert ModelFixture.requests(ctx.fixture) == []

      turn = start_turn(resumed, id, [%{"type" => "text", "text" => "Report synthetic status."}])
      finish_turn(resumed, id, turn)
      assert [request] = ModelFixture.requests(ctx.fixture)

      user_history =
        request["input"]
        |> Enum.filter(&(&1["role"] == "user"))
        |> Enum.flat_map(&Map.get(&1, "content", []))
        |> Enum.map_join("\n", &Map.get(&1, "text", ""))

      for text <- [
            automatic,
            "Missing provenance must not authorize this objective.",
            "Null provenance must not authorize this objective."
          ] do
        refute user_history =~ text
      end

      old = ~s(User set the goal: "Send the synthetic approved report.")
      new = ~s(User set the goal: "Draft the synthetic report without sending it.")
      assert {old_pos, _} = :binary.match(user_history, old)
      assert {new_pos, _} = :binary.match(user_history, new)
      assert old_pos < new_pos
      assert user_history =~ ~s(User set goal status: "paused".)
      assert user_history =~ "User cleared the goal."
    end
  end

  defp paused(id, objective),
    do: %{"threadId" => id, "objective" => objective, "status" => "paused"}

  defp set_goal(pid, params), do: call(pid, "thread/goal/set", params)["goal"]
  defp get_goal(pid, id), do: call(pid, "thread/goal/get", %{"threadId" => id})["goal"]

  defp assert_goal_event(pid, method, id, goal) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    params = await_goal_event(pid, method, id, goal, deadline)

    expected =
      if goal, do: %{"threadId" => id, "turnId" => nil, "goal" => goal}, else: %{"threadId" => id}

    assert params == expected
  end

  defp await_goal_event(pid, method, id, goal, deadline) do
    assert {:ok, events} = Session.drain(pid)

    params = notification(events, method, &(&1["threadId"] == id and Map.get(&1, "goal") == goal))

    if params do
      params
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          await_goal_event(pid, method, id, goal, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected native goal notification gap")
      after
        remaining -> flunk("Native goal notification deadline")
      end
    end
  end

  defp assert_no_execution(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
