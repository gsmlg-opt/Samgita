defmodule Samgita.Repo.Migrations.CreateAgentRuns do
  use Ecto.Migration

  def change do
    create table(:agent_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_type, :string, null: false
      add :node, :string
      add :pid, :string
      add :status, :string, default: "idle", null: false
      add :total_tasks, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :total_duration_ms, :integer, default: 0
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :current_task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:agent_runs, [:project_id])
    create index(:agent_runs, [:status])
  end
end
