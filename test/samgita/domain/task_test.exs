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
      assert Task.statuses() == [:pending, :running, :completed, :failed, :dead_letter]
    end
  end
end
