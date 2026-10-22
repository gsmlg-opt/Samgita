defmodule Samgita.Repo.Migrations.AddDurableCoordination do
  use Ecto.Migration

  def up do
    alter table(:domain_events) do
      add :correlation_id, :uuid
      add :causation_id, :uuid
      add :source, :text, null: false, default: "domain"
      add :source_id, :text
    end

    execute("UPDATE domain_events SET correlation_id = command_id WHERE correlation_id IS NULL")

    alter table(:event_subscriptions) do
      add :purpose, :text, null: false, default: "subscriber"
      add :target_digest, :text
      add :idempotency_guaranteed, :boolean, null: false, default: false
      add :cursor, :bigint, null: false, default: 0
    end

    create unique_index(:event_subscriptions, [:project_id],
             name: :one_responsible_agent_per_project,
             where: "purpose = 'responsible' AND enabled"
           )

    alter table(:event_deliveries) do
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict)
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict)
      add :operation_id, :uuid
      add :target_digest, :text
      add :version, :integer, null: false, default: 1
      add :attempt_count, :integer, null: false, default: 0
      add :cycle_attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 8
      add :next_attempt_at, :utc_datetime_usec
      add :fence, :bigint, null: false, default: 0
      add :lease_id, :uuid
      add :lease_expires_at, :utc_datetime_usec
      add :execution_epoch, :bigint
      add :last_attempt_id, :uuid
      add :last_error_class, :text
      add :last_error_code, :text
      add :transport_received_at, :utc_datetime_usec
      add :accepted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :processing_status, :text, null: false, default: "pending"
      add :remote_outcome_uncertain, :boolean, null: false, default: false
      add :result, :map, null: false, default: %{}
    end

    # P3 intents have no approved target/operation contract. Preserve them for
    # explicit review instead of upgrading them into network sends.
    execute("""
    UPDATE event_deliveries d SET state = 'legacy_unreviewed',
      project_id = e.project_id, agent_id = s.agent_id
    FROM domain_events e, event_subscriptions s
    WHERE d.event_id = e.id AND d.subscription_id = s.id
    """)

    create unique_index(:event_deliveries, [:operation_id])
    create index(:event_deliveries, [:state, :next_attempt_at])
    create index(:event_deliveries, [:project_id, :id])

    create table(:event_delivery_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :delivery_id, references(:event_deliveries, type: :uuid, on_delete: :restrict),
        null: false

      add :number, :integer, null: false
      add :action, :text, null: false
      add :fence, :bigint, null: false
      add :lease_id, :uuid, null: false
      add :execution_epoch, :bigint, null: false
      add :state, :text, null: false, default: "started"
      add :error_class, :text
      add :error_code, :text
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_delivery_attempts, [:delivery_id, :number])

    create table(:event_acknowledgements, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :delivery_id, references(:event_deliveries, type: :uuid, on_delete: :restrict),
        null: false

      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :attempt_id, references(:event_delivery_attempts, type: :uuid, on_delete: :restrict)
      add :source, :text, null: false
      add :acceptance, :text, null: false
      add :processing_status, :text, null: false
      add :decision_id, :text
      add :result, :map, null: false, default: %{}
      add :result_digest, :text, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_acknowledgements, [:delivery_id, :result_digest])

    create table(:event_recovery_actions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :delivery_id, references(:event_deliveries, type: :uuid, on_delete: :restrict),
        null: false

      add :previous_delivery_id, references(:event_deliveries, type: :uuid, on_delete: :restrict)
      add :command_id, :uuid, null: false
      add :action, :text, null: false
      add :reason, :text, null: false
      add :evidence_ref, :text
      add :risk_acknowledged, :boolean, null: false, default: false
      add :previous_state, :text, null: false
      add :resulting_state, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_recovery_actions, [:delivery_id, :command_id])

    create table(:external_event_inbox, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :source, :text, null: false
      add :external_id, :text, null: false
      add :payload_digest, :text, null: false
      add :event_id, references(:domain_events, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_event_inbox, [:project_id, :source, :external_id])

    create table(:event_schedules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :expression, :text, null: false
      add :timezone, :text, null: false, default: "Etc/UTC"
      add :event_type, :text, null: false, default: "schedule.check"
      add :payload, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true
      add :revision, :integer, null: false, default: 1
      add :version, :integer, null: false, default: 1
      add :scanned_through, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_schedules, [:enabled, :scanned_through])

    create table(:schedule_occurrences, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :schedule_id, references(:event_schedules, type: :uuid, on_delete: :restrict),
        null: false

      add :project_id, references(:projects, type: :uuid, on_delete: :restrict), null: false
      add :revision, :integer, null: false
      add :due_at, :utc_datetime_usec, null: false
      add :event_id, references(:domain_events, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:schedule_occurrences, [:schedule_id, :revision, :due_at])
  end

  def down do
    raise "Coordination history is forward-only; close admissions and use a compatible binary"
  end
end
