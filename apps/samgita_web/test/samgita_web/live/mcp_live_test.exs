defmodule SamgitaWeb.McpLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders MCP page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/mcp")
    assert html =~ "MCP Server Management"
    assert html =~ "MCP Configuration"
  end

  test "shows MCP server entries from config", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/mcp")

    # The page reads from ~/.claude.json or ~/.claude/mcp.json.
    # If servers exist, their names appear; otherwise the empty state shows.
    config_path = Path.expand("~/.claude.json")

    has_servers =
      with {:ok, content} <- File.read(config_path),
           {:ok, decoded} <- Jason.decode(content),
           servers when is_map(servers) and servers != %{} <- Map.get(decoded, "mcpServers") do
        true
      else
        _ -> false
      end

    if has_servers do
      refute html =~ "No MCP servers configured"
    else
      assert html =~ "No MCP servers configured"
    end
  end

  test "refresh event reloads servers without error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/mcp")
    html = render_click(view, "refresh")
    assert html =~ "MCP Server Management"
  end
end
