defmodule Samgita.Domain.Snapshot do
  @moduledoc "Ecto schema for periodic state snapshots used in project recovery."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "snapshots" do
    field :phase, :string
    field :agent_states, :map, default: %{}
    field :task_queue_state, :map, default: %{}
    field :memory_state, :map, default: %{}

    belongs_to :project, Samgita.Domain.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:phase, :agent_states, :task_queue_state, :memory_state, :project_id])
    |> validate_required([:phase, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
