defmodule Samgita.PlatformTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Error, Platform, Principal, Tasks}

  test "closing authority invalidates ownership and preserves unresolved effects across reopen" do
    active = activate_fixture()
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {principal, _, _} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => "isolated-runtime"})
      )

    {:ok, task} = Tasks.create(principal, project["id"], command(%{"title" => "test execution"}))
    claim = command(%{"expected_version" => task["version"], "session_id" => session["id"]})
    {:ok, attempt} = Attempts.claim(principal, project["id"], task["id"], claim)

    {:ok, closed} =
      Platform.close(
        Principal.operator(),
        command(%{"expected_version" => active["version"], "reason" => "operator fence"})
      )

    assert closed["owner"] == "none"
    assert closed["epoch"] > active["epoch"]

    assert {:error, %Error{code: :execution_closed}} =
             Attempts.claim(principal, project["id"], task["id"], claim)

    {:ok, held} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert held["state"] == "blocked"
    assert held["execution_hold"]

    {:ok, reopened} =
      Tasks.transition(
        Principal.operator(),
        project["id"],
        task["id"],
        command(%{"expected_version" => held["version"], "state" => "open"})
      )

    assert reopened["execution_hold"]

    assert {:error, %Error{code: :conflict}} =
             Platform.activate(
               Principal.operator(),
               command(%{
                 "expected_version" => closed["version"],
                 "evidence" => %{
                   "legacy_fenced" => true,
                   "effects_resolved" => true,
                   "reference" => "must-not-override-held-effect"
                 }
               })
             )

    assert {:ok, _} =
             Attempts.resolve(
               Principal.operator(),
               project["id"],
               attempt["id"],
               command(%{
                 "expected_version" => attempt["version"] + 1,
                 "effects_resolved" => true,
                 "evidence_ref" => "operator-confirmed-cessation"
               })
             )

    assert activate_fixture()["owner"] == "hub"

    assert {:error, %Error{code: :ownership_lost}} =
             Attempts.claim(principal, project["id"], task["id"], claim)
  end
end
