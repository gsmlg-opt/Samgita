defmodule Samgita.Tasks.ProgressTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Management, Principal, Tasks}

  setup do
    activate_fixture()
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["worker"])
    {actor, _, _} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(actor, project["id"], command(%{"external_id" => "progress-test"}))

    {:ok, task} =
      Tasks.create(
        Principal.operator(),
        project["id"],
        command(%{"title" => "Progress evidence"})
      )

    {:ok, attempt} =
      Attempts.claim(
        actor,
        project["id"],
        task["id"],
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(actor, project["id"], attempt["id"])

    {:ok, running} =
      Attempts.start(
        actor,
        project["id"],
        attempt["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    %{project: project, actor: actor, task: task, running: running, proof: proof}
  end

  test "progress receipts deduplicate, advance Attempt version, and cannot accept or renew work",
       ctx do
    p = ctx.project["id"]

    attrs =
      command(%{
        "expected_version" => ctx.running["version"],
        "proof" => ctx.proof,
        "payload" => %{"summary" => "A bounded step finished"}
      })

    assert {:ok, current} = Attempts.progress(ctx.actor, p, ctx.running["id"], attrs)
    assert {:ok, ^current} = Attempts.progress(ctx.actor, p, ctx.running["id"], attrs)
    assert current["lease_expires_at"] == ctx.running["lease_expires_at"]
    assert current["state"] == "running"
    assert {:ok, history} = Management.task(Principal.operator(), p, ctx.task["id"])
    assert history["task"]["state"] == "in_progress"
    assert history["totals"]["progress"] == 1
    refute inspect(history) =~ ctx.proof

    assert {:error, %{code: :stale_version}} =
             Attempts.progress(
               ctx.actor,
               p,
               ctx.running["id"],
               Map.put(attrs, "command_id", Ecto.UUID.generate())
             )
  end

  test "invalid payloads, invalid proofs, and cancelled ownership cannot append progress",
       ctx do
    p = ctx.project["id"]

    for payload <- [
          %{},
          %{"summary" => "safe", "token" => "sensitive"},
          [],
          %{"summary" => String.duplicate("x", 2001)}
        ] do
      assert {:error, %{code: :invalid}} =
               Attempts.progress(
                 ctx.actor,
                 p,
                 ctx.running["id"],
                 command(%{
                   "expected_version" => ctx.running["version"],
                   "proof" => ctx.proof,
                   "payload" => payload
                 })
               )
    end

    assert {:error, %{code: :ownership_lost}} =
             Attempts.progress(
               ctx.actor,
               p,
               ctx.running["id"],
               command(%{
                 "expected_version" => ctx.running["version"],
                 "proof" => "invalid",
                 "payload" => %{"summary" => "Rejected"}
               })
             )

    {:ok, task} = Tasks.get(Principal.operator(), p, ctx.task["id"])

    {:ok, blocked} =
      Tasks.transition(
        Principal.operator(),
        p,
        task["id"],
        command(%{"expected_version" => task["version"], "state" => "blocked"})
      )

    {:ok, _} =
      Tasks.transition(
        Principal.operator(),
        p,
        task["id"],
        command(%{"expected_version" => blocked["version"], "state" => "cancelled"})
      )

    assert {:error, %Samgita.Error{}} =
             Attempts.progress(
               ctx.actor,
               p,
               ctx.running["id"],
               command(%{
                 "expected_version" => ctx.running["version"] + 1,
                 "proof" => ctx.proof,
                 "payload" => %{"summary" => "Stale effect"}
               })
             )

    assert {:ok, %{"progress" => []}} = Management.task(Principal.operator(), p, ctx.task["id"])
  end
end
