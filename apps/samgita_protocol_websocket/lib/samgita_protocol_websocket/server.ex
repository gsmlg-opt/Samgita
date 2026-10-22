defmodule SamgitaProtocolWebSocket.Server do
  @moduledoc "Explicitly starts an authenticated, standalone app-server listener."

  def start_link(opts) do
    with {:ok, _} <- Keyword.fetch(opts, :authenticate),
         {:ok, _} <- Keyword.fetch(opts, :handler) do
      Bandit.start_link(
        plug: {SamgitaProtocolWebSocket.Plug, opts},
        ip: Keyword.get(opts, :ip, {127, 0, 0, 1}),
        port: Keyword.fetch!(opts, :port),
        startup_log: false,
        http_options: [log_protocol_errors: false],
        websocket_options: [
          max_frame_size: Keyword.get(opts, :max_frame_bytes, 1_048_576),
          max_fragmented_message_size: Keyword.get(opts, :max_frame_bytes, 1_048_576),
          log_protocol_errors: false
        ]
      )
    else
      :error -> {:error, :missing_configuration}
    end
  end

  def child_spec(opts) do
    %{id: {__MODULE__, make_ref()}, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  @doc "Enqueues a host-originated request through the core correlation state."
  def request(socket, method, params, opts),
    do: send(socket, {:protocol_request, method, params, opts})

  @doc "Emits a validated native notification."
  def notify(socket, notification), do: send(socket, {:protocol_notification, notification})

  def close(socket), do: send(socket, :protocol_close)
end
