defmodule SamgitaWeb.ProjectLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Live Test",
        git_url: "git@github.com:test/live-#{System.unique_integer([:positive])}.git",
        prd_content: "# Test PRD"
      })

    %{project: project}
  end

  test "renders project detail", %{conn: conn, project: project} do
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Live Test"
    assert html =~ "bootstrap"
  end

  test "shows start button for pending project", %{conn: conn, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Start")
  end

  test "redirects on 404", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/projects/#{Ecto.UUID.generate()}")
  end
end
