defmodule SamgitaWeb.ProjectFormLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp unique_git_url(prefix \\ "form") do
    "git@github.com:test/#{prefix}-#{System.unique_integer([:positive])}.git"
  end

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
        git_url: unique_git_url("created")
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

  test "shows cancel link to dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")
    assert has_element?(view, ~s|a[href="/"]|, "Cancel")
  end

  test "shows dashboard back link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")
    assert has_element?(view, ~s|a[href="/"]|, "Dashboard")
  end

  test "displays working path field", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects/new")
    assert html =~ "Working Path"
    assert html =~ "Auto-detected from git URL"
  end

  test "displays PRD content textarea", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects/new")
    assert html =~ "PRD Content"
    assert html =~ "Product Requirements Document"
  end

  test "validates invalid git URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    html =
      view
      |> form("form", project: %{name: "Test", git_url: "not-a-valid-url"})
      |> render_change()

    assert html =~ "must be a valid git URL"
  end

  test "accepts https git URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    html =
      view
      |> form("form",
        project: %{
          name: "HTTPS Project",
          git_url: "https://github.com/test/repo-#{System.unique_integer([:positive])}.git"
        }
      )
      |> render_change()

    refute html =~ "must be a valid git URL"
  end

  test "accepts local path git URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    html =
      view
      |> form("form",
        project: %{name: "Local Project", git_url: "/tmp/test-repo"}
      )
      |> render_change()

    refute html =~ "must be a valid git URL"
  end

  test "handles detect_path event with empty URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    # Simulate blur on empty git URL field
    html =
      view
      |> form("form", project: %{name: "Test", git_url: ""})
      |> render_change()

    # Should not crash and should still show the form
    assert html =~ "New Project"
  end

  test "shows error for duplicate git URL", %{conn: conn} do
    url = unique_git_url("dup")

    # Create first project
    {:ok, view1, _} = live(conn, ~p"/projects/new")

    view1
    |> form("form", project: %{name: "First", git_url: url})
    |> render_submit()

    assert_redirect(view1)

    # Try to create second with same URL
    {:ok, view2, _} = live(conn, ~p"/projects/new")

    html =
      view2
      |> form("form", project: %{name: "Second", git_url: url})
      |> render_submit()

    assert html =~ "has already been taken"
  end
end
