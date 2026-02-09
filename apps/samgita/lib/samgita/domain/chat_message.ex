defmodule Samgita.Domain.ChatMessage do
  @moduledoc "Ecto schema for chat messages in PRD conversations."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles [:user, :assistant, :system]

  schema "chat_messages" do
    field :role, Ecto.Enum, values: @roles
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :prd, Samgita.Domain.Prd

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :prd_id])
    |> validate_required([:role, :content, :prd_id])
    |> foreign_key_constraint(:prd_id)
  end

  def roles, do: @roles
end
