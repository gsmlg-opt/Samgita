defmodule Samgita.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :content, :text, null: false
      add :importance, :float, default: 0.5
      add :accessed_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:memories, [:project_id])
    create index(:memories, [:type])
  end
end
