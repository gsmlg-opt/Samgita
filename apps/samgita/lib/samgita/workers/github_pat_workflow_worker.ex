defmodule Samgita.Workers.GitHubPatWorkflowWorker do
  @moduledoc "Refreshes the recent workflow runs for one selected GitHub repository."
  use Styx.Worker, queue: :hub_github, max_attempts: 3

  @impl true
  def perform(job), do: Samgita.GitHub.PatWorkflowRuns.perform(job)
end
