defmodule Samgita.Domain.EventRecoveryAction do
  @moduledoc false
  use Samgita.Schema

  schema "event_recovery_actions" do
    field :delivery_id, :binary_id
    field :previous_delivery_id, :binary_id
    field :command_id, :binary_id
    field :action, :string
    field :reason, :string
    field :evidence_ref, :string
    field :risk_acknowledged, :boolean, default: false
    field :previous_state, :string
    field :resulting_state, :string
    timestamps()
  end
end
