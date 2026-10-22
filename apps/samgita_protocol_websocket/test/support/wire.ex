defmodule SamgitaProtocolWebSocket.TestWire do
  @moduledoc false

  def connect(url, token) do
    uri = URI.parse(url)

    {:ok, conn} =
      Mint.HTTP.connect(:http, uri.host, uri.port, mode: :passive, protocols: [:http1])

    {:ok, conn, ref} =
      Mint.WebSocket.upgrade(:ws, conn, uri.path, [{"authorization", "Bearer " <> token}])

    handshake(conn, ref, nil, [])
  end

  defp handshake(conn, ref, status, headers) do
    {:ok, conn, responses} = Mint.WebSocket.recv(conn, 0, 1_000)

    status =
      Enum.find_value(responses, status, fn
        {:status, ^ref, n} -> n
        _ -> nil
      end)

    headers =
      Enum.find_value(responses, headers, fn
        {:headers, ^ref, h} -> h
        _ -> nil
      end)

    if {:done, ref} in responses do
      {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status, headers)
      %{conn: conn, ref: ref, websocket: websocket}
    else
      handshake(conn, ref, status, headers)
    end
  end

  def send_frame(wire, frame) do
    {:ok, websocket, data} = Mint.WebSocket.encode(wire.websocket, frame)
    {:ok, conn} = Mint.WebSocket.stream_request_body(wire.conn, wire.ref, data)
    %{wire | conn: conn, websocket: websocket}
  end

  def receive_frame(wire) do
    case Mint.WebSocket.recv(wire.conn, 0, 1_000) do
      {:ok, conn, [{:data, _ref, data}]} ->
        {:ok, websocket, frames} = Mint.WebSocket.decode(wire.websocket, data)
        wire = %{wire | conn: conn, websocket: websocket}

        case frames do
          [frame | _] -> {frame, wire}
          [] -> receive_frame(wire)
        end

      {:error, conn, reason, _} ->
        {{:transport_error, reason}, %{wire | conn: conn}}
    end
  end

  def close(wire), do: Mint.HTTP.close(wire.conn)
end
