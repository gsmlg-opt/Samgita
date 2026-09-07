defmodule Samgita do
  @moduledoc """
  Samgita is an external Agent Hub control plane.

  PostgreSQL is authoritative for durable state. Execution belongs to external
  agents; this application does not run providers or local execution workers.
  """

  @doc """
  Checks the authoritative database without exposing connection details.
  """
  @spec health_checks() :: %{atom() => :ok | :error}
  def health_checks do
    %{samgita_repo: check_repo()}
  end

  defp check_repo do
    case Samgita.Repo.query("SELECT 1", [], timeout: 1_000, log: false) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end
end
