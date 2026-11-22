defmodule Samgita.Workers.GitHubPatSyncWorker do
  @moduledoc "Dispatches repository syncs and checks the persisted cleanup deadline on cron ticks."
  use Styx.Worker, queue: :hub_github, max_attempts: 5
  alias Samgita.GitHub.{PatCleanup, PatSync}

  @impl true
  def perform(%Styx.Job{args: args} = job) when args == %{} do
    with {:ok, _deleted} <- PatCleanup.run_due(), do: PatSync.dispatch(job)
  end

  def perform(%Styx.Job{} = job), do: PatSync.dispatch(job)
end
