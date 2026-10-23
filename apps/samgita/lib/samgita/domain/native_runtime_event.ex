defmodule Samgita.Domain.NativeRuntimeEvent do
  @moduledoc false
  use Samgita.Schema

  schema "native_runtime_events" do
    field :runtime_id, :binary_id
    field :instance_id, Ecto.UUID
    field :driver_generation, :integer
    field :source_sequence, :integer
    field :kind, :string
    field :method, :string
    field :fingerprint, :string
    field :request_id_digest, :string
    field :thread_id_digest, :string
    field :native_payload, :map
    field :state, :string
    field :expires_at, :utc_datetime_usec
    field :version, :integer, default: 1
    timestamps()
  end
end
