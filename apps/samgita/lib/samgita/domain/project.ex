defmodule Samgita.Domain.Project do
  @moduledoc false
  use Samgita.Schema

  schema "projects" do
    field :name, :string
    field :description, :string
    field :state, :string
    field :version, :integer, default: 1
    field :event_sequence, :integer, default: 0
    field :migration_metadata, :map, default: %{}
    field :git_url, :string
    field :status, :string, default: "pending"
    field :phase, :string, default: "bootstrap"
    field :config, :map, default: %{}
    field :start_mode, :string, default: "from_prd"
    field :provider_preference, :string, default: "claude_code"
    timestamps()
  end
end
