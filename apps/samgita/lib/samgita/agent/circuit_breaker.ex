defmodule Samgita.Agent.CircuitBreaker do
  @moduledoc """
  Circuit breaker per agent type to prevent cascading failures.

  Tracks consecutive failures per agent type. After `@failure_threshold`
  consecutive failures, the circuit opens and rejects new tasks for that
  agent type. After `@recovery_timeout_ms`, the circuit enters half-open
  state and allows a single probe request. If it succeeds, the circuit
  closes; if it fails, it re-opens.

  States:
    :closed    — Normal operation, failures are counted
    :open      — Rejecting requests, waiting for recovery timeout
    :half_open — Allowing one probe request to test recovery
  """

  use GenServer

  require Logger

  @failure_threshold 5
  @recovery_timeout_ms 60_000

  ## Types

  @type state :: :closed | :open | :half_open
  @type breaker :: %{
          state: state(),
          failure_count: non_neg_integer(),
          last_failure_at: DateTime.t() | nil,
          opened_at: DateTime.t() | nil
        }

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if the circuit allows a request for the given agent type."
  @spec allow?(String.t()) :: :ok | {:error, :circuit_open}
  def allow?(agent_type) do
    GenServer.call(__MODULE__, {:allow?, agent_type})
  end

  @doc "Record a successful execution for the given agent type."
  @spec record_success(String.t()) :: :ok
  def record_success(agent_type) do
    GenServer.cast(__MODULE__, {:success, agent_type})
  end

  @doc "Record a failed execution for the given agent type."
  @spec record_failure(String.t()) :: :ok
  def record_failure(agent_type) do
    GenServer.cast(__MODULE__, {:failure, agent_type})
  end

  @doc "Get the current circuit state for an agent type."
  @spec get_state(String.t()) :: breaker()
  def get_state(agent_type) do
    GenServer.call(__MODULE__, {:get_state, agent_type})
  end

  @doc "Reset the circuit breaker for an agent type."
  @spec reset(String.t()) :: :ok
  def reset(agent_type) do
    GenServer.cast(__MODULE__, {:reset, agent_type})
  end

  @doc "Get all circuit breaker states."
  @spec all_states() :: %{String.t() => breaker()}
  def all_states do
    GenServer.call(__MODULE__, :all_states)
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{breakers: %{}}}
  end

  @impl true
  def handle_call({:allow?, agent_type}, _from, state) do
    breaker = get_or_init_breaker(state.breakers, agent_type)

    case breaker.state do
      :closed ->
        {:reply, :ok, state}

      :half_open ->
        {:reply, :ok, state}

      :open ->
        if recovery_timeout_elapsed?(breaker) do
          # Transition to half-open, allow one probe
          breaker = %{breaker | state: :half_open}
          state = put_in(state, [:breakers, agent_type], breaker)

          Logger.info(
            "[CircuitBreaker] #{agent_type}: open → half_open (recovery timeout elapsed)"
          )

          {:reply, :ok, state}
        else
          {:reply, {:error, :circuit_open}, state}
        end
    end
  end

  def handle_call({:get_state, agent_type}, _from, state) do
    breaker = get_or_init_breaker(state.breakers, agent_type)
    {:reply, breaker, state}
  end

  def handle_call(:all_states, _from, state) do
    {:reply, state.breakers, state}
  end

  @impl true
  def handle_cast({:success, agent_type}, state) do
    breaker = get_or_init_breaker(state.breakers, agent_type)

    case breaker.state do
      :half_open ->
        # Probe succeeded, close the circuit
        Logger.info("[CircuitBreaker] #{agent_type}: half_open → closed (probe succeeded)")
        breaker = init_breaker()
        state = put_in(state, [:breakers, agent_type], breaker)
        {:noreply, state}

      _ ->
        # Reset failure count on success
        breaker = %{breaker | failure_count: 0}
        state = put_in(state, [:breakers, agent_type], breaker)
        {:noreply, state}
    end
  end

  def handle_cast({:failure, agent_type}, state) do
    breaker = get_or_init_breaker(state.breakers, agent_type)
    now = DateTime.utc_now()

    case breaker.state do
      :half_open ->
        # Probe failed, re-open the circuit
        Logger.warning("[CircuitBreaker] #{agent_type}: half_open → open (probe failed)")

        breaker = %{
          breaker
          | state: :open,
            failure_count: breaker.failure_count + 1,
            last_failure_at: now,
            opened_at: now
        }

        state = put_in(state, [:breakers, agent_type], breaker)
        {:noreply, state}

      :closed ->
        failure_count = breaker.failure_count + 1
        breaker = %{breaker | failure_count: failure_count, last_failure_at: now}

        if failure_count >= @failure_threshold do
          Logger.warning(
            "[CircuitBreaker] #{agent_type}: closed → open (#{failure_count} consecutive failures)"
          )

          breaker = %{breaker | state: :open, opened_at: now}
          state = put_in(state, [:breakers, agent_type], breaker)
          {:noreply, state}
        else
          state = put_in(state, [:breakers, agent_type], breaker)
          {:noreply, state}
        end

      :open ->
        # Already open, just update last_failure_at
        breaker = %{
          breaker
          | failure_count: breaker.failure_count + 1,
            last_failure_at: now
        }

        state = put_in(state, [:breakers, agent_type], breaker)
        {:noreply, state}
    end
  end

  def handle_cast({:reset, agent_type}, state) do
    state = put_in(state, [:breakers, agent_type], init_breaker())
    {:noreply, state}
  end

  ## Internal

  defp get_or_init_breaker(breakers, agent_type) do
    Map.get(breakers, agent_type, init_breaker())
  end

  defp init_breaker do
    %{
      state: :closed,
      failure_count: 0,
      last_failure_at: nil,
      opened_at: nil
    }
  end

  defp recovery_timeout_elapsed?(%{opened_at: nil}), do: true

  defp recovery_timeout_elapsed?(%{opened_at: opened_at}) do
    elapsed = DateTime.diff(DateTime.utc_now(), opened_at, :millisecond)
    elapsed >= @recovery_timeout_ms
  end
end
