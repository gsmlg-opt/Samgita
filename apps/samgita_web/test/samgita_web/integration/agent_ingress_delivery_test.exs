defmodule SamgitaWeb.AgentIngressDeliveryTest do
  @moduledoc "Functional delivery on pre-trusted synthetic devices; no pairing or permission decisions."
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias HTTP.WebSocket
  alias HTTP.WebSocket.Event.{Close, Message, Open}
  alias Samgita.{AgentIngress, EventDelivery, Events, Principal, Projects, Repo}
  alias Samgita.Domain.{AgentConnection, AgentCredential, EventAcknowledgement}
  alias Samgita.Domain.EventDelivery, as: Delivery

  setup do
    activate_fixture()
    project = project_fixture()

    agent =
      agent_fixture(%{
        "name" => "Inbound functional fixture",
        "implementation" => "synthetic",
        "advertised_capabilities" => ["project_events.v1"],
        "approved_capabilities" => ["project_events.v1"],
        "endpoint_metadata" => %{"transport" => "inbound_websocket"}
      })

    # Trust is fixture state. The tests below exercise delivery, not authentication/confirmation.
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    Repo.insert!(%AgentCredential{
      agent_id: agent["id"],
      digest: :crypto.hash(:sha256, token),
      reference: "device:" <> Ecto.UUID.generate()
    })

    member_fixture(project, agent, ["manager"])
    {:ok, current} = Projects.get(Principal.operator(), project["id"])

    {:ok, subscription} =
      Events.configure(
        Principal.operator(),
        project["id"],
        command(%{
          "agent_id" => agent["id"],
          "expected_version" => current["version"],
          "types" => ["manual.triggered"],
          "idempotency_guaranteed" => true
        })
      )

    {:ok, event} =
      Events.trigger(Principal.operator(), project["id"], command(%{"payload" => %{}}))

    delivery = Repo.get_by!(Delivery, event_id: event["id"], subscription_id: subscription["id"])

    listener =
      start_supervised!(
        {Gaoxy.HTTP,
         id: :ingress_delivery, plug: {SamgitaWeb.Endpoint, []}, ip: {127, 0, 0, 1}, port: 0}
      )

    %{local: {:ok, {_, port}}} = Gaoxy.info(listener, :ingress_delivery)
    connect = fn -> connect_socket(port, token) end
    {socket, connection} = connect.()

    %{
      agent: agent,
      socket: socket,
      event: event,
      delivery: delivery,
      connection: connection,
      connect: connect
    }
  end

  test "native event acknowledgement updates the durable delivery", ctx do
    task = Task.async(fn -> EventDelivery.dispatch(ctx.delivery.id) end)
    request = receive_json(ctx.socket)
    assert request["method"] == "project/event.receive"
    assert request["params"]["event"]["event_id"] == ctx.event["id"]
    assert request["command_id"] == ctx.delivery.operation_id
    assert request["correlation_id"] == ctx.delivery.operation_id

    event = request["params"]["event"]

    respond(ctx.socket, request, %{
      "event_id" => event["event_id"],
      "delivery_attempt_id" => event["delivery_attempt_id"],
      "acceptance" => "durable",
      "processing_status" => "pending"
    })

    assert {:ok, %{"state" => "accepted", "processing_status" => "pending"}} = Task.await(task)
    assert Repo.get!(Delivery, ctx.delivery.id).accepted_at
    assert Repo.get_by!(EventAcknowledgement, delivery_id: ctx.delivery.id).source == "receive"
  end

  test "status requests use the same initialized inbound channel", ctx do
    target = %{
      agent_id: ctx.agent["id"],
      endpoint_metadata: %{"transport" => "inbound_websocket"}
    }

    task =
      Task.async(fn ->
        Samgita.Connectors.AppServer.status(target, ctx.event["id"], ctx.delivery.operation_id)
      end)

    request = receive_json(ctx.socket)
    assert request["method"] == "project/event.status"
    assert request["correlation_id"] == ctx.delivery.operation_id

    result = %{
      "event_id" => ctx.event["id"],
      "acceptance" => "durable",
      "processing_status" => "pending"
    }

    respond(ctx.socket, request, result)
    assert {:ok, ^result} = Task.await(task)
  end

  test "a lost event reply leaves reconciliation pending instead of replaying receive", ctx do
    task = Task.async(fn -> EventDelivery.dispatch(ctx.delivery.id) end)
    assert receive_json(ctx.socket)["method"] == "project/event.receive"
    :ok = WebSocket.close(ctx.socket)

    assert {:ok, %{"state" => "reconciling", "remote_outcome_uncertain" => true}} =
             Task.await(task)

    assert Repo.get!(Delivery, ctx.delivery.id).attempt_count == 1
  end

  test "event timeout closes the consumed protocol state and preserves uncertainty",
       %{socket: socket} = ctx do
    task = Task.async(fn -> EventDelivery.dispatch(ctx.delivery.id) end)
    assert receive_json(ctx.socket)["method"] == "project/event.receive"

    assert {:ok, %{"state" => "reconciling", "remote_outcome_uncertain" => true}} =
             Task.await(task, 8_000)

    refute Map.has_key?(AgentIngress.snapshot().connected, ctx.agent["id"])
    assert Repo.get!(Delivery, ctx.delivery.id).attempt_count == 1
    assert_receive {WebSocket, ^socket, %Close{code: 1013}}, 3_000
  end

  test "an ingress restart tells the client to reconnect", %{socket: socket} do
    assert :ok = Supervisor.terminate_child(Samgita.Supervisor, AgentIngress)

    try do
      assert_receive {WebSocket, ^socket, %Close{code: 1012}}, 3_000
    after
      Supervisor.restart_child(Samgita.Supervisor, AgentIngress)
    end
  end

  test "an expired connection generation tells the client to reconnect",
       %{socket: socket, connection: %{"id" => connection_id}} do
    Repo.get!(AgentConnection, connection_id)
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    # Simulate traffic on the expired socket before the next periodic check.
    initialize(socket)
    assert_receive {WebSocket, ^socket, %Close{code: 1013}}, 3_000
  end

  test "a superseded socket yields the route to the new connection",
       %{socket: socket, connect: connect, agent: %{"id" => agent_id}} do
    {_new_socket, %{"id" => connection_id}} = connect.()

    assert_receive {WebSocket, ^socket, %Close{code: 4001}}, 3_000

    assert %{state: :connected, connection_id: ^connection_id} =
             AgentIngress.snapshot().connected[agent_id]
  end

  defp connect_socket(port, token) do
    socket =
      WebSocket.new("ws://127.0.0.1:#{port}/app-server", [], delivery: :ack, telemetry_url: nil)

    on_exit(fn -> WebSocket.close(socket) end)
    assert_receive {WebSocket, ^socket, %Open{}}, 3_000

    send_json(socket, %{
      "type" => "agent/connect",
      "name" => "Inbound functional fixture",
      "implementation" => "synthetic",
      "device_token" => token
    })

    assert %{"type" => "agent/connected", "connection" => connection} = receive_json(socket)
    initialize(socket)
    receive_json(socket)
    {socket, connection}
  end

  defp initialize(socket) do
    send_json(socket, %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => "initialize",
      "correlation_id" => "initialize",
      "method" => "connection/initialize",
      "params" => %{
        "versions" => ["1.0"],
        "capabilities" => ["project_events.v1"],
        "required_capabilities" => ["project_events.v1"]
      }
    })
  end

  defp send_json(socket, message), do: :ok = WebSocket.send(socket, JSON.encode!(message))

  defp receive_json(socket) do
    assert_receive {WebSocket, ^socket, %Message{data: text}, ref}, 3_000
    :ok = WebSocket.acknowledge(socket, ref)
    JSON.decode!(text)
  end

  defp respond(socket, request, result) do
    {:ok, response} = SamgitaProtocol.Client.response_to(request, {:ok, result})
    send_json(socket, response)
  end
end
