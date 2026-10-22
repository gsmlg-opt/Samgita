defmodule Samgita.ProjectsTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Error, Principal, Projects}

  test "stable Projects do not require URLs or spawn anything, and writes are versioned" do
    p = project_fixture()
    assert p["git_url"] == nil
    assert p["state"] == "active"

    assert {:ok, changed} =
             Projects.update(
               Principal.operator(),
               p["id"],
               command(%{"expected_version" => 1, "name" => "renamed"})
             )

    assert changed["id"] == p["id"]
    assert changed["version"] == 2

    assert {:error, %Error{code: :stale_version}} =
             Projects.update(
               Principal.operator(),
               p["id"],
               command(%{"expected_version" => 1, "name" => "stale"})
             )
  end

  test "capabilities grant no membership and revocation is checked before receipt replay" do
    p = project_fixture()
    a = agent_fixture(%{"implementation" => "Synapsis"})
    {principal, _, _} = connection_fixture(a)
    assert {:error, %Error{code: :forbidden}} = Projects.get(principal, p["id"])
    member_fixture(p, a, ["manager"])
    attrs = command(%{"expected_version" => 2, "name" => "managed"})
    assert {:ok, result} = Projects.update(principal, p["id"], attrs)
    assert {:ok, ^result} = Projects.update(principal, p["id"], attrs)
    {:ok, project} = Projects.get(Principal.operator(), p["id"])

    assert {:ok, _} =
             Projects.put_member(
               Principal.operator(),
               p["id"],
               command(%{
                 "agent_id" => a["id"],
                 "roles" => [],
                 "enabled" => false,
                 "expected_version" => project["version"]
               })
             )

    assert {:error, %Error{code: :forbidden}} = Projects.update(principal, p["id"], attrs)
    assert {:ok, _} = Agents.get(Principal.operator(), a["id"])
  end

  test "archive and restore preserve identity and history" do
    p = project_fixture()

    assert {:ok, archived} =
             Projects.transition(
               Principal.operator(),
               p["id"],
               command(%{"expected_version" => 1, "state" => "archived"})
             )

    assert archived["id"] == p["id"]

    assert {:error, %Error{code: :invalid_transition}} =
             Projects.update(
               Principal.operator(),
               p["id"],
               command(%{"expected_version" => 2, "name" => "no"})
             )

    assert {:ok, restored} =
             Projects.transition(
               Principal.operator(),
               p["id"],
               command(%{
                 "expected_version" => 2,
                 "state" => "paused",
                 "reason" => "operator review"
               })
             )

    assert restored["id"] == p["id"]
    assert restored["state"] == "paused"
  end

  test "paused Project context keeps existing execution reconciliation operations visible" do
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["worker"])
    {principal, _, _} = connection_fixture(agent)

    {:ok, _} =
      Projects.transition(
        Principal.operator(),
        project["id"],
        command(%{"expected_version" => 2, "state" => "paused"})
      )

    {:ok, context} = Projects.context(principal, project["id"])

    for operation <- ~w(attempt.renew attempt.report attempt.rebind attempt.resolve attempt.proof) do
      assert operation in context["allowed_operations"]
    end

    refute "attempt.claim" in context["allowed_operations"]
    refute "attempt.start" in context["allowed_operations"]
    refute "task.create" in context["allowed_operations"]
  end
end
