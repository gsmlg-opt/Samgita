defmodule Samgita.Domain.Task do
  @moduledoc "Logical work with neutral state alongside preserved legacy execution fields."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :project_id, :binary_id
    field :parent_task_id, :binary_id
    field :type, :string
    field :priority, :integer, default: 10
    field :status, :string, default: "pending"
    field :payload, :map, default: %{}
    field :result, :map
    field :error, :map
    field :agent_id, :string
    field :attempts, :integer, default: 0
    field :queued_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :tokens_used, :integer, default: 0
    field :duration_ms, :integer
    field :depends_on_ids, {:array, :binary_id}, default: []
    field :dependency_outputs, :map, default: %{}
    field :estimated_duration_minutes, :integer
    field :wave, :integer
    field :title, :string
    field :description, :string
    field :state, :string
    field :version, :integer, default: 1
    field :adopted, :boolean, default: false
    field :execution_hold, :boolean, default: false
    field :required_capabilities, {:array, :string}, default: []
    field :migration_metadata, :map, default: %{}
    field :accepted_at, :utc_datetime_usec
    field :fence_counter, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end
