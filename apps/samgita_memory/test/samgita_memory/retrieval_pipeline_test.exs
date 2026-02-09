defmodule SamgitaMemory.Retrieval.PipelineTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Retrieval.Pipeline
  alias SamgitaMemory.Memories

  describe "execute/2" do
    test "returns memories filtered by scope" do
      {:ok, m1} =
        Memories.store("project A memory",
          scope: {:project, "proj-a"},
          type: :episodic
        )

      {:ok, _m2} =
        Memories.store("project B memory",
          scope: {:project, "proj-b"},
          type: :episodic
        )

      results = Pipeline.execute(nil, scope: {:project, "proj-a"})
      assert length(results) == 1
      assert hd(results).id == m1.id
    end

    test "returns memories filtered by tags" do
      {:ok, m1} =
        Memories.store("tagged memory",
          scope: {:global, nil},
          tags: ["elixir", "otp"]
        )

      {:ok, _m2} =
        Memories.store("untagged memory",
          scope: {:global, nil},
          tags: ["python"]
        )

      results = Pipeline.execute(nil, tags: ["elixir"])
      assert length(results) == 1
      assert hd(results).id == m1.id
    end

    test "respects confidence threshold" do
      {:ok, _low} =
        Memories.store("low confidence",
          scope: {:global, nil},
          confidence: 0.1
        )

      {:ok, high} =
        Memories.store("high confidence",
          scope: {:global, nil},
          confidence: 0.9
        )

      results = Pipeline.execute(nil, min_confidence: 0.5)
      assert length(results) == 1
      assert hd(results).id == high.id
    end

    test "respects limit" do
      for i <- 1..5 do
        Memories.store("memory #{i}", scope: {:global, nil})
      end

      results = Pipeline.execute(nil, limit: 3)
      assert length(results) == 3
    end

    test "deduplicates identical content" do
      {:ok, _m1} =
        Memories.store("duplicate content",
          scope: {:global, nil},
          confidence: 0.9
        )

      {:ok, _m2} =
        Memories.store("duplicate content",
          scope: {:global, nil},
          confidence: 0.8
        )

      results = Pipeline.execute(nil, scope: {:global, nil})
      assert length(results) == 1
    end

    test "deduplication is case-insensitive" do
      {:ok, _m1} =
        Memories.store("Duplicate Content",
          scope: {:global, nil},
          confidence: 0.9
        )

      {:ok, _m2} =
        Memories.store("duplicate content",
          scope: {:global, nil},
          confidence: 0.8
        )

      results = Pipeline.execute(nil, scope: {:global, nil})
      assert length(results) == 1
    end

    test "returns empty list when no matches" do
      results = Pipeline.execute(nil, scope: {:project, "nonexistent"})
      assert results == []
    end

    test "combines scope and tag filters" do
      {:ok, m1} =
        Memories.store("elixir in proj-a",
          scope: {:project, "proj-a"},
          tags: ["elixir"]
        )

      {:ok, _m2} =
        Memories.store("python in proj-a",
          scope: {:project, "proj-a"},
          tags: ["python"]
        )

      {:ok, _m3} =
        Memories.store("elixir in proj-b",
          scope: {:project, "proj-b"},
          tags: ["elixir"]
        )

      results = Pipeline.execute(nil, scope: {:project, "proj-a"}, tags: ["elixir"])
      assert length(results) == 1
      assert hd(results).id == m1.id
    end
  end
end
