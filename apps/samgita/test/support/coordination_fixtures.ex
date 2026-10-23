defmodule Samgita.CoordinationFixtures do
  @moduledoc false
  import Samgita.DomainFixtures
  alias Samgita.Domain.EventDelivery
  alias Samgita.{Events, Principal, Projects, Repo}

  def routing_fixture(opts \\ []) do
    activate_fixture()
    project = project_fixture()

    agent =
      agent_fixture(%{
        "credential_ref" => "fake-event-credential",
        "endpoint_metadata" => %{
          "transport" => "websocket",
          "url" => "ws://127.0.0.1:9999/app-server"
        }
      })

    member_fixture(project, agent)
    {:ok, current} = Projects.get(Principal.operator(), project["id"])

    {:ok, subscription} =
      Events.configure(
        Principal.operator(),
        project["id"],
        command(%{
          "agent_id" => agent["id"],
          "expected_version" => current["version"],
          "types" => Keyword.get(opts, :types, []),
          "idempotency_guaranteed" => Keyword.get(opts, :idempotent, false)
        })
      )

    {project, agent, subscription}
  end

  def delivery_fixture(opts \\ []) do
    {project, agent, subscription} = routing_fixture(opts)

    {:ok, event} =
      Events.trigger(
        Principal.operator(),
        project["id"],
        command(%{"payload" => %{"reason" => "manual-check"}})
      )

    delivery =
      Repo.get_by!(EventDelivery, event_id: event["id"], subscription_id: subscription["id"])

    {project, agent, subscription, event, delivery}
  end

  def acknowledge(claim, acceptance \\ "durable", status \\ "pending"),
    do: %{
      "event_id" => claim.event["event_id"],
      "delivery_attempt_id" => claim.event["delivery_attempt_id"],
      "acceptance" => acceptance,
      "processing_status" => status
    }

  defmodule FakeConnector do
    @moduledoc false
    @behaviour Samgita.Connector
    alias Samgita.Connector.Failure

    def receive_event(target, event, operation) do
      send(self(), {:fake_receive, target.agent_id, event, operation})

      case Process.get(:fake_receive_result, :durable) do
        :durable ->
          {:ok,
           %{
             "event_id" => event["event_id"],
             "delivery_attempt_id" => event["delivery_attempt_id"],
             "acceptance" => "durable",
             "processing_status" => "pending"
           }}

        :received ->
          {:ok,
           %{
             "event_id" => event["event_id"],
             "delivery_attempt_id" => event["delivery_attempt_id"],
             "acceptance" => "received",
             "processing_status" => "pending"
           }}

        value ->
          value
      end
    end

    def status(target, id, operation) do
      send(self(), {:fake_status, target.agent_id, id, operation})

      case Process.get(:fake_status_result, :durable) do
        :durable ->
          {:ok, %{"event_id" => id, "acceptance" => "durable", "processing_status" => "pending"}}

        :not_found ->
          {:error, %Failure{class: :permanent, code: :not_found}}

        value ->
          value
      end
    end
  end

  defmodule CrashBeforeSendConnector do
    @moduledoc false
    @behaviour Samgita.Connector
    alias Samgita.Connector.Failure

    def receive_event(_target, event, operation) do
      send(Process.get(:crash_owner), {:before_wire_send, self(), event, operation})

      receive do
        :continue -> {:error, Failure.new(:ambiguous, :handler_lost)}
      end
    end

    def status(_, _, _), do: raise("unexpected status")
  end
end
