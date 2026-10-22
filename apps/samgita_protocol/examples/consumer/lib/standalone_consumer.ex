defmodule StandaloneConsumer do
  @moduledoc "An explicitly wired, in-memory Agent-event host. No platform or transport is required."
  alias SamgitaProtocol.{Capabilities, Client, Event, Server}

  defmodule Agent do
    @behaviour SamgitaProtocol.Handler
    alias SamgitaProtocol.{Error, Event}
    def capabilities, do: ["project_events.v1"]
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())

    def handle_request("project/event.receive", %{"event" => event}, _, state) do
      case state[event["event_id"]] do
        %{event: original} when original != event ->
          if Event.same?(original, event),
            do: received(event, state),
            else: {:error, Error.new("conflict"), state}

        _ ->
          received(event, state)
      end
    end

    def handle_request("project/event.status", %{"event_id" => id}, _, state) do
      case state[id] do
        nil ->
          {:error, Error.new("not_found"), state}

        entry ->
          {:ok,
           %{"event_id" => id, "acceptance" => "received", "processing_status" => entry.status},
           state}
      end
    end

    def handle_request("project/event.report", params, _, state) do
      id = params["event_id"]

      if state[id] do
        state = put_in(state[id].status, params["status"])

        {:ok,
         %{
           "event_id" => id,
           "decision_id" => params["decision_id"],
           "report_status" => "recorded",
           "management_acceptance" => "not_requested"
         }, state}
      else
        {:error, Error.new("not_found"), state}
      end
    end

    defp received(event, state) do
      state = Map.put_new(state, event["event_id"], %{event: event, status: "pending"})

      {:ok,
       %{
         "event_id" => event["event_id"],
         "delivery_attempt_id" => event["delivery_attempt_id"],
         "acceptance" => "received",
         "processing_status" => state[event["event_id"]].status
       }, state}
    end
  end

  def run do
    {:ok, client} = Client.new(capabilities: Agent.capabilities())
    {:ok, server} = Server.new(Agent, %{})

    {_, client, server} =
      exchange(
        client,
        server,
        "connection/initialize",
        %{"versions" => ["1.0"], "capabilities" => Agent.capabilities()},
        []
      )

    event = %{
      "schema_version" => "1.0",
      "event_id" => "event-1",
      "delivery_attempt_id" => "delivery-1",
      "created_at" => "2026-10-22T08:00:00Z",
      "correlation_id" => "flow-1",
      "type" => "schedule.tick",
      "payload" => %{}
    }

    {received, client, server} =
      exchange(client, server, "project/event.receive", %{"event" => event},
        command_id: "receive-1"
      )

    {:ok, retry} = Event.retry(event, "delivery-2")

    {redelivered, client, server} =
      exchange(client, server, "project/event.receive", %{"event" => retry},
        command_id: "receive-2"
      )

    {report, client, server} =
      exchange(
        client,
        server,
        "project/event.report",
        %{
          "event_id" => event["event_id"],
          "decision_id" => "decision-1",
          "status" => "completed",
          "decision" => %{"action" => "no_action"}
        },
        command_id: "report-1"
      )

    {status, _, server} =
      exchange(client, server, "project/event.status", %{"event_id" => event["event_id"]}, [])

    %{
      received: received,
      redelivered: redelivered,
      report: report,
      status: status,
      event_count: map_size(server.handler_state),
      unsupported_sessions: not Capabilities.supports?(Agent.capabilities(), "thread/start")
    }
  end

  defp exchange(client, server, method, params, opts) do
    {:ok, request, client} = Client.request(client, method, params, opts)
    {:ok, [response], server} = Server.receive(server, request)
    {:ok, [{:response, _, result}], client} = Client.receive(client, response)
    {result, client, server}
  end
end
