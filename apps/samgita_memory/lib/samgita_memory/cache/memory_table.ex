defmodule SamgitaMemory.Cache.MemoryTable do
  @moduledoc """
  ETS-backed cache for recently accessed memories.

  - Table: :sm_memory_cache, type :set, read concurrency enabled
  - Key: {scope_type, scope_id, memory_id}
  - Eviction: LRU-based, max entries configurable
  - Population: read-through cache on access
  - Invalidation: on update, delete, or confidence drop below threshold
  """

  use GenServer

  @table :sm_memory_cache
  @default_max_entries 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(scope_type, scope_id, memory_id) do
    case :ets.lookup(@table, {scope_type, scope_id, memory_id}) do
      [{_key, value, _accessed_at}] ->
        # Update access time
        :ets.update_element(@table, {scope_type, scope_id, memory_id}, {3, now()})
        {:ok, value}

      [] ->
        :miss
    end
  end

  def put(scope_type, scope_id, memory_id, value) do
    GenServer.call(__MODULE__, {:put, scope_type, scope_id, memory_id, value})
  end

  def invalidate(scope_type, scope_id, memory_id) do
    :ets.delete(@table, {scope_type, scope_id, memory_id})
    :ok
  end

  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  def size do
    :ets.info(@table, :size)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    max_entries = Application.get_env(:samgita_memory, :cache_max_memories, @default_max_entries)
    {:ok, %{table: table, max_entries: max_entries}}
  end

  @impl true
  def handle_call({:put, scope_type, scope_id, memory_id, value}, _from, state) do
    maybe_evict(state)
    :ets.insert(@table, {{scope_type, scope_id, memory_id}, value, now()})
    {:reply, :ok, state}
  end

  defp maybe_evict(%{max_entries: max_entries}) do
    current_size = :ets.info(@table, :size)

    if current_size >= max_entries do
      evict_lru(div(max_entries, 10))
    end
  end

  defp evict_lru(count) do
    # Get all entries sorted by access time, delete oldest
    entries =
      :ets.tab2list(@table)
      |> Enum.sort_by(fn {_key, _value, accessed_at} -> accessed_at end)
      |> Enum.take(count)

    Enum.each(entries, fn {key, _value, _accessed_at} ->
      :ets.delete(@table, key)
    end)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
