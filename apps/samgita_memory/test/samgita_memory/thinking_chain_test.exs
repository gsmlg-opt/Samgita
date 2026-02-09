defmodule SamgitaMemory.Memories.ThinkingChainTest do
  use SamgitaMemory.DataCase, async: true

  alias SamgitaMemory.Memories.ThinkingChain

  describe "start/2" do
    test "creates a new chain" do
      assert {:ok, chain} = ThinkingChain.start("How to implement auth?")
      assert chain.query == "How to implement auth?"
      assert chain.status == :active
      assert chain.scope_type == :global
      assert chain.thoughts == []
    end

    test "creates chain with scope" do
      assert {:ok, chain} =
               ThinkingChain.start("Design database schema",
                 scope_type: :project,
                 scope_id: "proj-1"
               )

      assert chain.scope_type == :project
      assert chain.scope_id == "proj-1"
    end
  end

  describe "add_thought/2" do
    setup do
      {:ok, chain} = ThinkingChain.start("Test query")
      %{chain: chain}
    end

    test "adds thought with auto-numbering", %{chain: chain} do
      {:ok, updated} =
        ThinkingChain.add_thought(chain.id, %{
          content: "First thought",
          is_revision: false
        })

      assert length(updated.thoughts) == 1
      thought = hd(updated.thoughts)
      # After Ecto JSON roundtrip, keys may be atoms or strings
      assert thought[:number] || thought["number"] == 1
      assert thought[:content] || thought["content"] == "First thought"
    end

    test "appends multiple thoughts in order", %{chain: chain} do
      {:ok, _} = ThinkingChain.add_thought(chain.id, %{content: "First"})
      {:ok, updated} = ThinkingChain.add_thought(chain.id, %{content: "Second"})

      assert length(updated.thoughts) == 2
      t1 = Enum.at(updated.thoughts, 0)
      t2 = Enum.at(updated.thoughts, 1)
      assert (t1[:number] || t1["number"]) == 1
      assert (t2[:number] || t2["number"]) == 2
    end

    test "returns error for non-existent chain" do
      assert {:error, :not_found} =
               ThinkingChain.add_thought(Ecto.UUID.generate(), %{content: "test"})
    end
  end

  describe "complete/1" do
    test "marks chain as completed" do
      {:ok, chain} = ThinkingChain.start("Complete me")
      {:ok, _} = ThinkingChain.add_thought(chain.id, %{content: "Done"})
      {:ok, completed} = ThinkingChain.complete(chain.id)
      assert completed.status == :completed
    end

    test "returns error for non-existent chain" do
      assert {:error, :not_found} = ThinkingChain.complete(Ecto.UUID.generate())
    end
  end

  describe "recall/2" do
    setup do
      {:ok, c1} =
        ThinkingChain.start("How to auth?", scope_type: :project, scope_id: "proj-1")

      {:ok, _} = ThinkingChain.add_thought(c1.id, %{content: "Use JWT"})
      {:ok, _} = ThinkingChain.complete(c1.id)

      {:ok, c2} =
        ThinkingChain.start("Database design", scope_type: :project, scope_id: "proj-1")

      {:ok, _} = ThinkingChain.add_thought(c2.id, %{content: "Normalize tables"})
      {:ok, _} = ThinkingChain.complete(c2.id)

      {:ok, c3} =
        ThinkingChain.start("Global thought", scope_type: :global)

      {:ok, _} = ThinkingChain.complete(c3.id)

      # Active chain — should NOT appear in recall
      {:ok, _active} =
        ThinkingChain.start("Still thinking", scope_type: :project, scope_id: "proj-1")

      %{c1: c1, c2: c2, c3: c3}
    end

    test "returns only completed chains" do
      results = ThinkingChain.recall("anything")
      assert Enum.all?(results, &(&1.status == :completed))
    end

    test "filters by scope" do
      results =
        ThinkingChain.recall("anything", scope_type: :project, scope_id: "proj-1")

      assert length(results) == 2
    end

    test "respects limit" do
      results = ThinkingChain.recall("anything", limit: 1)
      assert length(results) == 1
    end
  end
end
