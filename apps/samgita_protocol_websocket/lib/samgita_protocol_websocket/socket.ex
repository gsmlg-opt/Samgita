defmodule SamgitaProtocolWebSocket.Socket do
  @moduledoc false
  @behaviour WebSock
  alias SamgitaProtocol.{Capabilities, Client, Codec, Server}

  def init(opts) do
    principal = Keyword.fetch!(opts, :principal)
    handler_state = Keyword.get(opts, :handler_state)

    handler_state =
      if is_function(handler_state, 1), do: handler_state.(principal), else: handler_state

    case Server.new(Keyword.fetch!(opts, :handler), handler_state, opts) do
      {:ok, server} -> {:ok, %{server: server, opts: opts, timers: %{}}}
      {:error, _error} -> {:stop, :normal, 1008, %{server: nil, opts: opts, timers: %{}}}
    end
  end

  def handle_in({text, opcode: :text}, state) do
    state = expire(state)

    case Server.receive(state.server, text) do
      {:ok, messages, server} -> push(messages, sync_timers(%{state | server: server}))
      {:error, _error, server} -> stop(1008, %{state | server: server})
    end
  end

  def handle_in({_data, opcode: :binary}, state), do: stop(1003, state)

  def handle_info({:protocol_request, method, params, opts}, state) do
    state = expire(state)

    case Server.request(state.server, method, params, opts) do
      {:ok, message, server} -> push([message], sync_timers(%{state | server: server}))
      {:error, _error, server} -> stop(1008, %{state | server: server})
    end
  end

  def handle_info({:protocol_expire, id, token}, state) do
    case state.timers[id] do
      %{token: ^token} -> {:ok, expire(state)}
      _ -> {:ok, state}
    end
  end

  def handle_info({:protocol_notification, message}, state) do
    with %{"type" => "notification", "method" => method} <- message,
         true <- state.server.client.phase == :ready,
         true <- Capabilities.supports?(state.server.client.negotiated, method) do
      push([message], state)
    else
      _ -> stop(1008, state)
    end
  end

  def handle_info(:protocol_close, state), do: stop(1000, state)
  def handle_info(_message, state), do: {:ok, state}

  def terminate(_reason, state) do
    disconnect(state)
    :ok
  end

  defp stop(code, state), do: {:stop, :normal, code, disconnect(state)}

  defp disconnect(%{server: nil} = state), do: state

  defp disconnect(state) do
    {:ok, effects, client} = Client.disconnect(state.server.client)
    settle_failures(effects, client, state)
  end

  defp expire(state) do
    {:ok, effects, client} = Client.expire(state.server.client, now())
    settle_failures(effects, client, state)
  end

  defp settle_failures(effects, client, state) do
    previous = state.server.client.pending
    state = sync_timers(put_in(state.server.client, client))

    Enum.reduce(effects, state, fn {:error, id, error}, state ->
      request = previous[id].request

      context =
        request
        |> Map.take(~w(command_id correlation_id causation_id project_ref task_ref))
        |> Map.put("request_id", id)
        |> Map.put("connection_id", state.server.connection_id)

      notify_failure(state, request["method"], error, context)
    end)
  end

  defp notify_failure(state, method, error, context) do
    case state.server.handler.handle_response(
           method,
           {:error, error},
           context,
           state.server.handler_state
         ) do
      {:ok, handler_state} -> put_in(state.server.handler_state, handler_state)
      _ -> state
    end
  rescue
    _ -> state
  catch
    _, _ -> state
  end

  defp sync_timers(state) do
    timers =
      Enum.reduce(state.timers, %{}, fn {id, timer}, timers ->
        if Map.has_key?(state.server.client.pending, id) do
          Map.put(timers, id, timer)
        else
          Process.cancel_timer(timer.timer)
          timers
        end
      end)

    timers =
      Enum.reduce(state.server.client.pending, timers, fn {id, entry}, timers ->
        if Map.has_key?(timers, id) do
          timers
        else
          token = make_ref()

          timer =
            Process.send_after(
              self(),
              {:protocol_expire, id, token},
              max(entry.deadline - now(), 0)
            )

          Map.put(timers, id, %{timer: timer, token: token})
        end
      end)

    %{state | timers: timers}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp push([], state), do: {:ok, state}

  defp push(messages, state) do
    frames = Enum.map(messages, &Codec.encode(&1, state.opts))

    if Enum.all?(frames, &match?({:ok, _}, &1)) do
      {:push, Enum.map(frames, fn {:ok, text} -> {:text, text} end), state}
    else
      stop(1008, state)
    end
  end
end
