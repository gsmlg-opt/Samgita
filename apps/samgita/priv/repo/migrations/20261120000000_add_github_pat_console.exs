defmodule Samgita.Repo.Migrations.AddGitHubPatConsole do
  use Ecto.Migration

  def change do
    create table(:github_pat_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :github_id, :bigint, null: false
      add :login, :text, null: false
      add :ciphertext, :binary, null: false
      add :credential_version, :uuid, null: false
      add :version, :uuid, null: false
      add :retry_at, :bigint
    end

    create unique_index(:github_pat_connections, ["(true)"], name: :github_pat_singleton)

    create table(:github_pat_selections, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :github_id, :bigint, primary_key: true
      add :owner_id, :bigint, null: false
      add :owner, :text, null: false
      add :name, :text, null: false
    end
  end
end
