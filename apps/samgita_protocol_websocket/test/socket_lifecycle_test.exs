defmodule SamgitaProtocolWebSocket.SocketLifecycleTest do
  use ExUnit.Case, async: true
  alias __MODULE__.Handler
  alias SamgitaProtocol.{Client, Codec}
  alias SamgitaProtocolWebSocket.Socket

  test "real WebSocket deadlines release read capacity and disconnect reports mutations" do
    owner = self()

    listener =
      start_supervised!(
        {SamgitaProtocolWebSocket.Server,
         port: 0,
         max_pending: 1,
         request_timeout_ms: 20,
         authenticate: fn "fixture" -> {:ok, %{}} end,
         handler: Handler,
         handler_state: fn _ ->
           send(owner, {:socket, self()})
           owner
         end}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(listener)

    {:ok, client} =
      SamgitaProtocolWebSocket.Client.connect("ws://127.0.0.1:#{port}/app-server",
        token: "fixture",
        capabilities: Handler.capabilities()
      )

    assert_receive {:socket, socket}

    assert {:ok, _} =
             SamgitaProtocolWebSocket.Client.request(client, "connection/initialize", %{
               "versions" => ["1.0"],
               "capabilities" => Handler.capabilities()
             })

    SamgitaProtocolWebSocket.Server.request(
      socket,
      "project/event.status",
      %{"event_id" => "event"},
      id: "read"
    )

    assert_receive {:samgita_protocol, ^client, {:request, %{"id" => "read"}}}

    assert_receive {:outcome, "project/event.status", {:error, %{code: "timeout"}},
                    %{"request_id" => "read"}}

    SamgitaProtocolWebSocket.Server.request(socket, "approval/request", approval(),
      id: "approval",
      command_id: "approval-command",
      timeout_ms: 5_000
    )

    assert_receive {:samgita_protocol, ^client, {:request, %{"id" => "approval"}}}
    SamgitaProtocolWebSocket.Client.close(client)

    assert_receive {:outcome, "approval/request", {:error, %{code: "ambiguous_disconnect"}},
                    %{"request_id" => "approval"}}

    refute_receive {:outcome, _, _, _}
  end

  test "server read deadlines notify the host and release pending capacity" do
    state = ready(max_pending: 1, request_timeout_ms: 10)
    {:push, _, state} = request(state, "read", "project/event.status", %{"event_id" => "event"})
    assert_receive expiry, 100
    assert {:ok, state} = Socket.handle_info(expiry, state)

    assert_receive {:outcome, "project/event.status", {:error, %{code: "timeout"}},
                    %{"request_id" => "read"}}

    assert state.server.client.pending == %{}
    assert state.timers == %{}

    assert {:push, _, state} =
             request(state, "next", "project/event.status", %{"event_id" => "event"})

    Socket.terminate(:remote, state)
  end

  test "response cancels its timer and duplicate responses and stale timers settle once" do
    {:push, [{:text, text}], state} =
      request(ready(), "read", "project/event.status", %{"event_id" => "event"})

    timer = state.timers["read"].timer
    token = state.timers["read"].token

    response =
      response(text, %{
        "event_id" => "event",
        "acceptance" => "received",
        "processing_status" => "pending"
      })

    assert {:ok, state} = Socket.handle_in({response, opcode: :text}, state)
    assert_receive {:outcome, _, {:ok, _}, _}
    assert Process.read_timer(timer) == false
    assert state.timers == %{}
    assert {:ok, state} = Socket.handle_info({:protocol_expire, "read", token}, state)
    assert {:ok, state} = Socket.handle_in({response, opcode: :text}, state)
    Socket.terminate(:remote, state)
    refute_receive {:outcome, _, _, _}
  end

  test "timed-out mutations stay uncertain and a late approval cannot settle again" do
    {:push, [{:text, text}], state} =
      request(ready(request_timeout_ms: 10), "approval", "approval/request", approval())

    assert_receive expiry, 100
    assert {:ok, state} = Socket.handle_info(expiry, state)
    assert_receive {:outcome, "approval/request", {:error, %{code: "ambiguous_disconnect"}}, _}
    assert state.server.client.pending == %{}
    assert state.server.client.uncertain["command:approval"]

    assert {:stop, :normal, 1008, state} =
             Socket.handle_in(
               {response(text, %{
                  "approval_id" => "approval",
                  "decision" => "approve",
                  "scope" => "once"
                }), opcode: :text},
               state
             )

    Socket.terminate(:remote, state)
    refute_receive {:outcome, _, _, _}
  end

  test "a response processed after the deadline loses the race even before the timer message" do
    {:push, [{:text, text}], state} = request(ready(), "approval", "approval/request", approval())

    state =
      put_in(
        state.server.client.pending["approval"].deadline,
        System.monotonic_time(:millisecond) - 1
      )

    assert {:stop, :normal, 1008, state} =
             Socket.handle_in(
               {response(text, %{
                  "approval_id" => "approval",
                  "decision" => "approve",
                  "scope" => "once"
                }), opcode: :text},
               state
             )

    assert_receive {:outcome, "approval/request", {:error, %{code: "ambiguous_disconnect"}}, _}
    Socket.terminate(:remote, state)
    refute_receive {:outcome, _, _, _}
  end

  test "disconnect and send failure notify once and cancel outstanding timers" do
    for reason <- [:remote, {:error, :closed}] do
      {:push, _, state} = request(ready(), "approval", "approval/request", approval())
      timer = state.timers["approval"].timer
      assert :ok = Socket.terminate(reason, state)
      assert_receive {:outcome, "approval/request", {:error, %{code: "ambiguous_disconnect"}}, _}
      assert Process.read_timer(timer) == false
      refute_receive {:outcome, _, _, _}
    end
  end

  test "failed encoding settles the new request and closes with no timer leak" do
    state = %{ready() | opts: [max_frame_bytes: 1]}

    assert {:stop, :normal, 1008, state} =
             request(state, "approval", "approval/request", approval())

    assert_receive {:outcome, "approval/request", {:error, %{code: "ambiguous_disconnect"}}, _}
    assert state.timers == %{}
    assert state.server.client.pending == %{}
    Socket.terminate(:normal, state)
    refute_receive {:outcome, _, _, _}
  end

  defp ready(opts \\ []) do
    {:ok, state} =
      Socket.init(Keyword.merge([principal: %{}, handler: Handler, handler_state: self()], opts))

    put_in(
      state.server.client,
      Client.establish(state.server.client, Handler.capabilities(), "test-connection")
    )
  end

  defp request(state, id, method, params) do
    Socket.handle_info(
      {:protocol_request, method, params, [id: id, command_id: "command:" <> id]},
      state
    )
  end

  defp approval,
    do: %{
      "approval_id" => "approval",
      "thread_id" => "thread",
      "turn_id" => "turn",
      "action" => %{}
    }

  defp response(text, result) do
    {:ok, message} = Codec.decode(text)
    {:ok, message} = Client.response_to(message, {:ok, result})
    JSON.encode!(message)
  end

  defmodule Handler do
    def capabilities, do: SamgitaProtocol.Capabilities.all()
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())
    def handle_request(_, _, _, owner), do: {:ok, %{}, owner}

    def handle_response(method, result, context, owner) do
      send(owner, {:outcome, method, result, context})
      {:ok, owner}
    end
  end
end
