defmodule Samgita.Agent.ResultParser do
  @moduledoc """
  Pure-function module that classifies provider responses.

  Takes raw provider output and returns a tagged tuple:
  - `{:success, content}` — valid response ready for verification
  - `{:failure, reason}` — error with category for retry decisions
  """

  @type classified :: {:success, String.t()} | {:failure, term()}

  @doc "Classify a raw provider response."
  @spec classify(term()) :: classified()
  def classify({:ok, result}) when is_binary(result) and byte_size(result) > 0 do
    {:success, result}
  end

  def classify({:ok, ""}) do
    {:failure, :empty_response}
  end

  def classify({:ok, nil}) do
    {:failure, :nil_response}
  end

  def classify({:error, reason}) do
    {:failure, reason}
  end

  def classify(_other) do
    {:failure, :unexpected_format}
  end

  @doc "Returns true if the classified result is a success."
  @spec success?(classified()) :: boolean()
  def success?({:success, _}), do: true
  def success?({:failure, _}), do: false

  @doc "Extracts the error category from a classified result."
  @spec error_category(classified()) :: term() | nil
  def error_category({:failure, reason}), do: reason
  def error_category({:success, _}), do: nil
end
