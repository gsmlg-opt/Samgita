defmodule SamgitaCodexDriver.Transport.WebSocket do
  @moduledoc """
  Native Codex text WebSocket transport with bounded framing and explicit auth.

  `:url` accepts ws/wss without URL credentials, query or fragment. Plaintext
  remote destinations require `:allow_insecure`; platform consumers must also
  perform their own destination authorization. `:connect_address` pins the dialed
  address while the URL hostname remains the TLS/SNI/Host identity. `:token` or
  explicit `:headers` may supply upgrade authentication; Origin and WebSocket
  handshake headers cannot be overridden. No redirect or mutation retry occurs.
  `:tls_opts` permits trust/client-certificate settings, never verify-none.
  """
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaProtocolCodex.Failure
  @limit 8_388_608
  @tls_keys ~w(cacertfile cacerts certfile keyfile password versions depth)a

  @impl true
  def open(opts) do
    with {:ok, uri} <- url(opts[:url], opts),
         :ok <- options(opts),
         {:ok, headers} <- headers(opts) do
      address = Keyword.get(opts, :connect_address, uri.host)

      open_connection(
        uri,
        address,
        uri.port || if(uri.scheme == "wss", do: 443, else: 80),
        headers,
        opts,
        "websocket"
      )
    end
  rescue
    _ -> {:error, Failure.new(:invalid_transport_options)}
  end

  @doc false
  def open_unix(path, opts) do
    with true <-
           is_binary(path) and Path.type(path) == :absolute and not String.contains?(path, <<0>>),
         :ok <- options(opts),
         {:ok, headers} <- headers(opts),
         request_path when is_binary(request_path) <- Keyword.get(opts, :path, "/app-server"),
         true <-
           String.starts_with?(request_path, "/") and
             not String.contains?(request_path, ["?", "#", "\r", "\n"]) and
             request_path != "/daemon/shutdown" do
      uri = %URI{scheme: "ws", host: "localhost", path: request_path}
      open_connection(uri, {:local, String.to_charlist(path)}, 0, headers, opts, "unix_websocket")
    else
      {:error, %Failure{}} = error -> error
      _ -> {:error, Failure.new(:invalid_transport_options)}
    end
  rescue
    _ -> {:error, Failure.new(:invalid_transport_options)}
  end

  defp open_connection(uri, address, port, headers, opts, kind) do
    timeout = Keyword.get(opts, :connect_timeout_ms, 5_000)

    transport_opts = [
      timeout: timeout,
      send_timeout: Keyword.get(opts, :send_timeout_ms, 5_000),
      send_timeout_close: true
    ]

    transport_opts =
      if is_tuple(address) and tuple_size(address) == 8,
        do: transport_opts ++ [inet6: true, inet4: false],
        else: transport_opts

    transport_opts = transport_opts ++ Keyword.get(opts, :tls_opts, [])
    scheme = if uri.scheme == "wss", do: :https, else: :http

    case Mint.HTTP.connect(scheme, address, port,
           hostname: uri.host,
           mode: :passive,
           protocols: [:http1],
           transport_opts: transport_opts
         ) do
      {:ok, conn} ->
        state = %{
          conn: conn,
          websocket: nil,
          ref: nil,
          max_message_bytes: Keyword.get(opts, :max_message_bytes, @limit),
          max_frame_bytes:
            Keyword.get(opts, :max_frame_bytes, Keyword.get(opts, :max_message_bytes, @limit)),
          max_read_bytes:
            Keyword.get(
              opts,
              :max_read_bytes,
              max(65_536, Keyword.get(opts, :max_message_bytes, @limit) + 14)
            ),
          kind: kind,
          prebuffer_ref: make_ref(),
          peer_max_frame_bytes: nil
        }

        scheme = if uri.scheme == "wss", do: :wss, else: :ws

        case Mint.WebSocket.upgrade(scheme, conn, uri.path || "/app-server", headers) do
          {:ok, conn, ref} ->
            handshake(%{state | conn: conn, ref: ref}, now() + timeout, nil, [], [])

          {:error, conn, _} ->
            Mint.HTTP.close(conn)
            {:error, Failure.new(:websocket_upgrade_failed)}
        end

      {:error, _} ->
        {:error, Failure.new(:transport_connect_failed)}
    end
  end

  defp handshake(state, deadline, status, headers, data) do
    case Mint.WebSocket.recv(state.conn, 0, max(deadline - now(), 0)) do
      {:ok, conn, responses} ->
        status =
          Enum.find_value(responses, status, fn
            {:status, ref, value} when ref == state.ref -> value
            _ -> nil
          end)

        headers =
          Enum.find_value(responses, headers, fn
            {:headers, ref, value} when ref == state.ref -> value
            _ -> nil
          end)

        incoming = for {:data, ref, bytes} <- responses, ref == state.ref, do: bytes
        data = data ++ incoming
        state = %{state | conn: conn}

        cond do
          status && status != 101 ->
            upgrade_error(state, status, headers)

          Enum.reduce(data, 0, &(byte_size(&1) + &2)) > state.max_read_bytes ->
            Mint.HTTP.close(conn)
            {:error, Failure.new(:read_too_large)}

          Enum.member?(responses, {:done, state.ref}) ->
            finish_handshake(state, status, headers, data)

          now() >= deadline ->
            Mint.HTTP.close(conn)
            {:error, Failure.new(:transport_connect_timeout)}

          true ->
            handshake(state, deadline, status, headers, data)
        end

      {:error, conn, _, _} ->
        Mint.HTTP.close(conn)
        {:error, Failure.new(:websocket_upgrade_failed)}
    end
  end

  defp finish_handshake(state, status, headers, data) do
    with {:ok, conn, websocket} <- Mint.WebSocket.new(state.conn, state.ref, status, headers),
         {:ok, conn} <- Mint.HTTP.set_mode(conn, :active) do
      for bytes <- data,
          bytes != <<>>,
          do: Kernel.send(self(), {:codex_websocket_prebuffer, state.prebuffer_ref, bytes})

      peer_limit =
        Enum.find_value(headers, fn
          {"x-codex-websocket-max-unfragmented-message-bytes", value} ->
            case Integer.parse(value) do
              {number, ""} when number > 0 -> number
              _ -> nil
            end

          _ ->
            nil
        end)

      {:ok, %{state | conn: conn, websocket: websocket, peer_max_frame_bytes: peer_limit}}
    else
      _ -> upgrade_error(state, status, headers)
    end
  end

  defp upgrade_error(state, status, headers) do
    Mint.HTTP.close(state.conn)

    code =
      cond do
        status in [401, 403] -> :transport_unauthorized
        status == 429 -> :transport_rate_limited
        true -> :websocket_upgrade_failed
      end

    retry_after =
      Enum.find_value(headers, fn
        {"retry-after", value} when byte_size(value) <= 64 ->
          if Regex.match?(
               ~r/\A(?:[0-9]+|[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} GMT)\z/,
               value
             ),
             do: value

        _ ->
          nil
      end)

    details =
      %{"http_status" => status, "retry_after" => retry_after}
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    {:error, Failure.new(code, details)}
  end

  @impl true
  def send(%{conn: nil} = state, _), do: {:error, Failure.new(:transport_closed), state}

  def send(state, json) when is_binary(json) do
    limit = min(state.max_message_bytes, state.peer_max_frame_bytes || state.max_message_bytes)

    if byte_size(json) > limit,
      do: {:error, Failure.new(:message_too_large), state},
      else: send_frame(state, {:text, json})
  end

  def send(state, _), do: {:error, Failure.new(:invalid_message), state}

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
      {:ok, %{state | websocket: websocket, conn: conn}}
    else
      _ -> failure(state, :transport_send_failed)
    end
  end

  @impl true
  def handle_info({:codex_websocket_prebuffer, ref, data}, %{prebuffer_ref: ref} = state),
    do: decode(state, data)

  def handle_info(_, %{conn: nil}), do: :unknown

  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      :unknown ->
        :unknown

      {:ok, conn, responses} ->
        responses(%{state | conn: conn}, responses, [])

      {:error, conn, _, responses} ->
        case responses(%{state | conn: conn}, responses, []) do
          {:ok, events, %{conn: nil} = next} ->
            {:ok, events, next}

          {:ok, events, next} ->
            close(next)
            {:ok, events ++ [{:closed, %{}}], %{next | conn: nil}}

          other ->
            other
        end
    end
  end

  defp responses(state, [], acc), do: {:ok, acc, state}

  defp responses(state, [{:data, ref, bytes} | rest], acc) when ref == state.ref do
    case decode(state, bytes) do
      {:ok, events, next} -> responses(next, rest, acc ++ events)
      other -> other
    end
  end

  defp responses(state, [_ | rest], acc), do: responses(state, rest, acc)

  defp decode(%{conn: nil} = state, _), do: {:ok, [], state}

  defp decode(state, data) do
    buffered = byte_size(state.websocket.buffer)

    if byte_size(data) > state.max_read_bytes or buffered + byte_size(data) > state.max_read_bytes do
      failure(state, :read_too_large)
    else
      case check_frames(state.websocket.buffer <> data, state.max_frame_bytes) do
        :ok -> decode_frames(state, data)
        {:error, code} -> failure(state, code)
      end
    end
  end

  defp decode_frames(state, data) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        fragment = if websocket.fragment, do: byte_size(elem(websocket.fragment, 3)), else: 0

        cond do
          fragment > state.max_message_bytes ->
            failure(state, :message_too_large)

          byte_size(websocket.buffer) > state.max_frame_bytes + 14 ->
            failure(state, :frame_too_large)

          true ->
            frames(%{state | websocket: websocket}, frames, [])
        end

      {:error, _, _} ->
        failure(state, :invalid_websocket_frame)
    end
  end

  # Reject an oversized advertised frame before accumulating its payload. Each
  # read may contain several complete frames, so count per frame, not per read.
  defp check_frames(
         <<final::1, reserved::3, opcode::4, masked::1, length::7, rest::binary>>,
         limit
       ) do
    cond do
      reserved != 0 or masked != 0 or opcode not in [0, 1, 2, 8, 9, 10] ->
        {:error, :invalid_websocket_frame}

      opcode >= 8 and (final != 1 or length > 125) ->
        {:error, :invalid_websocket_frame}

      true ->
        case frame_length(length, rest) do
          {:ok, bytes, payload} when bytes <= limit ->
            if byte_size(payload) >= bytes do
              <<_::binary-size(bytes), tail::binary>> = payload
              check_frames(tail, limit)
            else
              :ok
            end

          {:ok, _, _} ->
            {:error, :frame_too_large}

          :partial ->
            :ok
        end
    end
  end

  defp check_frames(_, _), do: :ok
  defp frame_length(126, <<length::16, rest::binary>>), do: {:ok, length, rest}
  defp frame_length(127, <<length::64, rest::binary>>), do: {:ok, length, rest}
  defp frame_length(length, rest) when length < 126, do: {:ok, length, rest}
  defp frame_length(_, _), do: :partial

  defp frames(state, [], acc), do: {:ok, Enum.reverse(acc), state}

  defp frames(state, [{:text, json} | rest], acc) do
    if byte_size(json) <= state.max_message_bytes,
      do: frames(state, rest, [{:message, json} | acc]),
      else: failure(state, :message_too_large)
  end

  defp frames(state, [{:ping, payload} | rest], acc) do
    case send_frame(state, {:pong, payload}) do
      {:ok, state} -> frames(state, rest, acc)
      other -> other
    end
  end

  defp frames(state, [{:pong, _} | rest], acc), do: frames(state, rest, acc)

  defp frames(state, [{:close, code, _reason} | _], acc) do
    _ = send_frame(state, {:close, code, ""})
    close(%{state | websocket: nil})
    {:ok, Enum.reverse([{:closed, %{"close_code" => code}} | acc]), %{state | conn: nil}}
  end

  defp frames(state, [{:binary, _} | _], _), do: failure(state, :unsupported_binary_frame)
  defp frames(state, [_ | _], _), do: failure(state, :invalid_websocket_frame)

  defp failure(state, code) do
    close(state)
    {:error, Failure.new(code), %{state | conn: nil}}
  end

  @impl true
  def close(%{conn: nil}), do: :ok

  def close(state) do
    if state.websocket do
      with {:ok, _, data} <- Mint.WebSocket.encode(state.websocket, {:close, 1000, ""}) do
        Mint.WebSocket.stream_request_body(state.conn, state.ref, data)
      end
    end

    Mint.HTTP.close(state.conn)
    :ok
  rescue
    _ -> :ok
  end

  @impl true
  def metadata(state),
    do: %{
      "transport" => state.kind,
      "owned_process" => false,
      "max_message_bytes" => state.max_message_bytes,
      "max_frame_bytes" => state.max_frame_bytes,
      "max_read_bytes" => state.max_read_bytes,
      "peer_max_frame_bytes" => state.peer_max_frame_bytes
    }

  defp url(value, opts) when is_binary(value) do
    uri = URI.parse(value)
    address = opts[:connect_address]

    valid =
      uri.scheme in ~w(ws wss) and is_binary(uri.host) and uri.host != "" and
        is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
        (is_nil(uri.port) or uri.port in 1..65_535) and valid_address?(address) and
        not String.contains?(value, ["\r", "\n", <<0>>])

    secure =
      uri.scheme == "wss" or opts[:allow_insecure] == true or
        (uri.host in ~w(localhost 127.0.0.1 ::1) and (is_nil(address) or loopback?(address)))

    if valid and secure, do: {:ok, uri}, else: {:error, Failure.new(:invalid_transport_options)}
  end

  defp url(_, _), do: {:error, Failure.new(:invalid_transport_options)}
  defp valid_address?(nil), do: true

  defp valid_address?(address) when is_tuple(address) and tuple_size(address) == 4,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 in 0..255))

  defp valid_address?(address) when is_tuple(address) and tuple_size(address) == 8,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) and &1 in 0..65_535))

  defp valid_address?(_), do: false
  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp options(opts) do
    integers = [
      :max_message_bytes,
      :max_frame_bytes,
      :max_read_bytes,
      :connect_timeout_ms,
      :send_timeout_ms
    ]

    tls = Keyword.get(opts, :tls_opts, [])

    if Enum.all?(integers, fn name ->
         not Keyword.has_key?(opts, name) or (is_integer(opts[name]) and opts[name] > 0)
       end) and
         Keyword.keyword?(tls) and Enum.all?(Keyword.keys(tls), &(&1 in @tls_keys)),
       do: :ok,
       else: {:error, Failure.new(:invalid_transport_options)}
  end

  defp headers(opts) do
    headers = Keyword.get(opts, :headers, [])
    token = opts[:token]

    if is_list(headers) and
         Enum.all?(headers, fn
           {name, value} when is_binary(name) and is_binary(value) ->
             String.match?(name, ~r/\A[!#$%&'*+.^_`|~0-9a-zA-Z-]+\z/) and
               String.downcase(name) not in ~w(origin host connection upgrade) and
               not String.starts_with?(String.downcase(name), "sec-websocket-") and
               not String.contains?(value, ["\r", "\n", <<0>>])

           _ ->
             false
         end) and
         (is_nil(token) or
            (is_binary(token) and token != "" and byte_size(token) <= 16_384 and
               not String.contains?(token, ["\r", "\n", <<0>>]))) and
         not (is_binary(token) and
                Enum.any?(headers, fn {name, _} -> String.downcase(name) == "authorization" end)) do
      headers = Enum.map(headers, fn {name, value} -> {String.downcase(name), value} end)

      {:ok,
       if(is_binary(token), do: [{"authorization", "Bearer " <> token} | headers], else: headers)}
    else
      {:error, Failure.new(:invalid_transport_options)}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
