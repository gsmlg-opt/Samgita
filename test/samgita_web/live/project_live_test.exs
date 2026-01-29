defmodule SamgitaWeb.ProjectLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  defp create_project(attrs \\ %{}) do
    defaults = %{
      name: "Live Test",
      git_url: "git@github.com:test/live-#{System.unique_integer([:positive])}.git",
      prd_content: "# Test PRD"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end

  test "renders project detail", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Live Test"
    assert html =~ "bootstrap"
    assert html =~ "Phase Progress"
  end

  test "shows start button for pending project", %{conn: conn} do
    project = create_project(%{status: :pending})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Start")
  end

  test "redirects on 404", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/projects/#{Ecto.UUID.generate()}")
  end

  test "shows pause button for running project", %{conn: conn} do
    project = create_project(%{status: :running})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Pause")
  end

  test "shows resume button for paused project", %{conn: conn} do
    project = create_project(%{status: :paused})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Resume")
  end

  test "displays task count section", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Tasks"
    assert html =~ "No tasks yet"
  end

  test "start transitions project to running", %{conn: conn} do
    project = create_project(%{status: :pending})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "start")
    assert html =~ "running"
    assert html =~ "Pause"
  end

  test "pause transitions running project to paused", %{conn: conn} do
    project = create_project(%{status: :running})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "pause")
    assert html =~ "paused"
    assert html =~ "Resume"
  end

  test "resume transitions paused project to running", %{conn: conn} do
    project = create_project(%{status: :paused})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "resume")
    assert html =~ "running"
    assert html =~ "Pause"
  end
end
