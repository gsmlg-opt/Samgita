defmodule Samgita.Repo.Migrations.CreateTaskDependencies do
  use Ecto.Migration

  def change do
    create table(:task_dependencies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :depends_on_id, references(:tasks, type: :binary_id, on_delete: :delete_all),
        null: false

      add :dependency_type, :string, default: "hard", null: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(:task_dependencies, [:task_id, :depends_on_id])
    create index(:task_dependencies, [:depends_on_id])
  end
end
