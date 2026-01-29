defmodule Samgita.Domain.Memory do
  @moduledoc "Ecto schema for episodic, semantic, and procedural memory entries."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types [:episodic, :semantic, :procedural]

  schema "memories" do
    field :type, Ecto.Enum, values: @types
    field :content, :string
    field :importance, :float, default: 0.5
    field :accessed_at, :utc_datetime

    belongs_to :project, Samgita.Domain.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:type, :content, :importance, :accessed_at, :project_id])
    |> validate_required([:type, :content, :project_id])
    |> validate_number(:importance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:project_id)
  end
end
