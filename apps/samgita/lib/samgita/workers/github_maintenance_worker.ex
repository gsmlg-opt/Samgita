defmodule Samgita.Workers.GitHubMaintenanceWorker do
  @moduledoc "Bounded read-reconciliation and missed-wakeup maintenance, with no GitHub write capability."
  use Oban.Worker, queue: :hub_github, max_attempts: 5, unique: [period: 60]
  alias Samgita.GitHub.Reconciliation

  @impl true
  def perform(%Oban.Job{}) do
    case Reconciliation.maintain() do
      {:ok, _} -> :ok
      {:error, %{code: code}} -> {:error, code}
    end
  end
end
