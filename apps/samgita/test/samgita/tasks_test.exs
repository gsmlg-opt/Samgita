defmodule Samgita.TasksTest do
  use Samgita.DataCase, async: false
  alias Samgita.{LegacyMapping, Platform, Principal, Projects, Tasks}

  setup do
    operator = Principal.operator()
    {:ok, project} = Projects.create(operator, command(%{"name" => "Task project"}))
    %{operator: operator, project: project}
  end

  test "new Tasks use neutral identity and preserve historical fields", %{
    operator: op,
    project: p
  } do
    assert {:ok, task} = Tasks.create(op, p["id"], command(%{"title" => "Independent work"}))
    assert task["state"] == "open"
    assert task["adopted"]
    assert task["version"] == 1
    stored = Repo.get!(Samgita.Domain.Task, task["id"])
    assert stored.type == "task"
    assert stored.status == "pending"
    assert stored.agent_id == nil
    assert stored.attempts == 0

    assert {:ok, updated} =
             Tasks.update(
               op,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "title" => "Edited"})
             )

    assert updated["version"] == 2
    assert Repo.get!(Samgita.Domain.Task, task["id"]).status == "pending"
  end

  test "expected versions and command semantics serialize edits", %{operator: op, project: p} do
    {:ok, task} = Tasks.create(op, p["id"], command(%{"title" => "Versioned"}))
    attrs = command(%{"expected_version" => 1, "title" => "Once"})
    assert {:ok, result} = Tasks.update(op, p["id"], task["id"], attrs)
    assert {:ok, ^result} = Tasks.update(op, p["id"], task["id"], attrs)

    assert {:error, %{code: :conflict}} =
             Tasks.update(op, p["id"], task["id"], Map.put(attrs, "title", "Different"))

    assert {:error, %{code: :stale_version}} =
             Tasks.update(
               op,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "title" => "Stale"})
             )
  end

  test "parents stay in the Project and cannot introduce a cycle", %{operator: op, project: p} do
    {:ok, other} = Projects.create(op, command(%{"name" => "Other"}))
    {:ok, parent} = Tasks.create(op, p["id"], command(%{"title" => "Parent"}))

    {:ok, child} =
      Tasks.create(op, p["id"], command(%{"title" => "Child", "parent_task_id" => parent["id"]}))

    assert {:error, %{code: :invalid}} =
             Tasks.update(
               op,
               p["id"],
               parent["id"],
               command(%{"expected_version" => 1, "parent_task_id" => child["id"]})
             )

    assert {:error, %{code: :not_found}} =
             Tasks.create(
               op,
               other["id"],
               command(%{"title" => "Cross-project", "parent_task_id" => parent["id"]})
             )
  end

  test "management transitions cannot impersonate execution or acceptance", %{
    operator: op,
    project: p
  } do
    {:ok, task} = Tasks.create(op, p["id"], command(%{"title" => "State separation"}))

    assert {:error, %{code: :invalid_transition}} =
             Tasks.transition(
               op,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "state" => "accepted"})
             )

    assert {:ok, blocked} =
             Tasks.transition(
               op,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "state" => "blocked"})
             )

    assert blocked["state"] == "blocked"
  end

  test "legacy Tasks stay unadopted and an explicit review preserves old content", %{
    operator: op,
    project: p
  } do
    legacy =
      Repo.insert!(%Samgita.Domain.Task{
        project_id: p["id"],
        type: "legacy-development",
        status: "running",
        payload: %{"old" => true}
      })

    map_legacy!(op)

    assert {:error, %{code: :invalid}} =
             Tasks.adopt(op, p["id"], legacy.id, command(%{"expected_version" => 1}))

    reviewed = %{
      "expected_version" => 1,
      "evidence_ref" => "review-1",
      "effects_resolved" => true,
      "content_reviewed" => true,
      "relationships_reviewed" => true
    }

    assert {:error, %{code: :invalid}} = Tasks.adopt(op, p["id"], legacy.id, command(reviewed))

    assert {:error, %{code: :invalid}} =
             Tasks.adopt(op, p["id"], legacy.id, command(Map.put(reviewed, "title", " ")))

    assert {:error, %{code: :invalid}} =
             Tasks.adopt(
               op,
               p["id"],
               legacy.id,
               command(Map.put(reviewed, "title", String.duplicate("x", 501)))
             )

    refute Repo.get!(Samgita.Domain.Task, legacy.id).adopted
    {:ok, parent} = Tasks.create(op, p["id"], command(%{"title" => "Proposed parent"}))

    assert {:error, %{code: :invalid}} =
             Tasks.adopt(
               op,
               p["id"],
               legacy.id,
               command(
                 Map.merge(reviewed, %{
                   "title" => "Reviewed work",
                   "parent_task_id" => parent["id"]
                 })
               )
             )

    assert Repo.get!(Samgita.Domain.Task, legacy.id).parent_task_id == nil

    assert {:ok, adopted} =
             Tasks.adopt(
               op,
               p["id"],
               legacy.id,
               command(
                 Map.merge(reviewed, %{
                   "title" => "Reviewed work",
                   "description" => "Sanitized management context"
                 })
               )
             )

    assert adopted["adopted"]
    assert adopted["title"] == "Reviewed work"
    assert adopted["description"] == "Sanitized management context"
    assert Repo.get!(Samgita.Domain.Task, legacy.id).payload == %{"old" => true}
    assert Repo.get!(Samgita.Domain.Task, legacy.id).status == "running"

    assert {:error, %{code: :invalid}} =
             Tasks.update(
               op,
               p["id"],
               legacy.id,
               command(%{
                 "expected_version" => adopted["version"],
                 "parent_task_id" => parent["id"]
               })
             )

    assert Repo.get!(Samgita.Domain.Task, legacy.id).parent_task_id == nil
    assert Repo.get!(Samgita.Domain.Task, legacy.id).version == adopted["version"]

    assert {:ok, renamed} =
             Tasks.update(
               op,
               p["id"],
               legacy.id,
               command(%{
                 "expected_version" => adopted["version"],
                 "parent_task_id" => nil,
                 "title" => "Revised neutral title"
               })
             )

    assert renamed["title"] == "Revised neutral title"
    assert {:ok, repeated} = LegacyMapping.apply(op, command(%{}))

    assert Enum.any?(
             repeated["data"],
             &(&1["source_id"] == legacy.id && &1["status"] == "mapped")
           )
  end

  test "archived Projects retain Task reads but reject mutations", %{operator: op, project: p} do
    {:ok, task} = Tasks.create(op, p["id"], command(%{"title" => "Preserved"}))
    {:ok, current} = Projects.get(op, p["id"])

    {:ok, _} =
      Projects.transition(
        op,
        p["id"],
        command(%{"expected_version" => current["version"], "state" => "archived"})
      )

    assert {:ok, %{"id" => id}} = Tasks.get(op, p["id"], task["id"])
    assert id == task["id"]

    assert {:error, %{code: :invalid_transition}} =
             Tasks.create(op, p["id"], command(%{"title" => "Blocked"}))

    assert {:error, %{code: :invalid_transition}} =
             Tasks.update(
               op,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "title" => "Blocked"})
             )
  end

  test "audited legacy adoption resolves a legacy-only hold without inventing an Attempt", %{
    operator: op,
    project: p
  } do
    legacy =
      Repo.insert!(%Samgita.Domain.Task{
        project_id: p["id"],
        type: "legacy",
        status: "assigned"
      })

    map_legacy!(op)
    assert Repo.get!(Samgita.Domain.Task, legacy.id).execution_hold

    assert {:ok, adopted} =
             Tasks.adopt(
               op,
               p["id"],
               legacy.id,
               command(%{
                 "expected_version" => 1,
                 "title" => "Reconciled work",
                 "evidence_ref" => "legacy-process-cessation",
                 "effects_resolved" => true,
                 "content_reviewed" => true,
                 "relationships_reviewed" => true
               })
             )

    refute adopted["execution_hold"]
    assert Repo.get!(Samgita.Domain.Task, legacy.id).status == "assigned"

    assert Repo.aggregate(
             from(a in Samgita.Domain.TaskAttempt, where: a.task_id == ^legacy.id),
             :count
           ) == 0
  end

  test "legacy adoption requires an unchanged recorded source mapping", %{
    operator: op,
    project: p
  } do
    legacy =
      Repo.insert!(%Samgita.Domain.Task{project_id: p["id"], type: "legacy", state: "open"})

    attrs = %{
      "expected_version" => 1,
      "title" => "Reviewed",
      "evidence_ref" => "review",
      "effects_resolved" => true,
      "content_reviewed" => true,
      "relationships_reviewed" => true
    }

    assert {:error, _} = Tasks.adopt(op, p["id"], legacy.id, command(attrs))
    refute Repo.get!(Samgita.Domain.Task, legacy.id).adopted

    Repo.update!(Ecto.Changeset.change(legacy, state: nil))
    map_legacy!(op)

    Repo.update_all(from(t in Samgita.Domain.Task, where: t.id == ^legacy.id),
      set: [payload: %{"changed" => true}]
    )

    assert {:error, _} = Tasks.adopt(op, p["id"], legacy.id, command(attrs))
    refute Repo.get!(Samgita.Domain.Task, legacy.id).adopted
  end

  test "unmapped Projects retain history but cannot receive new Tasks", %{operator: op} do
    project =
      Repo.insert!(%Samgita.Domain.Project{
        name: "Unmapped",
        git_url: "/legacy",
        status: "pending"
      })

    assert {:error, %{code: :invalid_transition}} =
             Tasks.create(op, project.id, command(%{"title" => "Blocked"}))
  end

  defp map_legacy!(operator) do
    {:ok, authority} = Platform.status(operator)

    assert {:ok, _} =
             Platform.close(
               operator,
               command(%{
                 "expected_version" => authority["version"],
                 "reason" => "isolated legacy adoption test"
               })
             )

    assert {:ok, _} = LegacyMapping.apply(operator, command(%{}))
  end

  defp command(attrs), do: Map.put(attrs, "command_id", Ecto.UUID.generate())
end
