defmodule Samgita.Domain.EventDelivery do
  @moduledoc false
  use Samgita.Schema

  schema "event_deliveries" do
    field :event_id, :binary_id
    field :subscription_id, :binary_id
    field :subscription_revision, :integer
    field :state, :string, default: "pending"
    field :project_id, :binary_id
    field :agent_id, :binary_id
    field :operation_id, :binary_id
    field :target_digest, :string
    field :version, :integer, default: 1
    field :attempt_count, :integer, default: 0
    field :cycle_attempt_count, :integer, default: 0
    field :max_attempts, :integer, default: 8
    field :next_attempt_at, :utc_datetime_usec
    field :fence, :integer, default: 0
    field :lease_id, :binary_id
    field :lease_expires_at, :utc_datetime_usec
    field :execution_epoch, :integer
    field :last_attempt_id, :binary_id
    field :last_error_class, :string
    field :last_error_code, :string
    field :transport_received_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :processing_status, :string, default: "pending"
    field :remote_outcome_uncertain, :boolean, default: false
    field :result, :map, default: %{}
    timestamps()
  end
end
