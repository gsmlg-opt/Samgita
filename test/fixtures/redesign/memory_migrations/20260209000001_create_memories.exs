defmodule SamgitaMemory.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    create table(:sm_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :source_type, :string, null: false
      add :source_id, :string
      add :scope_type, :string, null: false
      add :scope_id, :string
      add :memory_type, :string, null: false
      add :confidence, :float, default: 1.0, null: false
      add :access_count, :integer, default: 0, null: false
      add :tags, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :accessed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:sm_memories, [:scope_type, :scope_id])
    create index(:sm_memories, [:tags], using: "gin")
    create index(:sm_memories, [:memory_type])
    create index(:sm_memories, [:confidence], where: "confidence > 0.3")
  end
end
