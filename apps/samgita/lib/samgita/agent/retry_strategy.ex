defmodule Samgita.Agent.RetryStrategy do
  @moduledoc """
  Pure-function module encapsulating retry decisions and backoff calculation.

  Given an error category and retry count, determines whether to retry,
  how long to wait, and whether to escalate (open circuit breaker).
  """

  @max_retries 3
  @max_backoff_ms 3_600_000

  @type error_category :: :rate_limit | :overloaded | :timeout | :unknown

  @doc "Returns true if the error should be retried at the given retry count."
  @spec should_retry?(error_category(), non_neg_integer()) :: boolean()
  def should_retry?(_category, retry_count) when retry_count >= @max_retries, do: false
  def should_retry?(_category, _retry_count), do: true

  @doc "Returns the backoff duration in milliseconds."
  @spec backoff_ms(error_category(), non_neg_integer()) :: pos_integer()
  def backoff_ms(:timeout, _attempt), do: 5_000

  def backoff_ms(_category, attempt) do
    min(round(60_000 * :math.pow(2, attempt)), @max_backoff_ms)
  end

  @doc "Returns true if the failure should escalate to circuit breaker."
  @spec should_escalate?(error_category(), non_neg_integer()) :: boolean()
  def should_escalate?(_category, retry_count) when retry_count >= @max_retries, do: true
  def should_escalate?(_category, _retry_count), do: false

  @doc "Classifies a raw error term into a retry category."
  @spec classify_for_retry(term()) :: error_category()
  def classify_for_retry(:rate_limit), do: :rate_limit
  def classify_for_retry(:overloaded), do: :overloaded
  def classify_for_retry(:timeout), do: :timeout
  def classify_for_retry(_other), do: :unknown
end
