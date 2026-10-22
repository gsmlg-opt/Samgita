defmodule SamgitaProtocolWebSocket.IntegrationTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolWebSocket.{Client, FakeAgent}

  @capabilities Enum.sort(
                  ~w(project_events.v1 sessions.v1 streaming.v1 approvals.v1 cancellation.v1)
                )

  setup do
    agent = start_supervised!({FakeAgent, token: "isolated-test-token", owner: self(), port: 0})

    {:ok, client} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities
      )

    %{agent: agent, client: client}
  end

  test "negotiates, receives and reports an event without claiming durable or management acceptance",
       %{client: client} do
    initialize(client)
    event = event("event-1", "delivery-1")

    assert {:ok, %{"acceptance" => "received", "processing_status" => "pending"}} =
             request(client, "project/event.receive", %{"event" => event})

    assert {:ok, %{"management_acceptance" => "not_requested", "report_status" => "recorded"}} =
             request(client, "project/event.report", %{
               "event_id" => "event-1",
               "decision_id" => "decision-1",
               "status" => "completed",
               "decision" => %{"summary" => "Recorded in memory"}
             })

    assert {:ok, %{"acceptance" => "received", "processing_status" => "completed"}} =
             request(client, "project/event.status", %{"event_id" => "event-1"})
  end

  test "explicit reconnect reauthenticates, requires initialization and preserves host event deduplication",
       %{agent: agent, client: client} do
    initialize(client)

    assert {:ok, %{"event_id" => "stable-event"}} =
             request(client, "project/event.receive", %{
               "event" => event("stable-event", "attempt-1")
             })

    assert :ok = Client.reconnect(client)

    assert {:error, %{code: "not_initialized"}} =
             request(client, "project/event.status", %{"event_id" => "stable-event"})

    initialize(client)

    assert {:ok, %{"delivery_attempt_id" => "attempt-2", "acceptance" => "received"}} =
             request(client, "project/event.receive", %{
               "event" => event("stable-event", "attempt-2")
             })

    assert FakeAgent.event_count(agent) == 1

    altered = put_in(event("stable-event", "attempt-3"), ["payload"], %{"changed" => true})

    assert {:error, %{code: "conflict"}} =
             request(client, "project/event.receive", %{"event" => altered})
  end

  test "threads and turns emit replayable deltas, interruption and no automatic approvals", %{
    agent: agent,
    client: client
  } do
    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{"title" => "Demo"})

    assert {:ok, %{"thread_id" => ^thread, "turn_id" => turn, "status" => "running"}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Hello"}]
             })

    assert_receive {:samgita_protocol, ^client,
                    {:notification, %{"method" => "turn/started", "stream_id" => stream}}}

    assert :ok = FakeAgent.emit_delta(agent, thread, turn, "Hello from fake")

    assert_receive {:samgita_protocol, ^client,
                    {:notification,
                     %{
                       "method" => "item/delta",
                       "params" => %{"delta" => "Hello from fake"},
                       "cursor" => cursor
                     }}}

    assert :ok = Client.ack_cursor(client, stream, cursor)

    assert {:ok, %{"events" => [_ | _]}} =
             request(client, "stream/resume", %{"stream_id" => stream, "cursor" => 0})

    assert {:ok, %{"status" => "interrupted"}} =
             request(client, "turn/interrupt", %{"thread_id" => thread, "turn_id" => turn})

    assert {:ok, %{"status" => "already_finished"}} =
             request(client, "request/cancel", %{"request_id" => "unknown-request"})
  end

  test "server approval requests wait for the client owner's correlated response", %{
    agent: agent,
    client: client
  } do
    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Approval demo"}]
             })

    assert :ok = FakeAgent.request_approval(agent, thread, turn, "approval-1")

    assert_receive {:samgita_protocol, ^client,
                    {:request, %{"method" => "approval/request"} = approval}}

    refute_receive {:fake_agent_approval, _, _}, 30

    assert :ok =
             Client.reply(
               client,
               approval,
               {:ok, %{"approval_id" => "approval-1", "decision" => "deny", "scope" => "once"}}
             )

    assert_receive {:fake_agent_approval, "approval-1", "deny"}
  end

  test "disconnecting a pending mutation is ambiguous and reconnect never resends it", %{
    agent: agent,
    client: client
  } do
    initialize(client)
    {thread, turn} = start_turn(client)

    waiter =
      Task.async(fn ->
        request(
          client,
          "approval/request",
          %{
            "approval_id" => "pending-approval",
            "thread_id" => thread,
            "turn_id" => turn,
            "action" => %{"kind" => "test"}
          },
          command_id: "pending-command"
        )
      end)

    assert_receive {:fake_agent_approval_requested, "pending-approval", socket}
    Process.exit(socket, :kill)
    assert {:error, %{code: "ambiguous_disconnect"}} = Task.await(waiter)
    assert :ok = Client.reconnect(client)
    initialize(client)
    refute_receive {:fake_agent_approval_requested, "pending-approval", _}, 30
    assert FakeAgent.approval_count(agent) == 1

    assert {:error, %{code: "ambiguous_disconnect"}} =
             request(
               client,
               "turn/steer",
               %{
                 "thread_id" => thread,
                 "turn_id" => turn,
                 "input" => [%{"type" => "text", "text" => "Reconciled input"}]
               },
               command_id: "pending-command"
             )

    assert {:error, %{code: "invalid_params"}} =
             Client.resolve_uncertain(client, "pending-command", %{})

    assert {:ok, %{"method" => "approval/request"}} =
             Client.resolve_uncertain(client, "pending-command", %{
               "status" => "reconciled",
               "evidence_ref" => "operator-review-1"
             })

    assert {:ok, _} =
             request(
               client,
               "turn/steer",
               %{
                 "thread_id" => thread,
                 "turn_id" => turn,
                 "input" => [%{"type" => "text", "text" => "Reconciled input"}]
               },
               command_id: "pending-command"
             )
  end

  test "request waits are bounded and a timed-out mutation remains uncertain", %{client: client} do
    initialize(client)
    {thread, turn} = start_turn(client)

    assert {:error, %{code: "ambiguous_disconnect"}} =
             request(
               client,
               "approval/request",
               %{
                 "approval_id" => "timeout-approval",
                 "thread_id" => thread,
                 "turn_id" => turn,
                 "action" => %{"kind" => "test"}
               },
               timeout_ms: 30
             )
  end

  test "lifecycle and cancellation reject stale or mismatched turns", %{
    agent: agent,
    client: client
  } do
    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})
    input = [%{"type" => "text", "text" => "Example"}]

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{"thread_id" => thread, "input" => input},
               id: "tracked-turn-request"
             )

    assert {:error, %{code: "conflict"}} =
             request(client, "turn/start", %{"thread_id" => thread, "input" => input})

    assert {:error, %{code: "conflict"}} =
             request(client, "turn/steer", %{
               "thread_id" => "wrong",
               "turn_id" => turn,
               "input" => input
             })

    assert {:ok, %{"status" => "requested"}} =
             request(client, "request/cancel", %{"request_id" => "tracked-turn-request"})

    assert {:error, %{code: "conflict"}} = FakeAgent.emit_delta(agent, thread, turn, "Late data")

    assert {:error, %{code: "conflict"}} =
             FakeAgent.request_approval(agent, thread, turn, "late-approval")
  end

  test "a host replay retention gap is explicit", %{agent: agent, client: client} do
    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Stream"}]
             })

    for n <- 1..6, do: FakeAgent.emit_delta(agent, thread, turn, "#{n}")
    stream = "thread:" <> thread

    assert {:error, %{code: "replay_gap"}} =
             request(client, "stream/resume", %{"stream_id" => stream, "cursor" => 0})
  end

  test "host replay survives reconnect and explicit thread resume", %{
    agent: agent,
    client: client
  } do
    initialize(client)
    {thread, turn} = start_turn(client)
    assert :ok = FakeAgent.emit_delta(agent, thread, turn, "Before reconnect")

    assert_receive {:samgita_protocol, ^client,
                    {:notification, %{"method" => "item/delta", "cursor" => cursor}}}

    assert :ok = Client.reconnect(client)
    initialize(client)
    assert {:ok, _} = request(client, "thread/resume", %{"thread_id" => thread})
    assert :ok = FakeAgent.emit_delta(agent, thread, turn, "After reconnect")

    assert_receive {:samgita_protocol, ^client,
                    {:notification,
                     %{"method" => "item/delta", "params" => %{"delta" => "After reconnect"}}}}

    assert {:ok, %{"events" => [%{"params" => %{"delta" => "After reconnect"}}]}} =
             request(client, "stream/resume", %{
               "stream_id" => "thread:" <> thread,
               "cursor" => cursor
             })
  end

  test "the pending request bound rejects more work without resending it", %{agent: agent} do
    {:ok, client} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities,
        max_pending: 1
      )

    initialize(client)
    {thread, turn} = start_turn(client)

    waiter =
      Task.async(fn ->
        request(client, "approval/request", %{
          "approval_id" => "bounded-approval",
          "thread_id" => thread,
          "turn_id" => turn,
          "action" => %{}
        })
      end)

    assert_receive {:fake_agent_approval_requested, "bounded-approval", socket}

    assert {:error, %{code: "too_many_requests"}} =
             request(client, "thread/read", %{"thread_id" => thread})

    send(socket, {:fake_approval, "bounded-approval", "deny"})
    assert {:ok, %{"decision" => "deny"}} = Task.await(waiter)
  end

  test "a stalled owner causes a bounded disconnect instead of dropping notifications", %{
    agent: agent
  } do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: send(owner, :stop) end)

    {:ok, client} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities,
        owner: owner,
        max_buffer: 1
      )

    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Example"}]
             })

    assert :ok = FakeAgent.emit_delta(agent, thread, turn, "A further notification")
    assert_disconnected(client, 100)
    assert {:message_queue_len, 1} = Process.info(owner, :message_queue_len)
  end

  test "fake state has bounded record retention" do
    agent =
      start_supervised!({FakeAgent, token: "small-token", port: 0, max_records: 1},
        id: :small_agent
      )

    {:ok, client} =
      Client.connect(FakeAgent.url(agent), token: "small-token", capabilities: @capabilities)

    initialize(client)

    assert {:ok, _} =
             request(client, "project/event.receive", %{"event" => event("retained", "first")})

    assert {:error, %{code: "buffer_full"}} =
             request(client, "project/event.receive", %{"event" => event("overflow", "second")})

    assert {:ok, _} =
             request(client, "project/event.receive", %{"event" => event("retained", "retry")})

    assert FakeAgent.event_count(agent) == 1
  end

  test "overflow leaves an unforwarded event recoverable, then replay and live checkpoints advance",
       %{agent: agent} do
    owner = spawn(fn -> controlled_owner() end)
    on_exit(fn -> if Process.alive?(owner), do: send(owner, :stop) end)

    {:ok, client} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities,
        owner: owner,
        max_buffer: 1
      )

    initialize(client)
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Overflow recovery"}]
             })

    assert_disconnected(client, 100)
    stream = "thread:" <> thread
    assert %{"method" => "thread/started", "cursor" => 1} = take_owned_notification(owner)
    assert :ok = Client.ack_cursor(client, stream, 1)
    assert Client.checkpoints(client) == %{stream => 1}
    assert :ok = Client.reconnect(client)
    initialize(client)
    assert {:ok, _} = request(client, "thread/resume", %{"thread_id" => thread})

    assert {:ok, %{"cursor" => 2, "events" => [%{"method" => "turn/started"}]}} =
             request(client, "stream/resume", %{
               "stream_id" => stream,
               "cursor" => Client.replay_cursor(client, stream)
             })

    assert %{"method" => "turn/started", "cursor" => 2} = take_owned_notification(owner)
    assert :ok = Client.ack_cursor(client, stream, 2)
    assert :ok = FakeAgent.emit_delta(agent, thread, turn, "Next live event")
    assert %{"method" => "item/delta", "cursor" => 3} = take_owned_notification(owner)
    assert :ok = Client.ack_cursor(client, stream, 3)
    checkpoints = Client.checkpoints(client)
    assert checkpoints == %{stream => 3}
    Client.close(client)

    {:ok, restored} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities,
        checkpoints: checkpoints
      )

    assert Client.checkpoints(restored) == checkpoints
    assert Client.replay_cursor(restored, stream) == 3
  end

  test "cancellation IDs belong to a connection", %{agent: agent, client: first} do
    {:ok, second} =
      Client.connect(FakeAgent.url(agent),
        token: "isolated-test-token",
        capabilities: @capabilities
      )

    initialize(first)
    initialize(second)
    assert {:ok, %{"thread_id" => first_thread}} = request(first, "thread/start", %{})
    assert {:ok, %{"thread_id" => second_thread}} = request(second, "thread/start", %{})
    input = [%{"type" => "text", "text" => "Same local request ID"}]

    assert {:ok, %{"turn_id" => first_turn}} =
             request(first, "turn/start", %{"thread_id" => first_thread, "input" => input},
               id: "local-id"
             )

    assert {:ok, %{"turn_id" => second_turn}} =
             request(second, "turn/start", %{"thread_id" => second_thread, "input" => input},
               id: "local-id"
             )

    assert {:ok, %{"status" => "requested"}} =
             request(first, "request/cancel", %{"request_id" => "local-id"})

    assert {:error, %{code: "conflict"}} =
             FakeAgent.emit_delta(agent, first_thread, first_turn, "Stopped")

    assert :ok = FakeAgent.emit_delta(agent, second_thread, second_turn, "Still running")
  end

  defp controlled_owner do
    receive do
      {:forward_one, caller, ref} ->
        receive do
          {:samgita_protocol, _client, {:notification, message}} -> send(caller, {ref, message})
        end

        controlled_owner()

      :stop ->
        :ok
    end
  end

  defp take_owned_notification(owner) do
    ref = make_ref()
    send(owner, {:forward_one, self(), ref})
    assert_receive {^ref, message}
    message
  end

  defp assert_disconnected(client, attempts) do
    if :sys.get_state(client).conn == nil do
      :ok
    else
      assert attempts > 0
      Process.sleep(5)
      assert_disconnected(client, attempts - 1)
    end
  end

  defp initialize(client) do
    assert {:ok, %{"version" => "1.0", "capabilities" => @capabilities}} =
             request(client, "connection/initialize", %{
               "versions" => ["1.0"],
               "capabilities" => @capabilities,
               "required_capabilities" => []
             })
  end

  defp start_turn(client) do
    assert {:ok, %{"thread_id" => thread}} = request(client, "thread/start", %{})

    assert {:ok, %{"turn_id" => turn}} =
             request(client, "turn/start", %{
               "thread_id" => thread,
               "input" => [%{"type" => "text", "text" => "Example"}]
             })

    {thread, turn}
  end

  defp request(client, method, params, extra \\ []) do
    id = Integer.to_string(System.unique_integer([:positive]))

    Client.request(
      client,
      method,
      params,
      Keyword.merge(
        [id: id, correlation_id: "correlation-" <> id, command_id: "command-" <> id],
        extra
      )
    )
  end

  defp event(id, delivery) do
    %{
      "schema_version" => "1.0",
      "event_id" => id,
      "delivery_attempt_id" => delivery,
      "created_at" => "2026-10-22T00:00:00Z",
      "correlation_id" => "event-correlation",
      "type" => "project.updated",
      "payload" => %{"summary" => "Example"}
    }
  end
end
