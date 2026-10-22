defmodule Samgita.Repo.Migrations.AddNeutralDomain do
  use Ecto.Migration

  def up do
    # Historical migrations above are restored verbatim. Never rewrite their rows.
    alter table(:projects) do
      modify :git_url, :text, null: true
      add :description, :text
      add :state, :text
      add :version, :integer, null: false, default: 1
      add :event_sequence, :bigint, null: false, default: 0
      add :migration_metadata, :map, null: false, default: %{}
    end

    drop_if_exists unique_index(:projects, [:git_url])

    create constraint(:projects, :neutral_project_state,
             check: "state IS NULL OR state IN ('active','paused','archived')"
           )

    alter table(:tasks) do
      add :title, :text
      add :description, :text
      add :state, :text
      add :version, :integer, null: false, default: 1
      add :adopted, :boolean, null: false, default: false
      add :execution_hold, :boolean, null: false, default: false
      add :required_capabilities, {:array, :text}, null: false, default: []
      add :migration_metadata, :map, null: false, default: %{}
      add :accepted_at, :utc_datetime_usec
      add :fence_counter, :bigint, null: false, default: 0
    end

    create constraint(:tasks, :neutral_task_state,
             check:
               "state IS NULL OR state IN ('open','in_progress','blocked','awaiting_review','accepted','failed','cancelled')"
           )

    create unique_index(:tasks, [:id, :project_id])
    # NOT VALID preserves inconsistent historical relationships for review while
    # PostgreSQL checks newly written parent references.
    execute "ALTER TABLE tasks ADD CONSTRAINT task_parent_same_project FOREIGN KEY (parent_task_id, project_id) REFERENCES tasks(id, project_id) NOT VALID"

    create table(:platform_authority, primary_key: false) do
      add :id, :integer, primary_key: true
      add :owner, :text, null: false, default: "none"
      add :admission_open, :boolean, null: false, default: false
      add :epoch, :bigint, null: false, default: 1
      add :version, :integer, null: false, default: 1
      add :evidence, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:platform_authority, :authority_singleton,
             check:
               "id = 1 AND owner IN ('none', 'hub') AND (owner = 'hub' OR NOT admission_open)"
           )

    execute "INSERT INTO platform_authority (id, inserted_at, updated_at) VALUES (1, now(), now())"

    create table(:agents, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :implementation, :text
      add :enabled, :boolean, null: false, default: true
      add :capacity, :integer, null: false, default: 1
      add :advertised_capabilities, {:array, :text}, null: false, default: []
      add :approved_capabilities, {:array, :text}, null: false, default: []
      add :protocol, :text, null: false
      add :protocol_version, :text, null: false
      add :endpoint_metadata, :map, null: false, default: %{}
      add :credential_ref, :text
      add :generation, :integer, null: false, default: 0
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:agents, :positive_capacity, check: "capacity BETWEEN 1 AND 1000")

    create table(:agent_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :digest, :binary, null: false
      add :reference, :text
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_credentials, [:digest])

    create table(:agent_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false

      add :credential_id, references(:agent_credentials, type: :uuid, on_delete: :restrict),
        null: false

      add :generation, :bigint, null: false
      add :state, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_connections, [:agent_id, :generation])

    create unique_index(:agent_connections, [:agent_id],
             where: "state = 'connected'",
             name: :one_current_connection
           )

    create table(:project_agents, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :roles, {:array, :text}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_agents, [:project_id, :agent_id])

    create constraint(:project_agents, :known_roles,
             check: "roles <@ ARRAY['observer','worker','manager','reviewer']::text[]"
           )

    create table(:repositories, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :text, null: false
      add :provider, :text
      add :host, :text
      add :external_id, :text
      add :display_name, :text
      add :verification, :text, null: false, default: "unverified"
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:repositories, [:provider, :host, :external_id],
             where: "verification = 'verified'"
           )

    create table(:repository_aliases, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :repository_id, references(:repositories, type: :uuid, on_delete: :restrict),
        null: false

      add :url, :text, null: false
      add :normalized_url, :text, null: false
      add :source, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:repository_aliases, [:repository_id, :url])
    create index(:repository_aliases, [:normalized_url])

    create table(:project_repositories, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false

      add :repository_id, references(:repositories, type: :uuid, on_delete: :restrict),
        null: false

      add :role, :text, null: false, default: "source"
      add :primary, :boolean, null: false, default: false
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_repositories, [:project_id, :repository_id])

    create unique_index(:project_repositories, [:project_id],
             where: "\"primary\"",
             name: :one_primary_repository
           )

    create table(:execution_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false

      add :connection_id, references(:agent_connections, type: :uuid, on_delete: :restrict),
        null: false

      add :external_id, :text, null: false
      add :state, :text, null: false, default: "open"
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:execution_sessions, [:agent_id, :project_id, :external_id])

    create table(:task_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :task_id, references(:tasks, type: :uuid, on_delete: :restrict), null: false
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :session_id, references(:execution_sessions, type: :uuid, on_delete: :restrict)

      add :connection_id, references(:agent_connections, type: :uuid, on_delete: :restrict),
        null: false

      add :connection_generation, :bigint, null: false
      add :number, :integer, null: false
      add :state, :text, null: false
      add :version, :integer, null: false, default: 1
      add :fence, :bigint, null: false
      add :execution_epoch, :bigint, null: false
      add :proof_key_id, :text, null: false
      add :lease_expires_at, :utc_datetime_usec, null: false
      add :start_deadline, :utc_datetime_usec, null: false
      add :execution_deadline, :utc_datetime_usec, null: false
      add :terminal_at, :utc_datetime_usec
      add :outcome, :map, null: false, default: %{}
      add :effects_resolved, :boolean, null: false, default: false
      add :resolution_evidence, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:task_attempts, [:task_id, :number])

    create unique_index(:task_attempts, [:task_id],
             where: "state IN ('leased','running')",
             name: :one_active_attempt_per_task
           )

    create index(:task_attempts, [:agent_id, :effects_resolved])

    create constraint(:task_attempts, :known_attempt_state,
             check:
               "state IN ('leased','running','succeeded','failed','expired','released','cancelled')"
           )

    execute "ALTER TABLE task_attempts ADD CONSTRAINT attempt_task_scope FOREIGN KEY (task_id, project_id) REFERENCES tasks(id, project_id)"

    create table(:decision_records, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :task_id, references(:tasks, type: :uuid, on_delete: :restrict), null: false
      add :attempt_id, references(:task_attempts, type: :uuid, on_delete: :restrict)
      add :author_agent_id, references(:agents, type: :uuid, on_delete: :restrict)
      add :kind, :text, null: false
      add :verdict, :text, null: false
      add :summary, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:decision_records, [:task_id, :inserted_at])

    execute "ALTER TABLE decision_records ADD CONSTRAINT decision_task_scope FOREIGN KEY (task_id, project_id) REFERENCES tasks(id, project_id)"

    create table(:artifact_references, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :task_id, references(:tasks, type: :uuid, on_delete: :restrict), null: false
      add :attempt_id, references(:task_attempts, type: :uuid, on_delete: :restrict)
      add :created_by_agent_id, references(:agents, type: :uuid, on_delete: :restrict)
      add :kind, :text, null: false
      add :locator, :text, null: false
      add :digest, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    execute "ALTER TABLE artifact_references ADD CONSTRAINT artifact_task_scope FOREIGN KEY (task_id, project_id) REFERENCES tasks(id, project_id)"

    create table(:command_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :principal, :text, null: false
      add :command_id, :uuid, null: false
      add :operation, :text, null: false
      add :request_digest, :text, null: false
      add :result, :map, null: false
      add :event_ids, {:array, :uuid}, null: false, default: []
      add :execution_epoch, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_receipts, [:principal, :command_id])

    create table(:domain_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict)
      add :sequence, :bigint
      add :type, :text, null: false
      add :schema_version, :text, null: false
      add :actor, :text, null: false
      add :command_id, :uuid, null: false
      add :resource_type, :text, null: false
      add :resource_id, :uuid, null: false
      add :data, :map, null: false, default: %{}
      add :before_state, :map
      add :after_state, :map
      add :created_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:domain_events, [:project_id, :sequence])
    create index(:domain_events, [:actor, :command_id])

    create table(:event_subscriptions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :types, {:array, :text}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create table(:event_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :event_id, references(:domain_events, type: :uuid, on_delete: :restrict), null: false

      add :subscription_id, references(:event_subscriptions, type: :uuid, on_delete: :restrict),
        null: false

      add :subscription_revision, :integer, null: false
      add :state, :text, null: false, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_deliveries, [:event_id, :subscription_id])

    create table(:migration_mappings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_table, :text, null: false
      add :source_id, :text, null: false
      add :source_digest, :text, null: false
      add :status, :text, null: false
      add :target_id, :uuid
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:migration_mappings, [:source_table, :source_id])
  end

  def down do
    raise "Preservation migration is forward-only; close admissions and use a compatible binary"
  end
end
