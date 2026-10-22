defmodule Samgita.Repo.Migrations.CreateFeatures do
  use Ecto.Migration

  def change do
    create table(:features, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :priority, :string, null: false, default: "medium"
      add :owner_email, :string
      add :documentation_url, :string
      add :max_retries, :integer, default: 3
      add :timeout_seconds, :integer, default: 30
      add :tags, {:array, :string}, default: []
      add :metadata, :map, default: %{}
      add :enabled, :boolean, default: false, null: false

      timestamps(type: :naive_datetime_usec)
    end

    create unique_index(:features, [:name])
    create index(:features, [:status])
    create index(:features, [:enabled])
  end
end
