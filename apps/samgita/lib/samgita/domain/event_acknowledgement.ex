defmodule Samgita.Domain.EventAcknowledgement do
  @moduledoc false
  use Samgita.Schema

  schema "event_acknowledgements" do
    field :delivery_id, :binary_id
    field :agent_id, :binary_id
    field :attempt_id, :binary_id
    field :source, :string
    field :acceptance, :string
    field :processing_status, :string
    field :decision_id, :string
    field :result, :map, default: %{}
    field :result_digest, :string
    field :recorded_at, :utc_datetime_usec
    timestamps()
  end
end
