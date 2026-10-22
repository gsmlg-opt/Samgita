defmodule Samgita.Workers.EventDeliveryWorker do
  @moduledoc "Outbox wakeup; delivery rows, not Oban attempts, own retry and uncertainty state."
  use Oban.Worker, queue: :hub_events, max_attempts: 5, unique: [period: 60, keys: [:delivery_id]]

  @impl true
  def perform(%Oban.Job{args: %{"delivery_id" => id}}) do
    case Samgita.EventDelivery.dispatch(id) do
      {:ok, %{"state" => state} = delivery}
      when state in ~w(pending retry_wait reconciling delivering) ->
        wait =
          case delivery["next_attempt_at"] do
            nil ->
              60

            time ->
              {:ok, due, _} = DateTime.from_iso8601(time)
              DateTime.diff(due, DateTime.utc_now()) |> max(1) |> min(3600)
          end

        {:snooze, wait}

      {:ok, %{"state" => state}} when state in ~w(accepted completed) ->
        :ok

      {:ok, %{"state" => state}} ->
        {:cancel, state}

      {:error, %{code: :execution_closed}} ->
        {:snooze, 60}

      {:error, %{code: code}} when code in [:ownership_lost, :not_found] ->
        {:cancel, code}

      {:error, %{code: code}} ->
        {:error, code}
    end
  end
end
