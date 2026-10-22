defmodule Samgita.Domain.ProjectRepository do
  @moduledoc false
  use Samgita.Schema

  schema "project_repositories" do
    field :project_id, :binary_id
    field :repository_id, :binary_id
    field :role, :string, default: "source"
    field :primary, :boolean, default: false
    field :version, :integer, default: 1
    timestamps()
  end
end
