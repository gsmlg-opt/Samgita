defmodule Samgita.Domain.EventDeliveryAttempt do
  @moduledoc false
  use Samgita.Schema

  schema "event_delivery_attempts" do
    field :delivery_id, :binary_id
    field :number, :integer
    field :action, :string
    field :fence, :integer
    field :lease_id, :binary_id
    field :execution_epoch, :integer
    field :state, :string, default: "started"
    field :error_class, :string
    field :error_code, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps()
  end
end
