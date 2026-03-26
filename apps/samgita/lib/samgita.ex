defmodule Samgita do
  @moduledoc """
  Samgita keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns health check results for all supervised repos.
  """
  @spec health_checks() :: %{atom() => :ok | :error}
  def health_checks do
    %{
      samgita_repo: check_repo(Samgita.Repo),
      samgita_memory_repo: check_repo(SamgitaMemory.Repo)
    }
  end

  defp check_repo(repo) do
    repo.query!("SELECT 1")
    :ok
  rescue
    _ -> :error
  end
end
