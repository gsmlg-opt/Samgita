defmodule SamgitaMemory.Repo.Migrations.CreatePrdExecutions do
  use Ecto.Migration

  def change do
    create table(:sm_prd_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :prd_ref, :string, null: false
      add :prd_hash, :string
      add :title, :string
      add :status, :string, default: "not_started", null: false
      add :progress, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sm_prd_executions, [:prd_ref])

    create table(:sm_prd_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id, references(:sm_prd_executions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :requirement_id, :string
      add :summary, :text, null: false
      add :detail, :map, default: %{}
      add :agent_id, :string
      add :thinking_chain_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:sm_prd_events, [:execution_id])
    create index(:sm_prd_events, [:requirement_id])

    create table(:sm_prd_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:sm_prd_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :requirement_id, :string
      add :decision, :text, null: false
      add :reason, :text
      add :alternatives, {:array, :string}, default: []
      add :agent_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:sm_prd_decisions, [:execution_id])
  end
end
