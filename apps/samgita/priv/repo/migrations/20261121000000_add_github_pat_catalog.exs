defmodule Samgita.Repo.Migrations.AddGitHubPatCatalog do
  use Ecto.Migration

  def change do
    create table(:github_pat_catalogs, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :credential_version, :uuid, null: false
      add :generation, :uuid, null: false
      add :status, :text, null: false
      add :data, :map
      add :error_code, :text
      add :prune, :boolean, null: false, default: false
      add :fence, :uuid
      add :job_id, :bigint
    end

    create constraint(:github_pat_catalogs, :github_pat_catalog_status,
             check: "status IN ('refreshing', 'ready', 'failed')"
           )

    create table(:github_pat_owner_selections, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :owner_id, :bigint, primary_key: true
      add :login, :text, null: false
    end
  end
end
