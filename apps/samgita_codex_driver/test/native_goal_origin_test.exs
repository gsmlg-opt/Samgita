defmodule SamgitaCodexDriver.NativeGoalOriginTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @sentinel "Unrelated paused goal must remain unchanged."
  @prompt "Report synthetic clear provenance only."
  @cases [
    {:absent, "Missing-origin paused objective.", "Missing-origin edited objective."},
    {nil, "Null-origin paused objective.", "Null-origin edited objective."},
    {"automatic", "Automatic-origin paused objective.", "Automatic-origin edited objective."},
    {"user", "User-origin paused objective.", "User-origin edited objective."}
  ]

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) == @sha
    path = Path.join(ctx.fixture.codex_home, "config.toml")
    File.write!(path, "\n[features]\ngoals = true\n", [:append])
    ctx
  end

  test "real clears distinguish missing/null/automatic/user origin and retain cold provenance",
       ctx do
    pid = start(ctx, experimental: false)
    id = thread(ctx, pid)
    sentinel_id = thread(ctx, pid)
    refute id == sentinel_id

    sentinel =
      set_goal(pid, %{
        "threadId" => sentinel_id,
        "objective" => @sentinel,
        "status" => "paused",
        "tokenBudget" => 73,
        "origin" => "automatic"
      })

    assert_paused(sentinel, sentinel_id, @sentinel, 73)

    assert_goal_notice(pid, "thread/goal/updated", %{
      "threadId" => sentinel_id,
      "turnId" => nil,
      "goal" => sentinel
    })

    assert_inert(ctx, pid)

    # All four clears operate on a real goal row. An empty-row null clear
    # alone cannot prove the branch's successful deletion/notification behavior.
    for {origin, objective, edited_objective} <- @cases do
      assert get_goal(pid, id) == nil
      created_after = System.system_time(:second)

      params =
        with_origin(
          %{
            "threadId" => id,
            "objective" => objective,
            "status" => "paused",
            "tokenBudget" => 71
          },
          origin
        )

      created = set_goal(pid, params)
      assert_paused(created, id, objective, 71)
      assert created["createdAt"] >= created_after

      assert_goal_notice(pid, "thread/goal/updated", %{
        "threadId" => id,
        "turnId" => nil,
        "goal" => created
      })

      # Explicit null status is a separate physical branch from omission.
      # Change the objective simultaneously so this is an observable mutation,
      # while status, budget, accounting and creation identity remain retained.
      edit =
        with_origin(
          %{"threadId" => id, "objective" => edited_objective, "status" => nil},
          origin
        )

      assert Map.fetch!(edit, "status") == nil
      updated = set_goal(pid, edit)
      assert_paused(updated, id, edited_objective, 71)

      assert Map.drop(updated, ["objective", "updatedAt"]) ==
               Map.drop(created, ["objective", "updatedAt"])

      assert updated["updatedAt"] >= created["updatedAt"]
      assert get_goal(pid, id) == updated

      assert_goal_notice(pid, "thread/goal/updated", %{
        "threadId" => id,
        "turnId" => nil,
        "goal" => updated
      })

      assert get_goal(pid, sentinel_id) == sentinel
      assert_inert(ctx, pid)

      clear = with_origin(%{"threadId" => id}, origin)
      assert call(pid, "thread/goal/clear", clear) == %{"cleared" => true}
      assert get_goal(pid, id) == nil
      assert get_goal(pid, sentinel_id) == sentinel
      assert_goal_notice(pid, "thread/goal/cleared", %{"threadId" => id})

      # Upstream deliberately records a User clear instruction even when there
      # is no goal. The state result and notification are idempotent, while
      # explicit user provenance is appended again. Do not change that behavior.
      assert call(pid, "thread/goal/clear", clear) == %{"cleared" => false}
      assert get_goal(pid, id) == nil
      assert get_goal(pid, sentinel_id) == sentinel
      assert_no_goal_notice(ctx, pid)
    end

    assert get_goal(pid, id) == nil
    assert get_goal(pid, sentinel_id) == sentinel
    assert_inert(ctx, pid)
    assert :ok = Session.close(pid)
    cold = start(ctx, experimental: false)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    # Durable reads before runtime loading must preserve both the deletion and
    # the unrelated full goal, without activating either thread.
    assert get_goal(cold, id) == nil
    assert_paused(get_goal(cold, sentinel_id), sentinel_id, @sentinel, 73)
    assert get_goal(cold, sentinel_id) == sentinel
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_inert(ctx, cold)
    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert get_goal(cold, id) == nil
    assert get_goal(cold, sentinel_id) == sentinel
    assert_goal_notice(cold, "thread/goal/cleared", %{"threadId" => id})
    assert_inert(ctx, cold)

    # The sole requested inference is an assistant-only synthetic response on
    # the cleared target. Paused/set/clear/resume never supplies an execution
    # trigger. No actual model tools, remote provider or Task acceptance occurs.
    turn = start_turn(cold, id, [%{"type" => "text", "text" => @prompt}])
    events = finish_turn(cold, id, turn)
    assert_single_completion(events, id, turn)
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert request["model"] == "mock-model"
    assert_provenance(request)
    assert get_goal(cold, id) == nil
    assert get_goal(cold, sentinel_id) == sentinel
    assert length(ModelFixture.requests(ctx.fixture)) == 1
  end

  defp with_origin(params, :absent) do
    refute Map.has_key?(params, "origin")
    params
  end

  defp with_origin(params, origin) do
    params = Map.put(params, "origin", origin)
    assert Map.fetch!(params, "origin") == origin
    params
  end

  defp assert_paused(goal, id, objective, budget) do
    assert Enum.sort(Map.keys(goal)) == Enum.sort(~w(threadId objective status tokenBudget
      tokensUsed timeUsedSeconds createdAt updatedAt))
    assert goal["threadId"] == id and goal["objective"] == objective
    assert goal["status"] == "paused" and goal["tokenBudget"] == budget
    assert goal["tokensUsed"] == 0 and goal["timeUsedSeconds"] == 0
    assert_clock(goal)
  end

  defp assert_clock(goal) do
    for key <- ~w(tokenBudget tokensUsed timeUsedSeconds createdAt updatedAt),
        do: assert(is_integer(Map.fetch!(goal, key)))

    assert goal["createdAt"] > 0 and goal["createdAt"] <= System.system_time(:second)
    assert goal["updatedAt"] >= goal["createdAt"]
    assert goal["updatedAt"] <= System.system_time(:second)
  end

  defp assert_provenance(request) do
    history =
      request["input"]
      |> Enum.filter(&(&1["role"] == "user"))
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.map_join("\n", &Map.get(&1, "text", ""))

    assert history =~ @prompt
    refute history =~ @sentinel

    for {_origin, objective, edited} <- Enum.take(@cases, 3) do
      refute history =~ objective
      refute history =~ edited
    end

    old = ~s(User set the goal: "User-origin paused objective.")
    new = ~s(User set the goal: "User-origin edited objective.")
    assert occurrences(history, old) == 1
    assert occurrences(history, new) == 1
    assert {old_position, _} = :binary.match(history, old)
    assert {new_position, _} = :binary.match(history, new)
    assert old_position < new_position
    assert occurrences(history, ~s(User set goal status: "paused".)) == 1
    refute history =~ "User set goal status: null"
    assert occurrences(history, "User cleared the goal.") == 2
    [_, first_tail] = String.split(history, new, parts: 2)
    assert occurrences(first_tail, "User cleared the goal.") == 2
  end

  defp assert_single_completion(events, id, turn) do
    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/started",
               do: event.wire["params"]
             )

    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/completed",
               do: event.wire["params"]
             )

    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))

    assert [message] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]["item"]
             )

    assert message["id"] == "fixture-message-1"
    assert message["text"] == "Deterministic local fixture answer"
  end

  defp assert_goal_notice(pid, method, expected) do
    events = await_goal_notice(pid, method, [], System.monotonic_time(:millisecond) + 5_000)

    goals =
      for event <- events,
          event.wire["method"] in ["thread/goal/updated", "thread/goal/cleared"],
          do: {event.wire["method"], event.wire["params"]}

    assert goals == [{method, expected}]
  end

  defp await_goal_notice(pid, method, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    assert_inert_events(events)
    acc = acc ++ events

    if Enum.any?(acc, &(&1.wire["method"] == method)) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline, "Native goal-origin notice deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Native goal-origin notification gap")
      after
        20 -> :ok
      end

      await_goal_notice(pid, method, acc, deadline)
    end
  end

  defp assert_no_goal_notice(ctx, pid) do
    assert_no_goal_notice_until(pid, System.monotonic_time(:millisecond) + 200)
    assert_inert(ctx, pid)
  end

  defp assert_no_goal_notice_until(pid, deadline) do
    assert {:ok, events} = Session.drain(pid)
    assert_inert_events(events)

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ["thread/goal/updated", "thread/goal/cleared"])
           )

    if System.monotonic_time(:millisecond) < deadline do
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Native repeated-clear notification gap")
      after
        20 -> :ok
      end

      assert_no_goal_notice_until(pid, deadline)
    end
  end

  defp assert_inert(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert {:ok, events} = Session.drain(pid)
    assert_inert_events(events)

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ["thread/goal/updated", "thread/goal/cleared"])
           )

    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp assert_inert_events(events) do
    refute Enum.any?(
             events,
             &(&1.kind == :server_request or
                 &1.wire["method"] in ["error", "turn/started", "turn/completed"])
           )
  end

  defp occurrences(text, fragment), do: length(String.split(text, fragment)) - 1
  defp set_goal(pid, params), do: call(pid, "thread/goal/set", params)["goal"]
  defp get_goal(pid, id), do: call(pid, "thread/goal/get", %{"threadId" => id})["goal"]
end
