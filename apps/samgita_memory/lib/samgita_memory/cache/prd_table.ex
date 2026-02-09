defmodule SamgitaMemory.Cache.PRDTable do
  @moduledoc """
  ETS-backed cache for active PRD executions.

  - Table: :sm_prd_cache, type :set
  - Key: prd_id
  - Contents: full execution struct with recent events (last 50) and all decisions
  - Population: on first access or on event append
  - Eviction: on completion + compaction, or LRU at max entries
  """

  use GenServer

  @table :sm_prd_cache
  @default_max_entries 100

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(prd_id) do
    case :ets.lookup(@table, prd_id) do
      [{_key, value, _accessed_at}] ->
        :ets.update_element(@table, prd_id, {3, now()})
        {:ok, value}

      [] ->
        :miss
    end
  end

  def put(prd_id, value) do
    GenServer.call(__MODULE__, {:put, prd_id, value})
  end

  def invalidate(prd_id) do
    :ets.delete(@table, prd_id)
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

    max_entries =
      Application.get_env(:samgita_memory, :cache_max_prd_executions, @default_max_entries)

    {:ok, %{table: table, max_entries: max_entries}}
  end

  @impl true
  def handle_call({:put, prd_id, value}, _from, state) do
    maybe_evict(state)
    :ets.insert(@table, {prd_id, value, now()})
    {:reply, :ok, state}
  end

  defp maybe_evict(%{max_entries: max_entries}) do
    current_size = :ets.info(@table, :size)

    if current_size >= max_entries do
      evict_lru(div(max_entries, 10))
    end
  end

  defp evict_lru(count) do
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
