defmodule Samgita.Domain.GitHubPatItem do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "github_pat_items" do
    field :connection_id, :binary_id, primary_key: true
    field :repository_id, :integer, primary_key: true
    field :kind, :string, primary_key: true
    field :number, :integer, primary_key: true
    field :credential_version, :binary_id
    field :title, :string
    field :state, :string
    field :author, :string
    field :issue_type, :string
    field :labels, {:array, :string}, default: []
    field :label_colors, :map, default: %{}
    field :head_sha, :string
    field :github_updated_at, :utc_datetime_usec
    field :url, :string
  end
end
