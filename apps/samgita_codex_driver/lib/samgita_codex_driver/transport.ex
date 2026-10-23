defmodule SamgitaCodexDriver.Transport do
  @moduledoc """
  Session-owned transport. Open, send, receive and close run in the session process.

  Transports deliver complete JSON message binaries, without decoding or mapping
  the protocol. They must enforce `:max_message_bytes` during framing, separate
  stderr from stdio JSONL, and never log payloads or credentials. Errors contain
  safe local codes and allowlisted metadata. `close/1` closes only owned resources;
  closing a borrowed server connection never stops its server or removes a socket.
  Successful `close/1` returns `:ok` only after owned process cleanup is confirmed.
  Unconfirmed cleanup raises a safe local `Error`; Session retains uncertainty
  and refuses replacement execution after that failure.
  """

  alias SamgitaProtocolCodex.Error

  @type state :: term()
  @type event :: {:message, binary()} | {:closed, map()}

  @callback open(keyword()) :: {:ok, state()} | {:error, Error.t()}
  @callback send(state(), binary()) :: {:ok, state()} | {:error, Error.t(), state()}
  @callback handle_info(term(), state()) ::
              :unknown | {:ok, [event()], state()} | {:error, Error.t(), state()}
  @callback close(state()) :: :ok
  @callback metadata(state()) :: map()
end
