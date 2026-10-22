defmodule Samgita.Domain.TaskAttempt do
  @moduledoc "One fenced execution, independent of logical Task acceptance."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "task_attempts" do
    field :task_id, :binary_id
    field :project_id, :binary_id
    field :agent_id, :binary_id
    field :session_id, :binary_id
    field :connection_id, :binary_id
    field :connection_generation, :integer
    field :number, :integer
    field :state, :string
    field :version, :integer, default: 1
    field :fence, :integer
    field :execution_epoch, :integer
    field :proof_key_id, :string
    field :lease_expires_at, :utc_datetime_usec
    field :start_deadline, :utc_datetime_usec
    field :execution_deadline, :utc_datetime_usec
    field :terminal_at, :utc_datetime_usec
    field :outcome, :map, default: %{}
    field :effects_resolved, :boolean, default: false
    field :resolution_evidence, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
