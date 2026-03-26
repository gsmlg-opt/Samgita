defmodule Samgita.Agent.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.CircuitBreaker

  setup do
    # Reset any state from previous tests by using a unique agent type per test
    agent_type = "test-agent-#{System.unique_integer([:positive])}"
    {:ok, agent_type: agent_type}
  end

  describe "initial state" do
    test "starts in closed state", %{agent_type: agent_type} do
      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :closed
      assert breaker.failure_count == 0
      assert breaker.last_failure_at == nil
      assert breaker.opened_at == nil
    end

    test "allows requests when closed", %{agent_type: agent_type} do
      assert :ok == CircuitBreaker.allow?(agent_type)
    end
  end

  describe "failure tracking" do
    test "counts consecutive failures", %{agent_type: agent_type} do
      CircuitBreaker.record_failure(agent_type)
      CircuitBreaker.record_failure(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.failure_count == 2
      assert breaker.state == :closed
    end

    test "resets failure count on success", %{agent_type: agent_type} do
      CircuitBreaker.record_failure(agent_type)
      CircuitBreaker.record_failure(agent_type)
      CircuitBreaker.record_success(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.failure_count == 0
      assert breaker.state == :closed
    end

    test "opens circuit after 5 consecutive failures", %{agent_type: agent_type} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :open
      assert breaker.failure_count == 5
      assert breaker.opened_at != nil
    end
  end

  describe "open state" do
    test "rejects requests when open", %{agent_type: agent_type} do
      # Open the circuit
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      Process.sleep(10)
      assert {:error, :circuit_open} == CircuitBreaker.allow?(agent_type)
    end
  end

  describe "success before threshold" do
    test "4 failures then success keeps circuit closed", %{agent_type: agent_type} do
      for _ <- 1..4 do
        CircuitBreaker.record_failure(agent_type)
      end

      CircuitBreaker.record_success(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :closed
      assert breaker.failure_count == 0
    end
  end

  describe "reset" do
    test "reset closes the circuit", %{agent_type: agent_type} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      CircuitBreaker.reset(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :closed
      assert breaker.failure_count == 0
    end
  end

  describe "all_states" do
    test "returns all tracked agent types", %{agent_type: agent_type} do
      CircuitBreaker.record_failure(agent_type)
      Process.sleep(10)

      states = CircuitBreaker.all_states()
      assert Map.has_key?(states, agent_type)
      assert states[agent_type].failure_count == 1
    end
  end

  describe "half-open state" do
    test "transitions open → half_open after recovery timeout and allows probe", %{
      agent_type: agent_type
    } do
      # Open the circuit with 5 consecutive failures
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      Process.sleep(10)

      assert {:error, :circuit_open} == CircuitBreaker.allow?(agent_type)

      # Back-date opened_at so the recovery timeout appears to have elapsed
      past = DateTime.add(DateTime.utc_now(), -61, :second)

      :sys.replace_state(CircuitBreaker, fn %{breakers: breakers} = s ->
        updated =
          Map.update!(breakers, agent_type, fn breaker ->
            %{breaker | opened_at: past}
          end)

        %{s | breakers: updated}
      end)

      # Now allow? should transition to half_open and return :ok
      assert :ok == CircuitBreaker.allow?(agent_type)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :half_open
    end

    test "success in half_open closes the circuit", %{agent_type: agent_type} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      Process.sleep(10)

      # Force the circuit into half_open by back-dating opened_at
      past = DateTime.add(DateTime.utc_now(), -61, :second)

      :sys.replace_state(CircuitBreaker, fn %{breakers: breakers} = s ->
        updated =
          Map.update!(breakers, agent_type, fn breaker ->
            %{breaker | opened_at: past}
          end)

        %{s | breakers: updated}
      end)

      # Trigger the open → half_open transition
      assert :ok == CircuitBreaker.allow?(agent_type)

      # A successful probe must close the circuit
      CircuitBreaker.record_success(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :closed
      assert breaker.failure_count == 0
    end

    test "failure in half_open re-opens the circuit", %{agent_type: agent_type} do
      for _ <- 1..5 do
        CircuitBreaker.record_failure(agent_type)
      end

      Process.sleep(10)

      # Force the circuit into half_open by back-dating opened_at
      past = DateTime.add(DateTime.utc_now(), -61, :second)

      :sys.replace_state(CircuitBreaker, fn %{breakers: breakers} = s ->
        updated =
          Map.update!(breakers, agent_type, fn breaker ->
            %{breaker | opened_at: past}
          end)

        %{s | breakers: updated}
      end)

      # Trigger the open → half_open transition
      assert :ok == CircuitBreaker.allow?(agent_type)

      # A failed probe must re-open the circuit
      CircuitBreaker.record_failure(agent_type)
      Process.sleep(10)

      breaker = CircuitBreaker.get_state(agent_type)
      assert breaker.state == :open
      assert breaker.opened_at != nil
    end
  end

  describe "independent agent types" do
    test "failures in one type don't affect another" do
      type_a = "independent-a-#{System.unique_integer([:positive])}"
      type_b = "independent-b-#{System.unique_integer([:positive])}"

      for _ <- 1..5 do
        CircuitBreaker.record_failure(type_a)
      end

      Process.sleep(10)

      assert {:error, :circuit_open} == CircuitBreaker.allow?(type_a)
      assert :ok == CircuitBreaker.allow?(type_b)
    end
  end
end
