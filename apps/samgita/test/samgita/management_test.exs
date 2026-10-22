defmodule Samgita.ManagementTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Management, Principal, Tasks}

  test "operator read models use durable state, page history, and hide credentials" do
    project = project_fixture()
    {:ok, baseline} = Management.overview(Principal.operator())
    agent = agent_fixture(%{"name" => "Independent Agent"})
    member_fixture(project, agent)
    {machine, _, token} = connection_fixture(agent)

    {:ok, _} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Persisted"}))

    assert {:ok, %{"counts" => counts}} = Management.overview(Principal.operator())
    assert counts["agents"] == baseline["counts"]["agents"] + 1
    assert counts["tasks"] == baseline["counts"]["tasks"] + 1

    assert {:ok, %{"agent" => current} = detail} =
             Management.agent(Principal.operator(), agent["id"])

    # Registered connection is not a heartbeat or evidence of execution health.
    assert current["connection_state"] == "connected"
    assert current["availability"] == "stale"
    assert current["last_activity_at"] == nil
    refute inspect(detail) =~ token
    refute inspect(detail) =~ "digest"
    assert [%{"reference" => "test-only"}] = detail["credentials"]

    assert {:ok, %{"tasks" => [%{"title" => "Persisted"}], "totals" => %{"tasks" => 1}}} =
             Management.project(Principal.operator(), project["id"])

    assert {:ok, %{"tasks" => [], "totals" => %{"tasks" => 1}}} =
             Management.project(Principal.operator(), project["id"], %{"offset" => 25})

    assert {:error, %Samgita.Error{code: :forbidden}} = Management.agents(machine)

    assert {:error, %Samgita.Error{code: :forbidden}} =
             Management.project(machine, project["id"])
  end

  test "task history scopes IDs and disabled/offline status remains explicit" do
    p = project_fixture()
    other = project_fixture()
    a = agent_fixture()

    assert {:ok, %{"agent" => %{"availability" => "offline"}}} =
             Management.agent(Principal.operator(), a["id"])

    {:ok, task} =
      Tasks.create(Principal.operator(), p["id"], command(%{"title" => "Review work"}))

    assert {:ok,
            %{"task" => %{"id" => id}, "attempts" => [], "decisions" => [], "artifacts" => []}} =
             Management.task(Principal.operator(), p["id"], task["id"])

    assert id == task["id"]

    assert {:error, %Samgita.Error{code: :not_found}} =
             Management.task(Principal.operator(), other["id"], id)

    assert {:error, %Samgita.Error{code: :not_found}} =
             Management.agent(Principal.operator(), "invalid")

    {:ok, _} =
      Agents.update(
        Principal.operator(),
        a["id"],
        command(%{"expected_version" => a["version"], "enabled" => false})
      )

    assert {:ok, %{"agent" => %{"availability" => "disabled"}}} =
             Management.agent(Principal.operator(), a["id"])
  end
end
