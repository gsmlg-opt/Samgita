defmodule SamgitaMemory.Workers.Embedding do
  @moduledoc "Oban worker that generates embeddings for memories asynchronously."

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 5,
    priority: 1

  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"memory_id" => memory_id}}) do
    case Repo.get(Memory, memory_id) do
      nil ->
        :ok

      %Memory{embedding: embedding} when not is_nil(embedding) ->
        :ok

      memory ->
        case generate_embedding(memory.content) do
          {:ok, embedding} ->
            memory
            |> Ecto.Changeset.change(%{embedding: embedding})
            |> Repo.update()

            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Enqueue embedding generation for a memory."
  def enqueue(memory_id) do
    %{memory_id: memory_id}
    |> new()
    |> Oban.insert(SamgitaMemory.Oban)
  end

  defp generate_embedding(content) do
    provider = Application.get_env(:samgita_memory, :embedding_provider, :mock)

    case provider do
      :mock -> generate_mock_embedding(content)
      :anthropic -> generate_anthropic_embedding(content)
      _ -> generate_mock_embedding(content)
    end
  end

  defp generate_mock_embedding(content) do
    dimensions = Application.get_env(:samgita_memory, :embedding_dimensions, 1536)
    # Deterministic mock: hash content to seed, produce consistent embeddings
    seed = :erlang.phash2(content)
    :rand.seed(:exsss, {seed, seed, seed})

    embedding = for _ <- 1..dimensions, do: :rand.uniform() * 2 - 1

    # Normalize to unit vector
    magnitude = :math.sqrt(Enum.reduce(embedding, 0, fn x, acc -> acc + x * x end))

    normalized =
      if magnitude > 0,
        do: Enum.map(embedding, &(&1 / magnitude)),
        else: embedding

    {:ok, Pgvector.new(normalized)}
  end

  defp generate_anthropic_embedding(content) do
    # Uses Voyage API for embeddings (Anthropic-recommended)
    api_key = Application.get_env(:samgita_provider, :anthropic_api_key)
    model = Application.get_env(:samgita_memory, :embedding_model, "voyage-3")

    body =
      Jason.encode!(%{
        input: [content],
        model: model,
        input_type: "document"
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case :httpc.request(
           :post,
           {~c"https://api.voyageai.com/v1/embeddings", headers, ~c"application/json", body},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(List.to_string(resp_body)) do
          {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
            {:ok, Pgvector.new(embedding)}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
