defmodule Samgita.Domain.TaskDependency do
  @moduledoc "Ecto schema for task dependency edges in the task DAG."

  use Ecto.Schema
  import Ecto.Changeset

  alias Samgita.Domain.Task

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "task_dependencies" do
    belongs_to :task, Task
    belongs_to :depends_on, Task

    field :dependency_type, :string, default: "hard"

    timestamps(updated_at: false, type: :utc_datetime)
  end

  def changeset(dependency, attrs) do
    dependency
    |> cast(attrs, [:task_id, :depends_on_id, :dependency_type])
    |> validate_required([:task_id, :depends_on_id])
    |> validate_inclusion(:dependency_type, ["hard", "soft"])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:depends_on_id)
    |> unique_constraint([:task_id, :depends_on_id])
  end
end
