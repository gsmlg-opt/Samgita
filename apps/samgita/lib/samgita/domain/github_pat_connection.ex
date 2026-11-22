defmodule Samgita.Domain.GitHubPatConnection do
  @moduledoc false
  use Samgita.Schema

  schema "github_pat_connections" do
    field :github_id, :integer
    field :login, :string
    field :ciphertext, :binary, redact: true, load_in_query: false
    field :credential_version, :binary_id
    field :version, :binary_id
    field :retry_at, :integer
    field :next_cleanup_at, :utc_datetime_usec, read_after_writes: true
    has_many :selections, Samgita.Domain.GitHubPatSelection, foreign_key: :connection_id

    has_many :owner_selections, Samgita.Domain.GitHubPatOwnerSelection,
      foreign_key: :connection_id
  end
end
