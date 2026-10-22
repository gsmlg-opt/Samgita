defmodule Samgita.Workers.ScheduleTickWorkerTest do
  use Samgita.DataCase, async: false
  alias Samgita.Workers.ScheduleTickWorker

  test "a durable scanner wake-up uses its own queue and performs no development action" do
    job = ScheduleTickWorker.new(%{})
    assert Ecto.Changeset.get_field(job, :queue) == "hub_schedules"
    assert Ecto.Changeset.get_field(job, :max_attempts) == 5
    assert {:ok, %{"emitted" => 0}} = ScheduleTickWorker.perform(%Oban.Job{args: %{}})
  end
end
