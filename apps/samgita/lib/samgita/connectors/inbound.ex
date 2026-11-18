defmodule Samgita.Connectors.Inbound do
  @moduledoc "Native event delivery over an operator-confirmed, Agent-initiated connection."
  @behaviour Samgita.Connector
  alias Samgita.{AgentIngress, Connector.Failure}
  alias SamgitaProtocol.{Event, Schema}

  @impl true
  def receive_event(target, event, operation_id) do
    with :ok <- Event.validate(event), true <- Schema.valid?(operation_id, :id) do
      opts =
        [command_id: operation_id, correlation_id: operation_id, timeout_ms: 5_000] ++
          for {key, name} <- [
                causation_id: "causation_id",
                project_ref: "project_ref",
                task_ref: "task_ref"
              ],
              Map.has_key?(event, name),
              do: {key, event[name]}

      AgentIngress.request(target.agent_id, "project/event.receive", %{"event" => event}, opts)
    else
      _ -> {:error, Failure.new(:permanent, :invalid_event)}
    end
  end

  @impl true
  def status(target, event_id, operation_id) do
    if Schema.valid?(event_id, :id) && Schema.valid?(operation_id, :id),
      do:
        AgentIngress.request(target.agent_id, "project/event.status", %{"event_id" => event_id},
          correlation_id: operation_id,
          timeout_ms: 5_000
        ),
      else: {:error, Failure.new(:permanent, :invalid_event)}
  end
end
