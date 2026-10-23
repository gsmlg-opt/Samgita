defmodule Samgita.Domain.NativeRuntimeLink do
  @moduledoc false
  use Samgita.Schema

  schema "native_runtime_links" do
    field :runtime_id, :binary_id
    field :kind, :string
    field :external_id, :string
    field :parent_external_id, :string
    field :state, :string
    timestamps()
  end
end
