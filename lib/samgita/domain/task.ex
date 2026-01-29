defmodule Samgita.Domain.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :running, :completed, :failed, :dead_letter]

  schema "tasks" do
    field :type, :string
    field :priority, :integer, default: 10
    field :status, Ecto.Enum, values: @statuses, default: :pending
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

    belongs_to :project, Samgita.Domain.Project
    belongs_to :parent_task, Samgita.Domain.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :type,
      :priority,
      :status,
      :payload,
      :result,
      :error,
      :agent_id,
      :attempts,
      :queued_at,
      :started_at,
      :completed_at,
      :tokens_used,
      :duration_ms,
      :project_id,
      :parent_task_id
    ])
    |> validate_required([:type, :project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:parent_task_id)
  end

  def statuses, do: @statuses
end
