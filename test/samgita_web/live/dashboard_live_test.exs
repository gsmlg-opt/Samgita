defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  defp unique_git_url(prefix \\ "dash") do
    "git@github.com:test/#{prefix}-#{System.unique_integer([:positive])}.git"
  end

  test "renders empty dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Dashboard"
    assert html =~ "No projects yet"
    assert has_element?(view, "a", "New Project")
  end

  test "lists projects", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Test Project", git_url: unique_git_url()})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Test Project"
  end

  test "shows multiple projects", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Alpha", git_url: unique_git_url("alpha")})
    {:ok, _} = Projects.create_project(%{name: "Beta", git_url: unique_git_url("beta")})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Alpha"
    assert html =~ "Beta"
    refute html =~ "No projects yet"
  end

  test "displays project status badges", %{conn: conn} do
    {:ok, _} =
      Projects.create_project(%{
        name: "Running Project",
        git_url: unique_git_url("running"),
        status: :running
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "running"
  end

  test "displays project phase", %{conn: conn} do
    {:ok, _} =
      Projects.create_project(%{
        name: "Dev Project",
        git_url: unique_git_url("dev"),
        phase: :development
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "development"
  end

  test "displays git URL for each project", %{conn: conn} do
    url = unique_git_url("giturl")
    {:ok, _} = Projects.create_project(%{name: "URL Test", git_url: url})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ url
  end

  test "new project link navigates to form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s|a[href="/projects/new"]|)
  end

  test "updates when project_updated message received", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{name: "PubSub Test", git_url: unique_git_url("pubsub")})

    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "PubSub Test"

    # Update the project name and send a PubSub event
    {:ok, updated} = Projects.update_project(project, %{name: "Updated Name"})
    send(view.pid, {:project_updated, updated})

    html = render(view)
    assert html =~ "Updated Name"
  end

  test "updates when project_updated with phase message received", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Phase Test",
        git_url: unique_git_url("phase"),
        phase: :bootstrap
      })

    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "bootstrap"

    # Simulate phase change
    {:ok, _} = Projects.update_project(project, %{phase: :development})
    send(view.pid, {:project_updated, project.id, :development})

    html = render(view)
    assert html =~ "development"
  end

  test "shows different status colors for each status", %{conn: conn} do
    for status <- [:pending, :running, :paused, :completed, :failed] do
      {:ok, _} =
        Projects.create_project(%{
          name: "#{status} proj",
          git_url: unique_git_url("color-#{status}"),
          status: status
        })
    end

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "pending"
    assert html =~ "running"
    assert html =~ "paused"
    assert html =~ "completed"
    assert html =~ "failed"
  end
end
