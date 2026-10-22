defmodule SamgitaProtocol.Error do
  @moduledoc "A typed, serializable failure. Messages must not contain request payloads or credentials."
  defexception [:code, :message, retryable: false, details: %{}]

  @messages %{
    "parse_error" => "Invalid JSON.",
    "invalid_message" => "Invalid protocol message.",
    "invalid_params" => "Invalid method parameters.",
    "invalid_response" => "Invalid method response.",
    "unsupported_version" => "Unsupported schema version.",
    "unsupported_method" => "Unsupported operation.",
    "unsupported_capability" => "Required capability is unavailable.",
    "not_initialized" => "Initialize the connection first.",
    "already_initialized" => "The connection is already initialized.",
    "capability_mismatch" => "Handler registration does not match advertised capabilities.",
    "correlation_mismatch" => "Response context does not match the pending request.",
    "unknown_response" => "No matching pending request.",
    "conflicting_response" => "A duplicate response has different content.",
    "buffer_full" => "The bounded buffer is full.",
    "too_many_requests" => "The outstanding request limit is reached.",
    "disconnected" => "The transport disconnected.",
    "ambiguous_disconnect" => "The request outcome is unknown; reconcile before retrying.",
    "timeout" => "The request timed out.",
    "cancelled" => "The local wait was cancelled; remote effects may still be running.",
    "replay_gap" => "The replay cursor cannot be satisfied.",
    "stale_cursor" => "The cursor is not a valid processed checkpoint.",
    "stale_connection" => "The connection generation is stale.",
    "conflict" => "The identity was reused with different content.",
    "not_found" => "The requested resource was not found.",
    "handler_error" => "The host handler failed.",
    "unauthorized" => "Machine authentication is required.",
    "upstream_error" => "The upstream service rejected the request."
  }

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          retryable: boolean(),
          details: map()
        }

  def codes, do: Map.keys(@messages)

  def new(code, details \\ %{}) do
    %__MODULE__{
      code: code,
      message: Map.fetch!(@messages, code),
      retryable: code in ["disconnected", "timeout", "buffer_full", "too_many_requests"],
      details: details
    }
  end

  def to_map(%__MODULE__{} = e),
    do: %{
      "code" => e.code,
      "message" => e.message,
      "retryable" => e.retryable,
      "details" => e.details
    }

  def from_map(
        %{"code" => code, "message" => message, "retryable" => retryable, "details" => details} =
          map
      )
      when is_binary(message) and is_boolean(retryable) and is_map(details) and map_size(map) == 4 do
    if Map.has_key?(@messages, code) and byte_size(message) <= 512 and
         SamgitaProtocol.Schema.json?(details) do
      {:ok, %__MODULE__{code: code, message: message, retryable: retryable, details: details}}
    else
      {:error, new("invalid_response")}
    end
  end

  def from_map(_), do: {:error, new("invalid_response")}
end
