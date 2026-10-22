defmodule Samgita.Events.TransactionTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Commands, Error, Events, Principal, Projects, Repo}
  alias Samgita.Domain.{CommandReceipt, DomainEvent, EventDelivery, EventSubscription}

  test "rollback and receipt replay include exactly the committed event and delivery intent" do
    p = project_fixture()
    a = agent_fixture()

    subscription =
      Repo.insert!(%EventSubscription{
        project_id: p["id"],
        agent_id: a["id"],
        types: ["project.updated"]
      })

    failed = command()

    assert {:error, %Error{code: :invalid}} =
             Commands.run(
               Principal.operator(),
               p["id"],
               failed,
               [operation: "test.rollback"],
               fn ctx ->
                 Events.append!(
                   p["id"],
                   "project.updated",
                   ctx,
                   "project",
                   p["id"]
                 )

                 Commands.fail!(:invalid)
               end
             )

    refute Repo.get_by(CommandReceipt, command_id: failed["command_id"])
    refute Repo.get_by(DomainEvent, command_id: failed["command_id"])
    refute Repo.get_by(EventDelivery, subscription_id: subscription.id)
    attrs = command(%{"expected_version" => 1, "name" => "atomic"})
    assert {:ok, result} = Projects.update(Principal.operator(), p["id"], attrs)
    assert {:ok, ^result} = Projects.update(Principal.operator(), p["id"], attrs)
    assert [_] = Repo.all(from d in EventDelivery, where: d.subscription_id == ^subscription.id)

    assert [event] =
             Repo.all(
               from e in DomainEvent,
                 where: e.project_id == ^p["id"] and e.type == "project.updated"
             )

    assert event.schema_version == "1.0"
    assert event.sequence == 2
    assert event.command_id == attrs["command_id"]
    assert event.before_state == %{"state" => "active", "version" => 1}
    assert event.after_state == %{"state" => "active", "version" => 2}
    assert event.actor == "operator"
    assert event.created_at
    receipt = Repo.get_by!(CommandReceipt, command_id: attrs["command_id"])
    assert receipt.event_ids == [event.id]
  end
end
