defmodule Samgita.Repo.Migrations.AddDependencyFieldsToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :depends_on_ids, {:array, :binary_id}, default: []
      add :dependency_outputs, :map, default: %{}
      add :estimated_duration_minutes, :integer
      add :wave, :integer
    end

    create index(:tasks, [:wave])
  end
end
