defmodule Samgita.Domain.TaskDependencyTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.TaskDependency

  describe "changeset/2" do
    test "valid with task_id and depends_on_id" do
      cs =
        TaskDependency.changeset(%TaskDependency{}, %{
          task_id: Ecto.UUID.generate(),
          depends_on_id: Ecto.UUID.generate()
        })

      assert cs.valid?
    end

    test "invalid without task_id" do
      cs = TaskDependency.changeset(%TaskDependency{}, %{depends_on_id: Ecto.UUID.generate()})
      refute cs.valid?
    end

    test "invalid without depends_on_id" do
      cs = TaskDependency.changeset(%TaskDependency{}, %{task_id: Ecto.UUID.generate()})
      refute cs.valid?
    end

    test "defaults dependency_type to hard" do
      cs =
        TaskDependency.changeset(%TaskDependency{}, %{
          task_id: Ecto.UUID.generate(),
          depends_on_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_field(cs, :dependency_type) == "hard"
    end

    test "accepts soft dependency type" do
      cs =
        TaskDependency.changeset(%TaskDependency{}, %{
          task_id: Ecto.UUID.generate(),
          depends_on_id: Ecto.UUID.generate(),
          dependency_type: "soft"
        })

      assert cs.valid?
    end

    test "rejects invalid dependency type" do
      cs =
        TaskDependency.changeset(%TaskDependency{}, %{
          task_id: Ecto.UUID.generate(),
          depends_on_id: Ecto.UUID.generate(),
          dependency_type: "invalid"
        })

      refute cs.valid?
    end
  end
end
