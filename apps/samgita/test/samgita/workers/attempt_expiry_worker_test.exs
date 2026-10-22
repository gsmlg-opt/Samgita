defmodule Samgita.Workers.AttemptExpiryWorkerTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Principal, Repo, Tasks}
  alias Samgita.Domain.{Task, TaskAttempt}
  alias Samgita.Workers.{AttemptExpiryWorker, CoordinationMaintenanceWorker}

  test "expiry maintenance fences ownership, retains capacity hold and creates no new Attempt" do
    activate_fixture()
    p = project_fixture()
    a = agent_fixture()
    member_fixture(p, a)
    {actor, connection, _} = connection_fixture(a)

    {:ok, session} =
      Agents.open_session(
        actor,
        p["id"],
        command(%{"external_id" => "expiry-test", "connection_id" => connection["id"]})
      )

    {:ok, task} =
      Tasks.create(Principal.operator(), p["id"], command(%{"title" => "do not retry"}))

    {:ok, attempt} =
      Attempts.claim(
        actor,
        p["id"],
        task["id"],
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )

    Repo.get!(TaskAttempt, attempt["id"])
    |> change(lease_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:ok, 1} = AttemptExpiryWorker.expire_due()
    assert Repo.get!(TaskAttempt, attempt["id"]).state == "expired"
    assert Repo.get!(Task, task["id"]).execution_hold
    assert Repo.get!(Task, task["id"]).state == "blocked"
    assert Repo.aggregate(from(a in TaskAttempt, where: a.task_id == ^task["id"]), :count) == 1
    assert {:ok, 0} = AttemptExpiryWorker.expire_due()
    assert :ok = CoordinationMaintenanceWorker.perform(%Oban.Job{args: %{}})
  end
end
