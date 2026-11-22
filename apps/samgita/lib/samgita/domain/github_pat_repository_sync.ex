defmodule Samgita.Domain.GitHubPatRepositorySync do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "github_pat_repository_syncs" do
    field :connection_id, :binary_id, primary_key: true
    field :repository_id, :integer, primary_key: true
    field :credential_version, :binary_id
    field :owner_id, :integer
    field :synced_at, :utc_datetime_usec
    field :error_code, :string
    field :job_id, :integer
  end
end
