defmodule SamgitaWeb.RateLimiter do
  @moduledoc """
  Node-local sliding-window admission, serialized by a supervised owner.

  Only admitted requests consume quota. State is ephemeral: an owner/node restart
  starts empty; a cluster needs an upstream shared limiter for a global quota.
  Cleanup visits at most 500 keys per tick, retaining a cursor between ticks.
  """
  use GenServer

  @cleanup_batch 500
  @cleanup_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def admit(server, key, limit, window_ms) do
    GenServer.call(server, {:admit, key, limit, window_ms})
  end

  @impl true
  def init(opts) do
    schedule_cleanup()

    {:ok,
     %{
       table: :ets.new(__MODULE__, [:set, :private]),
       cursor: :start,
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
     }}
  end

  @impl true
  def handle_call({:admit, key, limit, window_ms}, _from, state) do
    now = state.clock.()
    key = {key, limit, window_ms}

    timestamps =
      case :ets.lookup(state.table, key) do
        [{^key, _expires, timestamps}] -> Enum.drop_while(timestamps, &(&1 <= now - window_ms))
        [] -> []
      end

    count = length(timestamps)

    if count < limit do
      :ets.insert(state.table, {key, now + window_ms, timestamps ++ [now]})
      {:reply, {:ok, limit - count - 1}, state}
    else
      {:reply, {:limited, max(hd(timestamps) + window_ms - now, 1)}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    key = if state.cursor == :start, do: :ets.first(state.table), else: state.cursor
    cursor = clean(state.table, key, state.clock.(), @cleanup_batch)
    schedule_cleanup()
    {:noreply, %{state | cursor: cursor}}
  end

  defp clean(_table, :"$end_of_table", _now, _remaining), do: :start
  defp clean(_table, key, _now, 0), do: key

  defp clean(table, key, now, remaining) do
    next = :ets.next(table, key)

    case :ets.lookup(table, key) do
      [{^key, expires, _}] when expires <= now -> :ets.delete(table, key)
      _ -> :ok
    end

    clean(table, next, now, remaining - 1)
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
