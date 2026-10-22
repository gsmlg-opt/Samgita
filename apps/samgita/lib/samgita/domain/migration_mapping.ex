defmodule Samgita.Domain.MigrationMapping do
  @moduledoc false
  use Samgita.Schema

  schema "migration_mappings" do
    field :source_table, :string
    field :source_id, :string
    field :source_digest, :string
    field :status, :string
    field :target_id, :binary_id
    field :details, :map, default: %{}
    timestamps()
  end
end
