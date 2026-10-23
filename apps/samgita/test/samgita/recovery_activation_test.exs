defmodule Samgita.RecoveryActivationTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias Samgita.{Agents, Attempts, Error, LegacyMapping, Platform, Principal, Tasks}
  alias Samgita.Domain.{MigrationMapping, Project, Task, TaskAttempt}

  setup do
    {:ok, authority} = Platform.status(Principal.operator())

    {:ok, closed} =
      Platform.close(
        Principal.operator(),
        command(%{
          "expected_version" => authority["version"],
          "reason" => "recovery guard fixture"
        })
      )

    %{closed: closed}
  end

  test "unmapped historical work blocks activation without changing its source", %{closed: closed} do
    project = Repo.insert!(%Project{name: "Unmapped recovery history"})
    task = Repo.insert!(%Task{project_id: project.id, type: "legacy", status: "pending"})

    assert_unresolved(closed)
    assert Repo.get!(Task, task.id) == task
    refute Repo.exists?(from m in MigrationMapping, where: m.source_id == ^task.id)
  end

  test "a genuine mapping conflict still blocks activation", %{closed: closed} do
    project = Repo.insert!(%Project{name: "Unknown legacy state", status: "unknown"})
    assert {:ok, _} = LegacyMapping.apply(Principal.operator(), command())
    mapping = Repo.get_by!(MigrationMapping, source_table: "projects", source_id: project.id)
    assert mapping.status == "conflict"

    assert_unresolved(closed)
    assert Repo.get!(MigrationMapping, mapping.id) == mapping
    assert Repo.get!(Project, project.id).state == nil
  end

  test "valid repeated mappings preserve history and permit activation", %{closed: closed} do
    project = Repo.insert!(%Project{name: "Mapped recovery history", status: "pending"})

    task =
      Repo.insert!(%Task{
        project_id: project.id,
        type: "legacy",
        status: "completed",
        payload: %{"history" => "preserve"}
      })

    assert {:ok, mapped} = LegacyMapping.apply(Principal.operator(), command())
    mappings = Repo.all(from m in MigrationMapping, order_by: m.id)
    assert {:ok, ^mapped} = LegacyMapping.apply(Principal.operator(), command())
    assert Repo.all(from m in MigrationMapping, order_by: m.id) == mappings

    assert {:ok, %{"owner" => "hub"}} = activate(closed)
    current = Repo.get!(Task, task.id)
    assert current.state == "awaiting_review"
    assert current.status == task.status
    assert current.payload == task.payload
    assert current.inserted_at == task.inserted_at
    refute current.adopted
    assert is_nil(current.accepted_at)
    refute Repo.exists?(from a in TaskAttempt, where: a.task_id == ^task.id)
  end

  test "an unresolved execution remains blocked despite activation evidence", %{closed: closed} do
    assert {:ok, active} = activate(closed)
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {actor, _, _} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(actor, project["id"], command(%{"external_id" => Ecto.UUID.generate()}))

    {:ok, task} = Tasks.create(actor, project["id"], command(%{"title" => "Unresolved recovery"}))

    {:ok, attempt} =
      Attempts.claim(
        actor,
        project["id"],
        task["id"],
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )

    {:ok, fenced} =
      Platform.close(
        Principal.operator(),
        command(%{"expected_version" => active["version"], "reason" => "retain unknown effect"})
      )

    held = Repo.get!(Task, task["id"])
    expired = Repo.get!(TaskAttempt, attempt["id"])
    assert held.state == "blocked"
    assert held.execution_hold
    refute expired.effects_resolved

    assert_unresolved(fenced)
    assert Repo.get!(Task, held.id) == held
    assert Repo.get!(TaskAttempt, expired.id) == expired
  end

  defp assert_unresolved(authority) do
    assert {:error, %Error{code: :conflict, details: %{reason: "unmapped_or_unresolved_tasks"}}} =
             activate(authority)
  end

  defp activate(authority) do
    Platform.activate(
      Principal.operator(),
      command(%{
        "expected_version" => authority["version"],
        "evidence" => %{
          "legacy_fenced" => true,
          "effects_resolved" => true,
          "reference" => "rollback-isolated-recovery-guard"
        }
      })
    )
  end
end
