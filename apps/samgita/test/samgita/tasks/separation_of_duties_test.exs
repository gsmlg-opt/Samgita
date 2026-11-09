defmodule Samgita.Tasks.SeparationOfDutiesTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Tasks}

  setup do
    activate_fixture()
    project = project_fixture()
    executor = agent_fixture(%{"name" => "Executor"})
    member_fixture(project, executor, ~w(worker reviewer))
    {worker, _, _} = connection_fixture(executor)
    coordinator = agent_fixture(%{"name" => "Coordinator"})
    member_fixture(project, coordinator, ~w(manager reviewer))
    {reviewer, _, _} = connection_fixture(coordinator)

    {:ok, task} = Tasks.create(reviewer, project["id"], command(%{"title" => "Reviewed work"}))
    task = assign_fixture(project, task, executor)

    {:ok, session} =
      Agents.open_session(worker, project["id"], command(%{"external_id" => "sod"}))

    {:ok, attempt} =
      Attempts.claim(
        worker,
        project["id"],
        task["id"],
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(worker, project["id"], attempt["id"])

    {:ok, running} =
      Attempts.start(
        worker,
        project["id"],
        attempt["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    {:ok, _} =
      Attempts.report(
        worker,
        project["id"],
        attempt["id"],
        command(%{
          "expected_version" => running["version"],
          "proof" => proof,
          "outcome" => "succeeded",
          "result" => %{"summary" => "done"},
          "effects_resolved" => true
        })
      )

    {:ok, pending} = Tasks.get(reviewer, project["id"], task["id"])
    assert pending["state"] == "awaiting_review"
    %{project: project, worker: worker, reviewer: reviewer, task: pending}
  end

  defp decide(ctx, principal, task, kind) do
    Tasks.decide(
      principal,
      ctx.project["id"],
      task["id"],
      command(%{"expected_version" => task["version"], "kind" => kind, "verdict" => "approve"})
    )
  end

  test "a separate reviewer Agent reviews and accepts the executor's submission", ctx do
    assert {:ok, reviewed} = decide(ctx, ctx.reviewer, ctx.task, "review")
    assert {:ok, accepted} = decide(ctx, ctx.reviewer, reviewed, "acceptance")
    assert accepted["state"] == "accepted"
  end

  # Recorded as unrun under the verification restriction (implementation plan P8).
  test "the executor holding reviewer cannot review or accept its own submission (authorization)",
       ctx do
    assert {:error, %{code: :forbidden}} = decide(ctx, ctx.worker, ctx.task, "review")
    {:ok, reviewed} = decide(ctx, ctx.reviewer, ctx.task, "review")
    assert {:error, %{code: :forbidden}} = decide(ctx, ctx.worker, reviewed, "acceptance")
  end
end
