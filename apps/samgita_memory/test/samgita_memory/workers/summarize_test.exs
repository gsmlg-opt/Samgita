defmodule SamgitaMemory.Workers.SummarizeTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Workers.Summarize
  alias SamgitaMemory.Memories
  alias SamgitaMemory.Memories.ThinkingChain
  alias SamgitaMemory.PRD
  alias SamgitaMemory.Repo

  describe "thinking chain summarization" do
    test "generates summary for completed chain" do
      {:ok, chain} =
        ThinkingChain.start("How to implement caching?", scope_type: :project, scope_id: "proj-1")

      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{content: "Consider ETS for hot data"})

      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{content: "Use GenServer for management"})

      {:ok, completed} = ThinkingChain.complete(chain.id)
      assert completed.status == :completed

      # Perform summarization directly
      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "thinking_chain", "chain_id" => chain.id}
               })

      updated = Repo.get!(ThinkingChain, chain.id)
      assert updated.summary != nil
      assert String.contains?(updated.summary, "caching")
    end

    test "extracts revision patterns as procedural memories" do
      {:ok, chain} =
        ThinkingChain.start("Architecture choice", scope_type: :project, scope_id: "proj-1")

      {:ok, _} = ThinkingChain.add_thought(chain.id, %{content: "Use GenServer"})

      {:ok, _} =
        ThinkingChain.add_thought(chain.id, %{
          content: "Use gen_statem instead",
          is_revision: true,
          revises: 1
        })

      {:ok, _} = ThinkingChain.complete(chain.id)

      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "thinking_chain", "chain_id" => chain.id}
               })

      # Should have created a procedural memory from the revision
      procedural =
        Memories.retrieve(nil,
          scope: {:project, "proj-1"},
          type: :procedural,
          tags: ["revision-pattern"]
        )

      assert length(procedural) >= 1
    end

    test "handles non-existent chain" do
      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "thinking_chain", "chain_id" => Ecto.UUID.generate()}
               })
    end
  end

  describe "PRD execution compaction" do
    test "creates semantic memories from decisions" do
      {:ok, execution} = PRD.start_execution("test-prd-compact", title: "Test PRD")

      {:ok, _} =
        PRD.record_decision(execution.id, %{
          requirement_id: "req-1",
          decision: "Use PostgreSQL",
          reason: "Better for complex queries",
          alternatives: ["MySQL", "SQLite"],
          agent_id: "eng-backend"
        })

      {:ok, _} = PRD.update_status(execution.id, :completed)

      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "prd_execution", "execution_id" => execution.id}
               })

      # Should have created decision memories
      decision_memories =
        Memories.retrieve(nil,
          type: :semantic,
          tags: ["prd-decision"]
        )

      assert length(decision_memories) >= 1
    end

    test "creates summary memory" do
      {:ok, execution} = PRD.start_execution("test-prd-summary", title: "Summary PRD")

      {:ok, _} =
        PRD.append_event(execution.id, %{
          type: :requirement_completed,
          summary: "Implemented auth",
          agent_id: "eng-backend"
        })

      {:ok, _} = PRD.update_status(execution.id, :completed)

      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "prd_execution", "execution_id" => execution.id}
               })

      summary_memories =
        Memories.retrieve(nil,
          type: :semantic,
          tags: ["prd-summary"]
        )

      assert length(summary_memories) >= 1
    end

    test "handles non-existent execution" do
      assert :ok =
               Summarize.perform(%Oban.Job{
                 args: %{"type" => "prd_execution", "execution_id" => Ecto.UUID.generate()}
               })
    end
  end
end
