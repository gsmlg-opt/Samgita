defmodule SamgitaMemory.IntegrationTest do
  @moduledoc "Full integration tests across all subsystems."
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Memories
  alias SamgitaMemory.PRD
  alias SamgitaMemory.Memories.ThinkingChain
  alias SamgitaMemory.Workers.{Embedding, Compaction, Summarize}
  alias SamgitaMemory.Repo

  describe "store → embed → retrieve by semantic similarity" do
    test "full memory lifecycle with embeddings" do
      # Store memories
      {:ok, m1} =
        Memories.store("Phoenix uses Plug for HTTP middleware",
          scope: {:project, "samgita"},
          type: :semantic,
          tags: ["phoenix", "plug"]
        )

      {:ok, m2} =
        Memories.store("Ecto provides database query composability",
          scope: {:project, "samgita"},
          type: :semantic,
          tags: ["ecto", "database"]
        )

      {:ok, m3} =
        Memories.store("GenServer handles synchronous and async messages",
          scope: {:project, "samgita"},
          type: :semantic,
          tags: ["otp", "genserver"]
        )

      # Generate embeddings
      for m <- [m1, m2, m3] do
        assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => m.id}})
      end

      # Verify embeddings exist
      for m <- [m1, m2, m3] do
        updated = Repo.get!(Memories.Memory, m.id)
        refute is_nil(updated.embedding)
      end

      # Retrieve by scope
      results = Memories.retrieve("phoenix", scope: {:project, "samgita"})
      assert length(results) == 3

      # Retrieve by tags
      results = Memories.retrieve("database", scope: {:project, "samgita"}, tags: ["ecto"])
      assert length(results) == 1
      assert hd(results).id == m2.id

      # Forget one
      assert :ok = Memories.forget(m3.id)
      results = Memories.retrieve("all", scope: {:project, "samgita"})
      assert length(results) == 2
    end
  end

  describe "PRD full lifecycle" do
    test "start → events → decisions → resume → complete → compact" do
      # Start PRD
      {:ok, exec} = PRD.start_execution("integration-prd", title: "Integration Test PRD")
      assert exec.status == :in_progress

      # Add events
      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :requirement_started,
          summary: "Starting auth module",
          requirement_id: "req-1",
          agent_id: "eng-backend"
        })

      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :requirement_completed,
          summary: "Auth module done",
          requirement_id: "req-1",
          agent_id: "eng-backend"
        })

      {:ok, _} =
        PRD.append_event(exec.id, %{
          type: :test_passed,
          summary: "Auth tests pass",
          requirement_id: "req-1",
          agent_id: "eng-qa"
        })

      # Record decisions
      {:ok, _} =
        PRD.record_decision(exec.id, %{
          requirement_id: "req-1",
          decision: "Use bcrypt for password hashing",
          reason: "Industry standard, configurable work factor",
          alternatives: ["argon2", "scrypt"],
          agent_id: "eng-backend"
        })

      # Get context (cached after first read)
      {:ok, ctx1} = PRD.get_context(exec.id)
      assert length(ctx1.recent_events) == 3
      assert length(ctx1.decisions) == 1

      # Simulate resume — start_execution returns existing
      {:ok, resumed} = PRD.start_execution("integration-prd", title: "Integration Test PRD")
      assert resumed.id == exec.id

      # Complete
      {:ok, completed} = PRD.update_status(exec.id, :completed)
      assert completed.status == :completed

      # Run compaction
      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "prd_execution", "execution_id" => exec.id}
               })

      # Verify semantic memories were created from decisions
      decision_memories =
        Memories.retrieve(nil,
          type: :semantic,
          tags: ["prd-decision", "integration-prd"]
        )

      assert length(decision_memories) >= 1
      assert String.contains?(hd(decision_memories).content, "bcrypt")
    end
  end

  describe "thinking chain full lifecycle" do
    test "start → thoughts → complete → summarize → recall" do
      # Start chain
      {:ok, chain} =
        ThinkingChain.start("How to implement distributed caching?",
          scope_type: :project,
          scope_id: "samgita"
        )

      # Add thoughts with revisions
      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{content: "Use Redis for distributed cache"})

      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{
          content: "Actually, use ETS + Horde for BEAM-native distribution",
          is_revision: true,
          revises: 1
        })

      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{content: "Add GenServer wrapper for LRU eviction"})

      # Complete
      {:ok, completed} = ThinkingChain.complete(chain.id)
      assert completed.status == :completed

      # Run summarization
      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "thinking_chain", "chain_id" => chain.id}
               })

      # Verify summary was generated
      updated = Repo.get!(ThinkingChain, chain.id)
      refute is_nil(updated.summary)
      assert String.contains?(updated.summary, "distributed caching")

      # Verify revision pattern was extracted
      procedural =
        Memories.retrieve(nil,
          scope: {:project, "samgita"},
          type: :procedural,
          tags: ["revision-pattern"]
        )

      assert length(procedural) >= 1

      # Recall similar chains
      chains = ThinkingChain.recall("caching", scope_type: :project, scope_id: "samgita")
      assert length(chains) >= 1
      assert hd(chains).id == chain.id
    end
  end

  describe "confidence decay and pruning" do
    test "decay reduces confidence, prune removes low-confidence memories" do
      # Create memories of different types
      {:ok, episodic} =
        Memories.store("episodic fact", scope: {:global, nil}, type: :episodic, confidence: 1.0)

      {:ok, semantic} =
        Memories.store("semantic fact", scope: {:global, nil}, type: :semantic, confidence: 1.0)

      {:ok, procedural} =
        Memories.store("procedural fact",
          scope: {:global, nil},
          type: :procedural,
          confidence: 1.0
        )

      {:ok, near_prune} =
        Memories.store("almost dead", scope: {:global, nil}, type: :episodic, confidence: 0.11)

      # Run decay
      Compaction.run_decay()

      # Check decay rates applied correctly
      assert_in_delta Repo.get!(Memories.Memory, episodic.id).confidence, 0.98, 0.001
      assert_in_delta Repo.get!(Memories.Memory, semantic.id).confidence, 0.995, 0.001
      assert_in_delta Repo.get!(Memories.Memory, procedural.id).confidence, 0.999, 0.001

      # Near-prune memory should be decayed
      decayed = Repo.get!(Memories.Memory, near_prune.id)
      assert decayed.confidence < 0.11

      # Run multiple decay cycles to push near_prune below threshold
      for _ <- 1..10, do: Compaction.run_decay()

      # Prune
      {:ok, count} = Compaction.run_prune()
      assert count >= 1

      # Near-prune should be gone
      assert is_nil(Repo.get(Memories.Memory, near_prune.id))

      # Others should still exist
      refute is_nil(Repo.get(Memories.Memory, episodic.id))
      refute is_nil(Repo.get(Memories.Memory, semantic.id))
      refute is_nil(Repo.get(Memories.Memory, procedural.id))
    end
  end

  describe "scope isolation" do
    test "memories from different projects never mix" do
      {:ok, _} =
        Memories.store("project A secret",
          scope: {:project, "alpha"},
          tags: ["secret"]
        )

      {:ok, _} =
        Memories.store("project B secret",
          scope: {:project, "beta"},
          tags: ["secret"]
        )

      alpha_results = Memories.retrieve(nil, scope: {:project, "alpha"})
      beta_results = Memories.retrieve(nil, scope: {:project, "beta"})

      assert length(alpha_results) == 1
      assert length(beta_results) == 1
      assert hd(alpha_results).content == "project A secret"
      assert hd(beta_results).content == "project B secret"
    end
  end
end
