defmodule SamgitaMemory.Workers.EmbeddingTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Workers.Embedding
  alias SamgitaMemory.Memories
  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory

  describe "perform/1" do
    test "generates embedding for a memory" do
      {:ok, memory} = Memories.store("test content for embedding", scope: {:global, nil})
      assert is_nil(memory.embedding)

      # Perform the embedding job directly
      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})

      updated = Repo.get!(Memory, memory.id)
      refute is_nil(updated.embedding)
    end

    test "skips if memory already has embedding" do
      {:ok, memory} = Memories.store("already embedded", scope: {:global, nil})

      # Generate embedding first
      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      updated = Repo.get!(Memory, memory.id)
      embedding1 = updated.embedding

      # Running again should be a no-op
      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      updated2 = Repo.get!(Memory, memory.id)
      assert updated2.embedding == embedding1
    end

    test "returns :ok for non-existent memory" do
      assert :ok =
               Embedding.perform(%Oban.Job{
                 args: %{"memory_id" => Ecto.UUID.generate()}
               })
    end

    test "produces deterministic embeddings for same content" do
      {:ok, m1} = Memories.store("deterministic test", scope: {:global, nil})
      {:ok, m2} = Memories.store("deterministic test", scope: {:global, nil})

      Embedding.perform(%Oban.Job{args: %{"memory_id" => m1.id}})
      Embedding.perform(%Oban.Job{args: %{"memory_id" => m2.id}})

      updated1 = Repo.get!(Memory, m1.id)
      updated2 = Repo.get!(Memory, m2.id)

      assert updated1.embedding == updated2.embedding
    end

    test "produces different embeddings for different content" do
      {:ok, m1} = Memories.store("content alpha", scope: {:global, nil})
      {:ok, m2} = Memories.store("content beta", scope: {:global, nil})

      Embedding.perform(%Oban.Job{args: %{"memory_id" => m1.id}})
      Embedding.perform(%Oban.Job{args: %{"memory_id" => m2.id}})

      updated1 = Repo.get!(Memory, m1.id)
      updated2 = Repo.get!(Memory, m2.id)

      refute updated1.embedding == updated2.embedding
    end
  end

  describe "enqueue/1" do
    test "enqueues an embedding job" do
      {:ok, memory} = Memories.store("to be embedded", scope: {:global, nil})
      assert {:ok, %Oban.Job{}} = Embedding.enqueue(memory.id)
    end
  end
end
