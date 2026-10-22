defmodule Samgita.Domain.ExternalEvent do
  @moduledoc false
  use Samgita.Schema

  schema "external_event_inbox" do
    field :project_id, :binary_id
    field :source, :string
    field :external_id, :string
    field :payload_digest, :string
    field :event_id, :binary_id
    timestamps()
  end
end
