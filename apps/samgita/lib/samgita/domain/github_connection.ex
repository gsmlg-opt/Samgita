defmodule Samgita.Domain.GitHubConnection do
  @moduledoc false
  use Samgita.Schema

  schema "github_connections" do
    field :host, :string
    field :app_id, :string
    field :installation_id, :string
    field :private_key_ref, :string
    field :webhook_secret_ref, :string
    field :enabled, :boolean, default: true
    field :state, :string, default: "configured"
    field :version, :integer, default: 1
    field :rate_limited_until, :utc_datetime_usec
    timestamps()
  end
end
