defmodule Samgita.Domain.GitHubPatOwnerSelection do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "github_pat_owner_selections" do
    field :connection_id, :binary_id, primary_key: true
    field :owner_id, :integer, primary_key: true
    field :login, :string
  end
end
