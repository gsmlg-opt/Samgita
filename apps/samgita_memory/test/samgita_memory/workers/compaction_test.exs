defmodule SamgitaMemory.Workers.CompactionTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Memories
  alias SamgitaMemory.Memories.Memory
  alias SamgitaMemory.Repo
  alias SamgitaMemory.Workers.Compaction

  import Ecto.Query

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

  describe "prune_threshold/0" do
    test "returns 0.1" do
      assert Compaction.prune_threshold() == 0.1
    end
  end

  describe "memory lifecycle (prd-014)" do
    test "confidence decay compounds across multiple runs" do
      {:ok, memory} =
        Memories.store("compound decay test",
          scope: {:global, nil},
          type: :episodic,
          confidence: 1.0
        )

      # Simulate 3 days of decay: 1.0 * 0.98^3 = 0.9412
      Compaction.run_decay()
      Compaction.run_decay()
      Compaction.run_decay()

      updated = Repo.get!(Memory, memory.id)
      expected = 1.0 * 0.98 * 0.98 * 0.98
      assert_in_delta updated.confidence, expected, 0.001
    end

    test "decay eventually pushes episodic below prune threshold" do
      {:ok, memory} =
        Memories.store("slow decay to threshold",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.12
        )

      # After decay: 0.12 * 0.98 = 0.1176 (still above 0.1)
      Compaction.run_decay()
      after_one = Repo.get!(Memory, memory.id)
      assert after_one.confidence > 0.1

      # Run decay again: 0.1176 * 0.98 = 0.1152 (still above)
      Compaction.run_decay()
      after_two = Repo.get!(Memory, memory.id)
      assert after_two.confidence > 0.1

      # Once below 0.1, prune removes it
      Repo.update_all(
        from(m in Memory, where: m.id == ^memory.id),
        set: [confidence: 0.09]
      )

      {:ok, count} = Compaction.run_prune()
      assert count >= 1
      assert is_nil(Repo.get(Memory, memory.id))
    end

    test "run_decay_and_prune/0 decays and removes in one call" do
      {:ok, keep} =
        Memories.store("keep this",
          scope: {:global, nil},
          type: :semantic,
          confidence: 1.0
        )

      {:ok, prune_me} =
        Memories.store("prune this",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.05
        )

      assert :ok = Compaction.run_decay_and_prune()

      # Decayed but kept
      updated_keep = Repo.get!(Memory, keep.id)
      assert_in_delta updated_keep.confidence, 0.995, 0.001

      # Pruned
      assert is_nil(Repo.get(Memory, prune_me.id))
    end

    test "access retrieve boosts low-confidence memory to at least 0.8" do
      {:ok, memory} =
        Memories.store("fading memory",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.3
        )

      # Retrieve the memory — access should boost confidence to max(0.3, 0.8) = 0.8
      _results = Memories.retrieve("fading memory", scope: {:global, nil})

      updated = Repo.get!(Memory, memory.id)
      assert updated.confidence >= 0.8
    end

    test "access does not lower high-confidence memory" do
      {:ok, memory} =
        Memories.store("strong memory",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.95
        )

      _results = Memories.retrieve("strong memory", scope: {:global, nil})

      updated = Repo.get!(Memory, memory.id)
      # max(0.95, 0.8) = 0.95 — should not be lowered
      assert_in_delta updated.confidence, 0.95, 0.001
    end

    test "semantic tier decays more slowly than episodic over 10 cycles" do
      {:ok, ep} =
        Memories.store("episodic 10 cycles",
          scope: {:global, nil},
          type: :episodic,
          confidence: 1.0
        )

      {:ok, sem} =
        Memories.store("semantic 10 cycles",
          scope: {:global, nil},
          type: :semantic,
          confidence: 1.0
        )

      for _ <- 1..10, do: Compaction.run_decay()

      ep_updated = Repo.get!(Memory, ep.id)
      sem_updated = Repo.get!(Memory, sem.id)

      # episodic: 0.98^10 ≈ 0.817; semantic: 0.995^10 ≈ 0.951
      assert ep_updated.confidence < sem_updated.confidence
      assert_in_delta ep_updated.confidence, :math.pow(0.98, 10), 0.005
      assert_in_delta sem_updated.confidence, :math.pow(0.995, 10), 0.005
    end

    test "procedural tier decays slowest of all three tiers" do
      {:ok, ep} =
        Memories.store("episodic tier",
          scope: {:global, nil},
          type: :episodic,
          confidence: 1.0
        )

      {:ok, sem} =
        Memories.store("semantic tier",
          scope: {:global, nil},
          type: :semantic,
          confidence: 1.0
        )

      {:ok, proc} =
        Memories.store("procedural tier",
          scope: {:global, nil},
          type: :procedural,
          confidence: 1.0
        )

      for _ <- 1..30, do: Compaction.run_decay()

      ep_final = Repo.get!(Memory, ep.id)
      sem_final = Repo.get!(Memory, sem.id)
      proc_final = Repo.get!(Memory, proc.id)

      # procedural > semantic > episodic after 30 days
      assert proc_final.confidence > sem_final.confidence
      assert sem_final.confidence > ep_final.confidence
    end

    test "prune does not remove memories exactly at threshold" do
      {:ok, memory} =
        Memories.store("exactly at threshold",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.1
        )

      {:ok, count} = Compaction.run_prune()
      assert count == 0
      refute is_nil(Repo.get(Memory, memory.id))
    end

    test "access_count increments on retrieve" do
      {:ok, memory} =
        Memories.store("access counter",
          scope: {:global, nil},
          type: :episodic,
          confidence: 0.9
        )

      assert memory.access_count == 0

      Memories.retrieve("access counter", scope: {:global, nil})

      updated = Repo.get!(Memory, memory.id)
      assert updated.access_count == 1
    end
  end
end
