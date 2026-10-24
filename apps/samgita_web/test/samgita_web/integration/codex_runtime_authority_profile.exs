defmodule SamgitaWeb.CodexRuntimeAuthorityProfile do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures, only: [command: 1]

  import SamgitaWeb.CodexRuntimeFixture,
    only: [
      pending_authority_fixture: 0,
      pending_authority_fixture: 1,
      authority_snapshot: 1,
      assert_native_pending: 4
    ]

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{CodexRuntime, Error, Platform, Principal, Repo, Tasks}
  alias Samgita.CodexRuntime.Driver
  alias Samgita.Domain.{CommandReceipt, TaskAttempt}
  alias Samgita.Domain.Task, as: DomainTask
  alias SamgitaCodexDriver.{ModelFixture, Session}

  @moduletag :e2e
  @moduletag timeout: 90_000
  @databases ~w(samgita_redesign_codex_authority_repair_test samgita_redesign_codex_authority_ci_test)
  @retained_schemas [
    Samgita.Domain.Project,
    Samgita.Domain.Agent,
    Samgita.Domain.AgentCredential,
    Samgita.Domain.AgentConnection,
    Samgita.Domain.ExecutionSession,
    Samgita.Domain.ProjectAgent,
    DomainTask,
    TaskAttempt,
    Samgita.Domain.NativeRuntimeBinding,
    Samgita.Domain.NativeRuntimeOperation,
    Samgita.Domain.NativeRuntimeEvent,
    Samgita.Domain.NativeRuntimeLink,
    Samgita.Domain.DomainEvent,
    CommandReceipt,
    Oban.Job
  ]

  setup_all do
    database = System.fetch_env!("SAMGITA_TEST_DATABASE")
    assert database in @databases
    Sandbox.unboxed_run(Repo, fn -> database_backend!(database) end)
    {:ok, database: database}
  end

  test "committed management fencing rejects a waiting real native approval dispatch", %{
    database: database
  } do
    {ctx, pid, fixture, event, operation, receipt, before, retained} =
      Sandbox.unboxed_run(Repo, fn ->
        database_backend!(database)
        retained = retained_records()
        {ctx, pid, fixture, event, recorded} = pending_authority_fixture()

        reply =
          command(%{
            "expected_version" => recorded["version"],
            "native" => %{"id" => event.wire["id"], "result" => %{"decision" => "accept"}}
          })

        assert {:ok, operation} =
                 CodexRuntime.reply(
                   Principal.operator(),
                   ctx.project["id"],
                   ctx.runtime["id"],
                   recorded["id"],
                   reply
                 )

        receipt =
          Repo.get_by!(CommandReceipt, principal: "operator", command_id: reply["command_id"])

        before = snapshot(ctx, receipt.id)
        assert before.task.state == "in_progress"
        assert before.attempt.state == "running"
        assert before.event.state == "reply_prepared"
        stored = Enum.find(before.operations, &(&1.id == operation["id"]))
        assert stored.state == "prepared"
        assert stored.dispatch_token_digest == nil
        assert stored.dispatch_expires_at == nil
        assert_native_pending(ctx, pid, fixture, event)
        {ctx, pid, fixture, event, operation, receipt, before, retained}
      end)

    provider_requests = ModelFixture.requests(fixture)
    owner = self()
    commit_ref = make_ref()

    management =
      start_worker(fn -> hold_management(ctx, receipt.id, database, owner, commit_ref) end)

    management_pid = management.pid

    {management_backend, expected} =
      receive do
        {:management_ready, ^management_pid, backend, expected} -> {backend, expected}
      after
        5_000 -> flunk("native authority management transaction did not reach its barrier")
      end

    assert_management_delta(before, expected.snapshot, expected.commands)

    dispatch =
      start_worker(fn ->
        backend = database_backend!(database)
        send(owner, {:dispatch_ready, self(), backend})
        dispatch(ctx, operation)
      end)

    dispatch_pid = dispatch.pid

    dispatch_backend =
      receive do
        {:dispatch_ready, ^dispatch_pid, backend} -> backend
      after
        5_000 -> flunk("native authority dispatch did not check out its independent backend")
      end

    Sandbox.unboxed_run(Repo, fn ->
      observer_backend = database_backend!(database)
      assert length(Enum.uniq([management_backend, dispatch_backend, observer_backend])) == 3

      await_blocker!(
        management_backend,
        dispatch_backend,
        System.monotonic_time(:millisecond) + 5_000
      )

      assert Process.alive?(dispatch_pid)

      IO.puts(
        "native authority lock barrier database=#{database} management=#{management_backend} dispatch=#{dispatch_backend} observer=#{observer_backend}"
      )
    end)

    # Management commits before this waiting dispatch can acquire its authority
    # locks. This says nothing about revoking a ticket that already committed.
    send(management_pid, {:commit, commit_ref})
    assert {:ok, ^expected} = Task.await(management, 10_000)
    assert Task.await(dispatch, 10_000) == {:error, Error.new(:ownership_lost)}

    Sandbox.unboxed_run(Repo, fn ->
      database_backend!(database)
      assert_preserved(ctx, receipt.id, expected.snapshot, pid, fixture, event, provider_requests)
      assert dispatch(ctx, operation) == {:error, Error.new(:ownership_lost)}
      assert_preserved(ctx, receipt.id, expected.snapshot, pid, fixture, event, provider_requests)

      assert Driver.execute(
               pid,
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"],
               %{"expected_version" => operation["version"], "proof" => ctx.proof},
               interaction_handle: event.handle
             ) == {:error, Error.new(:ownership_lost)}

      assert_preserved(ctx, receipt.id, expected.snapshot, pid, fixture, event, provider_requests)
      assert :ok = Session.close(pid)
      assert snapshot(ctx, receipt.id) == expected.snapshot
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])

      assert {:ok, %{"owner" => "hub", "admission_open" => true}} =
               Platform.status(Principal.operator())

      assert_retained_records(retained)
    end)
  end

  test "a spoofed native interaction reference settles uncertain without consuming the genuine approval",
       %{database: database} do
    Sandbox.unboxed_run(Repo, fn ->
      database_backend!(database)
      retained = retained_records()
      {ctx, pid, fixture, event, recorded} = pending_authority_fixture()

      reply =
        command(%{
          "expected_version" => recorded["version"],
          "native" => %{"id" => event.wire["id"], "result" => %{"decision" => "accept"}}
        })

      assert {:ok, operation} =
               CodexRuntime.reply(
                 Principal.operator(),
                 ctx.project["id"],
                 ctx.runtime["id"],
                 recorded["id"],
                 reply
               )

      receipt =
        Repo.get_by!(CommandReceipt, principal: "operator", command_id: reply["command_id"])

      before = snapshot(ctx, receipt.id)
      stored = Enum.find(before.operations, &(&1.id == operation["id"]))
      assert stored.state == "prepared"
      assert stored.version == operation["version"]
      assert stored.dispatch_token_digest == nil
      assert stored.dispatch_expires_at == nil
      assert stored.response_payload == nil
      assert before.event.state == "reply_prepared"
      provider_requests = ModelFixture.requests(fixture)
      interaction = Map.fetch!(:sys.get_state(pid).interactions, event.handle.id)
      assert interaction.handle == event.handle
      assert_pending_handle(pid, event, interaction)
      assert_native_pending(ctx, pid, fixture, event)

      spoofed = %{event.handle | reference: make_ref()}
      assert spoofed.id == event.wire["id"]
      assert spoofed.generation == before.runtime.driver_generation
      refute spoofed.reference == event.handle.reference

      # Keep the real ID/generation so the bridge reaches Session.respond after
      # committing its ticket. The fresh reference cannot authorize this request.
      assert {:ok, %{"state" => "uncertain"} = settled} =
               Driver.execute(
                 pid,
                 ctx.principal,
                 ctx.project["id"],
                 ctx.runtime["id"],
                 operation["id"],
                 %{"expected_version" => operation["version"], "proof" => ctx.proof},
                 interaction_handle: spoofed
               )

      current = snapshot(ctx, receipt.id)

      settlement_receipt =
        assert_invalid_reference_delta(ctx, before, current, operation, settled)

      assert_preserved(ctx, receipt.id, current, pid, fixture, event, provider_requests)
      assert_pending_handle(pid, event, interaction)

      for _submission <- 1..2 do
        # Use the current version and genuine handle: rejection must be the
        # consumed ticket, rather than a stale version or another forged handle.
        assert dispatch(ctx, settled) ==
                 {:error, Error.new(:conflict, %{reason: "dispatch_not_repeatable"})}

        assert Driver.execute(
                 pid,
                 ctx.principal,
                 ctx.project["id"],
                 ctx.runtime["id"],
                 operation["id"],
                 %{"expected_version" => settled["version"], "proof" => ctx.proof},
                 interaction_handle: event.handle
               ) == {:error, Error.new(:conflict, %{reason: "dispatch_not_repeatable"})}

        assert {:error,
                %SamgitaProtocolCodex.Error{
                  code: :stale_interaction,
                  uncertain: false,
                  wire: nil
                }} = Session.respond(pid, spoofed, {:ok, %{"decision" => "accept"}})

        assert_preserved(ctx, receipt.id, current, pid, fixture, event, provider_requests)
        assert_pending_handle(pid, event, interaction)
        assert Repo.get!(CommandReceipt, settlement_receipt.id) == settlement_receipt
        assert_retained_records(retained)
      end

      assert :ok = Session.close(pid)
      assert snapshot(ctx, receipt.id) == current
      assert Repo.get!(CommandReceipt, settlement_receipt.id) == settlement_receipt
      assert ModelFixture.requests(fixture) == provider_requests
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])

      assert {:ok, %{"owner" => "hub", "admission_open" => true}} =
               Platform.status(Principal.operator())

      assert_retained_records(retained)
    end)
  end

  defp assert_pending_handle(pid, event, interaction) do
    assert :sys.get_state(pid).interactions == %{event.handle.id => interaction}
    assert Session.interaction_outcomes(pid) == []
    assert %{interaction_outcomes: 0, gap: nil} = Session.status(pid)
  end

  defp assert_invalid_reference_delta(ctx, before, current, operation, settled) do
    previous = Enum.find(before.operations, &(&1.id == operation["id"]))
    stored = Enum.find(current.operations, &(&1.id == operation["id"]))
    assert settled["id"] == previous.id
    assert settled["version"] == previous.version + 2
    assert is_binary(stored.dispatch_token_digest)
    assert byte_size(stored.dispatch_token_digest) == 32
    assert %DateTime{} = stored.dispatch_expires_at

    for deadline <- [before.attempt.execution_deadline, before.attempt.lease_expires_at] do
      assert DateTime.compare(stored.dispatch_expires_at, deadline) in [:lt, :eq]
    end

    assert stored == %{
             previous
             | state: "uncertain",
               version: previous.version + 2,
               dispatch_token_digest: stored.dispatch_token_digest,
               dispatch_expires_at: stored.dispatch_expires_at,
               updated_at: stored.updated_at
           }

    assert current.operations ==
             Enum.map(before.operations, fn record ->
               if record.id == previous.id, do: stored, else: record
             end)

    assert current.event == %{
             before.event
             | state: "uncertain",
               version: before.event.version + 1
           }

    assert current.events ==
             Enum.map(before.events, fn record ->
               if record.id == before.event.id, do: current.event, else: record
             end)

    assert current.project == %{
             before.project
             | event_sequence: before.project.event_sequence + 2
           }

    changed = [:project, :operations, :event, :events, :audit, :receipts]
    assert Map.drop(current, changed) == Map.drop(before, changed)
    assert current.receipts == before.receipts + 1
    old_events = Map.new(before.audit, &{&1.id, &1})
    assert Map.take(Map.new(current.audit, &{&1.id, &1}), Map.keys(old_events)) == old_events
    added = Enum.reject(current.audit, &Map.has_key?(old_events, &1.id))
    assert [dispatched, settled_event] = Enum.sort_by(added, & &1.sequence)
    assert dispatched.type == "native_operation.dispatched"
    assert dispatched.command_id == previous.id
    assert settled_event.type == "native_operation.settled"
    assert dispatched.sequence == before.project.event_sequence + 1
    assert settled_event.sequence == before.project.event_sequence + 2

    for audit <- [dispatched, settled_event] do
      assert audit.actor == "agent:" <> ctx.agent["id"]
      assert audit.resource_type == "native_operation"
      assert audit.resource_id == previous.id
    end

    data = %{"runtime_id" => ctx.runtime["id"], "task_id" => ctx.task["id"]}
    assert dispatched.data == data
    assert settled_event.data == Map.put(data, "state", "uncertain")

    receipt =
      Repo.get_by!(CommandReceipt,
        principal: "agent:" <> ctx.agent["id"],
        command_id: settled_event.command_id
      )

    assert receipt.operation == "native_runtime.settle"
    assert receipt.result == settled
    assert receipt.event_ids == [settled_event.id]
    assert receipt.execution_epoch == before.reply_receipt.execution_epoch
    receipt
  end

  test "a completed native approval cannot settle after its owner loses the worker role",
       %{database: database} do
    Sandbox.unboxed_run(Repo, fn ->
      database_backend!(database)
      retained = retained_records()
      {ctx, pid, fixture, event, recorded} = pending_authority_fixture(persistent: true)
      wire = %{"id" => event.wire["id"], "result" => %{"decision" => "accept"}}
      reply = command(%{"expected_version" => recorded["version"], "native" => wire})

      assert {:ok, operation} =
               CodexRuntime.reply(
                 Principal.operator(),
                 ctx.project["id"],
                 ctx.runtime["id"],
                 recorded["id"],
                 reply
               )

      receipt =
        Repo.get_by!(CommandReceipt, principal: "operator", command_id: reply["command_id"])

      prepared = snapshot(ctx, receipt.id)
      assert_native_pending(ctx, pid, fixture, event)
      assert {:ok, ticket} = dispatch(ctx, operation)
      dispatched = snapshot(ctx, receipt.id)
      assert_programmatic_ticket_delta(ctx, prepared, dispatched, operation, ticket)
      assert ticket["native"] == wire
      assert ticket["instance_id"] == Session.status(pid).instance_id
      assert ticket["driver_generation"] == event.handle.generation
      assert {:ok, deadline, 0} = DateTime.from_iso8601(ticket["dispatch_expires_at"])

      guards = [
        expected_instance_id: ticket["instance_id"],
        expected_generation: ticket["driver_generation"],
        dispatch_deadline_ms: DateTime.to_unix(deadline, :millisecond)
      ]

      # This is the supported direct consumer sequence: the one-use ticket
      # commits, then the genuine decision is sent while the owner is authorized.
      assert :ok = Session.respond(pid, event.handle, {:ok, ticket["native"]["result"]}, guards)

      events =
        collect_unjournaled_completion(
          pid,
          event,
          [],
          System.monotonic_time(:millisecond) + 25_000
        )

      thread_id = event.wire["params"]["threadId"]
      turn_id = event.wire["params"]["turnId"]
      item_id = event.wire["params"]["itemId"]
      request_id = event.wire["id"]

      assert [%{"threadId" => ^thread_id, "requestId" => ^request_id}] =
               for(
                 observed <- events,
                 observed.wire["method"] == "serverRequest/resolved",
                 do: observed.wire["params"]
               )

      assert [%{"threadId" => ^thread_id, "turn" => %{"id" => ^turn_id, "status" => "completed"}}] =
               for(
                 observed <- events,
                 observed.wire["method"] == "turn/completed",
                 do: observed.wire["params"]
               )

      assert [
               %{
                 "threadId" => ^thread_id,
                 "turnId" => ^turn_id,
                 "item" => %{
                   "id" => ^item_id,
                   "type" => "commandExecution",
                   "status" => "completed",
                   "exitCode" => 0,
                   "aggregatedOutput" => "samgita_fixture"
                 }
               }
             ] =
               for(
                 observed <- events,
                 observed.wire["method"] == "item/completed",
                 get_in(observed.wire, ["params", "item", "type"]) == "commandExecution",
                 do: observed.wire["params"]
               )

      assert Enum.all?(events, &(&1.generation == event.generation))
      sequences = Enum.map(events, & &1.sequence)
      assert sequences == Enum.sort(Enum.uniq(sequences))
      assert Enum.all?(sequences, &(&1 > dispatched.runtime.source_sequence))
      provider_requests = ModelFixture.requests(fixture)
      assert length(provider_requests) == 2
      native_history = completed_native_history(pid, thread_id, turn_id, item_id)
      assert {:ok, encoded} = SamgitaProtocolCodex.Wire.encode(ticket["native"])

      outcomes = [
        %{
          handle: event.handle,
          method: event.wire["method"],
          thread_id: thread_id,
          status: :resolution_observed,
          response_digest: Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
        }
      ]

      assert Session.interaction_outcomes(pid) == outcomes
      assert_programmatic_native_idle(pid)
      # Draining native evidence does not grant permission to invent journal
      # resolution. Leave these original events unjournaled for this boundary.
      assert snapshot(ctx, receipt.id) == dispatched

      membership_command =
        command(%{
          "expected_version" => dispatched.project.version,
          "agent_id" => ctx.agent["id"],
          "roles" => ["observer"],
          "enabled" => true
        })

      assert {:ok, membership} =
               Samgita.Projects.put_member(
                 Principal.operator(),
                 ctx.project["id"],
                 membership_command
               )

      revoked = snapshot(ctx, receipt.id)
      assert_settlement_membership_delta(dispatched, revoked, membership_command["command_id"])

      membership_receipt =
        Repo.get_by!(CommandReceipt,
          principal: "operator",
          command_id: membership_command["command_id"]
        )

      assert membership_receipt.operation == "project.member"
      assert membership_receipt.result == membership

      settlement =
        command(%{
          "expected_version" => ticket["version"],
          "dispatch_token" => ticket["dispatch_token"],
          "delivery_outcome" => "sent_unconfirmed"
        })

      for attrs <- [
            settlement,
            settlement,
            Map.put(settlement, "command_id", Ecto.UUID.generate())
          ] do
        assert CodexRuntime.settle(
                 ctx.principal,
                 ctx.project["id"],
                 ctx.runtime["id"],
                 ticket["id"],
                 attrs
               ) == {:error, Error.new(:forbidden)}

        assert snapshot(ctx, receipt.id) == revoked

        refute Repo.get_by(CommandReceipt,
                 principal: "agent:" <> ctx.agent["id"],
                 command_id: attrs["command_id"]
               )

        assert Repo.get!(CommandReceipt, membership_receipt.id) == membership_receipt
        assert ModelFixture.requests(fixture) == provider_requests
        assert completed_native_history(pid, thread_id, turn_id, item_id) == native_history
        assert Session.interaction_outcomes(pid) == outcomes
        assert_programmatic_native_idle(pid)
        assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
        assert_retained_records(retained)
      end

      assert revoked.task.state == "in_progress"
      assert revoked.task.accepted_at == nil
      assert revoked.attempt.state == "running"
      refute revoked.attempt.effects_resolved
      assert :ok = Session.close(pid)
      assert snapshot(ctx, receipt.id) == revoked
      assert Repo.get!(CommandReceipt, membership_receipt.id) == membership_receipt
      assert ModelFixture.requests(fixture) == provider_requests
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])

      assert {:ok, %{"owner" => "hub", "admission_open" => true}} =
               Platform.status(Principal.operator())

      assert_retained_records(retained)
    end)
  end

  defp assert_programmatic_ticket_delta(ctx, before, current, operation, ticket) do
    previous = Enum.find(before.operations, &(&1.id == operation["id"]))
    stored = Enum.find(current.operations, &(&1.id == operation["id"]))
    assert previous.state == "prepared"
    assert previous.dispatch_token_digest == nil
    assert previous.dispatch_expires_at == nil
    assert previous.response_payload == nil
    assert ticket["id"] == previous.id
    assert ticket["version"] == previous.version + 1
    assert is_binary(ticket["dispatch_token"])
    assert stored.dispatch_token_digest == :crypto.hash(:sha256, ticket["dispatch_token"])
    assert DateTime.to_iso8601(stored.dispatch_expires_at) == ticket["dispatch_expires_at"]

    assert stored == %{
             previous
             | state: "in_flight",
               version: previous.version + 1,
               dispatch_token_digest: stored.dispatch_token_digest,
               dispatch_expires_at: stored.dispatch_expires_at,
               updated_at: stored.updated_at
           }

    assert current.operations ==
             Enum.map(before.operations, fn record ->
               if record.id == previous.id, do: stored, else: record
             end)

    assert current.event.state == "reply_prepared"

    assert current.project == %{
             before.project
             | event_sequence: before.project.event_sequence + 1
           }

    changed = [:operations, :project, :audit]
    assert Map.drop(current, changed) == Map.drop(before, changed)
    old_events = Map.new(before.audit, &{&1.id, &1})
    assert Map.take(Map.new(current.audit, &{&1.id, &1}), Map.keys(old_events)) == old_events
    assert [added] = Enum.reject(current.audit, &Map.has_key?(old_events, &1.id))
    assert added.type == "native_operation.dispatched"
    assert added.command_id == previous.id
    assert added.resource_id == previous.id
    assert added.resource_type == "native_operation"
    assert added.actor == "agent:" <> ctx.agent["id"]
    assert added.sequence == before.project.event_sequence + 1
    assert added.data == %{"runtime_id" => ctx.runtime["id"], "task_id" => ctx.task["id"]}
  end

  defp assert_settlement_membership_delta(before, current, command_id) do
    assert current.member == %{
             before.member
             | roles: ["observer"],
               enabled: true,
               version: before.member.version + 1,
               updated_at: current.member.updated_at
           }

    assert current.project == %{
             before.project
             | version: before.project.version + 1,
               event_sequence: before.project.event_sequence + 1,
               updated_at: current.project.updated_at
           }

    changed = [:member, :project, :audit, :receipts]
    assert Map.drop(current, changed) == Map.drop(before, changed)
    assert current.receipts == before.receipts + 1
    old_events = Map.new(before.audit, &{&1.id, &1})
    assert Map.take(Map.new(current.audit, &{&1.id, &1}), Map.keys(old_events)) == old_events
    assert [added] = Enum.reject(current.audit, &Map.has_key?(old_events, &1.id))
    assert added.type == "project.membership_changed"
    assert added.command_id == command_id
    assert added.resource_id == before.member.id
    assert added.actor == "operator"
    assert added.sequence == before.project.event_sequence + 1
  end

  defp collect_unjournaled_completion(pid, approval, events, deadline) do
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch
    refute Enum.any?(events, &(&1.kind == :server_request))
    thread_id = approval.wire["params"]["threadId"]
    turn_id = approval.wire["params"]["turnId"]

    resolved =
      Enum.any?(events, fn observed ->
        observed.wire["method"] == "serverRequest/resolved" &&
          observed.wire["params"]["requestId"] == approval.wire["id"] &&
          observed.wire["params"]["threadId"] == thread_id
      end)

    completed =
      Enum.any?(events, fn observed ->
        observed.wire["method"] == "turn/completed" &&
          observed.wire["params"]["threadId"] == thread_id &&
          observed.wire["params"]["turn"]["id"] == turn_id
      end)

    if resolved && completed do
      events
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Native completion before settlement revocation deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Native settlement revocation event gap")
      after
        min(remaining, 20) -> :ok
      end

      collect_unjournaled_completion(pid, approval, events, deadline)
    end
  end

  defp completed_native_history(pid, thread_id, turn_id, item_id) do
    assert {:ok, %{"result" => %{"thread" => history}}} =
             Session.request(pid, "thread/read", %{
               "threadId" => thread_id,
               "includeTurns" => true
             })

    assert history["id"] == thread_id
    assert [%{"id" => ^turn_id, "status" => "completed", "items" => items}] = history["turns"]

    assert [%{"id" => ^item_id, "exitCode" => 0, "aggregatedOutput" => "samgita_fixture"}] =
             Enum.filter(items, &(&1["type"] == "commandExecution"))

    history
  end

  defp assert_programmatic_native_idle(pid) do
    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             interaction_outcomes: 1,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp hold_management(ctx, receipt_id, database, owner, commit_ref) do
    backend = database_backend!(database)

    Repo.transaction(fn ->
      commands =
        for state <- ["blocked", "open"] do
          current = Repo.get!(DomainTask, ctx.task["id"])
          attrs = command(%{"expected_version" => current.version, "state" => state})

          assert {:ok, _} =
                   Tasks.transition(Principal.operator(), ctx.project["id"], current.id, attrs)

          attrs["command_id"]
        end

      for {command_id, state} <- Enum.zip(commands, ["blocked", "open"]) do
        receipt = Repo.get_by!(CommandReceipt, principal: "operator", command_id: command_id)
        assert receipt.operation == "task.transition:" <> ctx.task["id"]
        assert receipt.result["state"] == state
      end

      expected = %{snapshot: snapshot(ctx, receipt_id), commands: commands}
      send(owner, {:management_ready, self(), backend, expected})

      receive do
        {:commit, ^commit_ref} -> expected
      after
        10_000 -> flunk("native authority management commit barrier timed out")
      end
    end)
  end

  defp dispatch(ctx, operation) do
    CodexRuntime.dispatch(
      ctx.principal,
      ctx.project["id"],
      ctx.runtime["id"],
      operation["id"],
      %{"expected_version" => operation["version"], "proof" => ctx.proof}
    )
  end

  defp database_backend!(database) do
    assert database in @databases

    assert %{rows: [[backend, ^database]]} =
             Repo.query!("SELECT pg_backend_pid(), current_database()", [])

    backend
  end

  defp await_blocker!(management, dispatch, deadline) do
    %{rows: [[blockers]]} = Repo.query!("SELECT pg_blocking_pids($1)", [dispatch])

    if management in blockers do
      :ok
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "native dispatch did not wait on the management backend"

      receive do
      after
        min(remaining, 10) -> await_blocker!(management, dispatch, deadline)
      end
    end
  end

  defp start_worker(fun) do
    worker = Task.async(fn -> Sandbox.unboxed_run(Repo, fun) end)
    on_exit(fn -> stop_worker(worker.pid) end)
    worker
  end

  defp stop_worker(pid) do
    monitor = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
  end

  defp snapshot(ctx, receipt_id) do
    Map.put(authority_snapshot(ctx), :reply_receipt, Repo.get!(CommandReceipt, receipt_id))
  end

  defp assert_preserved(ctx, receipt_id, expected, pid, fixture, event, provider_requests) do
    assert snapshot(ctx, receipt_id) == expected
    assert ModelFixture.requests(fixture) == provider_requests
    assert_native_pending(ctx, pid, fixture, event)
  end

  defp assert_management_delta(before, current, [block_command, open_command]) do
    assert current.task == %{
             before.task
             | state: "open",
               version: before.task.version + 2,
               execution_hold: true,
               fence_counter: before.task.fence_counter + 1,
               updated_at: current.task.updated_at
           }

    assert current.attempt.terminal_at

    assert current.attempt == %{
             before.attempt
             | state: "cancelled",
               version: before.attempt.version + 1,
               terminal_at: current.attempt.terminal_at,
               updated_at: current.attempt.updated_at
           }

    refute current.attempt.effects_resolved
    assert is_nil(current.task.accepted_at)

    assert current.project == %{
             before.project
             | event_sequence: before.project.event_sequence + 3
           }

    changed = [:task, :attempt, :project, :audit, :receipts]
    assert Map.drop(current, changed) == Map.drop(before, changed)
    assert current.receipts == before.receipts + 2
    old_events = Map.new(before.audit, &{&1.id, &1})
    assert Map.take(Map.new(current.audit, &{&1.id, &1}), Map.keys(old_events)) == old_events
    added = Enum.reject(current.audit, &Map.has_key?(old_events, &1.id))

    assert Enum.sort(Enum.map(added, &{&1.type, &1.command_id})) ==
             Enum.sort([
               {"task.transitioned", block_command},
               {"attempt.closed", open_command},
               {"task.transitioned", open_command}
             ])

    assert added |> Enum.map(& &1.sequence) |> Enum.sort() ==
             Enum.to_list((before.project.event_sequence + 1)..current.project.event_sequence)
  end

  defp retained_records do
    Map.new(@retained_schemas, fn schema ->
      {schema, Repo.all(from record in schema, order_by: record.id)}
    end)
  end

  defp assert_retained_records(retained) do
    Enum.each(retained, fn {schema, records} ->
      Enum.each(records, fn record -> assert Repo.get!(schema, record.id) == record end)
    end)
  end
end
