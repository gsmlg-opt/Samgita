defmodule SamgitaWeb.ProjectFormLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders new project form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects/new")
    assert html =~ "New Project"
    assert html =~ "Git URL"
    assert html =~ "Create Project"
  end

  test "creates project with valid data", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    view
    |> form("form",
      project: %{
        name: "Created",
        git_url: "git@github.com:test/created-#{System.unique_integer([:positive])}.git"
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/projects/"
  end

  test "validates required fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    html =
      view
      |> form("form", project: %{name: "", git_url: ""})
      |> render_change()

    assert html =~ "can&#39;t be blank"
  end
end
