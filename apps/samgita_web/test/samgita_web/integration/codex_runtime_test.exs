unless Code.ensure_loaded?(SamgitaCodexDriver.ModelFixture) do
  Code.require_file(
    Path.expand("../../../../samgita_codex_driver/test/support/model_fixture.ex", __DIR__)
  )
end

defmodule SamgitaWeb.CodexRuntimeIntegrationTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, CodexRuntime, Principal, Tasks}
  alias Samgita.CodexRuntime.Driver
  alias Samgita.Domain.{NativeRuntimeBinding, Task, TaskAttempt}
  alias SamgitaCodexDriver.{ModelFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  @moduletag :e2e
  @moduletag timeout: 90_000

  test "ordinary Agents drive the pinned process through explicit approval and separate Task acceptance" do
    binary = System.fetch_env!("CODEX_BINARY")
    assert File.regular?(binary)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    activate_fixture()

    for name <- ["Ordinary Codex runtime", "Synapsis ordinary registered Agent"] do
      root = Path.join(System.tmp_dir!(), "samgita-platform-codex-#{Ecto.UUID.generate()}")
      fixture = ModelFixture.start(root, "command")

      on_exit(fn ->
        ModelFixture.close(fixture)
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
               env: %{
                 "HOME" => fixture.home,
                 "CODEX_HOME" => fixture.codex_home,
                 "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
                 "RUST_LOG" => "off"
               }
             ]}
        )

      on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
      ctx = registered_runtime(name, pid)
      assert_wrong_instance(ctx, pid)

      invoke(ctx, pid, "initialize", %{
        "clientInfo" => %{"name" => "samgita_platform_qualification", "version" => "0.1.0"},
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
          "input" => [
            %{
              "type" => "text",
              "text" => "Synthetic fixture execution only",
              "text_elements" => []
            }
          ]
        })["turn"]["id"]

      events = collect(ctx, pid, fixture, [], System.monotonic_time(:millisecond) + 25_000)

      assert Enum.any?(
               events,
               &(get_in(&1, [:wire, "method"]) == "turn/completed" &&
                   get_in(&1, [:wire, "params", "turn", "id"]) == turn)
             )

      assert Enum.any?(
               events,
               &(get_in(&1, [:wire, "method"]) == "item/commandExecution/requestApproval")
             )

      assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"

      assert {:ok, runtime} =
               CodexRuntime.get(ctx.principal, ctx.project["id"], ctx.runtime["id"])

      assert Enum.any?(
               runtime["links"],
               &(&1["kind"] == "turn" && &1["external_id"] == turn && &1["state"] == "completed")
             )

      attempt = Repo.get!(TaskAttempt, ctx.attempt["id"])

      assert {:ok, progress} =
               Attempts.progress(
                 ctx.principal,
                 ctx.project["id"],
                 attempt.id,
                 command(%{
                   "expected_version" => attempt.version,
                   "proof" => ctx.proof,
                   "payload" => %{"summary" => "Pinned native command fixture completed"}
                 })
               )

      task = Repo.get!(Task, ctx.task["id"])

      assert {:ok, _} =
               Tasks.add_artifact(
                 ctx.principal,
                 ctx.project["id"],
                 task.id,
                 command(%{
                   "expected_version" => task.version,
                   "attempt_id" => attempt.id,
                   "kind" => "git_commit",
                   "locator" => "git:deadbeef",
                   "digest" => "deadbeef"
                 })
               )

      assert {:ok, _} =
               Attempts.report(
                 ctx.principal,
                 ctx.project["id"],
                 attempt.id,
                 command(%{
                   "expected_version" => progress["version"],
                   "proof" => ctx.proof,
                   "outcome" => "succeeded",
                   "effects_resolved" => true
                 })
               )

      assert Repo.get!(Task, task.id).state == "awaiting_review"

      for kind <- ~w(review acceptance) do
        current = Repo.get!(Task, task.id)

        assert {:ok, _} =
                 Tasks.decide(
                   Principal.operator(),
                   ctx.project["id"],
                   task.id,
                   command(%{
                     "expected_version" => current.version,
                     "kind" => kind,
                     "verdict" => "approve"
                   })
                 )
      end

      assert Repo.get!(Task, task.id).state == "accepted"
      Session.close(pid)
    end
  end

  defp registered_runtime(name, pid) do
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
      principal: principal,
      task: task,
      attempt: attempt,
      proof: proof,
      runtime: runtime
    }
  end

  defp invoke(ctx, pid, method, params) do
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

  defp assert_wrong_instance(ctx, pid) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])
    # A different process's identity must fail before a ticket is issued, even
    # when its generation happens to match this driver's first connection.
    Repo.update!(Ecto.Changeset.change(runtime, instance_id: Ecto.UUID.generate()))
    wire = %{"id" => Ecto.UUID.generate(), "method" => "thread/list", "params" => %{}}

    {:ok, operation} =
      CodexRuntime.prepare(
        ctx.principal,
        ctx.project["id"],
        runtime.id,
        command(%{"expected_version" => runtime.version, "proof" => ctx.proof, "native" => wire})
      )

    assert {:error, %{code: :ownership_lost}} =
             Driver.execute(pid, ctx.principal, ctx.project["id"], runtime.id, operation["id"], %{
               "expected_version" => operation["version"],
               "proof" => ctx.proof
             })

    assert Repo.get!(Samgita.Domain.NativeRuntimeOperation, operation["id"]).state == "prepared"

    assert {:ok, _} =
             CodexRuntime.cancel(
               ctx.principal,
               ctx.project["id"],
               runtime.id,
               operation["id"],
               command(%{"expected_version" => 1})
             )

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(NativeRuntimeBinding, runtime.id),
        instance_id: runtime.instance_id
      )
    )
  end

  defp collect(ctx, pid, fixture, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    Enum.each(events, &persist_event(ctx, pid, fixture, &1))
    acc = acc ++ events
    completed = Enum.any?(acc, &(get_in(&1, [:wire, "method"]) == "turn/completed"))

    cond do
      completed && !CodexRuntime.unresolved_effects?(ctx.attempt["id"]) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native platform event deadline")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
        after
          20 -> :ok
        end

        collect(ctx, pid, fixture, acc, deadline)
    end
  end

  defp persist_event(ctx, pid, fixture, event) do
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

    respond_to_fixture(ctx, pid, fixture, event, recorded)
  end

  defp respond_to_fixture(ctx, pid, fixture, %{kind: :server_request} = event, recorded) do
    assert event.wire["method"] == "item/commandExecution/requestApproval"
    assert event.wire["params"]["cwd"] == fixture.workspace

    assert event.wire["params"]["command"] ==
             Path.join(fixture.bin, "sh") <> " -c 'printf samgita_fixture'"

    wire = %{"id" => event.wire["id"], "result" => %{"decision" => "accept"}}

    assert {:ok, decision} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               recorded["id"],
               command(%{"expected_version" => recorded["version"], "native" => wire})
             )

    assert {:ok, %{"state" => "sent_unconfirmed"}} =
             Driver.execute(
               pid,
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               decision["id"],
               %{"expected_version" => decision["version"], "proof" => ctx.proof},
               interaction_handle: event.handle
             )
  end

  defp respond_to_fixture(_ctx, _pid, _fixture, _event, _recorded), do: :ok
end
