defmodule Samgita.Repo.Migrations.AddGitHubPatRepositoryDetails do
  use Ecto.Migration

  def change do
    alter table(:github_pat_items) do
      add :issue_type, :text
      add :labels, {:array, :text}, null: false, default: []
      add :head_sha, :text
    end

    create table(:github_pat_workflow_snapshots, primary_key: false) do
      add :connection_id,
          references(:github_pat_connections, type: :uuid, on_delete: :delete_all),
          primary_key: true

      add :repository_id, :bigint, primary_key: true
      add :credential_version, :uuid, null: false
      add :owner_id, :bigint, null: false
      add :runs, {:array, :map}, null: false, default: []
      add :synced_at, :utc_datetime_usec
      add :error_code, :text
      add :job_id, :bigint
      add :fence, :uuid
    end
  end
end
