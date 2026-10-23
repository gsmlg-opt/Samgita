defmodule SamgitaProtocolWebSocket.ClientControlFramesTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolWebSocket.Client

  setup do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_ip, port}} = :inet.sockname(listener)
    owner = self()
    peer = spawn_link(fn -> accept(listener, owner) end)
    {:ok, client} = Client.connect("ws://127.0.0.1:#{port}/app-server", max_frame_bytes: 1_024)
    assert_receive :upgraded

    on_exit(fn ->
      # ExUnit's owner is gone before on_exit; let its monitor stop the client.
      monitor = Process.monitor(client)
      assert_receive {:DOWN, ^monitor, :process, ^client, _}, 1_000

      send(peer, :stop)
      :gen_tcp.close(listener)
    end)

    %{client: client, peer: peer}
  end

  test "long idle ping and pong traffic consumes no unread budget", %{client: client, peer: peer} do
    for _ <- 1..20 do
      send_bytes(peer, frame(10, String.duplicate("p", 125)))
      ping(peer)
      state = :sys.get_state(client)
      assert state.conn != nil
      assert state.unread_bytes == 0
    end
  end

  test "fragmented text survives interleaved control frames and split frame reads", %{
    client: client,
    peer: peer
  } do
    ready(client)
    text = notification()
    <<first::binary-size(40), rest::binary>> = text
    send_bytes(peer, frame(1, first, 0))
    ping(peer)
    assert :sys.get_state(client).unread_bytes == byte_size(first)
    tail = frame(0, rest)
    <<header::binary-size(1), remaining::binary>> = tail
    send_bytes(peer, header)
    send_bytes(peer, remaining)
    assert_receive {:samgita_protocol, ^client, {:notification, %{"method" => "thread/started"}}}
    assert :sys.get_state(client).unread_bytes == 0
  end

  test "a text frame cannot erase a following incomplete frame's budget", %{
    client: client,
    peer: peer
  } do
    ready(client)
    partial = frame(1, String.duplicate("x", 1_000))
    <<partial::binary-size(900), _::binary>> = partial
    send_bytes(peer, frame(1, notification()) <> partial)
    assert_receive {:samgita_protocol, ^client, {:notification, _}}
    assert :sys.get_state(client).unread_bytes == byte_size(partial)
  end

  test "control frames fit alongside a fragmented message near its size limit", %{
    client: client,
    peer: peer
  } do
    ready(client)
    text = String.pad_trailing(notification(), 1_024)
    <<first::binary-size(1_000), rest::binary>> = text
    send_bytes(peer, frame(1, first, 0))
    assert eventually(fn -> :sys.get_state(client).unread_bytes == 1_000 end, 100)
    ping(peer)
    assert :sys.get_state(client).unread_bytes == 1_000
    send_bytes(peer, frame(0, rest))
    assert_receive {:samgita_protocol, ^client, {:notification, _}}
    assert :sys.get_state(client).unread_bytes == 0
  end

  for opcode <- [9, 10] do
    test "oversized control opcode #{opcode} still disconnects", %{client: client, peer: peer} do
      send_bytes(peer, frame(unquote(opcode), String.duplicate("x", 1_100)))
      assert_disconnected(client)
    end
  end

  test "an unfinished fragmented message is bounded before its final frame", %{
    client: client,
    peer: peer
  } do
    send_bytes(peer, frame(1, String.duplicate("x", 1_000), 0))
    assert eventually(fn -> :sys.get_state(client).unread_bytes == 1_000 end, 100)
    ping(peer)
    send_bytes(peer, frame(0, String.duplicate("x", 30), 0))
    assert_disconnected(client)
  end

  test "oversized frames and fragmented messages still disconnect", %{client: client, peer: peer} do
    send_bytes(peer, frame(1, String.duplicate("x", 1_100)))
    assert_disconnected(client)
  end

  test "control frames do not erase an oversized fragmented message", %{
    client: client,
    peer: peer
  } do
    ready(client)
    send_bytes(peer, frame(1, String.duplicate("x", 600), 0))
    ping(peer)
    send_bytes(peer, frame(0, String.duplicate("x", 600)))
    assert_disconnected(client)
  end

  defp ready(client) do
    :sys.replace_state(client, fn state ->
      %{state | core: SamgitaProtocol.Client.establish(state.core, ["sessions.v1"], "test")}
    end)
  end

  defp notification do
    JSON.encode!(%{
      "schema_version" => "1.0",
      "type" => "notification",
      "method" => "thread/started",
      "params" => %{"thread_id" => "thread"},
      "correlation_id" => "test"
    })
  end

  defp ping(peer) do
    send_bytes(peer, frame(9, String.duplicate("p", 125)))
    send(peer, {:recv, self()})
    assert_receive {:peer_received, {:ok, <<0x8A, _::binary>>}}, 1_000
  end

  defp send_bytes(peer, bytes) do
    send(peer, {:send, bytes, self()})
    assert_receive :sent
  end

  defp frame(opcode, payload, fin \\ 1) do
    size = byte_size(payload)
    length = if size <= 125, do: <<0::1, size::7>>, else: <<0::1, 126::7, size::16>>
    <<fin::1, 0::3, opcode::4, length::binary, payload::binary>>
  end

  defp accept(listener, owner) do
    {:ok, socket} = :gen_tcp.accept(listener)
    {:ok, request} = :gen_tcp.recv(socket, 0, 1_000)
    [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)
    accept = :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n"
      )

    send(owner, :upgraded)
    serve(socket)
  end

  defp serve(socket) do
    receive do
      {:send, bytes, caller} ->
        :ok = :gen_tcp.send(socket, bytes)
        send(caller, :sent)
        serve(socket)

      {:recv, caller} ->
        send(caller, {:peer_received, :gen_tcp.recv(socket, 0, 500)})
        serve(socket)

      :stop ->
        :gen_tcp.close(socket)
    end
  end

  defp assert_disconnected(client) do
    # The peer's send acknowledgement precedes TCP delivery; synchronize by polling state.
    assert eventually(fn -> :sys.get_state(client).conn == nil end, 100)
  end

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        attempts > 0 and
          (
            Process.sleep(5)
            eventually(fun, attempts - 1)
          )
  end
end
