defmodule Samgita.Domain.AgentRun do
  @moduledoc "Ecto schema for agent run records tracking RARV cycle execution."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:idle, :reason, :act, :reflect, :verify, :failed]

  schema "agent_runs" do
    field :agent_type, :string
    field :node, :string
    field :pid, :string
    field :status, Ecto.Enum, values: @statuses, default: :idle
    field :total_tasks, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :total_duration_ms, :integer, default: 0
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :project, Samgita.Domain.Project
    belongs_to :current_task, Samgita.Domain.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(agent_run, attrs) do
    agent_run
    |> cast(attrs, [
      :agent_type,
      :node,
      :pid,
      :status,
      :total_tasks,
      :total_tokens,
      :total_duration_ms,
      :started_at,
      :ended_at,
      :project_id,
      :current_task_id
    ])
    |> validate_required([:agent_type, :project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:current_task_id)
  end

  def statuses, do: @statuses
end
