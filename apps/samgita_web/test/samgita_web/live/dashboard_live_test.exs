defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "renders the empty Agent Hub with no unavailable actions", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "h1", "Agent Hub")
    assert has_element?(view, "#hub-empty-state", "No projects yet")
    assert html =~ "external agents"
    refute has_element?(view, "a[href='/projects/new']")
    refute html =~ "Codex"
    refute html =~ "Command Center"
  end

  test "browser shell exposes only available navigation", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "csrf-token"
    assert html =~ "theme-toggle"
    assert html =~ "/images/favicon-32.png"
    refute html =~ "heavy-elements.js"

    for path <- ["/agents", "/mcp", "/skills", "/references"] do
      refute html =~ "href=\"#{path}\""
    end
  end
end
