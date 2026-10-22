defmodule Samgita.Workers.GitHubReconcileWorker do
  @moduledoc "Read-only GitHub state reconciliation; durable sync rows own eligibility and retry limits."
  use Oban.Worker, queue: :hub_github, max_attempts: 5, unique: [period: 60, keys: [:sync_id]]

  @impl true
  def perform(%Oban.Job{args: %{"sync_id" => id}}) do
    case Samgita.GitHub.Reconciliation.run(id) do
      {:ok, %{"state" => state} = sync} when state in ~w(pending retry_wait running) ->
        {:ok, due, _} = DateTime.from_iso8601(sync["next_attempt_at"])
        {:snooze, DateTime.diff(due, DateTime.utc_now()) |> max(1) |> min(3600)}

      {:ok, %{"state" => "idle"}} ->
        :ok

      {:ok, %{"state" => state}} ->
        {:cancel, state}

      {:error, %{code: code}} when code in [:not_found, :ownership_lost] ->
        {:cancel, code}

      {:error, %{code: code}} ->
        {:error, code}
    end
  end
end
