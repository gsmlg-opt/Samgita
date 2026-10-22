defmodule Samgita.Domain.Repository do
  @moduledoc false
  use Samgita.Schema

  schema "repositories" do
    field :kind, :string, default: "git"
    field :provider, :string
    field :host, :string
    field :external_id, :string
    field :display_name, :string
    field :verification, :string, default: "unverified"
    field :version, :integer, default: 1
    timestamps()
  end
end
