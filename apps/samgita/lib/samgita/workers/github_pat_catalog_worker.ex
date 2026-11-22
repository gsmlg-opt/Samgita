defmodule Samgita.Workers.GitHubPatCatalogWorker do
  @moduledoc "Refreshes the persisted operator GitHub directory on explicit request."
  use Styx.Worker,
    queue: :hub_github,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:connection_id, :credential_version, :generation],
      states: :incomplete
    ]

  @impl true
  def perform(%Styx.Job{} = job), do: Samgita.GitHub.PatCatalog.perform(job)
end
