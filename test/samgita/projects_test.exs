defmodule Samgita.ProjectsTest do
  use Samgita.DataCase, async: true

  alias Samgita.Projects
  alias Samgita.Domain.Project

  @valid_attrs %{name: "Test Project", git_url: "git@github.com:org/test.git"}

  defp create_project(attrs \\ %{}) do
    {:ok, project} = Projects.create_project(Map.merge(@valid_attrs, attrs))
    project
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
