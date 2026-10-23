defmodule Samgita.Workers.CoordinationMaintenanceWorker do
  @moduledoc "Repair durable wakeups and fence expired execution ownership; never restart work."
  use Oban.Worker, queue: :hub_maintenance, max_attempts: 5, unique: [period: 60]
  alias Samgita.Workers.AttemptExpiryWorker

  @impl true
  def perform(%Oban.Job{}) do
    with {:ok, _} <- Samgita.EventDelivery.maintain(),
         {:ok, _} <- AttemptExpiryWorker.expire_due() do
      :ok
    else
      {:error, %{code: code}} -> {:error, code}
    end
  end
end
