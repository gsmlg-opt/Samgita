defmodule SamgitaWeb.McpLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders MCP page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/mcp")
    assert html =~ "MCP Server Management"
    assert html =~ "Model Context Protocol"
  end

  test "shows MCP server entries", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/mcp")
    assert html =~ "dart"
    assert html =~ "github"
  end

  test "refresh event reloads servers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/mcp")
    html = render_click(view, "refresh")
    assert html =~ "dart"
  end
end
