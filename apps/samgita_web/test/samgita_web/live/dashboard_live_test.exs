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
    assert has_element?(view, "a[href='/projects']", "Manage Projects")
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
    assert html =~ "theme-toggle"
    assert html =~ "/images/favicon-32.png"
    refute html =~ "heavy-elements.js"

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
