defmodule Samgita.ProjectsTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Project
  alias Samgita.Projects

  @valid_attrs %{name: "Test Project", git_url: "git@github.com:org/test.git"}

  defp create_project(attrs \\ %{}) do
    {:ok, project} = Projects.create_project(Map.merge(@valid_attrs, attrs))
    project
  end

  defp create_prd(project, attrs \\ %{}) do
    defaults = %{
      project_id: project.id,
      title: "Test PRD",
      content: "# Test PRD Content",
      status: :approved
    }

    {:ok, prd} = Samgita.Prds.create_prd(Map.merge(defaults, attrs))
    prd
  end

  describe "list_projects/0" do
    test "returns all projects" do
      project = create_project()
      assert [listed] = Projects.list_projects()
      assert listed.id == project.id
    end

    test "returns empty list when no projects" do
      assert [] = Projects.list_projects()
    end
  end

  describe "get_project/1" do
    test "returns project by id" do
      project = create_project()
      assert {:ok, found} = Projects.get_project(project.id)
      assert found.id == project.id
    end

    test "returns error for nonexistent id" do
      assert {:error, :not_found} = Projects.get_project(Ecto.UUID.generate())
    end
  end

  describe "create_project/1" do
    test "creates project with valid attrs" do
      assert {:ok, %Project{} = project} = Projects.create_project(@valid_attrs)
      assert project.name == "Test Project"
      assert project.git_url == "git@github.com:org/test.git"
      assert project.phase == :bootstrap
      assert project.status == :pending
    end

    test "fails with invalid attrs" do
      assert {:error, changeset} = Projects.create_project(%{})
      refute changeset.valid?
    end

    test "enforces unique git_url" do
      create_project()
      assert {:error, changeset} = Projects.create_project(@valid_attrs)
      assert %{git_url: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_project/2" do
    test "updates with valid attrs" do
      project = create_project()
      assert {:ok, updated} = Projects.update_project(project, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "delete_project/1" do
    test "deletes the project" do
      project = create_project()
      assert {:ok, _} = Projects.delete_project(project)
      assert {:error, :not_found} = Projects.get_project(project.id)
    end
  end

  describe "start_project/2" do
    test "starts a pending project with a PRD" do
      project = create_project(%{status: :pending})
      prd = create_prd(project)

      assert {:ok, started} = Projects.start_project(project.id, prd.id)
      assert started.status == :running
      assert started.phase == :bootstrap
      assert started.active_prd_id == prd.id

      # PRD should be in_progress
      {:ok, updated_prd} = Samgita.Prds.get_prd(prd.id)
      assert updated_prd.status == :in_progress
    end

    test "starts a completed project" do
      project = create_project(%{status: :completed})
      prd = create_prd(project)

      assert {:ok, started} = Projects.start_project(project.id, prd.id)
      assert started.status == :running
    end

    test "starts a failed project" do
      project = create_project(%{status: :failed})
      prd = create_prd(project)

      assert {:ok, started} = Projects.start_project(project.id, prd.id)
      assert started.status == :running
    end

    test "fails for already running project" do
      project = create_project(%{status: :running})
      prd = create_prd(project)

      assert {:error, :already_active} = Projects.start_project(project.id, prd.id)
    end

    test "fails when PRD belongs to different project" do
      project1 = create_project()
      project2 = create_project(%{git_url: "git@github.com:org/other.git"})
      prd = create_prd(project2)

      assert {:error, :prd_not_in_project} = Projects.start_project(project1.id, prd.id)
    end
  end

  describe "stop_project/1" do
    test "stops a running project and clears active_prd_id" do
      project = create_project(%{status: :running})
      prd = create_prd(project, %{status: :in_progress})
      {:ok, project} = Projects.update_project(project, %{active_prd_id: prd.id})

      assert {:ok, stopped} = Projects.stop_project(project.id)
      assert stopped.status == :completed
      assert stopped.active_prd_id == nil

      # PRD should be reset to approved
      {:ok, updated_prd} = Samgita.Prds.get_prd(prd.id)
      assert updated_prd.status == :approved
    end

    test "fails for non-active project" do
      project = create_project(%{status: :pending})
      assert {:error, :not_active} = Projects.stop_project(project.id)
    end
  end

  describe "restart_project/1" do
    test "restarts a running project with same PRD" do
      project = create_project(%{status: :running})
      prd = create_prd(project, %{status: :in_progress})
      {:ok, project} = Projects.update_project(project, %{active_prd_id: prd.id})

      assert {:ok, restarted} = Projects.restart_project(project.id)
      assert restarted.status == :running
      assert restarted.phase == :bootstrap
      assert restarted.active_prd_id == prd.id
    end

    test "fails when no active PRD" do
      project = create_project(%{status: :running})
      assert {:error, :no_active_prd} = Projects.restart_project(project.id)
    end

    test "fails for non-active project" do
      project = create_project(%{status: :pending})
      assert {:error, :not_active} = Projects.restart_project(project.id)
    end
  end

  describe "terminate_project/1" do
    test "terminates project and marks as failed" do
      project = create_project(%{status: :running})
      prd = create_prd(project, %{status: :in_progress})
      {:ok, project} = Projects.update_project(project, %{active_prd_id: prd.id})

      # Create some pending tasks
      {:ok, _task} =
        Projects.create_task(project.id, %{
          type: "test",
          payload: %{},
          status: :pending
        })

      assert {:ok, terminated} = Projects.terminate_project(project.id)
      assert terminated.status == :failed
      assert terminated.active_prd_id == nil

      # PRD should be reset to draft
      {:ok, updated_prd} = Samgita.Prds.get_prd(prd.id)
      assert updated_prd.status == :draft

      # Tasks should be failed
      [task] = Projects.list_tasks(project.id)
      assert task.status == :failed
    end

    test "fails for non-active project" do
      project = create_project(%{status: :pending})
      assert {:error, :not_active} = Projects.terminate_project(project.id)
    end
  end

  describe "list_tasks_for_prd/2" do
    test "returns tasks scoped to a PRD" do
      project = create_project()
      prd = create_prd(project)

      {:ok, _task1} =
        Projects.create_task(project.id, %{
          type: "bootstrap",
          payload: %{"prd_id" => prd.id}
        })

      {:ok, _task2} =
        Projects.create_task(project.id, %{
          type: "other",
          payload: %{"prd_id" => Ecto.UUID.generate()}
        })

      tasks = Projects.list_tasks_for_prd(project.id, prd.id)
      assert length(tasks) == 1
      assert hd(tasks).type == "bootstrap"
    end
  end

  describe "pause_project/1" do
    test "pauses a running project" do
      project = create_project(%{status: :running})
      assert {:ok, paused} = Projects.pause_project(project.id)
      assert paused.status == :paused
    end

    test "fails for non-running project" do
      project = create_project(%{status: :pending})
      assert {:error, :not_running} = Projects.pause_project(project.id)
    end
  end

  describe "resume_project/1" do
    test "resumes a paused project" do
      project = create_project(%{status: :paused})
      assert {:ok, resumed} = Projects.resume_project(project.id)
      assert resumed.status == :running
    end

    test "fails for non-paused project" do
      project = create_project(%{status: :running})
      assert {:error, :not_paused} = Projects.resume_project(project.id)
    end
  end
end
