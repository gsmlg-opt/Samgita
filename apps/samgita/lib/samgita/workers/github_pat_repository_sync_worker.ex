defmodule Samgita.Workers.GitHubPatRepositorySyncWorker do
  @moduledoc "Publishes both GitHub item kinds atomically for one selected repository."
  use Styx.Worker, queue: :hub_github, max_attempts: 5

  @impl true
  def perform(%Styx.Job{} = job), do: Samgita.GitHub.PatSync.perform(job)
end
