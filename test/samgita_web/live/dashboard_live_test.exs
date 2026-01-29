defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  test "renders empty dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Dashboard"
    assert html =~ "No projects yet"
    assert has_element?(view, "a", "New Project")
  end

  test "lists projects", %{conn: conn} do
    {:ok, _} =
      Projects.create_project(%{
        name: "Test Project",
        git_url: "git@github.com:test/dash-#{System.unique_integer([:positive])}.git"
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Test Project"
  end
end
