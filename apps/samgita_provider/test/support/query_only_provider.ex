defmodule SamgitaProvider.QueryOnlyProvider do
  @moduledoc """
  A minimal provider that only implements `query/2`.

  Used in tests to verify fallback behaviour when a provider does not
  implement the optional session lifecycle callbacks.
  """
  @behaviour SamgitaProvider.Provider

  @impl true
  def query(_prompt, _opts) do
    {:ok, "query_only response"}
  end
end
