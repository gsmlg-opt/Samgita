defmodule SamgitaProtocolWebSocket.Server do
  @moduledoc "Explicitly starts an authenticated, standalone app-server listener."

  def start_link(opts) do
    with {:ok, _} <- Keyword.fetch(opts, :authenticate),
         {:ok, _} <- Keyword.fetch(opts, :handler) do
      Gaoxy.HTTP.start_link(
        id: :app_server,
        plug: {SamgitaProtocolWebSocket.Plug, opts},
        ip: Keyword.get(opts, :ip, {127, 0, 0, 1}),
        port: Keyword.fetch!(opts, :port)
      )
    else
      :error -> {:error, :missing_configuration}
    end
  end

  def child_spec(opts) do
    %{id: {__MODULE__, make_ref()}, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  @doc "Returns the explicitly started listener's actual address and port."
  def listener_info(listener) do
    case Gaoxy.info(listener, :app_server) do
      %{local: local} -> local
      error -> error
    end
  end

  @doc "Enqueues a host-originated request through the core correlation state."
  def request(socket, method, params, opts),
    do: send(socket, {:protocol_request, method, params, opts})

  @doc "Emits a validated native notification."
  def notify(socket, notification), do: send(socket, {:protocol_notification, notification})

  def close(socket), do: send(socket, :protocol_close)
end
