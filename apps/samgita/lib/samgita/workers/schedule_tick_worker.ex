defmodule Samgita.Workers.ScheduleTickWorker do
  @moduledoc "Durable wake-up for bounded schedule catch-up; never chooses or starts work."
  use Oban.Worker, queue: :hub_schedules, max_attempts: 5, unique: [period: 60]

  @impl true
  def perform(%Oban.Job{}) do
    Samgita.Schedules.tick()
  end
end
