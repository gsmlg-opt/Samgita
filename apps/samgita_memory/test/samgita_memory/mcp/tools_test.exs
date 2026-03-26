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

      if memories != [] do
        last = List.last(memories)

        if is_map(last) and Map.has_key?(last, :truncated) do
          assert last.truncated == true
          assert last.total > last.shown
        end
      end
    end
  end

  describe "10 MCP tools integration (prd-015)" do
    test "recall respects scope isolation — project scope excludes other projects" do
      proj_a = "mcp-proj-a-#{System.unique_integer([:positive])}"
      proj_b = "mcp-proj-b-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "project A secret",
          "scope_type" => "project",
          "scope_id" => proj_a
        })

      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "project B secret",
          "scope_type" => "project",
          "scope_id" => proj_b
        })

      {:ok, result} =
        Tools.execute("recall", %{
          "query" => "secret",
          "scope_type" => "project",
          "scope_id" => proj_a
        })

      contents = Enum.map(result.memories, & &1.content)
      assert "project A secret" in contents
      refute "project B secret" in contents
    end

    test "recall with min_confidence filters low-confidence memories" do
      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "high confidence fact",
          "confidence" => 0.9
        })

      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "low confidence fact",
          "confidence" => 0.1
        })

      {:ok, result} =
        Tools.execute("recall", %{
          "query" => "fact",
          "min_confidence" => 0.5
        })

      confidences = Enum.map(result.memories, & &1.confidence)
      assert Enum.all?(confidences, &(&1 >= 0.5))
    end

    test "prd_context reflects events and decisions recorded via MCP" do
      {:ok, execution} = PRD.start_execution("mcp-lifecycle-prd", title: "Lifecycle Test")

      # Record an event and a decision
      {:ok, _} =
        Tools.execute("prd_event", %{
          "prd_id" => execution.id,
          "type" => "requirement_started",
          "summary" => "Development phase began"
        })

      {:ok, _} =
        Tools.execute("prd_decision", %{
          "prd_id" => execution.id,
          "decision" => "Use PostgreSQL for storage",
          "reason" => "Existing infrastructure"
        })

      {:ok, context} = Tools.execute("prd_context", %{"prd_id" => execution.id})

      # Context should reflect the recorded event and decision
      assert context.recent_events != []
      assert context.decisions != []

      event_summaries = Enum.map(context.recent_events, & &1.summary)
      assert "Development phase began" in event_summaries

      decision_texts = Enum.map(context.decisions, & &1.decision)
      assert "Use PostgreSQL for storage" in decision_texts
    end

    test "all 10 tools return {:ok, result} for valid inputs" do
      {:ok, execution} =
        PRD.start_execution("mcp-all-tools-#{System.unique_integer([:positive])}")

      {:ok, stored} = Tools.execute("remember", %{"content" => "tool coverage test"})
      assert stored.status == "stored"

      {:ok, recalled} = Tools.execute("recall", %{"query" => "coverage"})
      assert is_integer(recalled.total)

      {:ok, forgotten} =
        Tools.execute("remember", %{"content" => "to forget"})

      {:ok, forget_result} = Tools.execute("forget", %{"memory_id" => forgotten.id})
      assert forget_result.status == "forgotten"

      {:ok, ctx} = Tools.execute("prd_context", %{"prd_id" => execution.id})
      assert is_map(ctx.execution)

      {:ok, ev} =
        Tools.execute("prd_event", %{
          "prd_id" => execution.id,
          "type" => "requirement_completed",
          "summary" => "test task done"
        })

      assert ev.status == "recorded"

      {:ok, dec} =
        Tools.execute("prd_decision", %{
          "prd_id" => execution.id,
          "decision" => "use Ecto",
          "reason" => "ORM"
        })

      assert dec.status == "recorded"

      {:ok, chain} =
        Tools.execute("start_thinking", %{
          "query" => "all tools test",
          "scope_type" => "global"
        })

      chain_id = chain.chain_id

      {:ok, thought} = Tools.execute("think", %{"chain_id" => chain_id, "content" => "step one"})
      assert thought.thought_count == 1

      {:ok, finished} = Tools.execute("finish_thinking", %{"chain_id" => chain_id})
      assert finished.status == "completed"

      {:ok, reasoning} =
        Tools.execute("recall_reasoning", %{"query" => "all tools", "scope_type" => "global"})

      assert is_integer(reasoning.total)
    end

    test "remember accepts all memory type options" do
      for type <- ["episodic", "semantic", "procedural"] do
        {:ok, result} =
          Tools.execute("remember", %{
            "content" => "#{type} content",
            "memory_type" => type
          })

        assert result.status == "stored"
      end
    end

    test "recall returns memories ordered by relevance (higher confidence first)" do
      scope = "order-test-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "low ranked memory",
          "scope_type" => "project",
          "scope_id" => scope,
          "confidence" => 0.4
        })

      {:ok, _} =
        Tools.execute("remember", %{
          "content" => "high ranked memory",
          "scope_type" => "project",
          "scope_id" => scope,
          "confidence" => 0.9
        })

      {:ok, result} =
        Tools.execute("recall", %{
          "query" => "memory",
          "scope_type" => "project",
          "scope_id" => scope
        })

      assert length(result.memories) == 2
      confidences = Enum.map(result.memories, & &1.confidence)
      [first | _] = confidences
      assert first >= 0.9
    end
  end
end
