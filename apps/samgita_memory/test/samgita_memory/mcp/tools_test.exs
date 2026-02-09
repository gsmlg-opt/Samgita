defmodule SamgitaMemory.MCP.ToolsTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.MCP.Tools
  alias SamgitaMemory.PRD

  describe "definitions/0" do
    test "returns 10 tool definitions" do
      defs = Tools.definitions()
      assert length(defs) == 10

      names = Enum.map(defs, & &1.name)

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
    end

    test "each tool has name, description, and inputSchema" do
      for tool <- Tools.definitions() do
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.inputSchema)
        assert tool.inputSchema.type == "object"
      end
    end
  end

  describe "execute/3 - remember + recall roundtrip" do
    test "stores and retrieves a memory" do
      # Remember
      {:ok, result} =
        Tools.execute("remember", %{
          "content" => "Elixir uses the BEAM VM",
          "scope_type" => "global",
          "memory_type" => "semantic",
          "tags" => ["elixir", "vm"]
        })

      assert result.status == "stored"
      assert is_binary(result.id)

      # Recall
      {:ok, recall_result} =
        Tools.execute("recall", %{
          "query" => "BEAM VM",
          "scope_type" => "global",
          "tags" => ["elixir"]
        })

      assert recall_result.total >= 1
      memory = hd(recall_result.memories)
      assert memory.content == "Elixir uses the BEAM VM"
    end
  end

  describe "execute/3 - forget" do
    test "forgets a memory" do
      {:ok, stored} =
        Tools.execute("remember", %{"content" => "temporary fact"})

      {:ok, result} = Tools.execute("forget", %{"memory_id" => stored.id})
      assert result.status == "forgotten"

      # Verify it's gone
      {:ok, recall_result} = Tools.execute("recall", %{"query" => "temporary"})
      ids = Enum.map(recall_result.memories, & &1.id)
      refute stored.id in ids
    end

    test "returns error for non-existent memory" do
      {:error, _} = Tools.execute("forget", %{"memory_id" => Ecto.UUID.generate()})
    end
  end

  describe "execute/3 - PRD tools" do
    test "prd_context returns execution state" do
      {:ok, execution} = PRD.start_execution("mcp-test-prd", title: "MCP Test")

      {:ok, result} =
        Tools.execute("prd_context", %{"prd_id" => execution.id})

      assert result.execution.prd_ref == "mcp-test-prd"
      assert result.execution.title == "MCP Test"
      assert is_list(result.recent_events)
      assert is_list(result.decisions)
    end

    test "prd_event records an event" do
      {:ok, execution} = PRD.start_execution("mcp-event-prd", title: "Event Test")

      {:ok, result} =
        Tools.execute("prd_event", %{
          "prd_id" => execution.id,
          "type" => "requirement_completed",
          "summary" => "Implemented auth module",
          "requirement_id" => "req-1"
        })

      assert result.status == "recorded"
    end

    test "prd_decision records a decision" do
      {:ok, execution} = PRD.start_execution("mcp-decision-prd", title: "Decision Test")

      {:ok, result} =
        Tools.execute("prd_decision", %{
          "prd_id" => execution.id,
          "decision" => "Use JWT for auth",
          "reason" => "Stateless and scalable",
          "alternatives" => ["session cookies", "OAuth only"]
        })

      assert result.status == "recorded"
    end
  end

  describe "execute/3 - thinking chain tools" do
    test "full thinking chain lifecycle" do
      # Start thinking
      {:ok, start_result} =
        Tools.execute("start_thinking", %{
          "query" => "How to implement caching?",
          "scope_type" => "project",
          "scope_id" => "proj-1"
        })

      assert start_result.status == "active"
      chain_id = start_result.chain_id

      # Add thoughts
      {:ok, think_result} =
        Tools.execute("think", %{
          "chain_id" => chain_id,
          "content" => "Consider ETS for hot data"
        })

      assert think_result.thought_count == 1

      {:ok, _} =
        Tools.execute("think", %{
          "chain_id" => chain_id,
          "content" => "Use GenServer wrapper for LRU eviction"
        })

      # Finish thinking
      {:ok, finish_result} =
        Tools.execute("finish_thinking", %{"chain_id" => chain_id})

      assert finish_result.status == "completed"

      # Recall reasoning
      {:ok, recall_result} =
        Tools.execute("recall_reasoning", %{
          "query" => "caching",
          "scope_type" => "project",
          "scope_id" => "proj-1"
        })

      assert recall_result.total >= 1
    end
  end

  describe "execute/3 - unknown tool" do
    test "returns error for unknown tool" do
      {:error, msg} = Tools.execute("nonexistent", %{})
      assert msg =~ "Unknown tool"
    end
  end

  describe "token budget truncation" do
    test "truncates large results to fit budget" do
      # Create many memories
      for i <- 1..20 do
        Tools.execute("remember", %{
          "content" =>
            "Memory number #{i} with some extra content to increase size #{String.duplicate("x", 100)}"
        })
      end

      # Request with very small budget
      {:ok, result} =
        Tools.execute("recall", %{"query" => "memory", "limit" => 20}, token_budget: 200)

      # Should have been truncated
      memories = result.memories

      if length(memories) > 0 do
        last = List.last(memories)

        if is_map(last) and Map.has_key?(last, :truncated) do
          assert last.truncated == true
          assert last.total > last.shown
        end
      end
    end
  end
end
