defmodule Samgita.Domain.GitHubRepository do
  @moduledoc false
  use Samgita.Schema

  schema "github_repositories" do
    field :connection_id, :binary_id
    field :repository_id, :binary_id
    field :external_id, :string
    field :full_name, :string
    field :default_branch, :string
    field :permissions, :map, default: %{}
    field :state, :string, default: "verified"
    field :version, :integer, default: 1
    field :verified_at, :utc_datetime_usec
    field :connection_version, :integer
    timestamps()
  end
end
