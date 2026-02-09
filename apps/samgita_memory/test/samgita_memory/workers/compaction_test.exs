defmodule SamgitaMemory.Workers.CompactionTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Workers.Compaction
  alias SamgitaMemory.Memories
  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory

  describe "run_decay/0" do
    test "decays episodic memories by 0.98" do
      {:ok, memory} =
        Memories.store("episodic memory",
          scope: {:global, nil},
          type: :episodic,
          confidence: 1.0
        )

      Compaction.run_decay()

      updated = Repo.get!(Memory, memory.id)
      assert_in_delta updated.confidence, 0.98, 0.001
    end

    test "decays semantic memories by 0.995" do
      {:ok, memory} =
        Memories.store("semantic memory",
          scope: {:global, nil},
          type: :semantic,
          confidence: 1.0
        )

      Compaction.run_decay()

      updated = Repo.get!(Memory, memory.id)
      assert_in_delta updated.confidence, 0.995, 0.001
    end

    test "decays procedural memories by 0.999" do
      {:ok, memory} =
        Memories.store("procedural memory",
          scope: {:global, nil},
          type: :procedural,
          confidence: 1.0
        )

      Compaction.run_decay()

      updated = Repo.get!(Memory, memory.id)
      assert_in_delta updated.confidence, 0.999, 0.001
    end

    test "does not decay memories below prune threshold" do
      {:ok, memory} =
        Memories.store("low confidence",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.05
        )

      Compaction.run_decay()

      # Should not be decayed (already below threshold)
      updated = Repo.get!(Memory, memory.id)
      assert_in_delta updated.confidence, 0.05, 0.001
    end
  end

  describe "run_prune/0" do
    test "removes memories below threshold" do
      {:ok, _low} =
        Memories.store("to prune",
          scope: {:global, nil},
          confidence: 0.05
        )

      {:ok, high} =
        Memories.store("to keep",
          scope: {:global, nil},
          confidence: 0.5
        )

      {:ok, count} = Compaction.run_prune()

      assert count == 1
      assert is_nil(Repo.get(Memory, _low.id))
      refute is_nil(Repo.get(Memory, high.id))
    end

    test "returns 0 when nothing to prune" do
      {:ok, _} =
        Memories.store("high confidence",
          scope: {:global, nil},
          confidence: 0.9
        )

      {:ok, count} = Compaction.run_prune()
      assert count == 0
    end
  end

  describe "perform/1" do
    test "performs decay and prune via Oban job" do
      {:ok, _} =
        Memories.store("will be decayed",
          scope: {:global, nil},
          type: :episodic,
          confidence: 1.0
        )

      {:ok, _} =
        Memories.store("will be pruned",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.05
        )

      assert :ok = Compaction.perform(%Oban.Job{args: %{"action" => "decay"}})
      assert :ok = Compaction.perform(%Oban.Job{args: %{"action" => "prune"}})
    end
  end

  describe "decay_rate/1" do
    test "returns correct rates for each type" do
      assert Compaction.decay_rate(:episodic) == 0.98
      assert Compaction.decay_rate(:semantic) == 0.995
      assert Compaction.decay_rate(:procedural) == 0.999
    end
  end
end
