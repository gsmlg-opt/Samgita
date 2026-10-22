defmodule SamgitaProtocolWebSocket.WireErrorTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolWebSocket.{Server, TestWire}

  setup do
    owner = self()

    listener =
      start_supervised!(
        {Server,
         port: 0,
         max_frame_bytes: 1_024,
         authenticate: fn
           "wire-token" -> {:ok, %{id: "wire-client"}}
           _ -> :error
         end,
         handler: __MODULE__.Handler,
         handler_state: fn _principal ->
           send(owner, {:wire_socket, self()})
           owner
         end}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    %{url: "ws://127.0.0.1:#{port}/app-server"}
  end

  test "malformed JSON and binary frames close without invoking a handler", %{url: url} do
    for frame <- [{:text, "{"}, {:binary, "not JSON text"}] do
      wire = url |> TestWire.connect("wire-token") |> TestWire.send_frame(frame)
      assert {{:close, code, _}, wire} = TestWire.receive_frame(wire)
      assert code in [1003, 1008]
      TestWire.close(wire)
    end

    refute_received :handler_called
  end

  test "unknown method is a correlated typed error, with no callback", %{url: url} do
    message = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => "bad-method",
      "correlation_id" => "corr-1",
      "method" => "unknown/method",
      "params" => %{}
    }

    wire =
      url |> TestWire.connect("wire-token") |> TestWire.send_frame({:text, JSON.encode!(message)})

    assert {{:text, response}, wire} = TestWire.receive_frame(wire)

    assert %{
             "id" => "bad-method",
             "correlation_id" => "corr-1",
             "error" => %{"code" => "unsupported_method"}
           } = JSON.decode!(response)

    refute_received :handler_called
    TestWire.close(wire)
  end

  test "oversized input is closed at the transport boundary", %{url: url} do
    wire =
      url
      |> TestWire.connect("wire-token")
      |> TestWire.send_frame({:text, String.duplicate("x", 2_048)})

    assert {{:close, 1009, _}, wire} = TestWire.receive_frame(wire)
    TestWire.close(wire)
    refute_received :handler_called
  end

  test "wrong native envelope types are rejected before dispatch", %{url: url} do
    message = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => 42,
      "correlation_id" => "corr-1",
      "method" => "connection/initialize",
      "params" => []
    }

    wire =
      url |> TestWire.connect("wire-token") |> TestWire.send_frame({:text, JSON.encode!(message)})

    assert {{:close, 1008, _}, wire} = TestWire.receive_frame(wire)
    refute_received :handler_called
    TestWire.close(wire)
  end

  test "host notifications require initialization and a negotiated capability", %{url: url} do
    for initialize? <- [false, true] do
      wire = TestWire.connect(url, "wire-token")
      assert_receive {:wire_socket, socket}

      wire =
        if initialize? do
          init = %{
            "schema_version" => "1.0",
            "type" => "request",
            "id" => "init",
            "correlation_id" => "init",
            "method" => "connection/initialize",
            "params" => %{"versions" => ["1.0"], "capabilities" => []}
          }

          wire = TestWire.send_frame(wire, {:text, JSON.encode!(init)})
          assert {{:text, response}, wire} = TestWire.receive_frame(wire)
          assert %{"result" => %{"capabilities" => []}} = JSON.decode!(response)
          wire
        else
          wire
        end

      Server.notify(socket, %{
        "schema_version" => "1.0",
        "type" => "notification",
        "method" => "thread/started",
        "params" => %{"thread_id" => "unnegotiated"},
        "correlation_id" => "unnegotiated"
      })

      assert {{:close, 1008, _}, wire} = TestWire.receive_frame(wire)
      TestWire.close(wire)
    end
  end

  defmodule Handler do
    def capabilities, do: []
    def methods, do: []

    def handle_request(_method, _params, _context, owner) do
      send(owner, :handler_called)
      {:ok, %{}, owner}
    end
  end
end
