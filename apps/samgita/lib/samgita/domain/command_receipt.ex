defmodule Samgita.Domain.CommandReceipt do
  @moduledoc false
  use Samgita.Schema

  schema "command_receipts" do
    field :principal, :string
    field :command_id, :binary_id
    field :operation, :string
    field :request_digest, :string
    field :result, :map
    field :event_ids, {:array, :binary_id}, default: []
    field :execution_epoch, :integer
    timestamps()
  end
end
