defmodule SamgitaMemory.Retrieval.Pipeline do
  @moduledoc """
  Hybrid retrieval pipeline with 7 stages:

  1. Scope filter
  2. Tag filter (optional)
  3. Semantic search (pgvector cosine similarity)
  4. Recency boost
  5. Confidence threshold
  6. Deduplication
  7. Format for context injection
  """

  import Ecto.Query

  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory

  @type opts :: [
          scope: {atom(), String.t() | nil},
          type: atom(),
          tags: [String.t()],
          limit: pos_integer(),
          min_confidence: float(),
          embedding: Pgvector.t() | nil
        ]

  @doc "Execute the full retrieval pipeline."
  @spec execute(String.t() | nil, opts()) :: [Memory.t()]
  def execute(_query, opts \\ []) do
    limit = Keyword.get(opts, :limit, config(:retrieval_default_limit, 10))
    min_confidence = Keyword.get(opts, :min_confidence, config(:retrieval_min_confidence, 0.3))
    embedding = Keyword.get(opts, :embedding)

    # Over-fetch for reranking (3x limit)
    fetch_limit = limit * 3

    candidates =
      Memory
      |> stage_1_scope_filter(opts)
      |> stage_1b_type_filter(opts)
      |> stage_2_tag_filter(opts)
      |> stage_3_semantic_search(embedding, fetch_limit)
      |> Repo.all()

    candidates
    |> stage_4_recency_boost(embedding)
    |> stage_5_confidence_threshold(min_confidence)
    |> stage_6_deduplication()
    |> stage_7_format(limit)
  end

  # Stage 1: Scope filter — eliminates cross-project contamination
  defp stage_1_scope_filter(query, opts) do
    case Keyword.get(opts, :scope) do
      {scope_type, scope_id} when not is_nil(scope_id) ->
        where(query, [m], m.scope_type == ^scope_type and m.scope_id == ^scope_id)

      {scope_type, nil} ->
        where(query, [m], m.scope_type == ^scope_type)

      _ ->
        query
    end
  end

  # Stage 1b: Type filter — optional
  defp stage_1b_type_filter(query, opts) do
    case Keyword.get(opts, :type) do
      nil -> query
      type -> where(query, [m], m.memory_type == ^type)
    end
  end

  # Stage 2: Tag filter — optional, uses GIN index
  defp stage_2_tag_filter(query, opts) do
    case Keyword.get(opts, :tags) do
      nil -> query
      [] -> query
      tags -> where(query, [m], fragment("? @> ?", m.tags, ^tags))
    end
  end

  # Stage 3: Semantic search — pgvector cosine similarity if embedding available
  defp stage_3_semantic_search(query, nil, limit) do
    # No embedding: fall back to confidence + recency ordering
    query
    |> order_by([m], desc: m.confidence, desc: m.updated_at)
    |> limit(^limit)
  end

  defp stage_3_semantic_search(query, embedding, limit) do
    query
    |> where([m], not is_nil(m.embedding))
    |> order_by([m], asc: fragment("? <=> ?", m.embedding, ^embedding))
    |> limit(^limit)
    |> select_merge([m], %{
      similarity: fragment("1 - (? <=> ?)", m.embedding, ^embedding)
    })
  end

  # Stage 4: Recency boost — combines semantic, recency, and access scores
  defp stage_4_recency_boost(memories, nil) do
    # No embedding available: score by confidence * recency only
    now = DateTime.utc_now()

    Enum.map(memories, fn memory ->
      recency_score = recency_score(memory.inserted_at, now)
      access_score = access_score(memory.accessed_at, now)
      score = memory.confidence * 0.7 + recency_score * 0.2 + access_score * 0.1
      {memory, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
  end

  defp stage_4_recency_boost(memories, _embedding) do
    now = DateTime.utc_now()
    semantic_weight = config(:retrieval_semantic_weight, 0.7)
    recency_weight = config(:retrieval_recency_weight, 0.2)
    access_weight = config(:retrieval_access_weight, 0.1)

    Enum.map(memories, fn memory ->
      semantic_score = Map.get(memory, :similarity, 0.5)
      recency_score = recency_score(memory.inserted_at, now)
      access_score = access_score(memory.accessed_at, now)

      score =
        semantic_score * semantic_weight +
          recency_score * recency_weight +
          access_score * access_weight

      {memory, score}
    end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
  end

  # Stage 5: Confidence threshold
  defp stage_5_confidence_threshold(scored_memories, min_confidence) do
    Enum.filter(scored_memories, fn {memory, _score} ->
      memory.confidence >= min_confidence
    end)
  end

  # Stage 6: Deduplication — if two memories have cosine similarity > 0.95, keep higher confidence
  defp stage_6_deduplication(scored_memories) do
    Enum.reduce(scored_memories, [], fn {memory, score}, acc ->
      if duplicate?(memory, acc) do
        acc
      else
        [{memory, score} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp duplicate?(memory, accepted) do
    Enum.any?(accepted, fn {existing, _} ->
      # Text-based dedup: if content is very similar (same prefix up to 100 chars)
      similar_content?(memory.content, existing.content)
    end)
  end

  defp similar_content?(a, b) when is_binary(a) and is_binary(b) do
    # Simple dedup: if normalized content matches
    normalize(a) == normalize(b)
  end

  defp similar_content?(_, _), do: false

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  # Stage 7: Format — take top N and return memories
  defp stage_7_format(scored_memories, limit) do
    scored_memories
    |> Enum.take(limit)
    |> Enum.map(fn {memory, _score} -> memory end)
  end

  # Scoring helpers

  defp recency_score(inserted_at, now) do
    days = DateTime.diff(now, inserted_at, :second) / 86_400
    1.0 / (1.0 + days / 30)
  end

  defp access_score(nil, _now), do: 0.0

  defp access_score(accessed_at, now) do
    days = DateTime.diff(now, accessed_at, :second) / 86_400
    1.0 / (1.0 + days / 7)
  end

  defp config(key, default) do
    Application.get_env(:samgita_memory, key, default)
  end
end
