defmodule SamgitaMemory.PRD.Event do
  @moduledoc "Ecto schema for PRD execution events."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types [
    :requirement_started,
    :requirement_completed,
    :decision_made,
    :blocker_hit,
    :blocker_resolved,
    :test_passed,
    :test_failed,
    :revision,
    :review_feedback,
    :agent_handoff,
    :error_encountered,
    :rollback
  ]

  schema "sm_prd_events" do
    belongs_to :execution, SamgitaMemory.PRD.Execution

    field :type, Ecto.Enum, values: @event_types
    field :requirement_id, :string
    field :summary, :string
    field :detail, :map, default: %{}
    field :agent_id, :string
    field :thinking_chain_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :execution_id,
      :type,
      :requirement_id,
      :summary,
      :detail,
      :agent_id,
      :thinking_chain_id
    ])
    |> validate_required([:execution_id, :type, :summary])
    |> foreign_key_constraint(:execution_id)
  end

  def event_types, do: @event_types
end
