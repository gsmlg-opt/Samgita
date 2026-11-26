defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  alias Samgita.Domain.{Agent, Project}
  alias Samgita.Repo

  test "renders persisted counts, conditional empty state and management navigation", %{
    conn: conn
  } do
    agents = Repo.aggregate(Agent, :count)
    projects = Repo.aggregate(Project, :count)
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "h1", "Agent Hub")
    assert has_element?(view, "#hub-empty-state", "No projects yet") == (projects == 0)
    assert html =~ "external agents"
    refute has_element?(view, "a[href='/projects/new']")
    refute html =~ "Codex"
    refute html =~ "Command Center"
    assert count_text(view, "#hub-agents") == to_string(agents)
    assert count_text(view, "#hub-projects") == to_string(projects)
    assert has_element?(view, "a[href='/agents']", "Manage Agents")
    assert has_element?(view, "a[href='/hub/projects']", "Manage Projects")
  end

  test "dashboard links open platform projects and their tasks", %{conn: conn} do
    project = project_fixture()

    {:ok, task} =
      Samgita.Tasks.create(
        Samgita.Principal.operator(),
        project["id"],
        command(%{"title" => "Review task"})
      )

    {:ok, dashboard, _} = live(conn, ~p"/")

    {:ok, index, _} =
      dashboard |> element("#hub-tasks a") |> render_click() |> follow_redirect(conn)

    {:ok, detail, _} =
      index |> element("#project-#{project["id"]} a") |> render_click() |> follow_redirect(conn)

    {:ok, task_page, _} =
      detail
      |> element("a[href='/projects/#{project["id"]}/tasks/#{task["id"]}']")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(task_page, "h1", "Review task")
  end

  test "create a platform project from the dashboard", %{conn: conn} do
    {:ok, dashboard, _} = live(conn, ~p"/")

    {:ok, index, _} =
      dashboard |> element("#hub-projects a") |> render_click() |> follow_redirect(conn)

    {:ok, detail, _} =
      index
      |> form("#project-form", project: %{name: "Release review"})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(detail, "h1", "Release review")
    assert has_element?(detail, "a[href='/hub/projects']", "All projects")
  end

  test "counts and links survive a fresh LiveView connection", %{conn: conn} do
    agents = Repo.aggregate(Agent, :count)
    projects = Repo.aggregate(Project, :count)
    agent_fixture()
    project_fixture()

    for _ <- 1..2 do
      {:ok, view, _} = live(conn, ~p"/")
      assert count_text(view, "#hub-agents") == to_string(agents + 1)
      assert count_text(view, "#hub-projects") == to_string(projects + 1)
      refute has_element?(view, "#hub-empty-state")
      assert has_element?(view, "#hub-authority", "Execution admissions")
    end
  end

  test "browser shell exposes only available navigation", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "csrf-token"
    # The theme switcher lives in Settings > Appearance, not in the shell.
    refute html =~ "theme-toggle"
    assert html =~ "/images/favicon-32.png"
    refute html =~ "heavy-elements.js"

    assert html =~ "href=\"/settings\""
    assert html =~ "href=\"/agents\""
    assert html =~ "href=\"/projects\""

    for path <- ["/mcp", "/skills", "/references"] do
      refute html =~ "href=\"#{path}\""
    end
  end

  defp count_text(view, selector) do
    view
    |> element(selector <> " p")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end
end
