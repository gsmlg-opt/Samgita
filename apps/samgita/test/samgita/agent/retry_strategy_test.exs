defmodule Samgita.Agent.RetryStrategyTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.RetryStrategy

  describe "should_retry?/2" do
    test "retries rate_limit errors under max retries" do
      assert RetryStrategy.should_retry?(:rate_limit, 0) == true
      assert RetryStrategy.should_retry?(:rate_limit, 2) == true
    end

    test "retries overloaded errors under max retries" do
      assert RetryStrategy.should_retry?(:overloaded, 1) == true
    end

    test "retries timeout errors under max retries" do
      assert RetryStrategy.should_retry?(:timeout, 0) == true
    end

    test "retries unknown errors under max retries" do
      assert RetryStrategy.should_retry?(:unknown, 2) == true
    end

    test "stops retrying at max retries" do
      assert RetryStrategy.should_retry?(:rate_limit, 3) == false
      assert RetryStrategy.should_retry?(:unknown, 3) == false
    end

    test "stops retrying above max retries" do
      assert RetryStrategy.should_retry?(:rate_limit, 5) == false
    end
  end

  describe "backoff_ms/2" do
    test "exponential backoff for rate_limit" do
      assert RetryStrategy.backoff_ms(:rate_limit, 0) == 60_000
      assert RetryStrategy.backoff_ms(:rate_limit, 1) == 120_000
      assert RetryStrategy.backoff_ms(:rate_limit, 2) == 240_000
    end

    test "exponential backoff for overloaded" do
      assert RetryStrategy.backoff_ms(:overloaded, 0) == 60_000
    end

    test "shorter backoff for timeout" do
      assert RetryStrategy.backoff_ms(:timeout, 0) == 5_000
      assert RetryStrategy.backoff_ms(:timeout, 5) == 5_000
    end

    test "caps at max backoff" do
      assert RetryStrategy.backoff_ms(:rate_limit, 20) == 3_600_000
    end
  end

  describe "should_escalate?/2" do
    test "does not escalate under max retries" do
      assert RetryStrategy.should_escalate?(:unknown, 2) == false
    end

    test "escalates at max retries" do
      assert RetryStrategy.should_escalate?(:unknown, 3) == true
    end

    test "escalates above max retries" do
      assert RetryStrategy.should_escalate?(:rate_limit, 5) == true
    end
  end

  describe "classify_for_retry/1" do
    test "classifies known error atoms" do
      assert RetryStrategy.classify_for_retry(:rate_limit) == :rate_limit
      assert RetryStrategy.classify_for_retry(:overloaded) == :overloaded
      assert RetryStrategy.classify_for_retry(:timeout) == :timeout
    end

    test "classifies string errors as unknown" do
      assert RetryStrategy.classify_for_retry("some error message") == :unknown
    end

    test "classifies other atoms as unknown" do
      assert RetryStrategy.classify_for_retry(:something_else) == :unknown
    end
  end
end
