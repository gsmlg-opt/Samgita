defmodule Samgita.Events.AssigneeRoutingTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  import Samgita.CoordinationFixtures
  alias Samgita.{Attempts, EventDelivery, Events, Principal, Projects, Tasks}
  alias Samgita.CoordinationFixtures.FakeConnector
  alias Samgita.Domain.{DomainEvent, EventSubscription}
  alias Samgita.Domain.EventDelivery, as: Delivery

  @endpoint %{"transport" => "websocket", "url" => "ws://127.0.0.1:9999/app-server"}

  setup do
    {project, coordinator, responsible} = routing_fixture()
    first = executor(project, "First executor")
    second = executor(project, "Second executor")
    {:ok, task} = Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Work"}))

    %{
      project: project,
      coordinator: coordinator,
      responsible: responsible,
      first: first,
      second: second,
      task: task
    }
  end

  defp executor(project, name) do
    agent =
      agent_fixture(%{
        "name" => name,
        "credential_ref" => "fake-event-credential",
        "endpoint_metadata" => @endpoint
      })

    member_fixture(project, agent, ["worker"])
    agent
  end

  defp configure(project, agent, types \\ []) do
    {:ok, current} = Projects.get(Principal.operator(), project["id"])

    Events.configure_assignee(
      Principal.operator(),
      project["id"],
      command(%{
        "agent_id" => agent["id"],
        "expected_version" => current["version"],
        "types" => types
      })
    )
  end

  defp deliveries(event_id),
    do:
      Repo.all(from d in Delivery, where: d.event_id == ^event_id)
      |> Map.new(&{&1.agent_id, &1})

  defp latest(type, task_id),
    do:
      Repo.one!(
        from e in DomainEvent,
          where: e.type == ^type and e.resource_id == ^task_id,
          order_by: [desc: e.sequence],
          limit: 1
      )

  test "an operator configures one revisioned assignee subscription per executor", ctx do
    assert {:ok, first} = configure(ctx.project, ctx.first)
    assert first["purpose"] == "assignee"
    assert {:ok, replaced} = configure(ctx.project, ctx.first, ["task.assigned"])
    assert replaced["types"] == ["task.assigned"]
    refute Repo.get!(EventSubscription, first["id"]).enabled
    assert {:ok, _} = configure(ctx.project, ctx.second)

    assert {:ok, routing} = Events.routing(Principal.operator(), ctx.project["id"])
    assert routing["id"] == ctx.responsible["id"]

    assert Enum.sort(Enum.map(routing["assignees"], & &1["agent_id"])) ==
             Enum.sort([ctx.first["id"], ctx.second["id"]])
  end

  test "task.assigned reaches only the current and previous assignee plus the responsible Agent",
       ctx do
    {:ok, _} = configure(ctx.project, ctx.first)
    {:ok, _} = configure(ctx.project, ctx.second)

    assigned = assign_fixture(ctx.project, ctx.task, ctx.first)
    event = latest("task.assigned", ctx.task["id"])

    assert Map.keys(deliveries(event.id)) |> Enum.sort() ==
             Enum.sort([ctx.coordinator["id"], ctx.first["id"]])

    _reassigned = assign_fixture(ctx.project, assigned, ctx.second)
    event = latest("task.assigned", ctx.task["id"])

    assert Map.keys(deliveries(event.id)) |> Enum.sort() ==
             Enum.sort([ctx.coordinator["id"], ctx.first["id"], ctx.second["id"]])

    # Events about another Agent's Task and non-Task events stay with the coordinator.
    {:ok, other} =
      Tasks.create(Principal.operator(), ctx.project["id"], command(%{"title" => "x"}))

    created = latest("task.created", other["id"])
    assert Map.keys(deliveries(created.id)) == [ctx.coordinator["id"]]
    {:ok, manual} = Events.trigger(Principal.operator(), ctx.project["id"], command())
    assert Map.keys(deliveries(manual["id"])) == [ctx.coordinator["id"]]
  end

  test "assigned Task transitions and Attempt events reach the assignee; delivery and report work",
       ctx do
    {:ok, subscription} = configure(ctx.project, ctx.first)
    assigned = assign_fixture(ctx.project, ctx.task, ctx.first)
    {principal, _, _} = connection_fixture(ctx.first)

    {:ok, session} =
      Samgita.Agents.open_session(principal, ctx.project["id"], command(%{"external_id" => "s"}))

    {:ok, attempt} =
      Attempts.claim(
        principal,
        ctx.project["id"],
        ctx.task["id"],
        command(%{"expected_version" => assigned["version"], "session_id" => session["id"]})
      )

    claimed =
      Repo.one!(
        from e in DomainEvent,
          where: e.type == "attempt.claimed" and e.resource_id == ^attempt["id"]
      )

    delivery = deliveries(claimed.id)[ctx.first["id"]]
    assert delivery.subscription_id == subscription["id"]
    assert delivery.state == "pending"

    assert {:ok, _} = EventDelivery.dispatch(delivery.id, connector: FakeConnector)
    first_id = ctx.first["id"]
    assert_received {:fake_receive, ^first_id, envelope, _}
    assert envelope["event_id"] == claimed.id

    current = Repo.get!(Delivery, delivery.id)

    assert {:ok, %{"state" => "completed"}} =
             EventDelivery.report(
               principal,
               ctx.project["id"],
               delivery.id,
               command(%{
                 "expected_version" => current.version,
                 "operation_id" => current.operation_id,
                 "fence" => current.fence,
                 "processing_status" => "completed",
                 "decision_id" => Ecto.UUID.generate(),
                 "result" => %{"summary" => "claimed"}
               })
             )

    assert {:ok, %{"cursor" => _}} =
             Events.ack_cursor(
               principal,
               ctx.project["id"],
               subscription["id"],
               command(%{"cursor" => 0})
             )
  end

  test "redelivery to an assignee subscription keeps the original event identity", ctx do
    {:ok, subscription} = configure(ctx.project, ctx.first, ["task.assigned"])
    {:ok, manual} = Events.trigger(Principal.operator(), ctx.project["id"], command())
    previous = deliveries(manual["id"])[ctx.coordinator["id"]]

    assert {:ok, redelivered} =
             Events.redeliver(
               Principal.operator(),
               ctx.project["id"],
               manual["id"],
               command(%{
                 "subscription_id" => subscription["id"],
                 "expected_subscription_revision" => subscription["revision"],
                 "source_delivery_id" => previous.id,
                 "reason" => "executor needs this context",
                 "evidence_ref" => "operator-review"
               })
             )

    assert redelivered["event_id"] == manual["id"]
    assert redelivered["agent_id"] == ctx.first["id"]
  end

  # Authorization refusal cases are recorded as unrun under the verification
  # restriction (implementation plan P8).
  test "assignee routing refuses a non-worker, a missing project_events capability and a non-operator (authorization)",
       ctx do
    manager = agent_fixture(%{"name" => "Manager only", "endpoint_metadata" => @endpoint})
    member_fixture(ctx.project, manager, ["manager"])
    assert {:error, %{code: :forbidden}} = configure(ctx.project, manager)

    plain = agent_fixture(%{"name" => "No events", "approved_capabilities" => []})
    member_fixture(ctx.project, plain, ["worker"])
    assert {:error, %{code: :invalid}} = configure(ctx.project, plain)

    {principal, _, _} = connection_fixture(ctx.first)
    {:ok, current} = Projects.get(Principal.operator(), ctx.project["id"])

    assert {:error, %{code: :forbidden}} =
             Events.configure_assignee(
               principal,
               ctx.project["id"],
               command(%{"agent_id" => ctx.first["id"], "expected_version" => current["version"]})
             )
  end

  test "a worker cannot report the responsible Agent's delivery (authorization)", ctx do
    {:ok, manual} = Events.trigger(Principal.operator(), ctx.project["id"], command())
    delivery = deliveries(manual["id"])[ctx.coordinator["id"]]
    {:ok, _claim} = EventDelivery.claim(delivery.id)
    current = Repo.get!(Delivery, delivery.id)
    {principal, _, _} = connection_fixture(ctx.first)

    assert {:error, %{code: :forbidden}} =
             EventDelivery.report(
               principal,
               ctx.project["id"],
               delivery.id,
               command(%{
                 "expected_version" => current.version,
                 "operation_id" => current.operation_id,
                 "fence" => current.fence,
                 "processing_status" => "completed",
                 "decision_id" => Ecto.UUID.generate()
               })
             )
  end
end
