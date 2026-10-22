defmodule Samgita.Domain.RepositoryAlias do
  @moduledoc false
  use Samgita.Schema

  schema "repository_aliases" do
    field :repository_id, :binary_id
    field :url, :string
    field :normalized_url, :string
    field :source, :string, default: "operator"
    timestamps()
  end
end
