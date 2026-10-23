defmodule Samgita.Repo.Migrations.AddNativeRuntimeJournal do
  use Ecto.Migration

  def up do
    alter table(:agents) do
      add :runtime_driver, :text
      add :runtime_version, :text
    end

    create constraint(:agents, :known_native_runtime,
             check:
               "(runtime_driver IS NULL AND runtime_version IS NULL) OR (runtime_driver IS NOT NULL AND runtime_version IS NOT NULL AND runtime_driver = 'codex' AND runtime_version = '0.163.0')"
           )

    create unique_index(:task_attempts, [:id, :project_id, :task_id, :agent_id, :session_id],
             name: :native_attempt_scope
           )

    create table(:native_runtime_bindings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :task_id, references(:tasks, type: :uuid, on_delete: :restrict), null: false
      add :attempt_id, references(:task_attempts, type: :uuid, on_delete: :restrict), null: false
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false

      add :session_id, references(:execution_sessions, type: :uuid, on_delete: :restrict),
        null: false

      add :connection_id, references(:agent_connections, type: :uuid, on_delete: :restrict),
        null: false

      add :connection_generation, :bigint, null: false
      add :fence, :bigint, null: false
      add :execution_epoch, :bigint, null: false
      add :runtime_ref, :uuid, null: false
      add :instance_id, :uuid, null: false
      add :driver_generation, :integer, null: false
      add :driver, :text, null: false, default: "codex"
      add :driver_version, :text, null: false, default: "0.163.0"
      add :fingerprint_key_id, :text, null: false
      add :experimental, :boolean, null: false, default: false
      add :state, :text, null: false, default: "open"
      add :source_sequence, :bigint, null: false, default: 0
      add :notification_gap, :boolean, null: false, default: false
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:native_runtime_bindings, [:attempt_id])
    create unique_index(:native_runtime_bindings, [:runtime_ref])
    create index(:native_runtime_bindings, [:project_id, :agent_id])

    execute "ALTER TABLE native_runtime_bindings ADD CONSTRAINT native_runtime_attempt_scope FOREIGN KEY (attempt_id, project_id, task_id, agent_id, session_id) REFERENCES task_attempts(id, project_id, task_id, agent_id, session_id)"

    create constraint(:native_runtime_bindings, :native_runtime_contract,
             check:
               "driver = 'codex' AND driver_version = '0.163.0' AND driver_generation > 0 AND state IN ('open','closed') AND source_sequence >= 0"
           )

    create table(:native_runtime_events, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :runtime_id, references(:native_runtime_bindings, type: :uuid, on_delete: :restrict),
        null: false

      add :instance_id, :uuid, null: false
      add :driver_generation, :integer, null: false
      add :source_sequence, :bigint, null: false
      add :kind, :text, null: false
      add :method, :text, null: false
      add :fingerprint, :text, null: false
      add :request_id_digest, :text
      add :thread_id_digest, :text
      add :native_payload, :map, null: false
      add :state, :text, null: false
      add :expires_at, :utc_datetime_usec
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:native_runtime_events, [:runtime_id, :instance_id, :source_sequence])

    create unique_index(:native_runtime_events, [:runtime_id, :instance_id, :request_id_digest],
             where: "kind = 'server_request'"
           )

    create index(:native_runtime_events, [:runtime_id, :state, :expires_at])

    create table(:native_runtime_operations, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :runtime_id, references(:native_runtime_bindings, type: :uuid, on_delete: :restrict),
        null: false

      add :interaction_id, references(:native_runtime_events, type: :uuid, on_delete: :restrict)
      add :instance_id, :uuid, null: false
      add :driver_generation, :integer, null: false
      add :direction, :text, null: false
      add :method, :text, null: false
      add :wire_id_digest, :text, null: false
      add :request_payload, :map, null: false
      add :response_payload, :map
      add :state, :text, null: false, default: "prepared"
      add :effect, :text, null: false
      add :dispatch_token_digest, :binary
      add :dispatch_expires_at, :utc_datetime_usec
      add :timeout_ms, :integer, null: false, default: 30_000
      add :evidence_ref, :text
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :native_runtime_operations,
             [:runtime_id, :instance_id, :direction, :wire_id_digest],
             name: :native_runtime_request_identity
           )

    create index(:native_runtime_operations, [:runtime_id, :state])

    create constraint(:native_runtime_operations, :native_operation_contract,
             check:
               "state IN ('prepared','in_flight','completed','native_error','sent_unconfirmed','uncertain','cancelled','reconciled') AND direction IN ('client_request','client_notification','client_response') AND effect IN ('read','mutation')"
           )

    create table(:native_runtime_links, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :runtime_id, references(:native_runtime_bindings, type: :uuid, on_delete: :restrict),
        null: false

      add :kind, :text, null: false
      add :external_id, :text, null: false
      add :parent_external_id, :text
      add :state, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:native_runtime_links, [:runtime_id, :kind, :external_id])
  end

  def down do
    raise "Native journals preserve history; disable dispatch and use a compatible binary"
  end
end
