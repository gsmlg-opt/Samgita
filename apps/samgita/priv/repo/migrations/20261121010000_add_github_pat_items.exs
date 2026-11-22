defmodule Samgita.Repo.Migrations.AddGitHubPatItems do
  use Ecto.Migration

  def change do
    create table(:github_pat_repository_syncs, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :repository_id, :bigint, primary_key: true
      add :credential_version, :uuid, null: false
      add :owner_id, :bigint
      add :synced_at, :utc_datetime_usec
      add :error_code, :text
      add :job_id, :bigint
    end

    create table(:github_pat_items, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :repository_id, :bigint, primary_key: true
      add :kind, :text, primary_key: true
      add :number, :bigint, primary_key: true
      add :credential_version, :uuid, null: false
      add :title, :text, null: false
      add :state, :text, null: false
      add :author, :text, null: false
      add :github_updated_at, :utc_datetime_usec, null: false
      add :url, :text, null: false
    end

    create constraint(:github_pat_items, :github_pat_item_kind_state,
             check: """
             (kind = 'issue' AND state IN ('open', 'closed')) OR
             (kind = 'pull_request' AND state IN ('open', 'closed', 'merged'))
             """
           )

    create index(
             :github_pat_items,
             [
               :connection_id,
               :credential_version,
               :kind,
               :github_updated_at,
               :repository_id,
               :number
             ],
             name: :github_pat_items_feed_order
           )
  end
end
