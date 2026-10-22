defmodule Samgita.Domain.ArtifactReference do
  @moduledoc "Metadata referring to output; no artifact storage or execution capability."
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "artifact_references" do
    field :project_id, :binary_id
    field :task_id, :binary_id
    field :attempt_id, :binary_id
    field :created_by_agent_id, :binary_id
    field :kind, :string
    field :locator, :string
    field :digest, :string
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
