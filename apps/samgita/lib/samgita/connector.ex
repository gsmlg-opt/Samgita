defmodule Samgita.Connector do
  @moduledoc """
  Agent-neutral event delivery. A successful response is notification state, never work acceptance.

  Implementations must not retry a mutation after an ambiguous disconnect. The durable delivery
  context owns retry/reconciliation using the same operation ID. Implementations receive an
  operator-approved registered target; they cannot choose another Agent or execute a session.
  """
  alias Samgita.Connector.Failure

  @callback receive_event(map(), map(), String.t()) :: {:ok, map()} | {:error, Failure.t()}
  @callback status(map(), String.t(), String.t()) :: {:ok, map()} | {:error, Failure.t()}
end

defmodule Samgita.Connector.Failure do
  @moduledoc "Secret-free delivery failures. Only allowlisted codes and bounded delay reach state/logs."
  @enforce_keys [:class, :code]
  defstruct [:class, :code, :retry_after]

  @type t :: %__MODULE__{
          class: :retryable | :permanent | :authentication | :ambiguous,
          code: atom() | String.t(),
          retry_after: nil | pos_integer()
        }

  def new(class, code, retry_after \\ nil),
    do: %__MODULE__{class: class, code: code, retry_after: retry_after}

  def http(status, headers \\ []) do
    case status do
      429 -> new(:retryable, :rate_limited, retry_after(headers))
      n when n in [401, 403] -> new(:authentication, :remote_authentication)
      n when n in [408, 425] or n in 500..599 -> new(:retryable, :remote_unavailable)
      _ -> new(:permanent, :remote_rejected)
    end
  end

  def protocol(%SamgitaProtocol.Error{details: %{"http_status" => status} = details}, false)
      when is_integer(status) do
    http(status, [{"retry-after", details["retry_after"]}])
  end

  def protocol(%SamgitaProtocol.Error{code: code}, mutation) do
    cond do
      code == "unauthorized" ->
        new(:authentication, code)

      mutation &&
          code in ~w(ambiguous_disconnect disconnected timeout cancelled handler_error invalid_response correlation_mismatch unknown_response conflicting_response invalid_message parse_error upstream_error) ->
        new(:ambiguous, code)

      code in ~w(disconnected timeout buffer_full too_many_requests handler_error upstream_error) ->
        new(:retryable, code)

      true ->
        new(:permanent, code)
    end
  end

  defp retry_after(headers) do
    value =
      Enum.find_value(headers, fn
        {key, value} when is_binary(key) ->
          if String.downcase(key) == "retry-after", do: value

        _ ->
          nil
      end)

    case value do
      n when is_integer(n) -> clamp(n)
      value when is_binary(value) and byte_size(value) <= 64 -> parse_delay(value)
      _ -> nil
    end
  end

  defp parse_delay(value) do
    case Integer.parse(value) do
      {n, ""} ->
        clamp(n)

      _ ->
        parse_http_date(value)
    end
  end

  defp parse_http_date(value) do
    months = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    with [day, month, year, hour, minute, second] <-
           Regex.run(
             ~r/\A(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), ([0-9]{2}) ([A-Z][a-z]{2}) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT\z/,
             value,
             capture: :all_but_first
           ),
         index when is_integer(index) <- Enum.find_index(months, &(&1 == month)),
         {:ok, date} <- Date.new(String.to_integer(year), index + 1, String.to_integer(day)),
         {:ok, time} <-
           Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second)),
         {:ok, timestamp} <- DateTime.new(date, time, "Etc/UTC") do
      clamp(DateTime.diff(timestamp, DateTime.utc_now(), :second))
    else
      _ -> nil
    end
  end

  defp clamp(n), do: max(1, min(3600, n))
end
