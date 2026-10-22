defmodule Samgita.Domain.GitHubProjectMapping do
  @moduledoc false
  use Samgita.Schema

  schema "github_project_mappings" do
    field :github_repository_id, :binary_id
    field :project_id, :binary_id
    field :project_repository_id, :binary_id
    field :enabled, :boolean, default: true
    field :version, :integer, default: 1
    timestamps()
  end
end
