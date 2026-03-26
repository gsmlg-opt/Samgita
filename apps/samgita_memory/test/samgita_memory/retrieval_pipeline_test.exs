defmodule SamgitaMemory.Retrieval.PipelineTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Memories
  alias SamgitaMemory.Retrieval.Pipeline

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

  describe "stage 1b: type filter (prd-013)" do
    test "filters by episodic type only" do
      {:ok, ep} = Memories.store("episodic memory", type: :episodic, scope: {:global, nil})
      {:ok, _sem} = Memories.store("semantic memory", type: :semantic, scope: {:global, nil})
      {:ok, _proc} = Memories.store("procedural memory", type: :procedural, scope: {:global, nil})

      results = Pipeline.execute(nil, type: :episodic)
      assert Enum.all?(results, &(&1.memory_type == :episodic))
      assert Enum.any?(results, &(&1.id == ep.id))
    end

    test "filters by semantic type only" do
      {:ok, _ep} = Memories.store("episodic memory", type: :episodic, scope: {:global, nil})
      {:ok, sem} = Memories.store("semantic pattern", type: :semantic, scope: {:global, nil})

      results = Pipeline.execute(nil, type: :semantic)
      assert Enum.all?(results, &(&1.memory_type == :semantic))
      assert Enum.any?(results, &(&1.id == sem.id))
    end

    test "filters by procedural type only" do
      {:ok, _ep} = Memories.store("episodic fact", type: :episodic, scope: {:global, nil})
      {:ok, proc} = Memories.store("deploy procedure", type: :procedural, scope: {:global, nil})

      results = Pipeline.execute(nil, type: :procedural)
      assert Enum.all?(results, &(&1.memory_type == :procedural))
      assert Enum.any?(results, &(&1.id == proc.id))
    end

    test "type filter is independent of scope filter" do
      scope = {:project, "proj-type-test"}
      {:ok, ep} = Memories.store("episodic in scope", type: :episodic, scope: scope)
      {:ok, _sem} = Memories.store("semantic in scope", type: :semantic, scope: scope)

      results = Pipeline.execute(nil, type: :episodic, scope: scope)
      assert length(results) == 1
      assert hd(results).id == ep.id
    end
  end

  describe "stage 6: cosine similarity deduplication (prd-013)" do
    test "deduplicates memories with near-identical embeddings" do
      scope = {:project, "cosine-dedup-#{System.unique_integer([:positive])}"}

      # Create two memories with nearly identical embeddings (cosine > 0.95)
      base_vec = List.duplicate(0.1, 1536)
      # Same vector = cosine similarity 1.0
      embedding = Pgvector.new(base_vec)

      {:ok, m1} =
        Memories.store("memory A about elixir",
          scope: scope,
          confidence: 0.9
        )

      {:ok, m2} =
        Memories.store("memory B about erlang",
          scope: scope,
          confidence: 0.8
        )

      # Manually set identical embeddings to trigger cosine dedup
      import Ecto.Query

      SamgitaMemory.Repo.update_all(
        from(m in SamgitaMemory.Memories.Memory,
          where: m.id in ^[m1.id, m2.id]
        ),
        set: [embedding: embedding]
      )

      results = Pipeline.execute(nil, scope: scope)
      # Only one should survive dedup since embeddings are identical
      assert length(results) == 1
    end

    test "keeps memories with different embeddings" do
      scope = {:project, "cosine-keep-#{System.unique_integer([:positive])}"}

      {:ok, _m1} =
        Memories.store("completely different content A",
          scope: scope,
          confidence: 0.9
        )

      {:ok, _m2} =
        Memories.store("completely different content B",
          scope: scope,
          confidence: 0.8
        )

      results = Pipeline.execute(nil, scope: scope)
      # Without embeddings, text-based dedup shouldn't match these
      assert length(results) == 2
    end
  end

  describe "stage 4: recency boost ordering (prd-013)" do
    test "higher confidence memories are returned first when no embedding" do
      scope = {:project, "recency-test-#{System.unique_integer([:positive])}"}

      {:ok, low} = Memories.store("low confidence memory", confidence: 0.4, scope: scope)
      {:ok, high} = Memories.store("high confidence memory", confidence: 0.9, scope: scope)

      results = Pipeline.execute(nil, scope: scope)
      assert length(results) == 2

      # High confidence should score higher in stage 4 (confidence * 0.7 + recency * 0.2 + access * 0.1)
      assert hd(results).id == high.id
      assert List.last(results).id == low.id
    end
  end

  describe "all 7 pipeline stages active (prd-013)" do
    test "pipeline applies all stages: scope, type, tag, semantic, recency, confidence, dedup" do
      scope = {:project, "all-stages-#{System.unique_integer([:positive])}"}

      # Stage 1: scope filter — only proj-in-scope visible
      {:ok, _other} =
        Memories.store("other project memory",
          scope: {:project, "other-proj"},
          type: :episodic,
          tags: ["elixir"],
          confidence: 0.9
        )

      # Stage 1b: type filter — only episodic
      {:ok, _sem} =
        Memories.store("semantic in scope", type: :semantic, scope: scope, confidence: 0.9)

      # Stage 2: tag filter — only tagged with elixir
      {:ok, _notag} =
        Memories.store("no elixir tag", type: :episodic, scope: scope, tags: ["python"])

      # Stage 5: confidence filter — above min_confidence
      {:ok, _low} =
        Memories.store("low confidence",
          type: :episodic,
          scope: scope,
          tags: ["elixir"],
          confidence: 0.1
        )

      # Stage 6: dedup — two identical content entries = one result
      {:ok, _dup1} =
        Memories.store("unique finding",
          type: :episodic,
          scope: scope,
          tags: ["elixir"],
          confidence: 0.9
        )

      {:ok, _dup2} =
        Memories.store("unique finding",
          type: :episodic,
          scope: scope,
          tags: ["elixir"],
          confidence: 0.8
        )

      results =
        Pipeline.execute(nil,
          scope: scope,
          type: :episodic,
          tags: ["elixir"],
          min_confidence: 0.3
        )

      # Only the deduplicated "unique finding" should survive all stages
      assert length(results) == 1
      assert hd(results).content == "unique finding"
    end
  end
end
