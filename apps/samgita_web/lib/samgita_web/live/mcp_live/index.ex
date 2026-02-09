defmodule SamgitaWeb.McpLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "MCP Servers",
       servers: list_mcp_servers()
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, servers: list_mcp_servers())}
  end

  defp list_mcp_servers do
    # TODO: Implement actual MCP server listing
    # This should read from ~/.claude/mcp.json or similar
    [
      %{
        name: "dart",
        description: "Dart and Flutter development tools",
        status: :connected,
        capabilities: ["tools", "resources"]
      },
      %{
        name: "github",
        description: "GitHub API integration",
        status: :connected,
        capabilities: ["tools"]
      },
      %{
        name: "chrome-devtools",
        description: "Browser automation and testing",
        status: :disconnected,
        capabilities: ["tools"]
      }
    ]
  end

  def status_color(:connected), do: "bg-green-100 text-green-800"
  def status_color(:disconnected), do: "bg-zinc-100 text-zinc-600"
  def status_color(:error), do: "bg-red-100 text-red-800"
end
