defmodule Samgita.Cache do
  @moduledoc """
  ETS-based cache with PubSub invalidation across cluster nodes.
  """

  use GenServer

  @table :samgita_cache
  @default_ttl_ms 60_000

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  def put(key, value, ttl_ms \\ @default_ttl_ms) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl_ms, :millisecond)
    :ets.insert(@table, {key, value, expires_at})
    :ok
  end

  def invalidate(key) do
    :ets.delete(@table, key)

    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "cache:invalidate",
      {:invalidate, key}
    )

    :ok
  end

  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    Phoenix.PubSub.subscribe(Samgita.PubSub, "cache:invalidate")

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{table: table}}
  end

  @impl true
  def handle_info({:invalidate, key}, state) do
    :ets.delete(@table, key)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", {:const, now}}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end
end
