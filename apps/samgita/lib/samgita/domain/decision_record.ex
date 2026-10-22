defmodule Samgita.Domain.DecisionRecord do
  @moduledoc "A review or management acceptance decision, never a worker completion."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "decision_records" do
    field :project_id, :binary_id
    field :task_id, :binary_id
    field :attempt_id, :binary_id
    field :author_agent_id, :binary_id
    field :kind, :string
    field :verdict, :string
    field :summary, :string
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
