defmodule Samgita.Domain.ProjectAgent do
  @moduledoc false
  use Samgita.Schema

  schema "project_agents" do
    field :agent_id, :binary_id
    field :project_id, :binary_id
    field :roles, {:array, :string}, default: []
    field :enabled, :boolean, default: true
    field :version, :integer, default: 1
    timestamps()
  end
end
