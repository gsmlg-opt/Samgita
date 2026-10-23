defmodule Samgita.Domain.Agent do
  @moduledoc false
  use Samgita.Schema

  schema "agents" do
    field :name, :string
    field :implementation, :string
    field :enabled, :boolean, default: true
    field :capacity, :integer, default: 1
    field :advertised_capabilities, {:array, :string}, default: []
    field :approved_capabilities, {:array, :string}, default: []
    field :protocol, :string, default: "samgita"
    field :protocol_version, :string, default: "1.0"
    field :endpoint_metadata, :map, default: %{}
    field :credential_ref, :string
    field :runtime_driver, :string
    field :runtime_version, :string
    field :generation, :integer, default: 0
    field :version, :integer, default: 1
    timestamps()
  end
end
