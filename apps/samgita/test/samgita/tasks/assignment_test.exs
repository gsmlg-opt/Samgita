defmodule Samgita.Tasks.AssignmentTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Tasks}
  alias Samgita.Domain.{CommandReceipt, DomainEvent, Task}

  setup do
    activate_fixture()
    project = project_fixture()
    coordinator = agent_fixture(%{"name" => "Coordinator"})
    member_fixture(project, coordinator, ["manager"])
    {manager, _, _} = connection_fixture(coordinator)
    executor = agent_fixture(%{"name" => "Executor"})
    member_fixture(project, executor, ["worker"])
    {worker, _, _} = connection_fixture(executor)

    {:ok, session} =
      Agents.open_session(worker, project["id"], command(%{"external_id" => "assigned-work"}))

    {:ok, task} = Tasks.create(manager, project["id"], command(%{"title" => "Delegated"}))

    %{
      project: project,
      manager: manager,
      worker: worker,
      executor: executor,
      session: session,
      task: task
    }
  end

  defp assign(ctx, task, assignee, principal \\ nil) do
    Tasks.assign(
      principal || ctx.manager,
      ctx.project["id"],
      task["id"],
      command(%{"expected_version" => task["version"], "assignee_agent_id" => assignee})
    )
  end

  defp claim(ctx, task) do
    Attempts.claim(
      ctx.worker,
      ctx.project["id"],
      task["id"],
      command(%{"expected_version" => task["version"], "session_id" => ctx.session["id"]})
    )
  end

  test "a coordinator assigns a Task atomically with a receipt and task.assigned event", ctx do
    attrs =
      command(%{
        "expected_version" => ctx.task["version"],
        "assignee_agent_id" => ctx.executor["id"]
      })

    assert {:ok, assigned} = Tasks.assign(ctx.manager, ctx.project["id"], ctx.task["id"], attrs)
    assert assigned["assignee_agent_id"] == ctx.executor["id"]
    assert assigned["assigned_at"]
    assert assigned["version"] == ctx.task["version"] + 1

    receipt = Repo.get_by!(CommandReceipt, command_id: attrs["command_id"])
    assert receipt.operation == "task.assign:" <> ctx.task["id"]
    assert [event_id] = receipt.event_ids
    event = Repo.get!(DomainEvent, event_id)
    assert event.type == "task.assigned"

    assert event.data == %{
             "assignee_agent_id" => ctx.executor["id"],
             "previous_assignee_agent_id" => nil
           }

    # An identical retry replays the receipt without another version or event.
    assert {:ok, ^assigned} = Tasks.assign(ctx.manager, ctx.project["id"], ctx.task["id"], attrs)
    assert Repo.get!(Task, ctx.task["id"]).version == assigned["version"]

    assert Repo.aggregate(
             from(e in DomainEvent,
               where: e.type == "task.assigned" and e.resource_id == ^ctx.task["id"]
             ),
             :count
           ) == 1
  end

  test "a stale expected_version conflicts and unassignment records the previous assignee",
       ctx do
    {:ok, assigned} = assign(ctx, ctx.task, ctx.executor["id"])

    assert {:error, %{code: :stale_version}} = assign(ctx, ctx.task, nil)

    assert {:ok, unassigned} = assign(ctx, assigned, nil)
    assert unassigned["assignee_agent_id"] == nil
    assert unassigned["assigned_at"] == nil

    event =
      Repo.one!(
        from e in DomainEvent,
          where: e.type == "task.assigned" and e.resource_id == ^ctx.task["id"],
          order_by: [desc: e.sequence],
          limit: 1
      )

    assert event.data["previous_assignee_agent_id"] == ctx.executor["id"]
    assert event.data["assignee_agent_id"] == nil
  end

  test "assignment requires an open adopted Task without an active Attempt or execution hold",
       ctx do
    {:ok, assigned} = assign(ctx, ctx.task, ctx.executor["id"])
    {:ok, _attempt} = claim(ctx, assigned)
    current = Repo.get!(Task, ctx.task["id"])
    claimed = %{"id" => current.id, "version" => current.version}

    assert {:error, %{code: :invalid_transition}} = assign(ctx, claimed, nil)
    assert Repo.get!(Task, ctx.task["id"]).assignee_agent_id == ctx.executor["id"]

    {:ok, other} = Tasks.create(ctx.manager, ctx.project["id"], command(%{"title" => "Held"}))
    Repo.update!(Ecto.Changeset.change(Repo.get!(Task, other["id"]), execution_hold: true))
    assert {:error, %{code: :invalid_transition}} = assign(ctx, other, ctx.executor["id"])

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Task, other["id"]), execution_hold: false, state: "blocked")
    )

    assert {:error, %{code: :invalid_transition}} = assign(ctx, other, ctx.executor["id"])
    assert Repo.get!(Task, other["id"]).assignee_agent_id == nil
  end

  test "only the assignee claims; unassigned Tasks are not claimable", ctx do
    assert {:error, %{code: :invalid}} = assign(ctx, ctx.task, "not-a-uuid")
    assert {:error, %{code: :invalid_transition}} = claim(ctx, ctx.task)

    {:ok, assigned} = assign(ctx, ctx.task, ctx.executor["id"])
    assert {:ok, attempt} = claim(ctx, assigned)
    assert attempt["agent_id"] == ctx.executor["id"]
  end

  test "Tasks.list filters by assignee", ctx do
    {:ok, _} = assign(ctx, ctx.task, ctx.executor["id"])
    {:ok, _} = Tasks.create(ctx.manager, ctx.project["id"], command(%{"title" => "Unassigned"}))

    assert {:ok, %{"data" => [only]}} =
             Tasks.list(ctx.worker, ctx.project["id"], %{
               "assignee_agent_id" => ctx.executor["id"]
             })

    assert only["id"] == ctx.task["id"]
    assert {:ok, %{"data" => all}} = Tasks.list(ctx.worker, ctx.project["id"], %{})
    assert length(all) == 2
  end

  # Authorization refusal cases below are recorded as unrun under the
  # verification restriction (implementation plan P8).
  test "assignment refuses a non-member, a missing worker role, a missing capability and a disabled Agent (authorization)",
       ctx do
    outsider = agent_fixture(%{"name" => "Outsider"})
    assert {:error, %{code: :forbidden}} = assign(ctx, ctx.task, outsider["id"])

    manager_only = agent_fixture(%{"name" => "Manager only"})
    member_fixture(ctx.project, manager_only, ["manager"])
    assert {:error, %{code: :forbidden}} = assign(ctx, ctx.task, manager_only["id"])

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Task, ctx.task["id"]),
        required_capabilities: ["not-approved"]
      )
    )

    assert {:error, %{code: :forbidden}} = assign(ctx, ctx.task, ctx.executor["id"])

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Task, ctx.task["id"]), required_capabilities: [])
    )

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Samgita.Domain.Agent, ctx.executor["id"]), enabled: false)
    )

    assert {:error, %{code: :forbidden}} = assign(ctx, ctx.task, ctx.executor["id"])
    assert Repo.get!(Task, ctx.task["id"]).assignee_agent_id == nil

    assert {:error, %{code: :forbidden}} =
             assign(ctx, ctx.task, ctx.executor["id"], ctx.worker)
  end

  test "a Task assigned to another Agent refuses claim (authorization)", ctx do
    other = agent_fixture(%{"name" => "Other executor"})
    member_fixture(ctx.project, other, ["worker"])
    {:ok, assigned} = assign(ctx, ctx.task, other["id"])
    assert {:error, %{code: :invalid_transition}} = claim(ctx, assigned)
  end
end
