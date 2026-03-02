defmodule Samgita.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :title, :string, null: false
      add :message, :text, null: false
      add :type, :string, null: false, default: "info"
      add :priority, :integer, default: 3
      add :recipient_email, :string
      add :webhook_url, :string
      add :status, :string, null: false, default: "pending"
      add :retry_count, :integer, default: 0
      add :max_retries, :integer, default: 3
      add :timeout_seconds, :integer, default: 30
      add :metadata, :map, default: %{}
      add :sent_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:project_id])
    create index(:notifications, [:status])
    create index(:notifications, [:type])
  end
end
