defmodule Samgita.Domain.Prd do
  @moduledoc "Ecto schema for Product Requirements Documents."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:draft, :in_progress, :review, :approved, :archived]

  schema "prds" do
    field :title, :string
    field :content, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :version, :integer, default: 1
    field :metadata, :map, default: %{}

    belongs_to :project, Samgita.Domain.Project
    has_many :chat_messages, Samgita.Domain.ChatMessage

    timestamps(type: :utc_datetime)
  end

  def changeset(prd, attrs) do
    prd
    |> cast(attrs, [:title, :content, :status, :version, :metadata, :project_id])
    |> validate_required([:title, :project_id])
    |> foreign_key_constraint(:project_id)
  end

  def statuses, do: @statuses
end
