unless Code.ensure_loaded?(SamgitaCodexDriver.ModelFixture) do
  Code.require_file(
    Path.expand("../../../samgita_codex_driver/test/support/model_fixture.ex", __DIR__)
  )
end

defmodule SamgitaWeb.CodexRuntimeFixture do
  @moduledoc false
  import Ecto.Query
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, CodexRuntime, Principal, Repo, Tasks}
  alias Samgita.CodexRuntime.Driver

  alias Samgita.Domain.{
    CommandReceipt,
    DomainEvent,
    NativeRuntimeBinding,
    NativeRuntimeEvent,
    NativeRuntimeLink,
    NativeRuntimeOperation,
    ProjectAgent,
    Task,
    TaskAttempt
  }

  alias SamgitaCodexDriver.{ModelFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio

  @doc false
  def pending_authority_fixture do
    binary = System.fetch_env!("CODEX_BINARY")

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    activate_fixture()
    root = Path.join(System.tmp_dir!(), "samgita-native-authority-#{Ecto.UUID.generate()}")
    fixture = ModelFixture.start(root, "command")
    File.write!(fixture.requests, "[]")

    on_exit(fn ->
      assert :ok = ModelFixture.close(fixture)
      File.rm_rf!(root)
    end)

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: assert(:ok = Session.close(pid))
      after
        assert :ok = Stdio.close(connection)
      end
    end)

    ctx = registered_runtime("Owned native authority fixture", pid)

    invoke(ctx, pid, "initialize", %{
      "clientInfo" => %{"name" => "samgita_native_authority", "version" => "0.1.0"},
      "capabilities" => %{"experimentalApi" => true}
    })

    thread =
      invoke(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => fixture.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "ephemeral" => true,
        "config" => %{"web_search" => "disabled"}
      })["thread"]["id"]

    turn =
      invoke(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "Owned native authority fixture"}]
      })["turn"]["id"]

    {event, recorded} =
      await_pending_approval(ctx, pid, System.monotonic_time(:millisecond) + 25_000)

    assert event.wire["method"] == "item/commandExecution/requestApproval"
    assert event.wire["params"]["threadId"] == thread
    assert event.wire["params"]["turnId"] == turn
    assert event.wire["params"]["cwd"] == fixture.workspace

    assert event.wire["params"]["command"] ==
             Path.join(fixture.bin, "sh") <> " -c 'printf samgita_fixture'"

    ctx = Map.put(ctx, :event_id, recorded["id"])
    assert_native_pending(ctx, pid, fixture, event)
    {ctx, pid, fixture, event, recorded}
  end

  defp await_pending_approval(ctx, pid, deadline) do
    assert {:ok, events} = Session.drain(pid)
    recorded = Enum.map(events, &{&1, journal_pending_event(ctx, &1)})

    case Enum.find(recorded, fn {event, _} -> event.kind == :server_request end) do
      nil ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Native authority approval deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Native authority event gap")
        after
          min(remaining, 20) -> :ok
        end

        await_pending_approval(ctx, pid, deadline)

      approval ->
        approval
    end
  end

  defp journal_pending_event(ctx, event) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, recorded} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               runtime.id,
               command(%{
                 "expected_version" => runtime.version,
                 "proof" => ctx.proof,
                 "instance_id" => runtime.instance_id,
                 "driver_generation" => event.generation,
                 "source_sequence" => event.sequence,
                 "native" => event.wire
               })
             )

    recorded
  end

  @doc false
  def authority_snapshot(ctx) do
    %{
      project: Repo.get!(Samgita.Domain.Project, ctx.project["id"]),
      agent: Repo.get!(Samgita.Domain.Agent, ctx.agent["id"]),
      credential: Repo.get!(Samgita.Domain.AgentCredential, ctx.principal.credential_id),
      connection: Repo.get!(Samgita.Domain.AgentConnection, ctx.principal.connection_id),
      session: Repo.get!(Samgita.Domain.ExecutionSession, ctx.attempt["session_id"]),
      task: Repo.get!(Task, ctx.task["id"]),
      attempt: Repo.get!(TaskAttempt, ctx.attempt["id"]),
      runtime: Repo.get!(NativeRuntimeBinding, ctx.runtime["id"]),
      event: Repo.get!(NativeRuntimeEvent, ctx.event_id),
      member:
        Repo.get_by!(ProjectAgent, project_id: ctx.project["id"], agent_id: ctx.agent["id"]),
      operations:
        Repo.all(
          from o in NativeRuntimeOperation,
            where: o.runtime_id == ^ctx.runtime["id"],
            order_by: o.id
        ),
      events:
        Repo.all(
          from e in NativeRuntimeEvent, where: e.runtime_id == ^ctx.runtime["id"], order_by: e.id
        ),
      links:
        Repo.all(
          from l in NativeRuntimeLink, where: l.runtime_id == ^ctx.runtime["id"], order_by: l.id
        ),
      audit:
        Repo.all(from e in DomainEvent, where: e.project_id == ^ctx.project["id"], order_by: e.id),
      receipts: Repo.aggregate(CommandReceipt, :count),
      jobs: Repo.aggregate(Oban.Job, :count)
    }
  end

  @doc false
  def assert_native_pending(ctx, pid, fixture, event) do
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert length(ModelFixture.requests(fixture)) == 1
    assert Session.uncertain_operations(pid) == []
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    refute Repo.get!(Task, ctx.task["id"]).state in ["awaiting_review", "accepted"]

    assert {:ok, queued} = Session.drain(pid)

    refute Enum.any?(queued, fn item ->
             item.kind == :server_request ||
               item.wire["method"] == "turn/completed" ||
               (item.wire["method"] == "serverRequest/resolved" &&
                  item.wire["params"]["requestId"] == event.wire["id"])
           end)
  end

  @doc false
  def registered_runtime(name, pid) do
    project = project_fixture()

    agent =
      agent_fixture(%{
        "name" => name,
        "runtime_driver" => "codex",
        "runtime_version" => "0.163.0"
      })

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
        command(%{"title" => "Pinned runtime qualification"})
      )

    {:ok, attempt} =
      Attempts.claim(
        principal,
        project["id"],
        task["id"],
        command(%{"expected_version" => 1, "session_id" => session["id"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, project["id"], attempt["id"])

    {:ok, attempt} =
      Attempts.start(
        principal,
        project["id"],
        attempt["id"],
        command(%{"expected_version" => 1, "proof" => proof})
      )

    {:ok, runtime} =
      CodexRuntime.bind(
        principal,
        project["id"],
        command(%{
          "expected_version" => attempt["version"],
          "proof" => proof,
          "attempt_id" => attempt["id"],
          "runtime_ref" => Ecto.UUID.generate(),
          "instance_id" => Session.status(pid).instance_id,
          "driver_generation" => 1,
          "experimental" => true
        })
      )

    %{
      project: project,
      agent: agent,
      principal: principal,
      task: task,
      attempt: attempt,
      proof: proof,
      runtime: runtime
    }
  end

  @doc false
  def invoke(ctx, pid, method, params) do
    wire = %{"id" => Ecto.UUID.generate(), "method" => method, "params" => params}
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    {:ok, operation} =
      CodexRuntime.prepare(
        ctx.principal,
        ctx.project["id"],
        runtime.id,
        command(%{"expected_version" => runtime.version, "proof" => ctx.proof, "native" => wire})
      )

    assert {:ok, %{"state" => "completed"}} =
             Driver.execute(pid, ctx.principal, ctx.project["id"], runtime.id, operation["id"], %{
               "expected_version" => operation["version"],
               "proof" => ctx.proof
             })

    {:ok, payload} =
      CodexRuntime.native_operation(ctx.principal, ctx.project["id"], runtime.id, operation["id"])

    payload["response"]["result"]
  end
end
