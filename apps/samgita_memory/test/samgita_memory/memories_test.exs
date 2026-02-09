defmodule SamgitaMemory.MemoriesTest do
  use SamgitaMemory.DataCase, async: true

  alias SamgitaMemory.Memories
  alias SamgitaMemory.Memories.Memory

  describe "store/2" do
    test "creates a memory with required fields" do
      assert {:ok, memory} =
               Memories.store("Test fact",
                 source: {:observation, "test-1"},
                 scope: {:project, "proj-1"},
                 type: :episodic
               )

      assert memory.content == "Test fact"
      assert memory.source_type == :observation
      assert memory.source_id == "test-1"
      assert memory.scope_type == :project
      assert memory.scope_id == "proj-1"
      assert memory.memory_type == :episodic
      assert memory.confidence == 1.0
      assert memory.access_count == 0
    end

    test "creates memory with defaults" do
      assert {:ok, memory} = Memories.store("Default fact")
      assert memory.source_type == :observation
      assert memory.scope_type == :global
      assert memory.memory_type == :episodic
      assert memory.confidence == 1.0
      assert memory.tags == []
      assert memory.metadata == %{}
    end

    test "creates memory with tags and metadata" do
      assert {:ok, memory} =
               Memories.store("Tagged fact",
                 tags: ["elixir", "debugging"],
                 metadata: %{"key" => "value"},
                 type: :procedural
               )

      assert memory.tags == ["elixir", "debugging"]
      assert memory.metadata == %{"key" => "value"}
      assert memory.memory_type == :procedural
    end

    test "rejects empty content" do
      assert {:error, changeset} = Memories.store("")
      assert %{content: _} = errors_on(changeset)
    end
  end

  describe "retrieve/2" do
    setup do
      {:ok, m1} =
        Memories.store("Elixir fact", scope: {:project, "proj-1"}, tags: ["elixir"])

      {:ok, m2} =
        Memories.store("Python fact", scope: {:project, "proj-2"}, tags: ["python"])

      {:ok, m3} =
        Memories.store("General fact",
          scope: {:project, "proj-1"},
          tags: ["elixir", "otp"],
          type: :semantic
        )

      {:ok, m4} =
        Memories.store("Low confidence",
          scope: {:project, "proj-1"},
          confidence: 0.1
        )

      %{m1: m1, m2: m2, m3: m3, m4: m4}
    end

    test "filters by scope", %{m1: m1, m3: m3} do
      results = Memories.retrieve("anything", scope: {:project, "proj-1"})
      ids = Enum.map(results, & &1.id)
      assert m1.id in ids
      assert m3.id in ids
      assert length(results) == 2
    end

    test "filters by memory type", %{m3: m3} do
      results = Memories.retrieve("anything", scope: {:project, "proj-1"}, type: :semantic)
      assert length(results) == 1
      assert hd(results).id == m3.id
    end

    test "filters by tags", %{m3: m3} do
      results =
        Memories.retrieve("anything",
          scope: {:project, "proj-1"},
          tags: ["otp"]
        )

      assert length(results) == 1
      assert hd(results).id == m3.id
    end

    test "respects confidence threshold", %{m4: _m4} do
      # Default min_confidence is 0.3, so m4 (0.1) should be excluded
      results = Memories.retrieve("anything", scope: {:project, "proj-1"})
      confidences = Enum.map(results, & &1.confidence)
      assert Enum.all?(confidences, &(&1 >= 0.3))
    end

    test "respects limit" do
      results = Memories.retrieve("anything", limit: 1)
      assert length(results) <= 1
    end

    test "scope isolation — project A cannot see project B memories", %{m2: m2} do
      results = Memories.retrieve("anything", scope: {:project, "proj-1"})
      ids = Enum.map(results, & &1.id)
      refute m2.id in ids
    end
  end

  describe "forget/1" do
    test "deletes an existing memory" do
      {:ok, memory} = Memories.store("To forget")
      assert :ok = Memories.forget(memory.id)
      assert Memories.get(memory.id) == nil
    end

    test "returns error for non-existent memory" do
      assert {:error, :not_found} = Memories.forget(Ecto.UUID.generate())
    end
  end

  describe "reinforce/2" do
    test "updates confidence" do
      {:ok, memory} = Memories.store("To reinforce")
      assert {:ok, updated} = Memories.reinforce(memory.id, confidence: 0.9)
      assert updated.confidence == 0.9
    end

    test "merges metadata" do
      {:ok, memory} = Memories.store("With meta", metadata: %{"a" => 1})
      assert {:ok, updated} = Memories.reinforce(memory.id, metadata: %{"b" => 2})
      assert updated.metadata == %{"a" => 1, "b" => 2}
    end

    test "returns error for non-existent memory" do
      assert {:error, :not_found} = Memories.reinforce(Ecto.UUID.generate(), confidence: 0.5)
    end
  end

  describe "get/1" do
    test "returns memory by id" do
      {:ok, memory} = Memories.store("Findable")
      assert found = Memories.get(memory.id)
      assert found.id == memory.id
    end

    test "returns nil for non-existent id" do
      assert Memories.get(Ecto.UUID.generate()) == nil
    end
  end
end
