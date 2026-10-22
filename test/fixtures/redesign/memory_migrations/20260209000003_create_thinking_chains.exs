defmodule SamgitaMemory.Repo.Migrations.CreateThinkingChains do
  use Ecto.Migration

  def change do
    create table(:sm_thinking_chains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope_type, :string, null: false
      add :scope_id, :string
      add :query, :text
      add :summary, :text
      add :embedding, :vector, size: 1536
      add :status, :string, default: "active", null: false
      add :thoughts, {:array, :map}, default: []
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:sm_thinking_chains, [:scope_type, :scope_id])
    create index(:sm_thinking_chains, [:status])
  end
end
