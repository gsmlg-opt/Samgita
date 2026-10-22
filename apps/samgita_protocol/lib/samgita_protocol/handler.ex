defmodule SamgitaProtocol.Handler do
  @moduledoc """
  Host-owned behavior. Authenticate before `Server.receive/2`; persist command receipts atomically
  with actual effects in the host. The protocol cannot grant permissions or durable acceptance.
  """
  alias SamgitaProtocol.Error
  @callback capabilities() :: [String.t()]
  @callback methods() :: [String.t()]
  @callback handle_request(String.t(), map(), map(), term()) ::
              {:ok, map(), term()} | {:error, Error.t(), term()}
  @callback handle_notification(String.t(), map(), map(), term()) ::
              {:ok, term()} | {:error, Error.t(), term()}
  @callback handle_response(String.t(), {:ok, map()} | {:error, Error.t()}, map(), term()) ::
              {:ok, term()}
  @optional_callbacks handle_notification: 4, handle_response: 4
end
