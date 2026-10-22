defmodule Samgita.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :path, :string, null: false
      add :content, :text
      add :content_hash, :string
      add :metadata, :map, default: %{}

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:artifacts, [:project_id])
    create index(:artifacts, [:task_id])
  end
end
