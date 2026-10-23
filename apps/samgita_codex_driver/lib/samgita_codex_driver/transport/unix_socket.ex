defmodule SamgitaCodexDriver.Transport.UnixSocket do
  @moduledoc """
  Native WebSocket-over-UDS connection to an existing Codex control socket.

  Supply an absolute `:socket_path`. This owns only the client connection: it
  never starts/stops the server, unlinks its socket, or calls daemon shutdown.
  Wire framing and limits are identical to the WebSocket transport.
  """
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.WebSocket

  @impl true
  def open(opts), do: WebSocket.open_unix(Keyword.get(opts, :socket_path), opts)
  @impl true
  defdelegate send(state, json), to: WebSocket
  @impl true
  defdelegate handle_info(message, state), to: WebSocket
  @impl true
  defdelegate close(state), to: WebSocket
  @impl true
  defdelegate metadata(state), to: WebSocket
end
