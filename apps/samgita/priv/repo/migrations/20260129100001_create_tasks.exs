defmodule Samgita.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :priority, :integer, default: 10
      add :status, :string, default: "pending", null: false
      add :payload, :map, default: %{}
      add :result, :map
      add :error, :map
      add :agent_id, :string
      add :attempts, :integer, default: 0
      add :queued_at, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :tokens_used, :integer, default: 0
      add :duration_ms, :integer

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
    create index(:tasks, [:priority])
    create index(:tasks, [:parent_task_id])
  end
end
