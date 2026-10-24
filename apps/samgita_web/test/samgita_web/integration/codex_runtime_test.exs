defmodule SamgitaWeb.CodexRuntimeIntegrationTest do
  use Samgita.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  import Samgita.DomainFixtures
  import SamgitaWeb.CodexRuntimeFixture
  alias Samgita.{Attempts, CodexRuntime, Error, Principal, Projects, Tasks}
  alias Samgita.CodexRuntime.Driver

  alias Samgita.Domain.{
    CommandReceipt,
    NativeRuntimeBinding,
    NativeRuntimeOperation,
    Task,
    TaskAttempt
  }

  alias SamgitaCodexDriver.{ModelFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  @endpoint SamgitaWeb.Endpoint
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

  for invalidation <- [:membership, :task_fence, :lease_expiry, :execution_deadline] do
    @invalidation invalidation
    test "native pending approval rejects repeated operator replies after #{@invalidation}" do
      {ctx, pid, fixture, event, recorded} = pending_authority_fixture()
      invalidate_authority(ctx, @invalidation)
      before = authority_snapshot(ctx)
      assert before.event.state == "pending"
      reply = approval_reply(event, recorded)

      for _submission <- 1..2 do
        assert CodexRuntime.reply(
                 Principal.operator(),
                 ctx.project["id"],
                 ctx.runtime["id"],
                 recorded["id"],
                 reply
               ) == {:error, Error.new(:ownership_lost)}

        assert authority_snapshot(ctx) == before
        assert_native_pending(ctx, pid, fixture, event)
      end

      assert :ok = Session.close(pid)
      assert authority_snapshot(ctx) == before
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    end
  end

  test "prepared real native approval cannot dispatch after worker becomes observer" do
    {ctx, pid, fixture, event, recorded} = pending_authority_fixture()

    assert {:ok, decision} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               recorded["id"],
               approval_reply(event, recorded)
             )

    member_fixture(ctx.project, ctx.agent, ["observer"])
    before = authority_snapshot(ctx)
    assert before.event.state == "reply_prepared"
    operation = Repo.get!(NativeRuntimeOperation, decision["id"])
    assert operation.state == "prepared"
    assert operation.dispatch_token_digest == nil

    for _submission <- 1..2 do
      assert Driver.execute(
               pid,
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               decision["id"],
               %{"expected_version" => decision["version"], "proof" => ctx.proof},
               interaction_handle: event.handle
             ) == {:error, Error.new(:forbidden)}

      assert authority_snapshot(ctx) == before
      assert_native_pending(ctx, pid, fixture, event)
    end

    assert :ok = Session.close(pid)
    assert authority_snapshot(ctx) == before
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  test "successful native approval receipt replay requires current operator authority through REST" do
    previous = Application.fetch_env(:samgita, :api_keys)
    key = "native-receipt-operator-" <> Ecto.UUID.generate()
    Application.put_env(:samgita, :api_keys, [key])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:samgita, :api_keys, value)
        :error -> Application.delete_env(:samgita, :api_keys)
      end
    end)

    {ctx, pid, fixture, event, recorded} = pending_authority_fixture()
    <<a::16, b::16, c::16, d::16>> = <<System.unique_integer([:positive, :monotonic])::64>>
    conn = %{build_conn() | remote_ip: {0x2001, 0xDB8, 0, 0, a, b, c, d}}

    conn =
      conn |> put_req_header("accept", "application/json") |> put_req_header("x-api-key", key)

    path =
      "/api/projects/#{ctx.project["id"]}/codex-runtimes/#{ctx.runtime["id"]}/events/#{recorded["id"]}/reply"

    reply = approval_reply(event, recorded)
    response = post(conn, path, reply)
    assert %{"data" => decision} = json_response(response, 201)
    receipt = Repo.get_by!(CommandReceipt, principal: "operator", command_id: reply["command_id"])
    assert receipt.operation == "native_runtime.reply"
    assert receipt.result == decision
    prepared = authority_snapshot(ctx)

    assert post(conn, path, reply) |> json_response(201) == %{"data" => decision}
    assert authority_snapshot(ctx) == prepared
    assert Repo.get!(CommandReceipt, receipt.id) == receipt
    assert_native_pending(ctx, pid, fixture, event)

    assert {:ok, project} = Projects.get(Principal.operator(), ctx.project["id"])

    membership =
      post(
        conn,
        "/api/projects/#{ctx.project["id"]}/members",
        command(%{
          "expected_version" => project["version"],
          "agent_id" => ctx.agent["id"],
          "roles" => ["observer"],
          "enabled" => true
        })
      )
      |> json_response(200)

    assert membership["data"]["roles"] == ["observer"]
    assert membership["data"]["enabled"]
    before = authority_snapshot(ctx)
    assert before.task == prepared.task
    assert before.attempt == prepared.attempt
    assert before.task.state == "in_progress"
    assert before.attempt.state == "running"
    assert before.event.state == "reply_prepared"
    operation = Repo.get!(NativeRuntimeOperation, decision["id"])
    assert operation.state == "prepared"
    assert operation.version == decision["version"]
    assert operation.dispatch_token_digest == nil
    assert operation.dispatch_expires_at == nil
    provider_requests = ModelFixture.requests(fixture)
    error = Error.new(:ownership_lost)

    for _submission <- 1..2 do
      assert post(conn, path, reply) |> json_response(409) == %{
               "errors" => %{
                 "code" => Atom.to_string(error.code),
                 "detail" => error.message,
                 "fields" => error.details
               }
             }

      assert authority_snapshot(ctx) == before
      assert Repo.get!(CommandReceipt, receipt.id) == receipt
      assert ModelFixture.requests(fixture) == provider_requests
      assert_native_pending(ctx, pid, fixture, event)

      assert Driver.execute(
               pid,
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               decision["id"],
               %{"expected_version" => decision["version"], "proof" => ctx.proof},
               interaction_handle: event.handle
             ) == {:error, Error.new(:forbidden)}

      assert authority_snapshot(ctx) == before
      assert Repo.get!(CommandReceipt, receipt.id) == receipt
      assert ModelFixture.requests(fixture) == provider_requests
      assert_native_pending(ctx, pid, fixture, event)
    end

    assert :ok = Session.close(pid)
    assert authority_snapshot(ctx) == before
    assert Repo.get!(CommandReceipt, receipt.id) == receipt
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  defp approval_reply(event, recorded) do
    command(%{
      "expected_version" => recorded["version"],
      "native" => %{"id" => event.wire["id"], "result" => %{"decision" => "accept"}}
    })
  end

  defp invalidate_authority(ctx, :membership) do
    assert {:ok, project} = Projects.get(Principal.operator(), ctx.project["id"])

    assert {:ok, _} =
             Projects.put_member(
               Principal.operator(),
               ctx.project["id"],
               command(%{
                 "expected_version" => project["version"],
                 "agent_id" => ctx.agent["id"],
                 "roles" => ["worker"],
                 "enabled" => false
               })
             )
  end

  defp invalidate_authority(ctx, :task_fence) do
    before = Repo.get!(Task, ctx.task["id"])

    for state <- ["blocked", "open"] do
      current = Repo.get!(Task, ctx.task["id"])

      assert {:ok, _} =
               Tasks.transition(
                 Principal.operator(),
                 ctx.project["id"],
                 current.id,
                 command(%{"expected_version" => current.version, "state" => state})
               )
    end

    task = Repo.get!(Task, ctx.task["id"])
    assert task.state == "open"
    assert task.execution_hold
    assert task.fence_counter == before.fence_counter + 1
    assert Repo.get!(TaskAttempt, ctx.attempt["id"]).state == "cancelled"
  end

  defp invalidate_authority(ctx, :lease_expiry) do
    ctx.attempt["id"]
    |> then(&Repo.get!(TaskAttempt, &1))
    |> change(lease_expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()
  end

  defp invalidate_authority(ctx, :execution_deadline) do
    ctx.attempt["id"]
    |> then(&Repo.get!(TaskAttempt, &1))
    |> change(execution_deadline: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()
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
