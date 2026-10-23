defmodule Samgita.Migration.MappingTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL
  alias Samgita.Domain.{MigrationMapping, Project, Task, TaskAttempt}
  alias Samgita.{LegacyMapping, Platform, Principal, Projects, Repo, Tasks}

  setup do
    {:ok, a} = Platform.status(Principal.operator())

    {:ok, _} =
      Platform.close(
        Principal.operator(),
        command(%{"expected_version" => a["version"], "reason" => "mapping-rehearsal"})
      )

    :ok
  end

  test "status mappings preserve raw values, IDs and history and reruns add nothing" do
    p = legacy_project("git@github.com:Org/Repo.git", "running")
    other = legacy_project("https://github.com/Org/Repo.git", "paused")

    statuses =
      ~w(pending blocked assigned running completed failed dead_letter skipped unexpected)

    tasks =
      Enum.map(
        statuses,
        &Repo.insert!(%Task{
          project_id: p.id,
          type: "legacy_type",
          status: &1,
          agent_id: "old-worker",
          payload: %{"historical_secret" => "never-project-this"},
          attempts: 7
        })
      )

    before = Enum.map(tasks, &legacy_task/1)
    {:ok, preview} = LegacyMapping.preview(Principal.operator())
    refute Jason.encode!(preview) =~ "never-project-this"

    assert Enum.any?(
             preview["data"],
             &(&1["source_id"] == p.id && &1["details"]["ambiguous_alias"])
           )

    {:ok, result} = LegacyMapping.apply(Principal.operator(), command())
    assert Enum.map(tasks, &legacy_task/1) == before
    assert Repo.get!(Project, p.id).state == "active"
    assert Repo.get!(Project, other.id).state == "paused"
    expected = ~w(open blocked blocked blocked awaiting_review failed failed cancelled)

    for {task, state} <- Enum.zip(tasks, expected) do
      current = Repo.get!(Task, task.id)
      assert current.state == state
      refute current.adopted
      assert current.status == task.status
    end

    assert Repo.get!(Task, List.last(tasks).id).state == nil
    assert Repo.get!(Task, Enum.at(tasks, 3).id).execution_hold
    mappings = Repo.aggregate(MigrationMapping, :count)
    {:ok, repeated} = LegacyMapping.apply(Principal.operator(), command())
    assert repeated == result
    assert Repo.aggregate(MigrationMapping, :count) == mappings
    refute Repo.exists?(from a in TaskAttempt, where: a.project_id == ^p.id)
  end

  test "source changes and contradictory relationships require review rather than overwrite" do
    p = legacy_project("/unreachable/local", "pending")
    foreign = legacy_project("local-other", "pending")
    foreign_task = Repo.insert!(%Task{project_id: foreign.id, type: "legacy"})
    # Historical fixture bypasses the new NOT VALID FK by recording the edge in
    # its preserved dependency array, which has never had a foreign key.
    task =
      Repo.insert!(%Task{project_id: p.id, type: "legacy", depends_on_ids: [foreign_task.id]})

    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())
    current = Repo.get!(Task, task.id)
    assert current.migration_metadata["relationship_conflict"]

    assert {:error, _} =
             Tasks.adopt(
               Principal.operator(),
               p.id,
               task.id,
               command(%{
                 "expected_version" => 1,
                 "title" => "reviewed",
                 "effects_resolved" => true,
                 "content_reviewed" => true,
                 "relationships_reviewed" => true,
                 "evidence_ref" => "review"
               })
             )

    Repo.update_all(from(t in Task, where: t.id == ^task.id),
      set: [payload: %{"changed" => true}]
    )

    {:ok, result} = LegacyMapping.apply(Principal.operator(), command())

    assert Enum.any?(
             result["data"],
             &(&1["source_id"] == task.id && &1["status"] == "source_changed")
           )
  end

  test "same-Project dependency disagreements are ledger conflicts and source drift blocks adoption" do
    p = legacy_project("/local/graph", "pending")
    a = Repo.insert!(%Task{project_id: p.id, type: "legacy"})
    b = Repo.insert!(%Task{project_id: p.id, type: "legacy"})
    divergent = Repo.insert!(%Task{project_id: p.id, type: "legacy", depends_on_ids: [a.id]})

    SQL.query!(
      Repo,
      "INSERT INTO task_dependencies (id,task_id,depends_on_id,inserted_at) VALUES ($1,$2,$3,now())",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        Ecto.UUID.dump!(divergent.id),
        Ecto.UUID.dump!(b.id)
      ]
    )

    clean =
      Repo.insert!(%Task{project_id: p.id, type: "legacy", payload: %{"source" => "reviewed"}})

    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())
    conflict = Repo.get_by!(MigrationMapping, source_table: "tasks", source_id: divergent.id)
    assert conflict.status == "conflict"
    assert conflict.details["relationship_conflict"]

    Repo.update_all(from(t in Task, where: t.id == ^clean.id),
      set: [payload: %{"source" => "changed"}]
    )

    evidence =
      command(%{
        "expected_version" => 1,
        "title" => "sanitized",
        "effects_resolved" => true,
        "content_reviewed" => true,
        "relationships_reviewed" => true,
        "evidence_ref" => "cannot-override-source-change"
      })

    assert {:error, %{code: :conflict}} =
             Tasks.adopt(Principal.operator(), p.id, clean.id, evidence)

    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())

    assert Repo.get_by!(MigrationMapping, source_table: "tasks", source_id: clean.id).status ==
             "source_changed"

    assert Repo.get!(Task, clean.id).execution_hold

    assert {:error, %{code: :conflict}} =
             Tasks.adopt(Principal.operator(), p.id, clean.id, evidence)
  end

  test "every historical Project status has an inert mapping without rekeying" do
    statuses = [
      {"pending", "active"},
      {"running", "active"},
      {"paused", "paused"},
      {"completed", "archived"},
      {"failed", "paused"},
      {"unknown", nil}
    ]

    projects =
      Enum.map(statuses, fn {status, expected} ->
        {legacy_project("/local/" <> status, status), expected}
      end)

    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())

    for {project, expected} <- projects do
      stored = Repo.get!(Project, project.id)
      assert stored.state == expected
      assert stored.status == project.status
      assert stored.git_url == project.git_url
    end
  end

  test "managed Project edits preserve legacy identity and do not invalidate its source digest" do
    project = legacy_project("/local/frozen", "pending")
    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())

    assert {:error, %{code: :conflict}} =
             Projects.update(
               Principal.operator(),
               project.id,
               command(%{"expected_version" => 1, "name" => "would-rewrite-history"})
             )

    assert Repo.get!(Project, project.id).name == "legacy"

    assert {:ok, updated} =
             Projects.update(
               Principal.operator(),
               project.id,
               command(%{"expected_version" => 1, "description" => "Managed context"})
             )

    assert updated["version"] == 2
    {:ok, _} = LegacyMapping.apply(Principal.operator(), command())

    assert Repo.get_by!(MigrationMapping, source_table: "projects", source_id: project.id).status ==
             "mapped"
  end

  defp legacy_project(url, status),
    do: Repo.insert!(%Project{name: "legacy", git_url: url, status: status})

  defp legacy_task(task) do
    %{rows: [[row]]} =
      SQL.query!(
        Repo,
        "SELECT to_jsonb(t) - ARRAY['title','description','state','version','adopted','execution_hold','required_capabilities','migration_metadata','accepted_at','fence_counter']::text[] FROM tasks t WHERE id = $1::uuid",
        [Ecto.UUID.dump!(task.id)]
      )

    row
  end
end
