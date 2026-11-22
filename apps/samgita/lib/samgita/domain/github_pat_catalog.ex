defmodule Samgita.Domain.GitHubPatCatalog do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "github_pat_catalogs" do
    field :connection_id, :binary_id, primary_key: true
    field :credential_version, :binary_id
    field :generation, :binary_id
    field :status, :string
    field :data, :map
    field :error_code, :string
    field :prune, :boolean, default: false
    field :fence, :binary_id
    field :job_id, :integer
  end
end
