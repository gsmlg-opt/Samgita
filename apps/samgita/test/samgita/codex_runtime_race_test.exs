defmodule Samgita.CodexRuntimeRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{Agents, Attempts, CodexRuntime, Error, Principal, Projects, Repo, Tasks}
  alias Samgita.Domain.{NativeRuntimeOperation, TaskAttempt}

  setup_all do
    database = System.fetch_env!("SAMGITA_TEST_DATABASE")
    assert Regex.match?(~r/^samgita_redesign_[a-z0-9_]+_test[0-9]*$/, database)

    Sandbox.unboxed_run(Repo, fn ->
      assert %{rows: [[^database]]} = Repo.query!("SELECT current_database()", [])
    end)

    :ok
  end

  setup do
    ctx =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, ctx} = Repo.transaction(&runtime_fixture/0)
        ctx
      end)

    on_exit(fn -> Sandbox.unboxed_run(Repo, fn -> cleanup!(ctx) end) end)
    ctx
  end

  test "simultaneous native dispatches issue exactly one one-use ticket", ctx do
    results = race([fn -> dispatch(ctx) end, fn -> dispatch(ctx) end])
    assert [{:ok, ticket}] = Enum.filter(results, &match?({:ok, _}, &1))

    assert [{:error, %Error{code: :stale_version}}] =
             Enum.filter(results, &match?({:error, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      stored = Repo.get!(NativeRuntimeOperation, ticket["id"])
      assert stored.state == "in_flight"
      assert stored.version == ctx.operation["version"] + 1
      assert stored.dispatch_token_digest == :crypto.hash(:sha256, ticket["dispatch_token"])

      assert {:error, %Error{code: :conflict}} =
               CodexRuntime.dispatch(
                 ctx.principal,
                 ctx.project["id"],
                 ctx.runtime["id"],
                 ticket["id"],
                 %{"proof" => ctx.proof, "expected_version" => ticket["version"]}
               )
    end)
  end

  test "conflicting simultaneous settlements persist only the winning outcome", ctx do
    ticket =
      Sandbox.unboxed_run(Repo, fn ->
        assert {:ok, ticket} = dispatch(ctx)
        ticket
      end)

    failure = %{
      "native" => %{
        "id" => "native-race",
        "error" => %{
          "code" => -32_001,
          "message" => "Synthetic rejection; no external execution"
        }
      }
    }

    uncertain = %{"delivery_outcome" => "uncertain"}

    results =
      race(
        Enum.map([failure, uncertain], fn payload ->
          fn -> settle(ctx, ticket, payload) end
        end)
      )

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))

    assert [{:error, %Error{code: :stale_version}}] =
             Enum.filter(results, &match?({:error, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      stored = Repo.get!(NativeRuntimeOperation, ticket["id"])
      assert stored.state == winner["state"]
      assert stored.version == ticket["version"] + 1
      assert stored.state in ["native_error", "uncertain"]

      assert {:ok, protected} =
               CodexRuntime.native_operation(
                 Principal.operator(),
                 ctx.project["id"],
                 ctx.runtime["id"],
                 ticket["id"]
               )

      if stored.state == "native_error",
        do: assert(protected["response"] == failure["native"]),
        else: refute(Map.has_key?(protected, "response"))
    end)
  end

  test "credential revocation serializes with native dispatch and fences later transmission",
       ctx do
    revocation_race(ctx, :credential, :unauthorized)
  end

  test "project membership revocation serializes with native dispatch and fences later transmission",
       ctx do
    revocation_race(ctx, :membership, :forbidden)
  end

  defp revocation_race(ctx, kind, code) do
    revoke = Sandbox.unboxed_run(Repo, fn -> revocation(ctx, kind) end)
    results = race([fn -> dispatch(ctx) end, revoke])
    assert {:ok, _} = Enum.at(results, 1)
    outcome = hd(results)
    assert match?({:ok, _}, outcome) || match?({:error, %Error{code: ^code}}, outcome)

    Sandbox.unboxed_run(Repo, fn ->
      stored = Repo.get!(NativeRuntimeOperation, ctx.operation["id"])

      assert {:error, %Error{code: ^code}} =
               CodexRuntime.dispatch(
                 ctx.principal,
                 ctx.project["id"],
                 ctx.runtime["id"],
                 stored.id,
                 %{"proof" => ctx.proof, "expected_version" => stored.version}
               )

      case outcome do
        {:ok, ticket} ->
          assert stored.state == "in_flight"
          assert stored.dispatch_token_digest == :crypto.hash(:sha256, ticket["dispatch_token"])

          assert {:error, %Error{code: ^code}} =
                   settle(ctx, ticket, %{"delivery_outcome" => "uncertain"})

        {:error, _} ->
          assert stored.state == "prepared"
          assert stored.dispatch_token_digest == nil
      end
    end)
  end

  defp revocation(ctx, :credential) do
    {:ok, agent} = Agents.get(Principal.operator(), ctx.agent["id"])

    attrs =
      command(%{
        "expected_version" => agent["version"],
        "credential_id" => ctx.principal.credential_id
      })

    fn -> Agents.revoke_credential(Principal.operator(), ctx.agent["id"], attrs) end
  end

  defp revocation(ctx, :membership) do
    {:ok, project} = Projects.get(Principal.operator(), ctx.project["id"])

    attrs =
      command(%{
        "expected_version" => project["version"],
        "agent_id" => ctx.agent["id"],
        "enabled" => false,
        "roles" => ["worker"]
      })

    fn -> Projects.put_member(Principal.operator(), ctx.project["id"], attrs) end
  end

  defp runtime_fixture do
    activate_fixture()
    project = project_fixture(%{"name" => "Isolated native concurrency fixture"})
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.163.0"})
    member_fixture(project, agent, ["worker"])
    {principal, _, _} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => Ecto.UUID.generate()})
      )

    {:ok, task} =
      Tasks.create(
        Principal.operator(),
        project["id"],
        command(%{"title" => "No external native execution"})
      )

    {:ok, attempt} =
      Attempts.claim(
        principal,
        project["id"],
        task["id"],
        command(%{
          "expected_version" => task["version"],
          "session_id" => session["id"]
        })
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, project["id"], attempt["id"])

    {:ok, attempt} =
      Attempts.start(
        principal,
        project["id"],
        attempt["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    {:ok, runtime} =
      CodexRuntime.bind(
        principal,
        project["id"],
        command(%{
          "expected_version" => attempt["version"],
          "attempt_id" => attempt["id"],
          "proof" => proof,
          "runtime_ref" => Ecto.UUID.generate(),
          "instance_id" => Ecto.UUID.generate(),
          "driver_generation" => 1
        })
      )

    {:ok, operation} =
      CodexRuntime.prepare(
        principal,
        project["id"],
        runtime["id"],
        command(%{
          "expected_version" => runtime["version"],
          "proof" => proof,
          "native" => %{"id" => "native-race", "method" => "thread/list", "params" => %{}}
        })
      )

    %{
      project: project,
      agent: agent,
      principal: principal,
      attempt: attempt,
      proof: proof,
      runtime: runtime,
      operation: operation
    }
  end

  defp dispatch(ctx),
    do:
      CodexRuntime.dispatch(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        ctx.operation["id"],
        %{"proof" => ctx.proof, "expected_version" => ctx.operation["version"]}
      )

  defp settle(ctx, ticket, payload),
    do:
      CodexRuntime.settle(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        ticket["id"],
        command(
          Map.merge(payload, %{
            "expected_version" => ticket["version"],
            "dispatch_token" => ticket["dispatch_token"]
          })
        )
      )

  defp cleanup!(ctx) do
    operations =
      Repo.all(from o in NativeRuntimeOperation, where: o.runtime_id == ^ctx.runtime["id"])

    Enum.each(operations, &resolve_operation!(ctx, &1))
    attempt = Repo.get!(TaskAttempt, ctx.attempt["id"])

    assert {:ok, _} =
             Attempts.resolve(
               Principal.operator(),
               ctx.project["id"],
               attempt.id,
               command(%{
                 "expected_version" => attempt.version,
                 "effects_resolved" => true,
                 "evidence_ref" =>
                   "isolated-race-fixture:no-native-transport-or-external-execution"
               })
             )

    attempt = Repo.get!(TaskAttempt, attempt.id)
    assert attempt.effects_resolved
    assert attempt.state == "released"
  end

  defp resolve_operation!(ctx, %{state: "prepared"} = operation) do
    assert {:ok, _} =
             CodexRuntime.cancel(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               operation.id,
               command(%{"expected_version" => operation.version})
             )
  end

  defp resolve_operation!(ctx, %{state: state} = operation)
       when state in ["in_flight", "uncertain"] do
    if state == "in_flight" do
      operation
      |> Ecto.Changeset.change(dispatch_expires_at: DateTime.add(DateTime.utc_now(), -1))
      |> Repo.update!()
    end

    assert {:ok, _} =
             CodexRuntime.reconcile(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               operation.id,
               command(%{
                 "expected_version" => operation.version,
                 "evidence_ref" =>
                   "isolated-race-fixture:ticket-never-sent-to-any-native-transport"
               })
             )
  end

  defp resolve_operation!(_ctx, _operation), do: :ok

  defp race(commands) do
    parent = self()

    jobs = Enum.map(commands, &start_worker(parent, &1))

    backends =
      Enum.map(jobs, fn job ->
        receive do
          {:ready, pid, backend} when pid == job.pid -> backend
        after
          5_000 -> flunk("native race database checkout timed out")
        end
      end)

    assert length(Enum.uniq(backends)) == length(commands)
    Enum.each(jobs, &send(&1.pid, :go))
    Enum.map(jobs, &Task.await(&1, 10_000))
  end

  defp start_worker(parent, command) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> barrier(parent, command) end) end)
  end

  defp barrier(parent, command) do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()", [])
    send(parent, {:ready, self(), backend})

    receive do
      :go -> command.()
    after
      5_000 -> flunk("native race barrier timed out")
    end
  end
end
