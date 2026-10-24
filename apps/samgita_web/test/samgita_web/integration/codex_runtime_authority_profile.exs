defmodule SamgitaWeb.CodexRuntimeAuthorityProfile do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures, only: [command: 1]

  import SamgitaWeb.CodexRuntimeFixture,
    only: [pending_authority_fixture: 0, authority_snapshot: 1, assert_native_pending: 4]

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
