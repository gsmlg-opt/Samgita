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
    ["~/.claude/mcp.json", "~/.claude.json"]
    |> Enum.map(&Path.expand/1)
    |> Enum.find_value([], fn path ->
      with {:ok, content} <- File.read(path),
           {:ok, decoded} <- Jason.decode(content),
           servers when is_map(servers) <- Map.get(decoded, "mcpServers") do
        Enum.map(servers, fn {name, config} ->
          %{
            name: name,
            description: Map.get(config, "description", "MCP server: #{name}"),
            status: :connected,
            capabilities: Map.get(config, "capabilities", ["tools"])
          }
        end)
      else
        _ -> nil
      end
    end)
  end

  def status_badge_color(:connected), do: "success"
  def status_badge_color(:disconnected), do: ""
  def status_badge_color(:error), do: "error"
end
