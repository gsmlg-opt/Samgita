defmodule Samgita.Domain.AgentConnection do
  @moduledoc false
  use Samgita.Schema

  schema "agent_connections" do
    field :agent_id, :binary_id
    field :credential_id, :binary_id
    field :generation, :integer
    field :state, :string, default: "connected"
    field :expires_at, :utc_datetime_usec
    field :version, :integer, default: 1
    timestamps()
  end
end
