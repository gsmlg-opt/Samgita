defmodule SamgitaMemory.PRD.Decision do
  @moduledoc "Ecto schema for decisions made during PRD execution."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sm_prd_decisions" do
    belongs_to :execution, SamgitaMemory.PRD.Execution

    field :requirement_id, :string
    field :decision, :string
    field :reason, :string
    field :alternatives, {:array, :string}, default: []
    field :agent_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [
      :execution_id,
      :requirement_id,
      :decision,
      :reason,
      :alternatives,
      :agent_id
    ])
    |> validate_required([:execution_id, :decision])
    |> foreign_key_constraint(:execution_id)
  end
end
