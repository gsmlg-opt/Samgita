defmodule Samgita.Domain.AgentMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_messages" do
    belongs_to :project, Samgita.Domain.Project

    field :sender_agent_id, :string
    field :recipient_agent_id, :string
    field :message_type, :string
    field :content, :string
    field :correlation_id, :binary_id
    field :depth, :integer, default: 0
    field :inserted_at, :utc_datetime
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :project_id,
      :sender_agent_id,
      :recipient_agent_id,
      :message_type,
      :content,
      :correlation_id,
      :depth,
      :inserted_at
    ])
    |> validate_required([
      :project_id,
      :sender_agent_id,
      :recipient_agent_id,
      :message_type,
      :content
    ])
    |> validate_inclusion(:message_type, ["notify", "request", "response"])
    |> foreign_key_constraint(:project_id)
    |> put_inserted_at()
  end

  defp put_inserted_at(changeset) do
    if get_field(changeset, :inserted_at) do
      changeset
    else
      put_change(changeset, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
