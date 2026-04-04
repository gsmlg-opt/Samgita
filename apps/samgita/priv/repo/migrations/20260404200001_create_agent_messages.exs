defmodule Samgita.Repo.Migrations.CreateAgentMessages do
  use Ecto.Migration

  def change do
    create table(:agent_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sender_agent_id, :string, null: false
      add :recipient_agent_id, :string, null: false
      add :message_type, :string, null: false
      add :content, :text, null: false
      add :correlation_id, :binary_id
      add :depth, :integer, default: 0
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:agent_messages, [:project_id, :recipient_agent_id, :inserted_at])
    create index(:agent_messages, [:correlation_id])
  end
end
