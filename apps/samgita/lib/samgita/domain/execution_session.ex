defmodule Samgita.Domain.ExecutionSession do
  @moduledoc false
  use Samgita.Schema

  schema "execution_sessions" do
    field :agent_id, :binary_id
    field :project_id, :binary_id
    field :connection_id, :binary_id
    field :external_id, :string
    field :state, :string, default: "open"
    field :version, :integer, default: 1
    timestamps()
  end
end
