defmodule SamgitaProtocolWebSocket.Socket do
  @moduledoc false
  @behaviour WebSock
  alias SamgitaProtocol.{Capabilities, Codec, Server}

  def init(opts) do
    principal = Keyword.fetch!(opts, :principal)
    handler_state = Keyword.get(opts, :handler_state)

    handler_state =
      if is_function(handler_state, 1), do: handler_state.(principal), else: handler_state

    case Server.new(Keyword.fetch!(opts, :handler), handler_state, opts) do
      {:ok, server} -> {:ok, %{server: server, opts: opts}}
      {:error, _error} -> {:stop, :normal, 1008, %{server: nil, opts: opts}}
    end
  end

  def handle_in({text, opcode: :text}, state) do
    case Server.receive(state.server, text) do
      {:ok, messages, server} -> push(messages, %{state | server: server})
      {:error, _error, server} -> {:stop, :normal, 1008, %{state | server: server}}
    end
  end

  def handle_in({_data, opcode: :binary}, state), do: {:stop, :normal, 1003, state}

  def handle_info({:protocol_request, method, params, opts}, state) do
    case Server.request(state.server, method, params, opts) do
      {:ok, message, server} -> push([message], %{state | server: server})
      {:error, _error, server} -> {:stop, :normal, 1008, %{state | server: server}}
    end
  end

  def handle_info({:protocol_notification, message}, state) do
    with %{"type" => "notification", "method" => method} <- message,
         true <- state.server.client.phase == :ready,
         true <- Capabilities.supports?(state.server.client.negotiated, method) do
      push([message], state)
    else
      _ -> {:stop, :normal, 1008, state}
    end
  end

  def handle_info(:protocol_close, state), do: {:stop, :normal, 1000, state}
  def handle_info(_message, state), do: {:ok, state}

  defp push([], state), do: {:ok, state}

  defp push(messages, state) do
    frames = Enum.map(messages, &Codec.encode(&1, state.opts))

    if Enum.all?(frames, &match?({:ok, _}, &1)) do
      {:push, Enum.map(frames, fn {:ok, text} -> {:text, text} end), state}
    else
      {:stop, :normal, 1008, state}
    end
  end
end
