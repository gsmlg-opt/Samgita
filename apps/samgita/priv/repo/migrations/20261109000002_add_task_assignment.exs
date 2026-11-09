defmodule Samgita.Repo.Migrations.AddTaskAssignment do
  use Ecto.Migration

  # Coordinated delegation (design §10): a coordinator explicitly assigns a Task
  # to an executor Agent before it can be claimed. The legacy string
  # `tasks.agent_id` stays historical provenance and is not reused.
  def change do
    alter table(:tasks) do
      add :assignee_agent_id, references(:agents, type: :uuid, on_delete: :restrict)
      add :assigned_at, :utc_datetime_usec
    end

    create index(:tasks, [:project_id, :assignee_agent_id],
             where: "assignee_agent_id IS NOT NULL"
           )
  end
end
