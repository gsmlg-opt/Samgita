defmodule SamgitaMemory.Workers.EmbeddingTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Memories
  alias SamgitaMemory.Memories.Memory
  alias SamgitaMemory.Repo
  alias SamgitaMemory.Workers.Embedding

  # ---------------------------------------------------------------------------
  # Fake httpc modules for Anthropic provider path testing
  # ---------------------------------------------------------------------------

  defmodule FakeHttpcSuccess do
    @embedding Enum.map(1..1536, &(&1 / 1536.0))
    def request(:post, _, _, _) do
      body = Jason.encode!(%{"data" => [%{"embedding" => @embedding}]})
      {:ok, {{:http, 200, ~c"OK"}, [], String.to_charlist(body)}}
    end
  end

  defmodule FakeHttpcNon200 do
    def request(:post, _, _, _) do
      {:ok, {{:http, 401, ~c"Unauthorized"}, [], ~c"Unauthorized"}}
    end
  end

  defmodule FakeHttpcInvalidJson do
    def request(:post, _, _, _) do
      {:ok, {{:http, 200, ~c"OK"}, [], ~c"not-valid-json"}}
    end
  end

  defmodule FakeHttpcConnectionError do
    def request(:post, _, _, _) do
      {:error, {:failed_connect, []}}
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: temporarily switch to Anthropic provider with a fake httpc module
  # ---------------------------------------------------------------------------

  defp with_anthropic(httpc_mod, fun) do
    Application.put_env(:samgita_memory, :embedding_provider, :anthropic)
    Application.put_env(:samgita_memory, :httpc_module, httpc_mod)

    on_exit(fn ->
      Application.put_env(:samgita_memory, :embedding_provider, :mock)
      Application.delete_env(:samgita_memory, :httpc_module)
    end)

    fun.()
  end

  # ---------------------------------------------------------------------------
  # perform/1
  # ---------------------------------------------------------------------------

  describe "perform/1" do
    test "generates embedding for a memory" do
      {:ok, memory} = Memories.store("test content for embedding", scope: {:global, nil})
      assert is_nil(memory.embedding)

      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})

      updated = Repo.get!(Memory, memory.id)
      refute is_nil(updated.embedding)
    end

    test "skips if memory already has embedding" do
      {:ok, memory} = Memories.store("already embedded", scope: {:global, nil})

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

    test "returns {:error, reason} when embedding generation fails" do
      # Uses Anthropic provider + connection-error httpc so generate_embedding
      # returns {:error, _}, which perform/1 must propagate (triggers Oban retries)
      with_anthropic(FakeHttpcConnectionError, fn ->
        {:ok, memory} = Memories.store("embedding will fail", scope: {:global, nil})
        assert {:error, _reason} = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      end)
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

  # ---------------------------------------------------------------------------
  # generate_embedding — provider dispatch
  # ---------------------------------------------------------------------------

  describe "generate_embedding (provider dispatch)" do
    test "mock provider returns normalized unit vector" do
      {:ok, memory} = Memories.store("vector normalization test", scope: {:global, nil})
      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})

      updated = Repo.get!(Memory, memory.id)
      vec = Pgvector.to_list(updated.embedding)

      assert length(vec) == 1536

      # Normalized to unit length (magnitude ~1.0)
      magnitude = :math.sqrt(Enum.reduce(vec, 0, fn x, acc -> acc + x * x end))
      assert_in_delta magnitude, 1.0, 0.001
    end

    test "anthropic provider stores embedding on successful 200 response" do
      with_anthropic(FakeHttpcSuccess, fn ->
        {:ok, memory} = Memories.store("anthropic success path", scope: {:global, nil})
        assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})

        updated = Repo.get!(Memory, memory.id)
        refute is_nil(updated.embedding)
        assert length(Pgvector.to_list(updated.embedding)) == 1536
      end)
    end

    test "anthropic provider returns {:error, {:api_error, status}} on non-200 response" do
      with_anthropic(FakeHttpcNon200, fn ->
        {:ok, memory} = Memories.store("anthropic 401 path", scope: {:global, nil})

        assert {:error, {:api_error, 401}} =
                 Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      end)
    end

    test "anthropic provider returns {:error, :invalid_response} on bad json body" do
      with_anthropic(FakeHttpcInvalidJson, fn ->
        {:ok, memory} = Memories.store("anthropic invalid json path", scope: {:global, nil})

        assert {:error, :invalid_response} =
                 Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      end)
    end

    test "anthropic provider propagates connection error from httpc" do
      with_anthropic(FakeHttpcConnectionError, fn ->
        {:ok, memory} = Memories.store("anthropic connection error path", scope: {:global, nil})

        assert {:error, _reason} =
                 Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})
      end)
    end

    test "unknown provider falls back to mock embedding" do
      Application.put_env(:samgita_memory, :embedding_provider, :unknown_provider)

      on_exit(fn ->
        Application.put_env(:samgita_memory, :embedding_provider, :mock)
      end)

      {:ok, memory} = Memories.store("unknown provider fallback", scope: {:global, nil})
      assert :ok = Embedding.perform(%Oban.Job{args: %{"memory_id" => memory.id}})

      updated = Repo.get!(Memory, memory.id)
      refute is_nil(updated.embedding)
    end
  end

  # ---------------------------------------------------------------------------
  # enqueue/1
  # ---------------------------------------------------------------------------

  describe "enqueue/1" do
    test "enqueues an embedding job" do
      {:ok, memory} = Memories.store("to be embedded", scope: {:global, nil})
      assert {:ok, %Oban.Job{}} = Embedding.enqueue(memory.id)
    end
  end
end
