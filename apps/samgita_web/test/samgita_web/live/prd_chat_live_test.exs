defmodule SamgitaWeb.PrdChatLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.{Projects, Prds}

  defp create_project(attrs \\ %{}) do
    defaults = %{
      name: "Chat Test Project",
      git_url: "git@github.com:test/chat-#{System.unique_integer([:positive])}.git",
      prd_content: "# Chat Test"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end

  defp create_prd(project, attrs \\ %{}) do
    defaults = %{
      project_id: project.id,
      title: "Existing PRD",
      content: "# Existing Content",
      status: :approved
    }

    {:ok, prd} = Prds.create_prd(Map.merge(defaults, attrs))
    prd
  end

  describe "new PRD" do
    test "renders new PRD form", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert html =~ "New PRD"
      assert html =~ project.name
      assert html =~ "Create PRD"
    end

    test "validates title on change", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      html =
        render_change(view, "validate", %{
          "prd" => %{"title" => "Updated Title", "content" => "Some content"}
        })

      assert html =~ "Updated Title"
    end

    test "creates PRD with title and content", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      {:ok, _view, html} =
        view
        |> form("form", prd: %{title: "New Feature PRD", content: "# Feature"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "PRD created"
    end

    test "shows error for empty title", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      html =
        view
        |> form("form", prd: %{title: "", content: "content"})
        |> render_submit()

      assert html =~ "Title is required"
    end

    test "creates draft PRD when content is empty", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      {:ok, _view, _html} =
        view
        |> form("form", prd: %{title: "Draft PRD", content: ""})
        |> render_submit()
        |> follow_redirect(conn)

      # Verify the PRD was created as draft
      prds = Prds.list_prds(project.id)
      prd = Enum.find(prds, &(&1.title == "Draft PRD"))
      assert prd.status == :draft
    end

    test "redirects to project page on project not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/projects/#{Ecto.UUID.generate()}/prds/new")
    end
  end

  describe "edit PRD" do
    test "renders edit form with existing data", %{conn: conn} do
      project = create_project()
      prd = create_prd(project, %{title: "Edit Me", content: "# Edit Content"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")
      assert html =~ "Edit PRD"
      assert html =~ "Edit Me"
      assert html =~ "Update PRD"
    end

    test "updates PRD", %{conn: conn} do
      project = create_project()
      prd = create_prd(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")

      {:ok, _view, html} =
        view
        |> form("form", prd: %{title: "Updated Title", content: "# Updated"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "PRD updated"
    end

    test "redirects on PRD not found", %{conn: conn} do
      project = create_project()

      assert {:error, {:live_redirect, %{to: _path}}} =
               live(conn, ~p"/projects/#{project.id}/prds/#{Ecto.UUID.generate()}")
    end
  end

  describe "preview toggle" do
    test "toggles between edit and preview mode", %{conn: conn} do
      project = create_project()
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      # Initially in edit mode - shows textarea
      assert html =~ "Preview"

      # Toggle to preview
      html = render_click(view, "toggle_preview")
      assert html =~ "Edit"

      # Toggle back to edit
      html = render_click(view, "toggle_preview")
      assert html =~ "Preview"
    end
  end

  describe "back navigation" do
    test "has back link to project", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert has_element?(view, "a", "Back to Project")
    end

    test "has cancel link to project", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert has_element?(view, "a", "Cancel")
    end
  end
end
