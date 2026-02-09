defmodule Samgita.Domain.SnapshotTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Snapshot

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Snapshot.changeset(%Snapshot{}, %{
          phase: "bootstrap",
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid without phase" do
      changeset =
        Snapshot.changeset(%Snapshot{}, %{project_id: Ecto.UUID.generate()})

      refute changeset.valid?
      assert %{phase: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without project_id" do
      changeset = Snapshot.changeset(%Snapshot{}, %{phase: "bootstrap"})
      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults map fields to empty maps" do
      changeset =
        Snapshot.changeset(%Snapshot{}, %{
          phase: "development",
          project_id: Ecto.UUID.generate()
        })

      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.agent_states == %{}
      assert snapshot.task_queue_state == %{}
      assert snapshot.memory_state == %{}
    end

    test "accepts optional map fields" do
      changeset =
        Snapshot.changeset(%Snapshot{}, %{
          phase: "qa",
          project_id: Ecto.UUID.generate(),
          agent_states: %{"agent-1" => %{"status" => "idle"}},
          task_queue_state: %{"pending" => 3, "running" => 1},
          memory_state: %{"episodic_count" => 5}
        })

      assert changeset.valid?
    end
  end
end
