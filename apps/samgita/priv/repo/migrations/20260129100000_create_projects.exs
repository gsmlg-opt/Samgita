defmodule Samgita.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :git_url, :string, null: false
      add :working_path, :string
      add :prd_content, :text
      add :phase, :string, default: "bootstrap", null: false
      add :status, :string, default: "pending", null: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:git_url])
  end
end
