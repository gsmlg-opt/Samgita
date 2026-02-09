defmodule SamgitaMemory.Memories.Memory do
  @moduledoc "Ecto schema for episodic, semantic, and procedural memory entries."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @source_types [:conversation, :observation, :user_edit, :prd_event, :compaction]
  @scope_types [:global, :project, :agent]
  @memory_types [:episodic, :semantic, :procedural]

  schema "sm_memories" do
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :source_type, Ecto.Enum, values: @source_types
    field :source_id, :string
    field :scope_type, Ecto.Enum, values: @scope_types
    field :scope_id, :string
    field :memory_type, Ecto.Enum, values: @memory_types
    field :confidence, :float, default: 1.0
    field :access_count, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}
    field :accessed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :content,
      :embedding,
      :source_type,
      :source_id,
      :scope_type,
      :scope_id,
      :memory_type,
      :confidence,
      :access_count,
      :tags,
      :metadata,
      :accessed_at
    ])
    |> validate_required([:content, :source_type, :scope_type, :memory_type])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  def source_types, do: @source_types
  def scope_types, do: @scope_types
  def memory_types, do: @memory_types
end
