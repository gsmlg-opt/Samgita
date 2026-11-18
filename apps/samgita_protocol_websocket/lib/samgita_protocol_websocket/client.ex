defmodule SamgitaProtocolWebSocket.Client do
  @moduledoc """
  A bounded, explicitly connected WebSocket client; reconnect never replays requests.

  Hosts may provide `:connect_address` as a validated IPv4/IPv6 tuple after destination approval.
  The socket dials that tuple directly while the URL hostname still controls Host, TLS hostname
  verification and SNI. The transport does not follow redirects or approve destinations itself.
  Failed upgrades retain only HTTP status and a syntactically bounded Retry-After value.

  Connected sockets send a ping every `:keepalive_ms` (20 seconds by default; `false`
  disables it). The owner receives `{:samgita_protocol, pid, :disconnected}` once
  when an open transport disconnects. Reconnecting and native initialization remain explicit.
  """
  use GenServer
  alias HTTP.WebSocket, as: Socket
  alias HTTP.WebSocket.Event.{Close, Frame, Message, Open}
  alias HTTP.WebSocket.Event.Error, as: SocketError
  alias SamgitaProtocol.{Client, Codec, Error}

  @cleanup_timeout 1_000
  @control_payload_bytes 125

  def connect(url, opts \\ []) do
    with {:ok, uri} <- validate_url(url, opts),
         :ok <- validate_keepalive(opts),
         {:ok, core} <- Client.new(opts) do
      GenServer.start(__MODULE__, {uri, Keyword.put_new(opts, :owner, self()), core})
    end
  end

  def request(pid, method, params, opts \\ []) do
    # The connection owns the bounded timer, including its configured default.
    GenServer.call(pid, {:request, method, params, opts}, :infinity)
  end

  def reply(pid, request, result), do: GenServer.call(pid, {:reply, request, result})
  def reconnect(pid), do: GenServer.call(pid, :reconnect, 10_000)
  def close(pid), do: GenServer.stop(pid, :normal)
  def ack_cursor(pid, stream, cursor), do: GenServer.call(pid, {:ack_cursor, stream, cursor})
  def checkpoints(pid), do: GenServer.call(pid, :checkpoints)
  def replay_cursor(pid, stream), do: GenServer.call(pid, {:replay_cursor, stream})

  def resolve_uncertain(pid, command_id, evidence),
    do: GenServer.call(pid, {:resolve_uncertain, command_id, evidence})

  @impl true
  def init({uri, opts, core}) do
    owner = Keyword.fetch!(opts, :owner)

    state = %{
      uri: uri,
      opts: opts,
      owner: owner,
      owner_monitor: Process.monitor(owner),
      core: core,
      conn: nil,
      keepalive: nil,
      pending: %{}
    }

    case open(state) do
      {:ok, state} -> {:ok, state}
      {:error, error} -> {:stop, error}
    end
  end

  @impl true
  def handle_call({:request, method, params, opts}, from, state) do
    case Client.request(state.core, method, params, opts) do
      {:ok, message, core} ->
        state = %{state | core: core}

        case send_message(state, message) do
          {:ok, state} ->
            id = message["id"]

            wait =
              Keyword.get(opts, :timeout_ms, Keyword.get(state.opts, :request_timeout_ms, 30_000))

            timer = Process.send_after(self(), {:expire, id}, wait)

            {:noreply,
             %{
               state
               | pending: Map.put(state.pending, id, %{from: from, timer: timer, method: method})
             }}

          {:error, state} ->
            state = %{
              state
              | pending:
                  Map.put(state.pending, message["id"], %{from: from, timer: nil, method: method})
            }

            {:noreply, disconnected(state)}
        end

      {:error, error, core} ->
        {:reply, {:error, error}, %{state | core: core}}
    end
  end

  def handle_call({:reply, request, result}, _from, state) do
    case Client.reply(state.core, request, result) do
      {:ok, message, core} ->
        case send_message(%{state | core: core}, message) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, state} -> {:reply, {:error, Error.new("disconnected")}, disconnected(state)}
        end

      {:error, error, core} ->
        {:reply, {:error, error}, %{state | core: core}}
    end
  end

  def handle_call(:reconnect, _from, state) do
    state = disconnected(state)
    {:ok, core} = Client.reconnect(state.core)

    case open(%{state | core: core}) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:ack_cursor, stream, cursor}, _from, state) do
    case Client.ack_cursor(state.core, stream, cursor) do
      {:ok, core} -> {:reply, :ok, %{state | core: core}}
      {:error, error, core} -> {:reply, {:error, error}, %{state | core: core}}
    end
  end

  def handle_call(:checkpoints, _from, state),
    do: {:reply, Client.checkpoints(state.core), state}

  def handle_call({:replay_cursor, stream}, _from, state),
    do: {:reply, Client.replay_cursor(state.core, stream), state}

  def handle_call({:resolve_uncertain, command_id, evidence}, _from, state) do
    case Client.resolve_uncertain(state.core, command_id, evidence) do
      {:ok, request, core} -> {:reply, {:ok, request}, %{state | core: core}}
      {:error, error, core} -> {:reply, {:error, error}, %{state | core: core}}
    end
  end

  @impl true
  def handle_info({:expire, id}, state) do
    if Map.has_key?(state.pending, id) do
      {:ok, effects, core} = Client.expire(state.core, System.monotonic_time(:millisecond))
      {:noreply, apply_effects(effects, %{state | core: core})}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:keepalive, token}, %{keepalive: %{token: token}} = state) do
    state = %{state | keepalive: nil}

    case send_ping(state) do
      :ok -> {:noreply, schedule_keepalive(state)}
      :error -> {:noreply, disconnected(state)}
    end
  end

  def handle_info(
        {Socket, socket, %Frame{opcode: :text, data: text}, ref},
        %{conn: socket} = state
      ) do
    result = receive_frame({:text, text}, state)
    :ok = Socket.acknowledge(socket, ref)
    {:noreply, received(result)}
  end

  def handle_info({Socket, socket, %Frame{opcode: opcode}, ref}, %{conn: socket} = state)
      when opcode in [:ping, :pong] do
    # The transport answers Ping automatically; controls never enter native protocol buffers.
    :ok = Socket.acknowledge(socket, ref)
    {:noreply, state}
  end

  def handle_info({Socket, socket, %Frame{}, ref}, %{conn: socket} = state) do
    :ok = Socket.acknowledge(socket, ref)
    {:noreply, disconnected(state)}
  end

  def handle_info({Socket, socket, %Message{data: text}, ref}, %{conn: socket} = state) do
    result =
      if is_binary(text),
        do: receive_frame({:text, text}, state),
        else: {:disconnect, state}

    :ok = Socket.acknowledge(socket, ref)
    {:noreply, received(result)}
  end

  def handle_info({Socket, socket, event}, %{conn: socket} = state)
      when is_struct(event, SocketError) or is_struct(event, Close),
      do: {:noreply, disconnected(state)}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    state = disconnected(state)

    Enum.each(state.pending, fn {_id, pending} ->
      GenServer.reply(pending.from, {:error, Error.new("disconnected")})
    end)
  end

  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)

  defp validate_url(url, opts) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      invalid_uri?(uri) ->
        {:error, Error.new("invalid_params")}

      not valid_connect_address?(Keyword.get(opts, :connect_address)) ->
        {:error, Error.new("invalid_params")}

      uri.scheme == "ws" and uri.host not in ["localhost", "127.0.0.1", "::1"] and
          not Keyword.get(opts, :allow_insecure, false) ->
        {:error, Error.new("invalid_params")}

      true ->
        {:ok, uri}
    end
  end

  defp validate_url(_url, _opts), do: {:error, Error.new("invalid_params")}

  defp invalid_uri?(uri),
    do:
      uri.scheme not in ["ws", "wss"] or is_nil(uri.host) or not is_nil(uri.userinfo) or
        not is_nil(uri.query) or not is_nil(uri.fragment)

  defp valid_connect_address?(nil), do: true

  defp valid_connect_address?(address) when is_tuple(address) and tuple_size(address) == 4,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 in 0..255))

  defp valid_connect_address?(address) when is_tuple(address) and tuple_size(address) == 8,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 in 0..65_535))

  defp valid_connect_address?(_), do: false

  defp validate_keepalive(opts) do
    case Keyword.get(opts, :keepalive_ms, 20_000) do
      false -> :ok
      ms when is_integer(ms) and ms > 0 and ms <= 4_294_967_295 -> :ok
      _ -> {:error, Error.new("invalid_params")}
    end
  end

  defp open(state) do
    timeout = Keyword.get(state.opts, :connect_timeout_ms, 5_000)
    limit = Keyword.get(state.opts, :max_frame_bytes, 1_048_576)
    token = Keyword.get(state.opts, :token)
    headers = if is_binary(token), do: [{"authorization", "Bearer " <> token}], else: []
    uri = %{state.uri | path: state.uri.path || "/app-server"}

    case Socket.new(uri, [],
           owner: self(),
           headers: headers,
           http_version: :http1,
           mode: :proxy,
           connect_address: Keyword.get(state.opts, :connect_address),
           connect_timeout: timeout,
           opening_timeout: timeout,
           write_timeout: Keyword.get(state.opts, :send_timeout_ms, 5_000),
           close_timeout: 100,
           max_message_size: limit,
           max_frame_bytes: limit,
           # Admit one native frame plus an interleaved control frame, including headers.
           # Proxy control deliveries also need room beside one native ACK delivery.
           max_read_bytes: limit + 14 + @control_payload_bytes + 14,
           max_send_queue: limit,
           delivery: :ack,
           max_queue_bytes: max(limit, @control_payload_bytes) + 7 + @control_payload_bytes + 7,
           max_queue_events: Keyword.get(state.opts, :max_buffer, 128),
           telemetry_url: nil
         ) do
      %Socket{} = socket -> await_open(%{state | conn: socket}, timeout)
      {:error, _} -> {:error, Error.new("upstream_error")}
    end
  end

  defp await_open(%{conn: socket} = state, timeout) do
    receive do
      {Socket, ^socket, %Open{}} ->
        {:ok, schedule_keepalive(state)}

      {Socket, ^socket, %SocketError{handshake: handshake}} ->
        close_connection(state)
        details = handshake_details(handshake)
        code = if details["http_status"] in [401, 403], do: "unauthorized", else: "upstream_error"
        {:error, Error.new(code, details)}

      {Socket, ^socket, %Close{}} ->
        close_connection(state)
        {:error, Error.new("upstream_error")}
    after
      timeout ->
        close_connection(state)
        {:error, Error.new("upstream_error")}
    end
  end

  defp handshake_details(%{status: status, headers: headers}),
    do: upgrade_details(status, headers.headers)

  defp handshake_details(_), do: %{}

  defp upgrade_details(status, headers) when is_integer(status) do
    retry_after = Enum.find_value(headers, &retry_after/1)

    Map.reject(%{"http_status" => status, "retry_after" => retry_after}, fn {_, value} ->
      is_nil(value)
    end)
  end

  defp upgrade_details(_status, _headers), do: %{}

  defp retry_after({"retry-after", value}) when is_binary(value) and byte_size(value) <= 64 do
    if Regex.match?(
         ~r/\A(?:[0-9]+|[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} GMT)\z/,
         value
       ),
       do: value
  end

  defp retry_after(_), do: nil

  defp schedule_keepalive(state) do
    case Keyword.get(state.opts, :keepalive_ms, 20_000) do
      false ->
        state

      ms ->
        token = make_ref()
        timer = Process.send_after(self(), {:keepalive, token}, ms)
        %{state | keepalive: %{timer: timer, token: token}}
    end
  end

  defp cancel_keepalive(%{keepalive: nil} = state), do: state

  defp cancel_keepalive(state) do
    Process.cancel_timer(state.keepalive.timer)
    %{state | keepalive: nil}
  end

  defp send_ping(%{conn: socket} = state) when not is_nil(socket) do
    case Socket.send_frame_ack(socket, {:ping, ""}) do
      {:ok, ref} ->
        receive do
          {Socket, ^socket, {:send_result, ^ref, :ok}} -> :ok
          {Socket, ^socket, {:send_result, ^ref, {:error, _}}} -> :error
        after
          Keyword.get(state.opts, :send_timeout_ms, 5_000) -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp send_ping(_state), do: :error

  defp send_message(%{conn: nil} = state, _message), do: {:error, state}

  defp send_message(%{conn: socket} = state, message) do
    with {:ok, text} <- Codec.encode(message, state.opts),
         {:ok, ref} <- Socket.send_ack(socket, text) do
      receive do
        {Socket, ^socket, {:send_result, ^ref, :ok}} -> {:ok, state}
        {Socket, ^socket, {:send_result, ^ref, {:error, _}}} -> {:error, state}
      after
        Keyword.get(state.opts, :send_timeout_ms, 5_000) -> {:error, state}
      end
    else
      _ -> {:error, state}
    end
  end

  defp receive_frame({:text, text}, state) do
    case Client.receive(state.core, text) do
      {:ok, effects, core} ->
        with {:ok, effects, core} <- expand_replay(effects, core, state),
             true <- effects_fit?(effects, state) do
          state = apply_effects(effects, %{state | core: core})
          {_messages, core} = Client.drain(state.core, Keyword.get(state.opts, :max_buffer, 128))
          {:ok, %{state | core: core}}
        else
          _ ->
            # Receiving is pure: retain the prior cursor when nothing was forwarded.
            {:disconnect, state}
        end

      {:error, error, core} ->
        send(state.owner, {:samgita_protocol, self(), {:error, error}})
        {:disconnect, %{state | core: core}}
    end
  end

  # Settle the current delivery before closing; cleanup also waits for its ACK.
  defp received({:ok, state}), do: state
  defp received({:disconnect, state}), do: disconnected(state)

  defp apply_effects(effects, state) do
    Enum.reduce(effects, state, fn
      {:response, id, result}, state ->
        settle(id, {:ok, result}, state)

      {:error, id, error}, state ->
        settle(id, {:error, error}, state)

      effect, state ->
        send(state.owner, {:samgita_protocol, self(), effect})
        state
    end)
  end

  defp effects_fit?(effects, state) do
    forwarded = Enum.count(effects, &match?({kind, _} when kind in [:notification, :request], &1))

    case {forwarded, Process.info(state.owner, :message_queue_len)} do
      {0, _} -> true
      {n, {:message_queue_len, count}} -> count + n <= Keyword.get(state.opts, :max_buffer, 128)
      _ -> false
    end
  end

  defp expand_replay([{:response, id, result}] = effects, core, state) do
    case state.pending[id] do
      %{method: "stream/resume"} ->
        case Client.receive_replay(core, result) do
          {:ok, replay_effects, core} -> {:ok, replay_effects ++ effects, core}
          {:error, error, _core} -> {:error, error}
        end

      _ ->
        {:ok, effects, core}
    end
  end

  defp expand_replay(effects, core, _state), do: {:ok, effects, core}

  defp settle(id, result, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        state

      {%{from: from, timer: timer}, pending} ->
        if timer, do: Process.cancel_timer(timer)
        GenServer.reply(from, result)
        %{state | pending: pending}
    end
  end

  defp disconnected(%{conn: nil} = state), do: cancel_keepalive(state)

  defp disconnected(state) do
    state = cancel_keepalive(state)
    close_connection(state)
    {:ok, effects, core} = Client.disconnect(state.core)
    state = %{state | conn: nil, core: core}
    state = apply_effects(effects, state)
    send(state.owner, {:samgita_protocol, self(), :disconnected})
    state
  end

  defp close_connection(%{conn: nil}), do: :ok

  defp close_connection(%{conn: socket}) do
    _ = Socket.close(socket, 1000, "")
    receipt = Socket.completion(socket)
    await_cleanup(socket, receipt, System.monotonic_time(:millisecond) + @cleanup_timeout)
  end

  defp await_cleanup(socket, receipt, deadline) do
    case HTTP.ClientCompletion.await(receipt, 0) do
      :ok ->
        :ok

      {:error, :cleanup_pending} ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        if remaining == 0 do
          raise Error.new("upstream_error", %{"cleanup" => "unconfirmed"})
        else
          # This process owns ACK delivery. A synchronous wait alone would strand
          # already delivered Pong/native frames and prevent transport cleanup.
          receive do
            {Socket, ^socket, event, ref}
            when is_struct(event, Frame) or is_struct(event, Message) ->
              :ok = Socket.acknowledge(socket, ref)
              await_cleanup(socket, receipt, deadline)
          after
            min(remaining, 10) -> await_cleanup(socket, receipt, deadline)
          end
        end

      _error ->
        raise Error.new("upstream_error", %{"cleanup" => "unconfirmed"})
    end
  end
end
