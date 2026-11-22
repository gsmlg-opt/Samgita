defmodule Samgita.Workers.GitHubPatActionWorker do
  @moduledoc "Executes an explicitly requested GitHub item mutation once."
  use Styx.Worker,
    queue: :hub_github,
    max_attempts: 1,
    unique: [
      period: 60,
      keys: [:connection_id, :credential_version, :repository_id, :action, :number, :expected_sha],
      states: :incomplete
    ]

  @impl true
  def perform(%Styx.Job{} = job), do: Samgita.GitHub.PatActions.perform(job)
end
