defmodule Samgita.Domain.GitHubObject do
  @moduledoc false
  use Samgita.Schema

  schema "github_objects" do
    field :github_repository_id, :binary_id
    field :kind, :string
    field :resource_id, :string
    field :facts, :map, default: %{}
    field :untrusted_input, :map, default: %{}
    field :external_updated_at, :utc_datetime_usec
    field :observed_at, :utc_datetime_usec
    field :source_id, :string
    field :version, :integer, default: 1
    timestamps()
  end
end
