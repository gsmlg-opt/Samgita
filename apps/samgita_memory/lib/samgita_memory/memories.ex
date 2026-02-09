defmodule SamgitaMemory.Memories do
  @moduledoc "Context module for memory CRUD and retrieval."

  import Ecto.Query

  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory
  alias SamgitaMemory.Cache.MemoryTable

  @doc """
  Store a new memory fact.

  ## Options
    * `:source` - `{type, id}` tuple for the source
    * `:scope` - `{type, id}` tuple for the scope
    * `:type` - `:episodic`, `:semantic`, or `:procedural`
    * `:tags` - list of string tags
    * `:metadata` - arbitrary map
    * `:confidence` - float 0.0-1.0 (default 1.0)
  """
  def store(content, opts \\ []) do
    {source_type, source_id} = Keyword.get(opts, :source, {:observation, nil})
    {scope_type, scope_id} = Keyword.get(opts, :scope, {:global, nil})

    attrs = %{
      content: content,
      source_type: source_type,
      source_id: source_id,
      scope_type: scope_type,
      scope_id: scope_id,
      memory_type: Keyword.get(opts, :type, :episodic),
      tags: Keyword.get(opts, :tags, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      confidence: Keyword.get(opts, :confidence, 1.0),
      accessed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case %Memory{} |> Memory.changeset(attrs) |> Repo.insert() do
      {:ok, memory} ->
        # Enqueue async embedding generation
        SamgitaMemory.Workers.Embedding.enqueue(memory.id)
        {:ok, memory}

      error ->
        error
    end
  end

  @doc """
  Retrieve memories relevant to a query.

  ## Options
    * `:scope` - `{type, id}` tuple to filter by scope
    * `:type` - memory type to filter by
    * `:tags` - list of required tags
    * `:limit` - max results (default from config)
    * `:min_confidence` - minimum confidence threshold
  """
  def retrieve(query, opts \\ []) do
    results = SamgitaMemory.Retrieval.Pipeline.execute(query, opts)

    # Update access tracking for returned memories
    Enum.each(results, &touch_access/1)

    results
  end

  @doc "Explicitly forget a memory by ID."
  def forget(memory_id) do
    case Repo.get(Memory, memory_id) do
      nil ->
        {:error, :not_found}

      memory ->
        MemoryTable.invalidate(memory.scope_type, memory.scope_id, memory.id)
        Repo.delete(memory)
        :ok
    end
  end

  @doc """
  Reinforce a memory — update confidence or metadata.

  ## Options
    * `:confidence` - new confidence value
    * `:metadata` - metadata to merge
  """
  def reinforce(memory_id, opts \\ []) do
    case Repo.get(Memory, memory_id) do
      nil ->
        {:error, :not_found}

      memory ->
        attrs =
          %{}
          |> maybe_put(:confidence, Keyword.get(opts, :confidence))
          |> maybe_put(:metadata, merge_metadata(memory.metadata, Keyword.get(opts, :metadata)))

        memory
        |> Memory.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Get a single memory by ID."
  def get(memory_id) do
    Repo.get(Memory, memory_id)
  end

  # Private helpers

  defp touch_access(memory) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(m in Memory, where: m.id == ^memory.id)
    |> Repo.update_all(set: [accessed_at: now], inc: [access_count: 1])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_metadata(existing, nil), do: existing
  defp merge_metadata(existing, new), do: Map.merge(existing, new)
end
