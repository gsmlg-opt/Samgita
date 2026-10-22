defmodule Samgita.GitHub.Secrets do
  @moduledoc "Resolves versioned external secret references at use time; never caches values."
  alias Samgita.GitHub.Failure

  def resolve(reference) when is_binary(reference) and byte_size(reference) in 1..255 do
    case Application.get_env(:samgita, :github_secrets, %{}) do
      %{^reference => value} when is_binary(value) and byte_size(value) in 1..65_536 ->
        {:ok, value}

      _ ->
        {:error, Failure.new(:authentication, :secret_unavailable)}
    end
  end

  def resolve(_), do: {:error, Failure.new(:authentication, :secret_unavailable)}
end
