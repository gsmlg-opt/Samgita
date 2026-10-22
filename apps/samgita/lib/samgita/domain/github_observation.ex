defmodule Samgita.Domain.GitHubObservation do
  @moduledoc "Immutable evidence referenced by a reconciliation event, separate from the latest projection."
  use Samgita.Schema

  schema "github_observations" do
    field :object_id, :binary_id
    field :version, :integer
    field :facts, :map
    field :untrusted_input, :map
    field :external_updated_at, :utc_datetime_usec
    field :observed_at, :utc_datetime_usec
    field :source_id, :string
  end
end
