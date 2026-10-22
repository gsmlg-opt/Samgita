defmodule SamgitaProtocol.ServerTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Capabilities, Client, Error, Server}

  defmodule Host do
    @behaviour SamgitaProtocol.Handler
    def capabilities, do: ["project_events.v1", "approvals.v1", "cancellation.v1", "streaming.v1"]
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())

    def handle_request(method, params, context, state) do
      send(state.owner, {:handled, method, params, context})

      case state.mode do
        :raise -> raise "secret must never reach the wire"
        :invalid -> {:ok, %{}, state}
        :normal -> handle(method, params, state)
      end
    end

    defp handle("project/event.receive", %{"event" => event}, state) do
      {:ok,
       %{
         "event_id" => event["event_id"],
         "delivery_attempt_id" => event["delivery_attempt_id"],
         "acceptance" => "received",
         "processing_status" => "pending"
       }, state}
    end

    defp handle("request/cancel", %{"request_id" => id}, state),
      do: {:ok, %{"request_id" => id, "status" => "requested"}, state}

    defp handle(_, _, state),
      do: {:error, SamgitaProtocol.Error.new("not_found"), state}

    def handle_notification(_, _, _, %{mode: :raise}), do: raise("secret")

    def handle_notification(method, _, context, state) do
      send(state.owner, {:handled_notification, method, context})
      {:ok, state}
    end

    def handle_response(_, _, _, %{mode: :raise}), do: raise("secret")

    def handle_response(method, result, context, state) do
      send(state.owner, {:handled_response, method, result, context})
      {:ok, state}
    end
  end

  defmodule IncompleteHost do
    @behaviour SamgitaProtocol.Handler
    def capabilities, do: ["sessions.v1"]
    def methods, do: ["thread/start"]
    def handle_request(_, _, _, state), do: {:ok, %{}, state}
  end

  def ready(mode \\ :normal) do
    {:ok, server} = Server.new(Host, %{owner: self(), mode: mode}, connection_id: "conn-1")
    {:ok, client} = Client.new(capabilities: Host.capabilities())

    {:ok, init, client} =
      Client.request(client, "connection/initialize", %{
        "versions" => ["1.0"],
        "capabilities" => Host.capabilities()
      })

    {:ok, [response], server} = Server.receive(server, init)
    {:ok, _, client} = Client.receive(client, response)
    {server, client}
  end

  test "a registered host implements every operation of each advertised capability" do
    assert {:error, %Error{code: "capability_mismatch"}} = Server.new(IncompleteHost, nil)

    assert Capabilities.methods(["project_events.v1"]) ==
             ~w(project/event.receive project/event.report project/event.status)
  end

  test "initialization intersects groups and required omissions fail before dispatch" do
    {:ok, server} = Server.new(Host, %{owner: self(), mode: :normal})

    init =
      SamgitaProtocol.TestFixtures.request("connection/initialize", %{
        "versions" => ["1.0"],
        "capabilities" => ["project_events.v1", "future.v9"]
      })

    assert {:ok, [response], ready} = Server.receive(server, init)
    assert response["result"]["capabilities"] == ["project_events.v1"]

    assert {:ok, [%{"error" => %{"code" => "already_initialized"}}], _} =
             Server.receive(ready, init)

    init = put_in(init, ["params", "required_capabilities"], ["future.v9"])

    assert {:ok, [%{"error" => %{"code" => "unsupported_capability"}}], ^server} =
             Server.receive(server, init)

    refute_received {:handled, _, _, _}
  end

  test "malformed, premature and unsupported requests never call the host" do
    {:ok, server} = Server.new(Host, %{owner: self(), mode: :normal})
    request = SamgitaProtocol.TestFixtures.request("project/event.status", %{"event_id" => "e"})

    assert {:ok, [%{"error" => %{"code" => "not_initialized"}}], ^server} =
             Server.receive(server, request)

    {server, _} = ready()
    assert {:error, %Error{code: "parse_error"}, ^server} = Server.receive(server, "{bad")

    for {message, code} <- [
          {put_in(request, ["params", "event_id"], 12), "invalid_params"},
          {Map.put(request, "method", "unknown/operation"), "unsupported_method"},
          {SamgitaProtocol.TestFixtures.request("thread/read", %{"thread_id" => "t"}),
           "unsupported_capability"}
        ] do
      assert {:ok, [%{"error" => %{"code" => ^code}}], ^server} = Server.receive(server, message)
    end

    refute_received {:handled, _, _, _}
  end

  test "event receipt acknowledges only receipt and preserves opaque context" do
    {server, client} = ready()
    event = SamgitaProtocol.TestFixtures.event()

    {:ok, request, client} =
      Client.request(client, "project/event.receive", %{"event" => event},
        command_id: "delivery-command",
        project_ref: "project-opaque",
        causation_id: "cause-1"
      )

    assert {:ok, [response], _} = Server.receive(server, request)
    assert response["result"]["acceptance"] == "received"
    assert {:ok, [{:response, _, _}], _} = Client.receive(client, response)
    assert_received {:handled, "project/event.receive", %{"event" => ^event}, context}
    assert context["project_ref"] == "project-opaque"
    assert context["causation_id"] == "cause-1"
    assert context["connection_id"] == "conn-1"
  end

  test "bidirectional approvals wait for the matching reply, with no automatic approval" do
    {server, client} = ready()

    params = %{
      "approval_id" => "a",
      "thread_id" => "t",
      "turn_id" => "u",
      "action" => %{"command" => "demo"}
    }

    {:ok, request, server} =
      Server.request(server, "approval/request", params, command_id: "approval-1")

    assert {:ok, [{:request, ^request}], client} = Client.receive(client, request)
    refute_received {:handled_response, _, _, _}

    {:ok, reply, _} =
      Client.reply(
        client,
        request,
        {:ok, %{"approval_id" => "a", "decision" => "deny", "scope" => "once"}}
      )

    assert {:ok, [], server} = Server.receive(server, reply)
    assert_received {:handled_response, "approval/request", {:ok, %{"decision" => "deny"}}, _}
    assert {:ok, [], _} = Server.receive(server, reply)
    refute_received {:handled_response, _, _, _}
  end

  test "cancellation intent does not settle the target request or imply stopped effects" do
    {server, client} = ready()
    {:ok, original, client} = Client.request(client, "project/event.status", %{"event_id" => "e"})

    {:ok, cancel, client} =
      Client.request(client, "request/cancel", %{"request_id" => original["id"]},
        command_id: "cancel-1"
      )

    {:ok, [response], _} = Server.receive(server, cancel)
    {:ok, _, client} = Client.receive(client, response)
    assert Map.has_key?(client.pending, original["id"])
    assert response["result"]["status"] == "requested"
  end

  test "handler exceptions and invalid results return safe nonretryable errors" do
    for {mode, code} <- [{:raise, "handler_error"}, {:invalid, "invalid_response"}] do
      {server, client} = ready(mode)
      {:ok, request, _} = Client.request(client, "project/event.status", %{"event_id" => "e"})

      assert {:ok, [%{"error" => %{"code" => ^code, "retryable" => false} = error}], _} =
               Server.receive(server, request)

      refute inspect(error) =~ "secret"
    end
  end

  test "notification and response callback crashes stay within the typed boundary" do
    {server, client} = ready(:raise)

    notification = %{
      "schema_version" => "1.0",
      "type" => "notification",
      "correlation_id" => "flow",
      "method" => "project/event.updated",
      "params" => %{
        "event_id" => "e",
        "acceptance" => "received",
        "processing_status" => "pending"
      }
    }

    assert {:error, %Error{code: "handler_error"}, _} = Server.receive(server, notification)
    params = %{"approval_id" => "a", "thread_id" => "t", "turn_id" => "u", "action" => %{}}

    {:ok, request, server} =
      Server.request(server, "approval/request", params, command_id: "approval-1")

    {:ok, _, client} = Client.receive(client, request)

    {:ok, response, _} =
      Client.reply(
        client,
        request,
        {:ok, %{"approval_id" => "a", "decision" => "deny", "scope" => "once"}}
      )

    assert {:error, %Error{code: "handler_error"}, server} = Server.receive(server, response)
    assert server.client.pending == %{}
  end

  test "stream duplicates and gaps are checked before notification dispatch" do
    {server, _} = ready()
    message = SamgitaProtocol.TestFixtures.notification(1)
    assert {:ok, [], server} = Server.receive(server, message)

    assert_received {:handled_notification, "item/delta",
                     %{"stream_id" => "stream-1", "cursor" => 1}}

    assert {:ok, [], ^server} = Server.receive(server, message)
    refute_received {:handled_notification, _, _}

    assert {:error, %Error{code: "replay_gap"}, ^server} =
             Server.receive(server, %{message | "cursor" => 3})

    refute_received {:handled_notification, _, _}
  end
end
