defmodule SamgitaProtocolWebSocket.ClientKeepaliveTest do
  @moduledoc "Functional lifecycle checks against an owned loopback host with fixed fixture credentials."
  use ExUnit.Case, async: true

  alias __MODULE__.Handler
  alias HTTP.WebSocket
  alias HTTP.WebSocket.Event.Close
  alias SamgitaProtocolWebSocket.{Client, Server}

  test "ping keepalive preserves an otherwise idle socket past the host deadline" do
    {client, _socket} = connect(keepalive_ms: 40)

    refute_receive {:samgita_protocol, ^client, :disconnected}, 750

    # A real native round trip after three idle periods proves the host kept this socket.
    assert {:ok, %{"version" => "1.0"}} = initialize(client)

    assert {:ok, %{"thread_id" => "fixture"}} =
             Client.request(client, "thread/read", %{"thread_id" => "fixture"})
  end

  test "an idle host close is reported without an outstanding request when keepalive is disabled" do
    {client, _socket} = connect(keepalive_ms: false)
    assert :sys.get_state(client).keepalive == nil
    assert_receive {:samgita_protocol, ^client, :disconnected}, 1_500
    assert :sys.get_state(client).conn == nil
    refute_receive {:samgita_protocol, ^client, :disconnected}, 100
  end

  test "server close notifies once and cancels the keepalive timer" do
    {client, socket} = connect(keepalive_ms: 10_000)
    state = :sys.get_state(client)
    assert is_reference(state.keepalive.timer)

    Server.close(socket)
    assert_receive {:samgita_protocol, ^client, :disconnected}, 1_500
    assert Process.read_timer(state.keepalive.timer) == false
    assert :sys.get_state(client).keepalive == nil

    # Error/Close can both arrive for one transport; old events and queued ticks are harmless.
    send(client, {WebSocket, state.conn, %Close{}})
    send(client, {:keepalive, state.keepalive.token})
    assert :sys.get_state(client).conn == nil
    refute_receive {:samgita_protocol, ^client, :disconnected}, 100
  end

  test "explicit reconnect replaces its timer and ignores the old connection's queued tick" do
    {client, _socket} = connect(keepalive_ms: 10_000)
    previous = :sys.get_state(client)
    assert {:ok, _} = initialize(client)

    assert :ok = Client.reconnect(client)
    assert_receive {:samgita_protocol, ^client, :disconnected}
    assert_receive {:lifecycle_socket, _replacement}
    current = :sys.get_state(client)
    assert current.conn != previous.conn
    assert current.keepalive.token != previous.keepalive.token
    assert Process.read_timer(previous.keepalive.timer) == false

    send(client, {:keepalive, previous.keepalive.token})
    assert :sys.get_state(client).keepalive == current.keepalive

    assert {:error, %{code: "not_initialized"}} =
             Client.request(client, "thread/read", %{"thread_id" => "fixture"})

    assert {:ok, _} = initialize(client)

    assert {:ok, %{"thread_id" => "fixture"}} =
             Client.request(client, "thread/read", %{"thread_id" => "fixture"})
  end

  test "a default client schedules keepalive and cancels it when explicitly closed" do
    {client, _socket} = connect([])
    %{keepalive: %{timer: timer}} = :sys.get_state(client)
    assert Process.read_timer(timer) in 1..20_000

    Client.close(client)
    assert_receive {:samgita_protocol, ^client, :disconnected}
    assert Process.read_timer(timer) == false
  end

  for delivery <- [:pong, :notification] do
    test "explicit close drains a queued #{delivery} delivery and confirms cleanup" do
      {client, socket} = connect(keepalive_ms: false)
      assert {:ok, _} = initialize(client)
      transport = :sys.get_state(client).conn
      receipt = WebSocket.completion(transport)
      assert :ok = :sys.suspend(client)

      try do
        queue_delivery(unquote(delivery), transport, socket)

        assert eventually(fn ->
                 case WebSocket.status(transport) do
                   %{queued_events: count} -> count > 0
                   _ -> false
                 end
               end)

        assert {:error, :cleanup_pending} = HTTP.ClientCompletion.await(receipt, 0)
        assert :ok = Client.close(client)
        assert :ok = HTTP.ClientCompletion.await(receipt, 0)
        assert_receive {:samgita_protocol, ^client, :disconnected}
      after
        if Process.alive?(client), do: :sys.resume(client)
      end
    end
  end

  defp queue_delivery(:pong, transport, _socket),
    do: :ok = WebSocket.send_frame(transport, {:ping, "queued-pong"})

  defp queue_delivery(:notification, _transport, socket) do
    Server.notify(socket, %{
      "schema_version" => "1.0",
      "type" => "notification",
      "method" => "thread/started",
      "params" => %{"thread_id" => "fixture"},
      "correlation_id" => "queued-notification"
    })
  end

  defp eventually(fun, attempts \\ 100) do
    if fun.(),
      do: true,
      else:
        attempts > 0 and
          (
            Process.sleep(5)
            eventually(fun, attempts - 1)
          )
  end

  defp connect(opts) do
    owner = self()

    listener =
      start_supervised!(
        {Server,
         port: 0,
         idle_timeout_ms: 250,
         authenticate: fn "lifecycle-fixture" -> {:ok, %{}} end,
         handler: Handler,
         handler_state: fn _principal ->
           send(owner, {:lifecycle_socket, self()})
           nil
         end}
      )

    {:ok, {_address, port}} = Server.listener_info(listener)

    {:ok, client} =
      Client.connect(
        "ws://127.0.0.1:#{port}/app-server",
        Keyword.merge([token: "lifecycle-fixture", capabilities: ["sessions.v1"]], opts)
      )

    assert_receive {:lifecycle_socket, socket}

    on_exit(fn ->
      monitor = Process.monitor(client)
      assert_receive {:DOWN, ^monitor, :process, ^client, _}, 1_500
    end)

    {client, socket}
  end

  defp initialize(client) do
    Client.request(client, "connection/initialize", %{
      "versions" => ["1.0"],
      "capabilities" => ["sessions.v1"]
    })
  end

  defmodule Handler do
    def capabilities, do: ["sessions.v1"]
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())

    def handle_request("thread/read", %{"thread_id" => id}, _context, state),
      do: {:ok, %{"thread_id" => id}, state}
  end
end
