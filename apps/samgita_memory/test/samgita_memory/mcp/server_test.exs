defmodule SamgitaMemory.MCP.ServerTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.MCP.Server

  # Ensure atoms used by Tools.dispatch exist before JSON-decoded strings
  # are passed to String.to_existing_atom/1
  @memory_types [:episodic, :semantic, :procedural]
  @scope_types [:global, :project, :agent]
  @source_types [:conversation, :observation, :user_edit]

  # Suppress unused warnings
  def _atoms, do: {@memory_types, @scope_types, @source_types}

  describe "initialize" do
    test "returns server info and capabilities" do
      request = Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "initialize", params: %{}})
      response = Server.handle_message(request)
      decoded = Jason.decode!(response)

      assert decoded["id"] == 1
      assert decoded["jsonrpc"] == "2.0"

      result = decoded["result"]
      assert result["protocolVersion"] == "2024-11-05"
      assert result["serverInfo"]["name"] == "samgita-memory"
      assert result["serverInfo"]["version"] == "0.1.0"
      assert result["capabilities"]["tools"] == %{}
    end

    test "notifications/initialized returns nil (no response)" do
      request =
        Jason.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"})

      assert Server.handle_message(request) == nil
    end
  end

  describe "tools/list" do
    test "returns all 10 tools" do
      request = Jason.encode!(%{jsonrpc: "2.0", id: 2, method: "tools/list", params: %{}})
      response = Server.handle_message(request)
      decoded = Jason.decode!(response)

      tools = decoded["result"]["tools"]
      assert length(tools) == 10

      names = Enum.map(tools, & &1["name"])
      assert "recall" in names
      assert "remember" in names
      assert "forget" in names
      assert "prd_context" in names
      assert "prd_event" in names
      assert "prd_decision" in names
      assert "think" in names
      assert "start_thinking" in names
      assert "finish_thinking" in names
      assert "recall_reasoning" in names

      # Each tool has required fields
      for tool <- tools do
        assert is_binary(tool["name"])
        assert is_binary(tool["description"])
        assert is_map(tool["inputSchema"])
      end
    end
  end

  describe "tools/call" do
    test "recall tool returns memories" do
      # First store a memory
      remember_request =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: %{
            name: "remember",
            arguments: %{
              content: "MCP server test memory",
              scope_type: "global",
              memory_type: "semantic",
              tags: ["mcp", "test"]
            }
          }
        })

      remember_response = Server.handle_message(remember_request)
      remember_decoded = Jason.decode!(remember_response)
      assert remember_decoded["result"]["content"]

      [%{"text" => text}] = remember_decoded["result"]["content"]
      stored = Jason.decode!(text)
      assert stored["status"] == "stored"
      assert is_binary(stored["id"])

      # Now recall it
      recall_request =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 4,
          method: "tools/call",
          params: %{
            name: "recall",
            arguments: %{
              query: "MCP server test",
              scope_type: "global",
              tags: ["mcp"]
            }
          }
        })

      recall_response = Server.handle_message(recall_request)
      recall_decoded = Jason.decode!(recall_response)

      [%{"type" => "text", "text" => recall_text}] = recall_decoded["result"]["content"]
      recall_data = Jason.decode!(recall_text)

      assert recall_data["total"] >= 1

      contents = Enum.map(recall_data["memories"], & &1["content"])
      assert "MCP server test memory" in contents
    end

    test "tool error is returned with isError flag" do
      request =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: 5,
          method: "tools/call",
          params: %{
            name: "forget",
            arguments: %{memory_id: Ecto.UUID.generate()}
          }
        })

      response = Server.handle_message(request)
      decoded = Jason.decode!(response)

      assert decoded["result"]["isError"] == true
    end
  end

  describe "ping" do
    test "returns empty result" do
      request = Jason.encode!(%{jsonrpc: "2.0", id: 6, method: "ping", params: %{}})
      response = Server.handle_message(request)
      decoded = Jason.decode!(response)

      assert decoded["id"] == 6
      assert decoded["result"] == %{}
    end
  end

  describe "error handling" do
    test "unknown method returns method not found error" do
      request =
        Jason.encode!(%{jsonrpc: "2.0", id: 7, method: "unknown/method", params: %{}})

      response = Server.handle_message(request)
      decoded = Jason.decode!(response)

      assert decoded["error"]["code"] == -32_601
      assert decoded["error"]["message"] =~ "Method not found"
    end

    test "invalid JSON returns parse error" do
      response = Server.handle_message("not valid json{{{")
      decoded = Jason.decode!(response)

      assert decoded["error"]["code"] == -32_700
      assert decoded["error"]["message"] =~ "Parse error"
    end
  end
end
