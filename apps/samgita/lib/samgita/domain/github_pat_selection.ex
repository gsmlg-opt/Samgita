defmodule Samgita.Domain.GitHubPatSelection do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "github_pat_selections" do
    field :connection_id, :binary_id, primary_key: true
    field :github_id, :integer, primary_key: true
    field :owner_id, :integer
    field :owner, :string
    field :name, :string
  end
end
