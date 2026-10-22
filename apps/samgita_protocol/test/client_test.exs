defmodule SamgitaProtocol.ClientTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Client, Error}

  import SamgitaProtocol.TestFixtures

  test "requests cannot precede initialization or exceed negotiated support" do
    {:ok, client} = Client.new(capabilities: ["sessions.v1"])

    assert {:error, %Error{code: "not_initialized"}, _} =
             Client.request(client, "thread/read", %{"thread_id" => "t"})

    assert {:error, %Error{code: "unsupported_capability"}, _} =
             Client.request(ready(), "project/event.status", %{"event_id" => "e"})
  end

  test "correlation validates context and duplicate replies dispatch once" do
    {:ok, request, client} =
      Client.request(ready(), "thread/read", %{"thread_id" => "t"}, id: "read", project_ref: "p")

    reply = response(request, %{"thread_id" => "t"})

    assert {:error, %Error{code: "correlation_mismatch"}, ^client} =
             Client.receive(client, Map.put(reply, "project_ref", "other"))

    assert {:ok, [{:response, "read", %{"thread_id" => "t"}}], client} =
             Client.receive(client, reply)

    assert {:ok, [], ^client} = Client.receive(client, reply)

    assert {:error, %Error{code: "conflicting_response"}, _} =
             Client.receive(client, Map.put(reply, "result", %{"thread_id" => "other"}))
  end

  test "ambiguous disconnects retain mutation identity without automatic replay" do
    {:ok, request, client} =
      Client.request(ready(), "thread/start", %{}, id: "write", command_id: "command-1")

    assert {:ok, [{:error, "write", %Error{code: "ambiguous_disconnect"}}], client} =
             Client.disconnect(client)

    assert client.uncertain["command-1"].request == request
    assert {:ok, client} = Client.reconnect(client)

    assert {:error, %Error{code: "not_initialized"}, _} =
             Client.request(client, "thread/read", %{"thread_id" => "t"})

    assert map_size(client.pending) == 0
    assert Map.has_key?(client.uncertain, "command-1")
  end

  test "expired mutations are ambiguous and pending/buffer limits enforce backpressure" do
    {:ok, _, client} =
      Client.request(ready(max_pending: 1), "thread/start", %{},
        id: "write",
        command_id: "command-1",
        now_ms: 10,
        timeout_ms: 5
      )

    assert {:error, %Error{code: "too_many_requests"}, _} =
             Client.request(client, "thread/read", %{"thread_id" => "t"})

    assert {:ok, [{:error, "write", %Error{code: "ambiguous_disconnect"}}], _} =
             Client.expire(client, 15)

    client = ready(max_buffer: 1)
    assert {:ok, [{:notification, _}], client} = Client.receive(client, notification(1))
    assert {:error, %Error{code: "buffer_full"}, _} = Client.receive(client, notification(2))
    assert {:error, %Error{code: "stale_cursor"}, _} = Client.ack_cursor(client, "stream-1", 1)
    {[message], client} = Client.drain(client, 1)
    assert message["cursor"] == 1
    assert {:ok, client} = Client.ack_cursor(client, "stream-1", 1)
    assert {:error, %Error{code: "replay_gap"}, _} = Client.receive(client, notification(3))
  end

  test "approval responses require the exact original pending request" do
    client = ready()

    request = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => "approval",
      "command_id" => "approval-command",
      "correlation_id" => "flow-1",
      "method" => "approval/request",
      "params" => %{"approval_id" => "a", "thread_id" => "t", "turn_id" => "u", "action" => %{}}
    }

    assert {:ok, [{:request, ^request}], client} = Client.receive(client, request)

    assert {:error, %Error{code: "correlation_mismatch"}, _} =
             Client.reply(
               client,
               Map.put(request, "correlation_id", "other"),
               {:ok, %{"approval_id" => "a", "decision" => "approve", "scope" => "once"}}
             )

    assert {:error, %Error{code: "invalid_response"}, _} =
             Client.reply(
               client,
               request,
               {:ok, %{"approval_id" => "another", "decision" => "approve", "scope" => "once"}}
             )

    assert {:ok, response, _} =
             Client.reply(
               client,
               request,
               {:ok, %{"approval_id" => "a", "decision" => "deny", "scope" => "once"}}
             )

    assert response["id"] == "approval"
  end
end
