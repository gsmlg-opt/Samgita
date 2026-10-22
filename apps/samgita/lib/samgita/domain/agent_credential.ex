defmodule Samgita.Domain.AgentCredential do
  @moduledoc false
  use Samgita.Schema

  schema "agent_credentials" do
    field :agent_id, :binary_id
    field :digest, :binary, redact: true
    field :reference, :string
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    timestamps()
  end
end
