defmodule Samgita.Domain.NativeRuntimeOperation do
  @moduledoc false
  use Samgita.Schema

  schema "native_runtime_operations" do
    field :runtime_id, :binary_id
    field :interaction_id, :binary_id
    field :instance_id, Ecto.UUID
    field :driver_generation, :integer
    field :direction, :string
    field :method, :string
    field :wire_id_digest, :string
    field :request_payload, :map
    field :response_payload, :map
    field :state, :string, default: "prepared"
    field :effect, :string
    field :dispatch_token_digest, :binary
    field :dispatch_expires_at, :utc_datetime_usec
    field :timeout_ms, :integer, default: 30_000
    field :evidence_ref, :string
    field :version, :integer, default: 1
    timestamps()
  end
end
