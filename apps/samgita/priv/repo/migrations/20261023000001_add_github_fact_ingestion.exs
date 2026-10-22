defmodule Samgita.Repo.Migrations.AddGithubFactIngestion do
  use Ecto.Migration

  def up do
    create table(:github_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :host, :text, null: false
      add :app_id, :text, null: false
      add :installation_id, :text, null: false
      add :private_key_ref, :text, null: false
      add :webhook_secret_ref, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :state, :text, null: false, default: "configured"
      add :version, :integer, null: false, default: 1
      add :rate_limited_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_connections, [:host, :app_id, :installation_id])

    create table(:github_repositories, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :connection_id, references(:github_connections, type: :uuid, on_delete: :restrict),
        null: false

      add :repository_id, references(:repositories, type: :uuid, on_delete: :restrict),
        null: false

      add :external_id, :text, null: false
      add :full_name, :text, null: false
      add :default_branch, :text, null: false
      add :permissions, :map, null: false, default: %{}
      add :state, :text, null: false, default: "verified"
      add :version, :integer, null: false, default: 1
      add :verified_at, :utc_datetime_usec, null: false
      add :connection_version, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_repositories, [:connection_id, :external_id])

    create table(:github_project_mappings, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :github_repository_id,
          references(:github_repositories, type: :uuid, on_delete: :restrict),
          null: false

      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false

      add :project_repository_id,
          references(:project_repositories, type: :uuid, on_delete: :restrict),
          null: false

      add :enabled, :boolean, null: false, default: true
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_project_mappings, [:github_repository_id, :project_id])

    create table(:github_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :connection_id, references(:github_connections, type: :uuid, on_delete: :restrict),
        null: false

      add :delivery_id, :text, null: false
      add :body_digest, :text, null: false
      add :event_name, :text, null: false
      add :action, :text
      add :installation_id, :text
      add :repository_external_id, :text
      add :state, :text, null: false
      add :reason, :text
      add :payload, :map, null: false, default: %{}
      add :event_ids, {:array, :uuid}, null: false, default: []
      add :received_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_deliveries, [:connection_id, :delivery_id])

    create table(:github_objects, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :github_repository_id,
          references(:github_repositories, type: :uuid, on_delete: :restrict),
          null: false

      add :kind, :text, null: false
      add :resource_id, :text, null: false
      add :facts, :map, null: false, default: %{}
      add :untrusted_input, :map, null: false, default: %{}
      add :external_updated_at, :utc_datetime_usec
      add :observed_at, :utc_datetime_usec, null: false
      add :source_id, :text, null: false
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_objects, [:github_repository_id, :kind, :resource_id])

    create table(:github_observations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :object_id, references(:github_objects, type: :uuid, on_delete: :restrict), null: false
      add :version, :integer, null: false
      add :facts, :map, null: false
      add :untrusted_input, :map, null: false
      add :external_updated_at, :utc_datetime_usec
      add :observed_at, :utc_datetime_usec, null: false
      add :source_id, :text, null: false
    end

    create unique_index(:github_observations, [:object_id, :version])

    create table(:github_syncs, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :github_repository_id,
          references(:github_repositories, type: :uuid, on_delete: :restrict),
          null: false

      add :kind, :text, null: false
      add :resource_id, :text, null: false, default: ""
      add :page, :integer, null: false, default: 1
      add :since, :utc_datetime_usec
      add :state, :text, null: false, default: "pending"
      add :generation, :bigint, null: false, default: 1
      add :fence, :bigint, null: false, default: 0
      add :lease_id, :uuid
      add :lease_expires_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :scan_started_at, :utc_datetime_usec
      add :last_scan_started_at, :utc_datetime_usec
      add :attempt_count, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :last_completed_at, :utc_datetime_usec
      add :last_error_class, :text
      add :last_error_code, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_syncs, [:github_repository_id, :kind, :resource_id])
    create index(:github_syncs, [:state, :next_attempt_at])
  end

  def down do
    raise "GitHub provenance is forward-only; disable ingestion/queues and retain history"
  end
end
