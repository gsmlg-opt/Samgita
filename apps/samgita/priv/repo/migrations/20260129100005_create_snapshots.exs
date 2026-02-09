defmodule Samgita.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  def change do
    create table(:snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :phase, :string, null: false
      add :agent_states, :map, default: %{}
      add :task_queue_state, :map, default: %{}
      add :memory_state, :map, default: %{}

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:snapshots, [:project_id])
  end
end
