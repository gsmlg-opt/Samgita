defmodule Samgita.Connectors.AppServerTest do
  use ExUnit.Case, async: false

  alias Samgita.Connector.Failure
  alias Samgita.Connectors.{AppServer, Destination}
  alias SamgitaProtocolWebSocket.Server

  setup do
    old_destinations = Application.get_env(:samgita, :event_destinations)
    old_credentials = Application.get_env(:samgita, :event_credentials)

    on_exit(fn ->
      restore(:event_destinations, old_destinations)
      restore(:event_credentials, old_credentials)
    end)

    store = start_supervised!({Agent, fn -> %{events: %{}, calls: [], mode: :normal} end})
    owner = self()

    listener =
      start_supervised!(
        {Server,
         port: 0,
         handler: __MODULE__.Handler,
         handler_state: %{store: store, owner: owner},
         authenticate: fn token ->
           if token == "fake-outbound-credential", do: {:ok, %{id: "fake-client"}}, else: :error
         end}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    agent_id = Ecto.UUID.generate()
    url = "ws://127.0.0.1:#{port}/app-server"

    target = %{
      agent_id: agent_id,
      endpoint_metadata: %{"url" => url, "transport" => "websocket"},
      credential_ref: "fake-service-reference"
    }

    Application.put_env(:samgita, :event_destinations, %{
      agent_id => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    Application.put_env(:samgita, :event_credentials, %{
      "fake-service-reference" => "fake-outbound-credential"
    })

    %{target: target, store: store}
  end

  test "real WebSocket delivery keeps operation identity and deduplicates the original event", %{
    target: target,
    store: store
  } do
    event = event()
    operation_id = Ecto.UUID.generate()

    assert {:ok, %{"acceptance" => "durable", "processing_status" => "pending"}} =
             AppServer.receive_event(target, event, operation_id)

    retry = Map.put(event, "delivery_attempt_id", Ecto.UUID.generate())

    assert {:ok, %{"delivery_attempt_id" => attempt_id}} =
             AppServer.receive_event(target, retry, operation_id)

    assert attempt_id == retry["delivery_attempt_id"]

    assert {:ok, %{"acceptance" => "durable", "processing_status" => "pending"}} =
             AppServer.status(target, event["event_id"], operation_id)

    assert %{events: events, calls: calls} = Agent.get(store, & &1)
    assert map_size(events) == 1

    assert [
             {"project/event.receive", first_context},
             {"project/event.receive", retry_context},
             {"project/event.status", status_context}
           ] = calls

    assert first_context["command_id"] == operation_id
    assert retry_context["command_id"] == operation_id
    assert first_context["correlation_id"] == event["correlation_id"]
    assert status_context["correlation_id"] == operation_id
    refute Map.has_key?(status_context, "command_id")
    assert events[event["event_id"]]["created_at"] == event["created_at"]

    assert Enum.map(calls, &elem(&1, 0)) ==
             ["project/event.receive", "project/event.receive", "project/event.status"]
  end

  test "acknowledgement loss is ambiguous and status reconnect does not resend", %{
    target: target,
    store: store
  } do
    Agent.update(store, &%{&1 | mode: :lose_ack})
    event = event()
    operation_id = Ecto.UUID.generate()
    waiter = Task.async(fn -> AppServer.receive_event(target, event, operation_id) end)
    assert_receive {:fake_event_persisted, socket}, 2_000
    Process.exit(socket, :kill)

    assert {:error, %{class: :ambiguous}} = Task.await(waiter)

    assert {:ok, %{"acceptance" => "durable"}} =
             AppServer.status(target, event["event_id"], operation_id)

    assert %{calls: [{"project/event.receive", _}, {"project/event.status", _}]} =
             Agent.get(store, & &1)
  end

  test "remote authentication failure is explicit and has no credential material", %{
    target: target,
    store: store
  } do
    Application.put_env(:samgita, :event_credentials, %{
      "fake-service-reference" => "wrong-private-credential"
    })

    assert {:error, failure} = AppServer.receive_event(target, event(), Ecto.UUID.generate())
    assert %{class: :authentication} = failure
    refute inspect(failure) =~ "wrong-private-credential"
    assert %{calls: []} = Agent.get(store, & &1)
  end

  test "missing reference and unsupported capabilities fail without fallback", %{target: target} do
    assert {:error, %{class: :authentication, code: :credential_unavailable}} =
             AppServer.receive_event(%{target | credential_ref: "absent"}, event(), "operation")

    listener =
      start_supervised!(
        {Server,
         port: 0,
         authenticate: fn _ -> {:ok, %{id: "no-events"}} end,
         handler: __MODULE__.NoEventsHandler}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    url = "ws://127.0.0.1:#{port}/app-server"
    target = put_in(target.endpoint_metadata["url"], url)

    Application.put_env(:samgita, :event_destinations, %{
      target.agent_id => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    assert {:error, %{class: :permanent, code: "unsupported_capability"}} =
             AppServer.receive_event(target, event(), "operation")
  end

  test "a real 429 upgrade failure remains retryable rather than an acknowledgement", %{
    target: target
  } do
    listener =
      start_supervised!(%{
        id: :rate_limited_agent,
        start:
          {Bandit, :start_link,
           [[plug: __MODULE__.RateLimitedPlug, ip: {127, 0, 0, 1}, port: 0, startup_log: false]]}
      })

    {:ok, {_address, port}} = ThousandIsland.listener_info(listener)
    url = "ws://127.0.0.1:#{port}/app-server"
    target = put_in(target.endpoint_metadata["url"], url)

    Application.put_env(:samgita, :event_destinations, %{
      target.agent_id => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    assert {:error, %{class: :retryable, code: :rate_limited, retry_after: 120}} =
             AppServer.receive_event(target, event(), "operation")
  end

  test "an unavailable Agent fails before sending rather than returning delivery success", %{
    target: target
  } do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    url = "ws://127.0.0.1:#{port}/app-server"
    target = put_in(target.endpoint_metadata["url"], url)

    Application.put_env(:samgita, :event_destinations, %{
      target.agent_id => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    assert {:error, %{class: :retryable, code: "upstream_error"}} =
             AppServer.receive_event(target, event(), "operation")
  end

  test "only the exact approved destination and its pinned resolved addresses can be contacted",
       %{
         target: target
       } do
    assert {:ok, %{address: {127, 0, 0, 1}}} = Destination.resolve(target)

    for url <- [
          target.endpoint_metadata["url"] <> "?token=secret",
          target.endpoint_metadata["url"] <> "#fragment",
          String.replace(target.endpoint_metadata["url"], "/app-server", "/other"),
          "ws://user:secret@127.0.0.1/app-server"
        ] do
      assert {:error, %{class: :permanent}} =
               Destination.resolve(put_in(target.endpoint_metadata["url"], url))
    end

    Application.put_env(:samgita, :event_destinations, %{
      target.agent_id => %{
        url: target.endpoint_metadata["url"],
        addresses: [{127, 0, 0, 2}],
        allow_insecure: true
      }
    })

    assert {:error, %{code: :destination_address_changed}} = Destination.resolve(target)

    Application.put_env(:samgita, :event_destinations, %{
      target.agent_id => %{
        url: target.endpoint_metadata["url"],
        addresses: [{127, 0, 0, 1}]
      }
    })

    assert {:error, %{code: :insecure_destination}} = Destination.resolve(target)
  end

  test "429, authentication, permanent errors and ambiguous mutations remain distinct" do
    assert %{class: :retryable, code: :rate_limited, retry_after: 3600} =
             Failure.http(429, [{"retry-after", "999999"}])

    assert %{class: :retryable, retry_after: 1} = Failure.http(429, [{"retry-after", "0"}])
    assert %{class: :retryable, retry_after: nil} = Failure.http(429, [{"retry-after", "bad"}])

    assert %{class: :retryable, retry_after: 3600} =
             Failure.http(429, [{"retry-after", "Sun, 01 Nov 2099 00:00:00 GMT"}])

    assert %{class: :retryable, retry_after: nil} =
             Failure.http(429, [{"retry-after", "Sun, 99 Nov 2099 00:00:00 GMT"}])

    assert %{class: :authentication} = Failure.http(401)
    assert %{class: :authentication} = Failure.http(403)
    assert %{class: :permanent} = Failure.http(302)
    assert %{class: :permanent} = Failure.http(422)
    assert %{class: :retryable} = Failure.http(503)

    assert %{class: :ambiguous} =
             Failure.protocol(SamgitaProtocol.Error.new("ambiguous_disconnect"), true)

    assert %{class: :ambiguous} =
             Failure.protocol(
               SamgitaProtocol.Error.new("upstream_error", %{"http_status" => 429}),
               true
             )

    assert %{class: :retryable} =
             Failure.protocol(SamgitaProtocol.Error.new("timeout"), false)

    assert %{class: :permanent, code: "not_found"} =
             Failure.protocol(SamgitaProtocol.Error.new("not_found"), false)
  end

  defp event do
    %{
      "schema_version" => "1.0",
      "event_id" => Ecto.UUID.generate(),
      "delivery_attempt_id" => Ecto.UUID.generate(),
      "correlation_id" => Ecto.UUID.generate(),
      "project_ref" => Ecto.UUID.generate(),
      "created_at" => "2026-10-22T00:00:00.000000Z",
      "type" => "project.check_requested",
      "payload" => %{"summary" => "Fake event"}
    }
  end

  defp restore(key, nil), do: Application.delete_env(:samgita, key)
  defp restore(key, value), do: Application.put_env(:samgita, key, value)

  defmodule Handler do
    alias SamgitaProtocol.{Capabilities, Error, Event}

    def capabilities, do: ["project_events.v1"]
    def methods, do: Capabilities.methods(capabilities())

    def handle_request("project/event.receive", %{"event" => event}, context, state) do
      outcome =
        Agent.get_and_update(state.store, fn stored ->
          previous = stored.events[event["event_id"]]

          if previous && !Event.same?(previous, event) do
            {:conflict, stored}
          else
            next = %{
              stored
              | events: Map.put(stored.events, event["event_id"], previous || event),
                calls: stored.calls ++ [{"project/event.receive", context}]
            }

            {stored.mode, next}
          end
        end)

      case outcome do
        :conflict ->
          {:error, Error.new("conflict"), state}

        :lose_ack ->
          send(state.owner, {:fake_event_persisted, self()})

          receive do
            :release_fake_ack -> {:ok, ack(event), state}
          end

        :normal ->
          {:ok, ack(event), state}
      end
    end

    def handle_request("project/event.status", %{"event_id" => id}, context, state) do
      event =
        Agent.get_and_update(state.store, fn stored ->
          {stored.events[id],
           %{stored | calls: stored.calls ++ [{"project/event.status", context}]}}
        end)

      if event,
        do: {:ok, Map.delete(ack(event), "delivery_attempt_id"), state},
        else: {:error, Error.new("not_found"), state}
    end

    def handle_request(_method, _params, _context, state),
      do: {:error, Error.new("unsupported_method"), state}

    # This fake simulates a durable Agent contract. Its test-only store is in memory.
    defp ack(event) do
      %{
        "event_id" => event["event_id"],
        "delivery_attempt_id" => event["delivery_attempt_id"],
        "acceptance" => "durable",
        "processing_status" => "pending"
      }
    end
  end

  defmodule NoEventsHandler do
    def capabilities, do: []
    def methods, do: []
    def handle_request(_method, _params, _context, state), do: {:ok, %{}, state}
  end

  defmodule RateLimitedPlug do
    import Plug.Conn
    def init(opts), do: opts

    def call(conn, _opts),
      do: conn |> put_resp_header("retry-after", "120") |> send_resp(429, "Rate limited")
  end
end
