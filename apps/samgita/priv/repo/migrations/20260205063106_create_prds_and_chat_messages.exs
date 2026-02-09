defmodule Samgita.Repo.Migrations.CreatePrdsAndChatMessages do
  use Ecto.Migration

  def change do
    create table(:prds, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :content, :text
      add :status, :string, default: "draft"
      add :version, :integer, default: 1
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :prd_id, references(:prds, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:prds, [:project_id])
    create index(:prds, [:status])
    create index(:chat_messages, [:prd_id])
    create index(:chat_messages, [:inserted_at])
  end
end
