defmodule SamgitaProtocolWebSocket.NotificationFilterTest do
  # A host advertising more groups than a client negotiates keeps serving it:
  # notifications outside the negotiated groups are dropped, and the handler
  # sees which groups were negotiated.
  use ExUnit.Case, async: true
  alias SamgitaProtocolWebSocket.{Server, TestWire}

  setup do
    owner = self()

    listener =
      start_supervised!(
        {Server,
         port: 0,
         authenticate: fn
           "filter-token" -> {:ok, %{id: "filter-client"}}
           _ -> :error
         end,
         handler: __MODULE__.Handler,
         handler_state: fn _principal ->
           send(owner, {:filter_socket, self()})
           owner
         end}
      )

    {:ok, {_address, port}} = Server.listener_info(listener)
    %{url: "ws://127.0.0.1:#{port}/app-server"}
  end

  test "a sessions-only client stays connected and receives turn but not item notifications",
       %{url: url} do
    wire = TestWire.connect(url, "filter-token")
    assert_receive {:filter_socket, socket}

    wire =
      send_request(wire, "init", "connection/initialize", %{
        "versions" => ["1.0"],
        "capabilities" => ["sessions.v1"]
      })

    assert {{:text, response}, wire} = TestWire.receive_frame(wire)
    assert %{"result" => %{"capabilities" => ["sessions.v1"]}} = JSON.decode!(response)

    Server.notify(socket, notification("item/started", %{"item_id" => "i1", "item" => %{}}))
    Server.notify(socket, notification("turn/started", %{}))

    assert {{:text, delivered}, wire} = TestWire.receive_frame(wire)
    assert %{"method" => "turn/started"} = JSON.decode!(delivered)

    # The handler is told what this connection negotiated.
    wire = send_request(wire, "read", "thread/read", %{"thread_id" => "t1"})
    assert {{:text, reply}, wire} = TestWire.receive_frame(wire)
    assert %{"id" => "read", "result" => %{"thread" => %{}}} = JSON.decode!(reply)
    assert_receive {:handler_context, %{"capabilities" => ["sessions.v1"]}}

    TestWire.close(wire)
  end

  defp send_request(wire, id, method, params) do
    request = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => id,
      "correlation_id" => id,
      "method" => method,
      "params" => params
    }

    TestWire.send_frame(wire, {:text, JSON.encode!(request)})
  end

  defp notification(method, params),
    do: %{
      "schema_version" => "1.0",
      "type" => "notification",
      "method" => method,
      "correlation_id" => "c-" <> method,
      "params" => Map.merge(%{"thread_id" => "t1", "turn_id" => "u1"}, params)
    }

  defmodule Handler do
    alias SamgitaProtocol.Capabilities

    def capabilities, do: ["sessions.v1", "streaming.v1"]
    def methods, do: Capabilities.methods(capabilities())

    def handle_request("thread/read", %{"thread_id" => id}, context, owner) do
      send(owner, {:handler_context, context})
      {:ok, %{"thread_id" => id, "thread" => %{}}, owner}
    end
  end
end
