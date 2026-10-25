defmodule SamgitaCodexDriver.SessionTest do
  use ExUnit.Case, async: true
  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  test "process identity is stable across reconnects and distinct from another Session" do
    one = connection()
    two = connection()
    assert %{instance_id: instance, generation: 1} = Session.status(one)

    assert Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
             instance
           )

    refute Session.status(two).instance_id == instance
    assert :ok = Session.reconnect(one)
    assert %{instance_id: ^instance, generation: 2} = Session.status(one)
  end

  test "initialization gates calls and sends initialized only after success" do
    pid = connection()
    assert {:error, %Error{code: :not_initialized}} = Session.request(pid, "thread/list")
    initialize(pid)
    assert Session.status(pid).phase == :ready

    assert {:error, %Error{code: :invalid_initialization_state}} =
             Session.initialize(pid, info())

    assert {:error, %Error{code: :use_initialize}} = Session.request(pid, "initialize")
    refute_receive {:sent, ^pid, %{"method" => "initialize"}}
  end

  test "native dispatch rejects a ticket captured before reconnect and another process instance" do
    pid = ready()
    previous = Session.status(pid)
    assert :ok = Session.reconnect(pid)
    initialize(pid)
    wire = %{"id" => "stale-ticket", "method" => "thread/start", "params" => %{}}

    for expected <- [
          [expected_instance_id: previous.instance_id, expected_generation: previous.generation],
          [expected_instance_id: "another-instance", expected_generation: 2]
        ] do
      assert {:error, %Error{code: :stale_session, uncertain: false}} =
               Session.request_native(pid, wire, expected ++ [timeout_ms: 30])

      refute_receive {:sent, ^pid, ^wire}
    end

    assert Session.status(pid).pending == 0
    assert Session.uncertain_operations(pid) == []
  end

  test "a dispatch deadline expires while the native request waits in the Session mailbox" do
    pid = ready()
    status = Session.status(pid)
    wire = %{"id" => "queued-ticket", "method" => "thread/start", "params" => %{}}
    assert :ok = :sys.suspend(pid)
    deadline = System.system_time(:millisecond) + 100

    task =
      Task.async(fn ->
        Session.request_native(pid, wire,
          expected_instance_id: status.instance_id,
          expected_generation: status.generation,
          dispatch_deadline_ms: deadline,
          timeout_ms: 30
        )
      end)

    assert Task.yield(task, 120) == nil
    assert :ok = :sys.resume(pid)
    assert {:error, %Error{code: :dispatch_expired, uncertain: false}} = Task.await(task)
    refute_receive {:sent, ^pid, ^wire}
    assert Session.uncertain_operations(pid) == []
  end

  test "response dispatch guards reject expired or wrong-instance tickets without consuming approval" do
    pid = ready()
    status = Session.status(pid)
    send(pid, {:incoming, approval("guarded-response")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)
    decision = {:ok, %{"decision" => "decline"}}

    for {opts, code} <- [
          {[expected_instance_id: "other"], :stale_session},
          {[expected_generation: status.generation + 1], :stale_session},
          {[dispatch_deadline_ms: System.system_time(:millisecond) - 1], :dispatch_expired}
        ] do
      assert {:error, %Error{code: ^code, uncertain: false}} =
               Session.respond(pid, handle, decision, opts)

      refute_receive {:sent, ^pid, %{"id" => "guarded-response", "result" => _}}
      assert Session.status(pid).interactions == 1
    end

    assert :ok =
             Session.respond(pid, handle, decision,
               expected_instance_id: status.instance_id,
               expected_generation: status.generation,
               dispatch_deadline_ms: System.system_time(:millisecond) + 5_000
             )
  end

  test "concurrent out-of-order replies settle by typed ID without field loss" do
    pid = ready()

    one = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: 1, effect: :read) end)
    assert_receive {:sent, ^pid, %{"id" => 1}}, 2_000
    two = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: "1", effect: :read) end)
    assert_receive {:sent, ^pid, %{"id" => "1"}}, 2_000

    second = %{"id" => "1", "result" => %{"data" => [], "extension" => %{"null" => nil}}}
    send(pid, {:incoming, second})
    assert {:ok, ^second} = Task.await(two)
    first = %{"id" => 1, "result" => %{"data" => [], "nextCursor" => nil}}
    send(pid, {:incoming, first})
    assert {:ok, ^first} = Task.await(one)
    assert Session.status(pid).pending == 0

    assert {:error, %Error{code: :invalid_or_reused_request_id}} =
             Session.request(pid, "thread/list", %{}, id: 1)
  end

  test "native structured errors survive but inspect and exception output redact them" do
    pid = ready()
    task = Task.async(fn -> Session.request(pid, "thread/read", %{"threadId" => "missing"}) end)
    assert_receive {:sent, ^pid, %{"id" => id, "method" => "thread/read"}}, 2_000

    wire = %{
      "id" => id,
      "error" => %{"code" => -32_000, "message" => "synthetic-secret", "data" => [nil, 9]}
    }

    send(pid, {:incoming, wire})
    assert {:error, %Error{wire: ^wire} = failure} = Task.await(task)
    refute inspect(failure) =~ "synthetic-secret"
    refute Exception.message(failure) =~ "synthetic-secret"
  end

  test "server request ID can collide with client ID and requires an explicit decision" do
    pid = ready()
    task = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: 7) end)
    assert_receive {:sent, ^pid, %{"id" => 7, "method" => "thread/list"}}, 2_000
    send(pid, {:incoming, approval(7)})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{kind: :server_request, handle: handle, wire: wire}]} = Session.drain(pid)
    assert wire == approval(7)
    refute_receive {:sent, ^pid, %{"id" => 7, "result" => _}}
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})
    assert_receive {:sent, ^pid, %{"id" => 7, "result" => %{"decision" => "decline"}}}

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, handle, {:ok, %{"decision" => "accept"}})

    send(pid, {:incoming, %{"id" => 7, "result" => %{"data" => []}}})
    assert {:ok, _} = Task.await(task)
  end

  test "unknown server request fails explicitly and retains its original payload" do
    pid = ready()
    wire = %{"id" => "future", "method" => "future/approval", "params" => %{"opaque" => nil}}
    send(pid, {:incoming, wire})
    assert_receive {:sent, ^pid, %{"id" => "future", "error" => %{"code" => -32_601}}}
    assert {:ok, [%{kind: :unsupported_server_request, wire: ^wire}]} = Session.drain(pid)
    assert Session.status(pid).interactions == 0
  end

  test "resolved and expired interactions cannot accept late decisions" do
    pid = ready(interaction_timeout_ms: 500)
    send(pid, {:incoming, approval("resolved")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)

    send(
      pid,
      {:incoming,
       %{
         "method" => "serverRequest/resolved",
         "params" => %{"threadId" => "thread", "requestId" => "resolved"}
       }}
    )

    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert Session.status(pid).interactions == 0

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, handle, {:ok, %{"decision" => "accept"}})

    Session.drain(pid)
    send(pid, {:incoming, approval("expired")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: expired}]} = Session.drain(pid)
    assert_receive {:sent, ^pid, %{"id" => "expired", "error" => _}}, 2_000
    assert Session.status(pid).interactions == 0

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, expired, {:ok, %{"decision" => "accept"}})
  end

  test "disconnect exposes uncertainty, cleans pending state and never replays mutations" do
    pid = ready()
    task = Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "operation") end)
    assert_receive {:sent, ^pid, %{"id" => "operation", "method" => "thread/start"}}, 2_000
    send(pid, :drop_connection)
    assert {:error, %Error{uncertain: true}} = Task.await(task)
    assert [%{id: "operation", method: "thread/start"}] = Session.uncertain_operations(pid)
    assert %{pending: 0, interactions: 0, phase: :disconnected, gap: %{}} = Session.status(pid)

    assert :ok = Session.reconnect(pid)
    assert_receive {:transport_opened, ^pid}
    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}
    initialize(pid)
    assert Session.status(pid).generation == 2

    assert {:error, %Error{code: :invalid_or_reused_request_id}} =
             Session.request(pid, "thread/start", %{}, id: "operation")

    assert :ok =
             Session.record_reconciliation(
               pid,
               "operation",
               :abandoned,
               String.duplicate("a", 64)
             )

    assert [] = Session.uncertain_operations(pid)
    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}
  end

  test "a response deadline settles once and a late response is observable" do
    pid = ready()

    task =
      Task.async(fn ->
        Session.request(pid, "thread/list", %{}, timeout_ms: 30, effect: :read)
      end)

    assert_receive {:sent, ^pid, %{"id" => id, "method" => "thread/list"}}, 2_000
    assert {:error, %Error{code: :deadline_exceeded, uncertain: false}} = Task.await(task)
    send(pid, {:incoming, %{"id" => id, "result" => %{"data" => []}}})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{kind: :late_response}]} = Session.drain(pid)
    assert Session.status(pid).pending == 0
  end

  test "send failure is conservative and does not leak pending requests" do
    pid = ready([], fail_method: "thread/start")
    assert {:error, %Error{uncertain: true}} = Session.request(pid, "thread/start", %{})
    assert Session.status(pid).phase == :disconnected
    assert Session.status(pid).pending == 0
    assert length(Session.uncertain_operations(pid)) == 1
  end

  test "unconfirmed owned shutdown settles mutations uncertain and blocks reconnect" do
    pid = ready([], fail_close: true)
    task = Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "held") end)
    assert_receive {:sent, ^pid, %{"id" => "held"}}, 2_000

    assert {:error, %Error{code: :owned_process_shutdown_unconfirmed}} = Session.close(pid)
    assert {:error, %Error{uncertain: true}} = Task.await(task)
    assert %{phase: :shutdown_failed, pending: 0, uncertain: 1} = Session.status(pid)

    assert {:error, %Error{code: :owned_process_shutdown_unconfirmed}} = Session.reconnect(pid)
    refute_receive {:transport_opened, ^pid}
    assert [%{id: "held"}] = Session.uncertain_operations(pid)
  end

  test "bounded pull delivery has one wakeup and overflow exposes the lost-history gap" do
    pid = ready(max_events: 2)
    wire = %{"method" => "future/event", "params" => %{"data" => "kept"}}
    send(pid, {:incoming, wire})
    send(pid, {:incoming, wire})
    send(pid, {:incoming, wire})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :event_buffer_overflow}}}, 2_000
    refute_receive {:codex_driver, ^pid, :events_available}
    assert %{buffered_events: 2, phase: :disconnected} = Session.status(pid)
    assert {:ok, [%{wire: ^wire}, %{wire: ^wire}]} = Session.drain(pid)
    assert %{buffered_events: 0, buffered_bytes: 0} = Session.status(pid)
  end

  test "old handles and changed handles cannot authorize responses after reconnect" do
    pid = ready()
    send(pid, {:incoming, approval("same")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: old}]} = Session.drain(pid)
    assert :ok = Session.reconnect(pid)
    initialize(pid)
    send(pid, {:incoming, approval("same")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: current}]} = Session.drain(pid)

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, old, {:ok, %{"decision" => "accept"}})

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(
               pid,
               %{current | reference: make_ref()},
               {:ok, %{"decision" => "accept"}}
             )

    assert :ok = Session.respond(pid, current, {:ok, %{"decision" => "cancel"}})
  end

  test "local cancellation does not invent upstream cancellation or cessation" do
    pid = ready()
    task = Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "abandon") end)
    assert_receive {:sent, ^pid, %{"id" => "abandon"}}, 2_000
    assert :ok = Session.abandon(pid, "abandon")
    assert {:error, %Error{code: :locally_abandoned, uncertain: true}} = Task.await(task)
    refute_receive {:sent, ^pid, %{"method" => "$/cancelRequest"}}
    assert Session.status(pid).pending == 0
  end

  test "initialization timeout requires a new connection" do
    pid = connection(request_timeout_ms: 30)
    assert {:error, %Error{code: :deadline_exceeded}} = Session.initialize(pid, info())
    assert Session.status(pid).phase == :disconnected

    assert {:error, %Error{code: :invalid_initialization_state}} =
             Session.initialize(pid, info())
  end

  test "native calls retain envelope extensions and omitted parameters" do
    pid = ready()

    wire = %{
      "id" => "native",
      "method" => "thread/list",
      "trace" => %{"traceparent" => "synthetic-trace", "future" => nil},
      "future" => %{"preserved" => true}
    }

    call = Task.async(fn -> Session.request_native(pid, wire, validation: :wire) end)
    assert_receive {:sent, ^pid, ^wire}, 2_000
    response = %{"id" => "native", "result" => %{"data" => []}}
    send(pid, {:incoming, response})
    assert {:ok, ^response} = Task.await(call)
  end

  test "native initialization handles invalid capabilities without crashing" do
    pid = connection()
    invalid = %{"id" => "bad-init", "method" => "initialize", "params" => %{"capabilities" => []}}
    assert {:error, %Error{}} = Session.request_native(pid, invalid)
    assert Session.status(pid).phase == :new

    wire = %{
      "id" => "native-init",
      "method" => "initialize",
      "params" => %{"clientInfo" => info()},
      "future" => nil
    }

    call = Task.async(fn -> Session.request_native(pid, wire) end)
    assert_receive {:sent, ^pid, ^wire}, 2_000

    result = %{
      "userAgent" => "codex",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => "native-init", "result" => result}})
    assert {:ok, _} = Task.await(call)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
    assert Session.status(pid).phase == :ready
  end

  test "callers cannot classify a mutating request as a safe read" do
    pid = ready()

    assert {:error, %Error{code: :unsafe_read_classification, uncertain: false}} =
             Session.request(pid, "thread/start", %{}, effect: :read)

    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}
    assert Session.status(pid).pending == 0
  end

  test "local response encoding failure leaves the interaction usable and outcome certain" do
    pid = ready(max_message_bytes: 500)
    send(pid, {:incoming, approval("bounded")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)

    assert {:error, %Error{uncertain: false}} =
             Session.respond(
               pid,
               handle,
               {:error, %{"code" => -32_000, "message" => String.duplicate("x", 1_000)}}
             )

    assert %{phase: :ready, interactions: 1, interaction_outcomes: 0} = Session.status(pid)
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})
  end

  test "interaction sends expose unconfirmed resolution and disconnect uncertainty" do
    pid = ready()
    send(pid, {:incoming, approval("sent")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})

    assert [%{handle: ^handle, status: :sent_unconfirmed, response_digest: digest}] =
             Session.interaction_outcomes(pid)

    assert byte_size(digest) == 64

    send(pid, :drop_connection)
    assert %{phase: :disconnected} = Session.status(pid)
    assert [%{handle: ^handle, status: :uncertain}] = Session.interaction_outcomes(pid)
    assert :ok = Session.acknowledge_interaction_outcome(pid, handle)
    assert [] = Session.interaction_outcomes(pid)

    assert {:error, %Error{code: :unknown_interaction_outcome}} =
             Session.acknowledge_interaction_outcome(pid, handle)
  end

  test "failed transport response sends retain a bounded uncertain outcome" do
    pid = ready([], fail_response: true)
    send(pid, {:incoming, approval("failed-send")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)

    assert {:error, %Error{uncertain: true}} =
             Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})

    assert %{phase: :disconnected, interactions: 0} = Session.status(pid)
    assert [%{handle: ^handle, status: :uncertain}] = Session.interaction_outcomes(pid)
  end

  test "resolved notifications are thread-bound and never prove approval acceptance" do
    pid = ready()
    send(pid, {:incoming, approval("resolution")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})

    for {thread, expected} <- [
          {"other-thread", :sent_unconfirmed},
          {"thread", :resolution_observed}
        ] do
      send(
        pid,
        {:incoming,
         %{
           "method" => "serverRequest/resolved",
           "params" => %{"threadId" => thread, "requestId" => "resolution"}
         }}
      )

      assert_receive {:codex_driver, ^pid, :events_available}, 2_000
      assert {:ok, [_]} = Session.drain(pid)
      assert [%{status: ^expected}] = Session.interaction_outcomes(pid)
    end
  end

  test "unconsumed interaction outcomes bound new interaction capacity" do
    pid = ready(max_interaction_outcomes: 1)
    send(pid, {:incoming, approval("first")})
    assert_receive {:codex_driver, ^pid, :events_available}, 2_000
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})
    send(pid, {:incoming, approval("second")})
    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :interaction_outcome_overflow}}}, 2_000
    assert %{phase: :disconnected, interactions: 0, interaction_outcomes: 1} = Session.status(pid)
  end

  test "abandoning initialization closes its connection" do
    pid = connection()
    call = Task.async(fn -> Session.initialize(pid, info(), %{}, id: "abandoned-init") end)
    assert_receive {:sent, ^pid, %{"id" => "abandoned-init"}}, 2_000
    assert :ok = Session.abandon(pid, "abandoned-init")
    assert {:error, %Error{code: :locally_abandoned, uncertain: false}} = Task.await(call)
    assert %{phase: :disconnected, pending: 0} = Session.status(pid)
  end

  test "caller death releases pending state without retrying its mutation" do
    pid = ready()
    caller = spawn(fn -> Session.request(pid, "thread/start", %{}, id: "caller-died") end)
    assert_receive {:sent, ^pid, %{"id" => "caller-died"}}, 2_000
    monitor = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 2_000
    await_pending_cleanup(pid, System.monotonic_time(:millisecond) + 2_000)
    assert [%{id: "caller-died", reason: :caller_down}] = Session.uncertain_operations(pid)
    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}
  end

  defp await_pending_cleanup(pid, deadline) do
    if Session.status(pid).pending != 0 do
      assert System.monotonic_time(:millisecond) < deadline

      receive do
      after
        1 -> await_pending_cleanup(pid, deadline)
      end
    end
  end

  defp connection(opts \\ [], transport_opts \\ []) do
    opts =
      Keyword.put(
        opts,
        :transport,
        {ScriptedTransport, Keyword.put(transport_opts, :observer, self())}
      )

    pid = start_supervised!({Session, Keyword.put(opts, :owner, self())}, id: make_ref())
    assert_receive {:transport_opened, ^pid}
    pid
  end

  defp ready(opts \\ [], transport_opts \\ []) do
    pid = connection(opts, transport_opts)
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    task = Task.async(fn -> Session.initialize(pid, info()) end)
    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => id, "result" => result}})
    assert {:ok, %{"result" => ^result}} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
  end

  defp info, do: %{"name" => "session_test", "version" => "0.1.0"}

  defp approval(id) do
    %{
      "id" => id,
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "itemId" => "item",
        "startedAtMs" => 1
      }
    }
  end
end
