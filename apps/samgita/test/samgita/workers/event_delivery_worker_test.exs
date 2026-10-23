defmodule Samgita.Workers.EventDeliveryWorkerTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  import Samgita.CoordinationFixtures
  alias Samgita.Domain.EventDelivery, as: Delivery
  alias Samgita.{EventDelivery, Platform, Principal, Repo}
  alias Samgita.Workers.EventDeliveryWorker

  test "only dedicated delivery queue executes; auth failure is cancelled rather than successful" do
    {_, _, _, _, d} = delivery_fixture()

    assert Ecto.Changeset.get_field(EventDeliveryWorker.new(%{"delivery_id" => d.id}), :queue) ==
             "hub_events"

    assert {:cancel, "authentication_failed"} =
             EventDeliveryWorker.perform(%Oban.Job{args: %{"delivery_id" => d.id}})

    assert Repo.get!(Delivery, d.id).state == "authentication_failed"
  end

  test "closed admissions snooze without network requests or extra execution" do
    {_, _, _, _, d} = delivery_fixture()
    {:ok, a} = Platform.status(Principal.operator())

    assert {:ok, _} =
             Platform.close(
               Principal.operator(),
               command(%{"expected_version" => a["version"], "reason" => "closed"})
             )

    assert {:snooze, 60} = EventDeliveryWorker.perform(%Oban.Job{args: %{"delivery_id" => d.id}})
    assert Repo.get!(Delivery, d.id).attempt_count == 0
    assert {:ok, _} = EventDelivery.maintain()
  end
end
