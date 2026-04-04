defmodule Samgita.Domain.TaskTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Task

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Task.changeset(%Task{}, %{type: "frontend", project_id: Ecto.UUID.generate()})

      assert changeset.valid?
    end

    test "invalid without type" do
      changeset = Task.changeset(%Task{}, %{project_id: Ecto.UUID.generate()})
      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without project_id" do
      changeset = Task.changeset(%Task{}, %{type: "frontend"})
      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to pending" do
      changeset =
        Task.changeset(%Task{}, %{type: "frontend", project_id: Ecto.UUID.generate()})

      task = Ecto.Changeset.apply_changes(changeset)
      assert task.status == :pending
    end

    test "defaults priority to 10" do
      changeset =
        Task.changeset(%Task{}, %{type: "frontend", project_id: Ecto.UUID.generate()})

      task = Ecto.Changeset.apply_changes(changeset)
      assert task.priority == 10
    end

    test "defaults attempts to 0" do
      changeset =
        Task.changeset(%Task{}, %{type: "frontend", project_id: Ecto.UUID.generate()})

      task = Ecto.Changeset.apply_changes(changeset)
      assert task.attempts == 0
    end

    test "accepts optional fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Task.changeset(%Task{}, %{
          type: "backend",
          project_id: Ecto.UUID.generate(),
          priority: 5,
          status: :running,
          payload: %{"action" => "build"},
          result: %{"output" => "ok"},
          error: %{"reason" => "timeout"},
          agent_id: "agent-123",
          attempts: 2,
          queued_at: now,
          started_at: now,
          completed_at: now,
          tokens_used: 1500,
          duration_ms: 3000
        })

      assert changeset.valid?
    end

    test "statuses/0 returns all valid statuses" do
      assert Task.statuses() == [
               :pending,
               :blocked,
               :assigned,
               :running,
               :completed,
               :failed,
               :skipped,
               :dead_letter
             ]
    end

    test "statuses/0 includes blocked, assigned, and skipped" do
      statuses = Task.statuses()
      assert :blocked in statuses
      assert :assigned in statuses
      assert :skipped in statuses
    end

    test "new dependency fields have correct defaults" do
      changeset =
        Task.changeset(%Task{}, %{type: "frontend", project_id: Ecto.UUID.generate()})

      task = Ecto.Changeset.apply_changes(changeset)
      assert task.depends_on_ids == []
      assert task.dependency_outputs == %{}
      assert task.estimated_duration_minutes == nil
      assert task.wave == nil
    end

    test "accepts dependency fields" do
      dep_id = Ecto.UUID.generate()

      changeset =
        Task.changeset(%Task{}, %{
          type: "frontend",
          project_id: Ecto.UUID.generate(),
          depends_on_ids: [dep_id],
          dependency_outputs: %{"result" => "ok"},
          estimated_duration_minutes: 30,
          wave: 2
        })

      assert changeset.valid?
      task = Ecto.Changeset.apply_changes(changeset)
      assert task.depends_on_ids == [dep_id]
      assert task.dependency_outputs == %{"result" => "ok"}
      assert task.estimated_duration_minutes == 30
      assert task.wave == 2
    end
  end
end
