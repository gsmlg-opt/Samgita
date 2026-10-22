defmodule Samgita.Domain.GitHubSync do
  @moduledoc false
  use Samgita.Schema

  schema "github_syncs" do
    field :github_repository_id, :binary_id
    field :kind, :string
    field :resource_id, :string, default: ""
    field :page, :integer, default: 1
    field :since, :utc_datetime_usec
    field :state, :string, default: "pending"
    field :generation, :integer, default: 1
    field :fence, :integer, default: 0
    field :lease_id, :binary_id
    field :lease_expires_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :scan_started_at, :utc_datetime_usec
    field :last_scan_started_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :last_completed_at, :utc_datetime_usec
    field :last_error_class, :string
    field :last_error_code, :string
    timestamps()
  end
end
