defmodule Samgita.Domain.DomainEvent do
  @moduledoc false
  use Samgita.Schema

  schema "domain_events" do
    field :project_id, :binary_id
    field :sequence, :integer
    field :type, :string
    field :schema_version, :string, default: "1.0"
    field :actor, :string
    field :command_id, :binary_id
    field :correlation_id, :binary_id
    field :causation_id, :binary_id
    field :source, :string, default: "domain"
    field :source_id, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :data, :map, default: %{}
    field :before_state, :map
    field :after_state, :map
    field :created_at, :utc_datetime_usec
    timestamps()
  end
end
