defmodule SamgitaCodexDriver.SessionCapacityDeadlineTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  test "a sent mutation deadline remains uncertain after late reply and reconnect" do
    pid = ready()

    task =
      Task.async(fn ->
        Session.request(pid, "thread/start", %{}, id: "expired-mutation", timeout_ms: 30)
      end)

    assert_receive {:sent, ^pid, %{"id" => "expired-mutation", "method" => "thread/start"}}, 2_000
    assert {:error, %Error{code: :deadline_exceeded, uncertain: true}} = Task.await(task)
    assert %{phase: :ready, pending: 0, uncertain: 1} = Session.status(pid)

    assert [%{id: "expired-mutation", generation: 1, reason: :deadline_exceeded}] =
             Session.uncertain_operations(pid)

    late = %{"id" => "expired-mutation", "result" => %{"thread" => %{"id" => "remote-thread"}}}
    send(pid, {:incoming, late})
    assert {:ok, [%{kind: :late_response, wire: ^late}]} = Session.drain(pid)
    assert %{pending: 0, uncertain: 1} = Session.status(pid)
    assert :ok = Session.reconnect(pid)
    initialize(pid)
    assert %{generation: 2, pending: 0, uncertain: 1} = Session.status(pid)
    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}

    assert {:error, %Error{code: :invalid_or_reused_request_id, uncertain: false}} =
             Session.request(pid, "thread/start", %{}, id: "expired-mutation")

    assert {:error, %Error{code: :invalid_reconciliation}} =
             Session.record_reconciliation(pid, "expired-mutation", :applied, "not-a-digest")

    assert Session.status(pid).uncertain == 1
    assert :ok = Session.record_reconciliation(pid, "expired-mutation", :applied, digest())
    assert Session.uncertain_operations(pid) == []

    assert {:error, %Error{code: :invalid_reconciliation}} =
             Session.record_reconciliation(pid, "expired-mutation", :applied, digest())

    refute_receive {:sent, ^pid, %{"method" => "thread/start"}}
    assert Session.status(pid).pending == 0
  end

  test "pending capacity rejects without dispatch and recovers after exact settlement" do
    pid = ready(max_pending: 1)
    held = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: "held-read") end)
    assert_receive {:sent, ^pid, %{"id" => "held-read", "method" => "thread/list"}}, 2_000

    assert {:error, %Error{code: :too_many_requests, uncertain: false}} =
             Session.request(pid, "thread/start", %{}, id: "rejected-capacity")

    assert %{pending: 1, uncertain: 0, phase: :ready} = Session.status(pid)
    refute_receive {:sent, ^pid, %{"id" => "rejected-capacity"}}
    reply = %{"id" => "held-read", "result" => %{"data" => []}}
    send(pid, {:incoming, reply})
    assert {:ok, ^reply} = Task.await(held)
    assert %{pending: 0, uncertain: 0} = Session.status(pid)
    assert_read(pid, "rejected-capacity")
  end

  test "uncertainty reserves pending mutations and permits reads until explicit reconciliation" do
    pid = ready(max_uncertain: 1)
    held = Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "uncertain-slot") end)
    assert_receive {:sent, ^pid, %{"id" => "uncertain-slot", "method" => "thread/start"}}, 2_000
    assert_reconciliation_gate(pid, "pending-reject")
    assert_read(pid, "read-with-pending-mutation")
    assert :ok = Session.abandon(pid, "uncertain-slot")
    assert {:error, %Error{code: :locally_abandoned, uncertain: true}} = Task.await(held)
    assert %{pending: 0, uncertain: 1, phase: :ready} = Session.status(pid)
    assert_reconciliation_gate(pid, "uncertain-reject")
    assert_read(pid, "read-with-uncertain-mutation")
    assert :ok = Session.record_reconciliation(pid, "uncertain-slot", :not_applied, digest())

    replacement =
      Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "explicit-new") end)

    assert_receive {:sent, ^pid, %{"id" => "explicit-new", "method" => "thread/start"}}, 2_000
    assert :ok = Session.abandon(pid, "explicit-new")
    assert {:error, %Error{code: :locally_abandoned, uncertain: true}} = Task.await(replacement)
    assert [%{id: "explicit-new"}] = Session.uncertain_operations(pid)
    assert :ok = Session.record_reconciliation(pid, "explicit-new", :abandoned, digest())
    assert %{pending: 0, uncertain: 0, phase: :ready} = Session.status(pid)
  end

  test "request ID quota includes initialization and resets only on explicit reconnect" do
    pid = ready(max_request_ids: 2)
    assert_read(pid, 1)

    assert {:error, %Error{code: :connection_id_limit, uncertain: false}} =
             Session.request(pid, "thread/list", %{}, id: "no-room")

    refute_receive {:sent, ^pid, %{"id" => "no-room"}}
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    assert :ok = Session.reconnect(pid)
    refute_receive {:sent, ^pid, %{"method" => "thread/list"}}
    initialize(pid)
    assert Session.status(pid).generation == 2
    assert_read(pid, 1)

    assert {:error, %Error{code: :connection_id_limit, uncertain: false}} =
             Session.request(pid, "thread/start", %{}, id: "no-room-again")

    refute_receive {:sent, ^pid, %{"id" => "no-room-again"}}
  end

  test "interaction saturation exposes a gap and invalidates the retained approval handle" do
    pid = ready(max_interactions: 1)
    first = approval("first")
    send(pid, {:incoming, first})
    assert {:ok, [%{kind: :server_request, wire: ^first, handle: handle}]} = Session.drain(pid)
    send(pid, {:incoming, approval("second")})

    assert %{phase: :disconnected, interactions: 0, gap: %{reason: :interaction_overflow}} =
             Session.status(pid)

    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :interaction_overflow}}}, 2_000

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})

    refute_receive {:sent, ^pid, %{"result" => _}}
    assert Session.interaction_outcomes(pid) == []
  end

  test "outcome saturation preserves uncertain response evidence without admitting another approval" do
    pid = ready(max_interaction_outcomes: 1)
    send(pid, {:incoming, approval("answered")})
    assert {:ok, [%{handle: handle}]} = Session.drain(pid)
    assert :ok = Session.respond(pid, handle, {:ok, %{"decision" => "decline"}})
    assert_receive {:sent, ^pid, %{"id" => "answered", "result" => %{"decision" => "decline"}}}

    assert [%{handle: ^handle, status: :sent_unconfirmed, response_digest: proof}] =
             Session.interaction_outcomes(pid)

    send(pid, {:incoming, approval("blocked-outcome")})

    assert %{phase: :disconnected, gap: %{reason: :interaction_outcome_overflow}} =
             Session.status(pid)

    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :interaction_outcome_overflow}}}, 2_000

    assert [%{handle: ^handle, status: :uncertain, response_digest: ^proof}] =
             Session.interaction_outcomes(pid)

    assert byte_size(proof) == 64
    refute_receive {:sent, ^pid, %{"id" => "blocked-outcome"}}
    assert :ok = Session.acknowledge_interaction_outcome(pid, handle)
    assert Session.interaction_outcomes(pid) == []
    assert Session.status(pid).phase == :disconnected
  end

  test "byte overflow of a critical request exposes the gap and leaves mutation uncertainty" do
    wire = approval("oversized-approval")
    {:ok, encoded} = SamgitaProtocolCodex.Wire.encode(wire)
    pid = ready(max_event_bytes: byte_size(encoded) - 1)
    held = Task.async(fn -> Session.request(pid, "thread/start", %{}, id: "held-mutation") end)
    assert_receive {:sent, ^pid, %{"id" => "held-mutation", "method" => "thread/start"}}, 2_000
    send(pid, {:incoming, wire})
    assert {:error, %Error{code: :event_buffer_overflow, uncertain: true}} = Task.await(held)
    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :event_buffer_overflow}}}, 2_000

    assert %{phase: :disconnected, interactions: 0, buffered_events: 0, buffered_bytes: 0} =
             Session.status(pid)

    assert [%{id: "held-mutation", reason: :event_buffer_overflow}] =
             Session.uncertain_operations(pid)

    assert {:ok, []} = Session.drain(pid)
    refute_receive {:sent, ^pid, %{"id" => "oversized-approval"}}
  end

  defp assert_reconciliation_gate(pid, id) do
    assert {:error, %Error{code: :reconciliation_required, uncertain: false}} =
             Session.request(pid, "thread/start", %{}, id: id)

    refute_receive {:sent, ^pid, %{"id" => ^id}}
  end

  defp assert_read(pid, id) do
    task = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: id) end)
    assert_receive {:sent, ^pid, %{"id" => ^id, "method" => "thread/list"}}, 2_000
    reply = %{"id" => id, "result" => %{"data" => []}}
    send(pid, {:incoming, reply})
    assert {:ok, ^reply} = Task.await(task)
  end

  defp ready(opts \\ []) do
    opts =
      opts
      |> Keyword.put(:owner, self())
      |> Keyword.put(:transport, {ScriptedTransport, observer: self()})

    pid = start_supervised!({Session, opts}, id: make_ref())
    assert_receive {:transport_opened, ^pid}
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    task =
      Task.async(fn ->
        Session.initialize(pid, %{"name" => "capacity_deadline", "version" => "0.1.0"})
      end)

    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => id, "result" => result}})
    assert {:ok, %{"id" => ^id, "result" => ^result}} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
    assert Session.status(pid).phase == :ready
  end

  defp approval(id) do
    %{
      "id" => id,
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "itemId" => id,
        "startedAtMs" => 1
      }
    }
  end

  defp digest, do: String.duplicate("a", 64)
end
