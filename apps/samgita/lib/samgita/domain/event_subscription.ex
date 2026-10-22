defmodule Samgita.Domain.EventSubscription do
  @moduledoc false
  use Samgita.Schema

  schema "event_subscriptions" do
    field :project_id, :binary_id
    field :agent_id, :binary_id
    field :types, {:array, :string}, default: []
    field :enabled, :boolean, default: true
    field :revision, :integer, default: 1
    field :purpose, :string, default: "subscriber"
    field :target_digest, :string
    field :idempotency_guaranteed, :boolean, default: false
    field :cursor, :integer, default: 0
    timestamps()
  end
end
