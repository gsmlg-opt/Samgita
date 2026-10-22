defmodule Samgita.Domain.GitHubDelivery do
  @moduledoc false
  use Samgita.Schema

  schema "github_deliveries" do
    field :connection_id, :binary_id
    field :delivery_id, :string
    field :body_digest, :string
    field :event_name, :string
    field :action, :string
    field :installation_id, :string
    field :repository_external_id, :string
    field :state, :string
    field :reason, :string
    field :payload, :map, default: %{}
    field :event_ids, {:array, :binary_id}, default: []
    field :received_at, :utc_datetime_usec
    timestamps()
  end
end
