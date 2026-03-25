defmodule Samgita.ObanClient do
  @moduledoc """
  Thin wrapper around Oban.insert/1 to enable test injection via Mox.

  In production this delegates directly to Oban. In tests, the :oban_module
  application env can be overridden to inject a Mox mock.
  """

  @callback insert(Oban.Job.t()) :: {:ok, Oban.Job.t()} | {:error, term()}

  @doc "Insert a job. Delegates to the configured Oban module (default: Oban)."
  def insert(job) do
    impl().insert(job)
  end

  defp impl do
    Application.get_env(:samgita, :oban_module, Oban)
  end
end
