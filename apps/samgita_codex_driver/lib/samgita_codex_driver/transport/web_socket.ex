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
  alias HTTP.WebSocket, as: Socket
  alias HTTP.WebSocket.Event.{Close, Error, Message, Open}
  alias SamgitaProtocolCodex.Error, as: DriverError

  @limit 8_388_608
  @cleanup_timeout 1_000
  @close_timeout 100
  @tls_keys ~w(cacertfile cacerts certfile keyfile password versions depth)a

  @impl true
  def open(opts) do
    with {:ok, uri} <- url(opts[:url], opts),
         :ok <- options(opts),
         {:ok, headers} <- headers(opts) do
      open_connection(uri, headers, opts, "websocket")
    end
  rescue
    error in DriverError -> {:error, error}
    _ -> {:error, DriverError.new(:invalid_transport_options)}
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

      open_connection(
        uri,
        headers,
        opts |> Keyword.delete(:connect_address) |> Keyword.put(:unix_socket, path),
        "unix_websocket"
      )
    else
      {:error, %DriverError{}} = error -> error
      _ -> {:error, DriverError.new(:invalid_transport_options)}
    end
  rescue
    error in DriverError -> {:error, error}
    _ -> {:error, DriverError.new(:invalid_transport_options)}
  end

  defp open_connection(uri, headers, opts, kind) do
    timeout = Keyword.get(opts, :connect_timeout_ms, 5_000)
    message_limit = Keyword.get(opts, :max_message_bytes, @limit)
    uri = %{uri | path: uri.path || "/app-server"}

    socket_options = [
      owner: self(),
      headers: headers,
      http_version: :http1,
      tls_backend: :ex_ssl,
      ssl: Keyword.get(opts, :tls_opts, []),
      connect_address: Keyword.get(opts, :connect_address),
      unix_socket: Keyword.get(opts, :unix_socket),
      connect_timeout: timeout,
      opening_timeout: timeout,
      write_timeout: Keyword.get(opts, :send_timeout_ms, 5_000),
      close_timeout: @close_timeout,
      max_message_size: message_limit,
      max_frame_bytes: Keyword.get(opts, :max_frame_bytes, message_limit),
      max_read_bytes: Keyword.get(opts, :max_read_bytes, max(65_536, message_limit + 14)),
      max_send_queue: message_limit,
      max_queue_bytes: message_limit + 7,
      delivery: :ack,
      telemetry_url: nil
    ]

    case Socket.new(uri, [], socket_options) do
      %Socket{} = socket ->
        state = %{
          conn: socket,
          max_message_bytes: message_limit,
          max_frame_bytes: socket_options[:max_frame_bytes],
          max_read_bytes: socket_options[:max_read_bytes],
          send_timeout_ms: socket_options[:write_timeout],
          kind: kind,
          peer_max_frame_bytes: nil
        }

        await_open(state, timeout)

      {:error, _} ->
        {:error, DriverError.new(:transport_connect_failed)}
    end
  end

  defp await_open(%{conn: socket} = state, timeout) do
    receive do
      {Socket, ^socket, %Open{handshake: handshake}} ->
        {:ok, %{state | peer_max_frame_bytes: peer_frame_limit(handshake)}}

      {Socket, ^socket, %Error{handshake: handshake, reason: reason}} ->
        close(state)
        upgrade_error(handshake, reason)

      {Socket, ^socket, %Close{}} ->
        close(state)
        {:error, DriverError.new(:websocket_upgrade_failed)}
    after
      timeout ->
        close(state)
        {:error, DriverError.new(:transport_connect_timeout)}
    end
  end

  defp peer_frame_limit(%{headers: headers}) do
    case HTTP.Headers.get(headers, "x-codex-websocket-max-unfragmented-message-bytes") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} when number > 0 -> number
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp peer_frame_limit(_), do: nil

  defp upgrade_error(%{status: status, headers: headers}, _reason) do
    code =
      cond do
        status in [401, 403] -> :transport_unauthorized
        status == 429 -> :transport_rate_limited
        true -> :websocket_upgrade_failed
      end

    details =
      %{"http_status" => status, "retry_after" => retry_after(headers)}
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    {:error, DriverError.new(code, details)}
  end

  defp upgrade_error(_, reason) do
    code =
      if reason in [:timeout, :opening_timeout],
        do: :transport_connect_timeout,
        else: :transport_connect_failed

    {:error, DriverError.new(code)}
  end

  defp retry_after(headers) do
    case HTTP.Headers.get(headers, "retry-after") do
      value when is_binary(value) and byte_size(value) <= 64 ->
        if Regex.match?(
             ~r/\A(?:[0-9]+|[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} GMT)\z/,
             value
           ),
           do: value

      _ ->
        nil
    end
  end

  @impl true
  def send(%{conn: nil} = state, _), do: {:error, DriverError.new(:transport_closed), state}

  def send(state, json) when is_binary(json) do
    limit = min(state.max_message_bytes, state.peer_max_frame_bytes || state.max_message_bytes)

    cond do
      byte_size(json) > limit ->
        {:error, DriverError.new(:message_too_large), state}

      true ->
        case Socket.send_ack(state.conn, json) do
          {:ok, ref} -> await_send(state, ref)
          {:error, _} -> failure(state, :transport_send_failed)
        end
    end
  end

  def send(state, _), do: {:error, DriverError.new(:invalid_message), state}

  defp await_send(%{conn: socket} = state, ref) do
    receive do
      {Socket, ^socket, {:send_result, ^ref, :ok}} ->
        {:ok, state}

      {Socket, ^socket, {:send_result, ^ref, {:error, _}}} ->
        failure(state, :transport_send_failed)
    after
      state.send_timeout_ms -> failure(state, :transport_send_failed)
    end
  end

  @impl true
  def handle_info(_, %{conn: nil}), do: :unknown

  def handle_info({Socket, socket, %Message{data: json}, ref}, %{conn: socket} = state) do
    :ok = Socket.acknowledge(socket, ref)

    if is_binary(json),
      do: {:ok, [{:message, json}], state},
      else: failure(state, :unsupported_binary_frame)
  end

  def handle_info({Socket, socket, %Error{reason: reason}}, %{conn: socket} = state) do
    code =
      case reason do
        :frame_too_big -> :frame_too_large
        :message_too_big -> :message_too_large
        :read_buffer_too_big -> :read_too_large
        _ -> :invalid_websocket_frame
      end

    failure(state, code)
  end

  def handle_info({Socket, socket, %Close{code: code}}, %{conn: socket} = state) do
    close(state)
    {:ok, [{:closed, %{"close_code" => code}}], %{state | conn: nil}}
  end

  def handle_info(_, _state), do: :unknown

  defp failure(state, code) do
    close(state)
    {:error, DriverError.new(code), %{state | conn: nil}}
  end

  @impl true
  def close(%{conn: nil}), do: :ok

  def close(%{conn: socket}) do
    _ = Socket.close(socket, 1000, "")

    case HTTP.ClientCompletion.await(Socket.completion(socket), @cleanup_timeout) do
      :ok -> :ok
      _ -> raise DriverError.new(:owned_process_shutdown_unconfirmed)
    end
  end

  @impl true
  def metadata(state),
    do: %{
      "transport" => state.kind,
      "owned_process" => true,
      "max_message_bytes" => state.max_message_bytes,
      "max_frame_bytes" => state.max_frame_bytes,
      "max_read_bytes" => state.max_read_bytes,
      "peer_max_frame_bytes" => state.peer_max_frame_bytes
    }

  defp url(value, opts) when is_binary(value) do
    uri = URI.parse(value)
    address = opts[:connect_address]

    valid = valid_uri?(uri) and valid_address?(address) and safe_header_value?(value)

    if valid and secure_destination?(uri, address, opts),
      do: {:ok, uri},
      else: {:error, DriverError.new(:invalid_transport_options)}
  end

  defp url(_, _), do: {:error, DriverError.new(:invalid_transport_options)}

  defp valid_uri?(uri),
    do:
      uri.scheme in ~w(ws wss) and is_binary(uri.host) and uri.host != "" and
        is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
        (is_nil(uri.port) or uri.port in 1..65_535)

  defp secure_destination?(uri, address, opts),
    do:
      uri.scheme == "wss" or opts[:allow_insecure] == true or
        (uri.host in ~w(localhost 127.0.0.1 ::1) and (is_nil(address) or loopback?(address)))

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
       else: {:error, DriverError.new(:invalid_transport_options)}
  end

  defp headers(opts) do
    headers = Keyword.get(opts, :headers, [])
    token = opts[:token]

    if valid_headers?(headers) and valid_token?(token) and not duplicate_token?(token, headers) do
      headers = Enum.map(headers, fn {name, value} -> {String.downcase(name), value} end)

      {:ok,
       if(is_binary(token), do: [{"authorization", "Bearer " <> token} | headers], else: headers)}
    else
      {:error, DriverError.new(:invalid_transport_options)}
    end
  end

  defp valid_headers?(headers), do: is_list(headers) and Enum.all?(headers, &valid_header?/1)

  defp valid_header?({name, value}) when is_binary(name) and is_binary(value),
    do:
      String.match?(name, ~r/\A[!#$%&'*+.^_`|~0-9a-zA-Z-]+\z/) and
        String.downcase(name) not in ~w(origin host connection upgrade) and
        not String.starts_with?(String.downcase(name), "sec-websocket-") and
        safe_header_value?(value)

  defp valid_header?(_), do: false
  defp safe_header_value?(value), do: not String.contains?(value, ["\r", "\n", <<0>>])
  defp valid_token?(nil), do: true

  defp valid_token?(token),
    do:
      is_binary(token) and token != "" and byte_size(token) <= 16_384 and
        safe_header_value?(token)

  defp duplicate_token?(token, headers),
    do:
      is_binary(token) and
        Enum.any?(headers, fn {name, _} -> String.downcase(name) == "authorization" end)
end
