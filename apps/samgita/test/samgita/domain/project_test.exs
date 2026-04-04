defmodule Samgita.Domain.ProjectTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Project

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Project.changeset(%Project{}, %{name: "test", git_url: "git@github.com:org/repo.git"})

      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Project.changeset(%Project{}, %{git_url: "git@github.com:org/repo.git"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without git_url" do
      changeset = Project.changeset(%Project{}, %{name: "test"})
      refute changeset.valid?
      assert %{git_url: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults phase to bootstrap" do
      changeset =
        Project.changeset(%Project{}, %{name: "test", git_url: "git@github.com:org/repo.git"})

      project = Ecto.Changeset.apply_changes(changeset)
      assert project.phase == :bootstrap
    end

    test "defaults status to pending" do
      changeset =
        Project.changeset(%Project{}, %{name: "test", git_url: "git@github.com:org/repo.git"})

      project = Ecto.Changeset.apply_changes(changeset)
      assert project.status == :pending
    end

    test "accepts optional fields" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "test",
          git_url: "git@github.com:org/repo.git",
          working_path: "/tmp/test",
          prd_content: "# PRD",
          phase: :development,
          status: :running,
          config: %{"key" => "value"}
        })

      assert changeset.valid?
    end

    test "validates git_url format - accepts git@ URLs" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "Test",
          git_url: "git@github.com:org/repo.git"
        })

      assert changeset.valid?
    end

    test "validates git_url format - accepts https URLs" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "Test",
          git_url: "https://github.com/org/repo.git"
        })

      assert changeset.valid?
    end

    test "validates git_url format - accepts local paths" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "Test",
          git_url: "/Users/test/project"
        })

      assert changeset.valid?
    end

    test "validates git_url format - rejects invalid URLs" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "Test",
          git_url: "not-a-valid-url"
        })

      refute changeset.valid?
      assert %{git_url: [_]} = errors_on(changeset)
    end

    test "defaults start_mode to :from_prd" do
      changeset =
        Project.changeset(%Project{}, %{name: "test", git_url: "git@github.com:org/repo.git"})

      project = Ecto.Changeset.apply_changes(changeset)
      assert project.start_mode == :from_prd
    end

    test "defaults planning_auto_advance to false" do
      changeset =
        Project.changeset(%Project{}, %{name: "test", git_url: "git@github.com:org/repo.git"})

      project = Ecto.Changeset.apply_changes(changeset)
      assert project.planning_auto_advance == false
    end

    test "can set start_mode to :from_idea" do
      changeset =
        Project.changeset(%Project{}, %{
          name: "test",
          git_url: "git@github.com:org/repo.git",
          start_mode: :from_idea
        })

      assert changeset.valid?
      project = Ecto.Changeset.apply_changes(changeset)
      assert project.start_mode == :from_idea
    end
  end

  describe "phases/0" do
    test ":planning is included in phases" do
      assert :planning in Project.phases()
    end

    test ":planning is the first phase" do
      assert hd(Project.phases()) == :planning
    end
  end
end
