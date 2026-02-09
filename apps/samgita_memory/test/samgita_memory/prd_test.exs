defmodule SamgitaMemory.PRDTest do
  use SamgitaMemory.DataCase, async: true

  alias SamgitaMemory.PRD
  alias SamgitaMemory.PRD.{Execution, Event, Decision}

  describe "start_execution/2" do
    test "creates new execution" do
      assert {:ok, execution} = PRD.start_execution("path/to/prd.md", title: "Test PRD")
      assert execution.prd_ref == "path/to/prd.md"
      assert execution.title == "Test PRD"
      assert execution.status == :in_progress
    end

    test "returns existing execution on duplicate prd_ref" do
      {:ok, first} = PRD.start_execution("same/prd.md")
      {:ok, second} = PRD.start_execution("same/prd.md")
      assert first.id == second.id
    end

    test "transitions not_started to in_progress" do
      {:ok, execution} = PRD.start_execution("new/prd.md")
      # Already in_progress from creation
      assert execution.status == :in_progress
    end
  end

  describe "append_event/2" do
    setup do
      {:ok, execution} = PRD.start_execution("test/prd.md")
      %{execution: execution}
    end

    test "creates an event", %{execution: execution} do
      assert {:ok, event} =
               PRD.append_event(execution.id, %{
                 type: :requirement_started,
                 summary: "Started auth module",
                 requirement_id: "req-1"
               })

      assert event.type == :requirement_started
      assert event.summary == "Started auth module"
      assert event.requirement_id == "req-1"
      assert event.execution_id == execution.id
    end

    test "supports all event types", %{execution: execution} do
      for type <- Event.event_types() do
        assert {:ok, event} =
                 PRD.append_event(execution.id, %{
                   type: type,
                   summary: "Event of type #{type}"
                 })

        assert event.type == type
      end
    end
  end

  describe "record_decision/2" do
    setup do
      {:ok, execution} = PRD.start_execution("test/prd.md")
      %{execution: execution}
    end

    test "creates a decision", %{execution: execution} do
      assert {:ok, decision} =
               PRD.record_decision(execution.id, %{
                 decision: "Use JWT for auth",
                 reason: "Simpler than OAuth for this use case",
                 alternatives: ["OAuth 2.0", "Session-based auth"],
                 requirement_id: "req-1",
                 agent_id: "eng-backend"
               })

      assert decision.decision == "Use JWT for auth"
      assert decision.reason == "Simpler than OAuth for this use case"
      assert decision.alternatives == ["OAuth 2.0", "Session-based auth"]
    end
  end

  describe "get_context/2" do
    setup do
      {:ok, execution} = PRD.start_execution("context/prd.md", title: "Context Test")

      {:ok, _} =
        PRD.append_event(execution.id, %{
          type: :requirement_started,
          summary: "Started feature A"
        })

      {:ok, _} =
        PRD.append_event(execution.id, %{
          type: :requirement_completed,
          summary: "Completed feature A"
        })

      {:ok, _} =
        PRD.record_decision(execution.id, %{
          decision: "Use ETS caching",
          reason: "Performance"
        })

      %{execution: execution}
    end

    test "returns full context", %{execution: execution} do
      assert {:ok, context} = PRD.get_context(execution.id)
      assert context.execution.id == execution.id
      assert length(context.recent_events) == 2
      assert length(context.decisions) == 1
    end

    test "caches context in ETS", %{execution: execution} do
      # First call populates cache
      {:ok, _} = PRD.get_context(execution.id)

      # Second call should hit cache
      {:ok, cached} = PRD.get_context(execution.id)
      assert cached.execution.id == execution.id
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = PRD.get_context(Ecto.UUID.generate())
    end

    test "respects event_limit", %{execution: execution} do
      assert {:ok, context} = PRD.get_context(execution.id, event_limit: 1)
      # Cache invalidation needed for fresh query
      SamgitaMemory.Cache.PRDTable.invalidate(execution.id)
      {:ok, context} = PRD.get_context(execution.id, event_limit: 1)
      assert length(context.recent_events) == 1
    end
  end

  describe "update_status/2" do
    test "updates execution status" do
      {:ok, execution} = PRD.start_execution("status/prd.md")
      assert {:ok, updated} = PRD.update_status(execution.id, :paused)
      assert updated.status == :paused
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = PRD.update_status(Ecto.UUID.generate(), :completed)
    end
  end

  describe "full PRD lifecycle" do
    test "create → events → decisions → resume → complete" do
      # Start
      {:ok, exec} = PRD.start_execution("lifecycle/prd.md", title: "Lifecycle Test")
      assert exec.status == :in_progress

      # Add events
      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :requirement_started,
          summary: "Started auth",
          requirement_id: "auth-1"
        })

      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :blocker_hit,
          summary: "Blocked on API key",
          requirement_id: "auth-1"
        })

      # Record decision
      {:ok, _} =
        PRD.record_decision(exec.id, %{
          decision: "Use env var for API key",
          requirement_id: "auth-1"
        })

      # Resolve blocker
      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :blocker_resolved,
          summary: "API key configured",
          requirement_id: "auth-1"
        })

      # Complete requirement
      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :requirement_completed,
          summary: "Auth complete",
          requirement_id: "auth-1"
        })

      # Pause and resume
      {:ok, paused} = PRD.update_status(exec.id, :paused)
      assert paused.status == :paused

      {:ok, resumed} = PRD.update_status(exec.id, :in_progress)
      assert resumed.status == :in_progress

      # Complete PRD
      {:ok, completed} = PRD.update_status(exec.id, :completed)
      assert completed.status == :completed

      # Verify context
      SamgitaMemory.Cache.PRDTable.invalidate(exec.id)
      {:ok, context} = PRD.get_context(exec.id)
      assert length(context.recent_events) == 4
      assert length(context.decisions) == 1
    end
  end
end
