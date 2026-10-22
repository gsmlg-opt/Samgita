defmodule Samgita.Domain.EventDelivery do
  @moduledoc false
  use Samgita.Schema

  schema "event_deliveries" do
    field :event_id, :binary_id
    field :subscription_id, :binary_id
    field :subscription_revision, :integer
    field :state, :string, default: "pending"
    timestamps()
  end
end
