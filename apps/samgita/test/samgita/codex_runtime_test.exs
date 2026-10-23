defmodule Samgita.CodexRuntimeTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, CodexRuntime, Principal, Tasks}
  alias Samgita.CodexRuntime.Payload

  alias Samgita.Domain.{
    Agent,
    CommandReceipt,
    DomainEvent,
    NativeRuntimeBinding,
    NativeRuntimeEvent,
    NativeRuntimeOperation,
    Task,
    TaskAttempt
  }

  setup do
    activate_fixture()
    project = project_fixture()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.163.0"})
    member_fixture(project, agent, ["worker"])
    {principal, connection, credential} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => Ecto.UUID.generate()})
      )

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Native execution"}))

    {:ok, attempt} =
      Attempts.claim(
        principal,
        project["id"],
        task["id"],
        command(%{"session_id" => session["id"], "expected_version" => task["version"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, project["id"], attempt["id"])

    {:ok, attempt} =
      Attempts.start(
        principal,
        project["id"],
        attempt["id"],
        command(%{"proof" => proof, "expected_version" => attempt["version"]})
      )

    binding =
      command(%{
        "proof" => proof,
        "expected_version" => attempt["version"],
        "attempt_id" => attempt["id"],
        "runtime_ref" => Ecto.UUID.generate(),
        "instance_id" => Ecto.UUID.generate(),
        "driver_generation" => 1
      })

    assert {:ok, runtime} = CodexRuntime.bind(principal, project["id"], binding)

    %{
      project: project,
      agent: agent,
      principal: principal,
      connection: connection,
      credential: credential,
      attempt: attempt,
      proof: proof,
      task: task,
      runtime: runtime,
      binding: binding
    }
  end

  test "binding is inert, exclusive and receipt replay still requires current runtime ownership",
       ctx do
    assert {:ok, value} = CodexRuntime.bind(ctx.principal, ctx.project["id"], ctx.binding)
    assert value == ctx.runtime

    refute Repo.exists?(
             from o in NativeRuntimeOperation, where: o.runtime_id == ^ctx.runtime["id"]
           )

    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"

    assert {:error, %{code: :invalid}} =
             CodexRuntime.bind(
               ctx.principal,
               ctx.project["id"],
               Map.put(ctx.binding, "command_id", Ecto.UUID.generate())
             )

    Repo.get!(Agent, ctx.agent["id"])
    |> Ecto.Changeset.change(runtime_driver: nil, runtime_version: nil)
    |> Repo.update!()

    assert {:error, %{code: :invalid}} =
             CodexRuntime.bind(ctx.principal, ctx.project["id"], ctx.binding)

    assert {:error, %{code: :ownership_lost}} = prepare(ctx)
  end

  test "native payloads are lossless and encrypted; dispatch tickets are one-use and secret-free receipts stay safe",
       ctx do
    canary = "synthetic-native-secret-canary"

    wire = %{
      "id" => "native-1",
      "method" => "thread/start",
      "params" => %{"model" => canary, "futureExtension" => [nil, false]},
      "trace" => %{"secret" => canary}
    }

    attrs = native_attrs(ctx, wire)

    assert {:ok, operation} =
             CodexRuntime.prepare(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    assert {:ok, ^operation} =
             CodexRuntime.prepare(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    assert {:ok, protected} =
             CodexRuntime.native_operation(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"]
             )

    assert protected["request"] == wire
    stored = Repo.get!(NativeRuntimeOperation, operation["id"])
    refute Jason.encode!(stored.request_payload) =~ canary

    assert {:error, %{code: :native_payload_unreadable}} =
             Payload.open(
               stored.request_payload,
               Payload.aad(ctx.runtime["id"], Ecto.UUID.generate(), "request")
             )

    ticket = dispatch!(ctx, operation)
    assert ticket["native"] == wire
    assert {:error, %{code: :stale_version}} = dispatch(ctx, operation)
    assert {:error, %{code: :conflict}} = dispatch(ctx, ticket)

    response = %{
      "id" => "native-1",
      "error" => %{"code" => -32_001, "message" => canary, "data" => %{"opaque" => [nil, canary]}}
    }

    attrs =
      command(%{
        "expected_version" => ticket["version"],
        "dispatch_token" => ticket["dispatch_token"],
        "native" => response
      })

    assert {:ok, settled} =
             CodexRuntime.settle(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               attrs
             )

    assert settled["state"] == "native_error"

    assert {:ok, ^settled} =
             CodexRuntime.settle(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               attrs
             )

    assert {:ok, protected} =
             CodexRuntime.native_operation(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"]
             )

    assert protected["response"] == response

    for row <- Repo.all(CommandReceipt) do
      refute Jason.encode!(row.result) =~ canary
      refute Jason.encode!(row.result) =~ ticket["dispatch_token"]
      refute Jason.encode!(row.result) =~ ctx.proof
    end

    for event <- Repo.all(DomainEvent), do: refute(Jason.encode!(event.data) =~ canary)
    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
  end

  test "settlement rejects mismatched response IDs and stolen tickets", ctx do
    {:ok, operation} = prepare(ctx)
    ticket = dispatch!(ctx, operation)

    attrs =
      command(%{
        "expected_version" => ticket["version"],
        "dispatch_token" => "wrong",
        "native" => %{"id" => "r1", "result" => %{"data" => []}}
      })

    assert {:error, %{code: :unauthorized}} =
             CodexRuntime.settle(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               attrs
             )

    attrs =
      Map.put(attrs, "dispatch_token", ticket["dispatch_token"])
      |> put_in(["native", "id"], "wrong")

    assert {:error, %{code: :invalid_native_payload}} =
             CodexRuntime.settle(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               attrs
             )

    assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "in_flight"
  end

  test "lost results hold mutations, allow explicit interruption and require operator evidence",
       ctx do
    {:ok, operation} =
      prepare(ctx, %{"id" => "mutation", "method" => "thread/start", "params" => %{}})

    ticket = dispatch!(ctx, operation)

    Repo.get!(NativeRuntimeOperation, ticket["id"])
    |> Ecto.Changeset.change(dispatch_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, %{code: :uncertain_outcome}} = report(ctx, true)
    {:ok, other} = prepare(ctx, %{"id" => "other", "method" => "thread/start", "params" => %{}})
    assert {:error, %{code: :uncertain_outcome}} = dispatch(ctx, other)

    {:ok, interrupt} =
      prepare(ctx, %{
        "id" => "interrupt",
        "method" => "turn/interrupt",
        "params" => %{"threadId" => "thread", "turnId" => "turn"}
      })

    interrupted = dispatch!(ctx, interrupt)
    assert interrupted["state"] == "in_flight"

    evidence =
      command(%{
        "expected_version" => ticket["version"],
        "evidence_ref" => "isolated:observed-cessation"
      })

    assert {:error, %{code: :forbidden}} =
             CodexRuntime.reconcile(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               evidence
             )

    assert {:ok, reconciled} =
             CodexRuntime.reconcile(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               evidence
             )

    assert reconciled["state"] == "reconciled"
    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
  end

  test "cancellation permits no dispatch and history recovery does not release Task holds", ctx do
    {:ok, operation} = prepare(ctx)
    attrs = command(%{"expected_version" => operation["version"]})

    assert {:ok, cancelled} =
             CodexRuntime.cancel(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"],
               attrs
             )

    assert cancelled["state"] == "cancelled"
    assert {:error, %{code: :conflict}} = dispatch(ctx, cancelled)
    {:ok, mutation} = prepare(ctx, %{"id" => "next", "method" => "thread/start", "params" => %{}})
    ticket = dispatch!(ctx, mutation)

    assert {:error, %{code: :uncertain_outcome}} =
             CodexRuntime.cancel(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               command(%{"expected_version" => ticket["version"]})
             )

    assert {:ok, _} = report(ctx, false)
    assert Repo.get!(Task, ctx.task["id"]).execution_hold

    Repo.get!(NativeRuntimeOperation, ticket["id"])
    |> Ecto.Changeset.change(dispatch_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:ok, _} =
             CodexRuntime.reconcile(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               command(%{
                 "expected_version" => ticket["version"],
                 "evidence_ref" => "history:manually-observed-cessation"
               })
             )

    assert Repo.get!(Task, ctx.task["id"]).execution_hold

    assert {:ok, _} =
             Attempts.resolve(
               Principal.operator(),
               ctx.project["id"],
               ctx.attempt["id"],
               command(%{
                 "expected_version" => 3,
                 "effects_resolved" => true,
                 "evidence_ref" => "manual:task-effect-assessment"
               })
             )
  end

  test "events deduplicate source sequences without extending interaction expiry and replies need current authority",
       ctx do
    wire = approval()
    attrs = event_attrs(ctx, 1, wire)

    assert {:ok, event} =
             CodexRuntime.record_event(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    assert {:ok, ^event} =
             CodexRuntime.record_event(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    assert {:ok, ^event} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               Map.put(attrs, "command_id", Ecto.UUID.generate())
             )

    assert {:error, %{code: :conflict}} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               attrs
               |> Map.put("command_id", Ecto.UUID.generate())
               |> put_in(["native", "id"], "changed")
             )

    reply =
      command(%{
        "expected_version" => event["version"],
        "native" => %{"id" => wire["id"], "result" => %{"decision" => "decline"}}
      })

    assert {:ok, decision} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event["id"],
               reply
             )

    ticket = dispatch!(ctx, decision)

    assert {:ok, sent} =
             CodexRuntime.settle(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               command(%{
                 "expected_version" => ticket["version"],
                 "dispatch_token" => ticket["dispatch_token"],
                 "delivery_outcome" => "sent_unconfirmed"
               })
             )

    assert sent["outcome_uncertain"]

    {:ok, next} =
      prepare(ctx, %{
        "id" => "do-not-repeat-execution",
        "method" => "thread/start",
        "params" => %{}
      })

    assert {:error, %{code: :uncertain_outcome}} = dispatch(ctx, next)

    resolved = %{
      "method" => "serverRequest/resolved",
      "params" => %{"requestId" => wire["id"], "threadId" => "thread"}
    }

    assert {:ok, _} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 2, resolved)
             )

    assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "completed"
    current = Repo.get!(NativeRuntimeEvent, event["id"])

    assert {:error, %{code: :conflict}} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event["id"],
               reply
               |> Map.put("command_id", Ecto.UUID.generate())
               |> Map.put("expected_version", current.version)
             )
  end

  test "operator approvals cannot cross the execution authority epoch", ctx do
    {:ok, event} =
      CodexRuntime.record_event(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        event_attrs(ctx, 1, approval())
      )

    Repo.update_all(Samgita.Domain.PlatformAuthority, inc: [epoch: 1])

    attrs =
      command(%{
        "expected_version" => event["version"],
        "native" => %{"id" => "approval", "result" => %{"decision" => "accept"}}
      })

    assert {:error, %{code: :ownership_lost}} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event["id"],
               attrs
             )
  end

  test "expired or reconnected interactions cannot be approved", ctx do
    {:ok, event} =
      CodexRuntime.record_event(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        event_attrs(ctx, 1, approval())
      )

    Repo.get!(NativeRuntimeEvent, event["id"])
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, %{code: :stale_interaction}} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event["id"],
               command(%{
                 "expected_version" => 1,
                 "native" => %{"id" => "approval", "result" => %{"decision" => "accept"}}
               })
             )
  end

  test "a notification gap and live turn block finished reporting; completion only submits to review",
       ctx do
    started = turn_event("turn/started", "inProgress")

    assert {:ok, _} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 1, started)
             )

    assert {:error, %{code: :uncertain_outcome}} = report(ctx, true)

    assert {:ok, _} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 3, turn_event("turn/completed", "completed"))
             )

    assert {:error, %{code: :uncertain_outcome}} = report(ctx, true)
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, _} =
             CodexRuntime.attest_cessation(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               command(%{
                 "expected_version" => runtime.version,
                 "evidence_ref" => "operator:gap-reviewed-with-current-external-state"
               })
             )

    assert {:ok, _} = report(ctx, true)
    assert Repo.get!(Task, ctx.task["id"]).state == "awaiting_review"

    for kind <- ~w(review acceptance) do
      task = Repo.get!(Task, ctx.task["id"])

      assert {:ok, _} =
               Tasks.decide(
                 Principal.operator(),
                 ctx.project["id"],
                 task.id,
                 command(%{
                   "expected_version" => task.version,
                   "kind" => kind,
                   "verdict" => "approve"
                 })
               )
    end

    assert Repo.get!(Task, ctx.task["id"]).state == "accepted"
  end

  test "same-instance reconnect permits reused client IDs and correlates the current generation",
       ctx do
    assert {:ok, old} = prepare(ctx)
    ctx = reconnect_same_instance(ctx)
    assert Repo.get!(NativeRuntimeOperation, old["id"]).state == "cancelled"

    assert {:ok, current} =
             prepare(ctx, %{"id" => "r1", "method" => "model/list", "params" => %{}})

    assert current["driver_generation"] == 2

    assert {:ok, event} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 1, %{
                 "id" => "r1",
                 "error" => %{"code" => -32_001, "message" => "Synthetic generation-two error"}
               })
             )

    assert event["method"] == "model/list"
    assert event["driver_generation"] == 2
  end

  test "same-instance reconnect permits reused server request IDs and distinct generation events",
       ctx do
    attrs = event_attrs(ctx, 1, approval())

    assert {:ok, old} =
             CodexRuntime.record_event(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    ctx = reconnect_same_instance(ctx)

    assert {:ok, current} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 1, approval())
             )

    assert current["id"] != old["id"]
    assert current["driver_generation"] == 2
    assert Repo.get!(NativeRuntimeEvent, old["id"]).state == "stale"
  end

  test "a new-generation resolution cannot settle a prior-generation approval", ctx do
    assert {:ok, event} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 1, approval())
             )

    assert {:ok, decision} =
             CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event["id"],
               command(%{
                 "expected_version" => event["version"],
                 "native" => %{"id" => "approval", "result" => %{"decision" => "decline"}}
               })
             )

    ticket = dispatch!(ctx, decision)
    ctx = reconnect_same_instance(ctx)
    assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "uncertain"

    assert {:ok, _} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, 2, %{
                 "method" => "serverRequest/resolved",
                 "params" => %{"requestId" => "approval", "threadId" => "thread"}
               })
             )

    assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "uncertain"
    assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "stale"
  end

  test "reconnect fences old operations, cancels unsent work and never repeats transmission",
       ctx do
    {:ok, operation} = prepare(ctx, %{"id" => "old", "method" => "thread/start", "params" => %{}})
    ticket = dispatch!(ctx, operation)
    {:ok, unsent} = prepare(ctx)
    {principal, _, _} = connection_fixture(ctx.agent, ctx.credential)
    assert {:error, %{code: :unauthorized}} = prepare(ctx)

    assert {:ok, attempt} =
             Attempts.rebind(
               principal,
               ctx.project["id"],
               ctx.attempt["id"],
               command(%{"expected_version" => ctx.attempt["version"], "proof" => ctx.proof})
             )

    assert {:ok, %{"proof" => proof}} =
             Attempts.proof(principal, ctx.project["id"], attempt["id"])

    assert {:error, %{code: :ownership_lost}} =
             prepare(%{ctx | principal: principal, proof: proof})

    attrs =
      command(%{
        "expected_version" => ctx.runtime["version"],
        "proof" => proof,
        "instance_id" => Ecto.UUID.generate(),
        "driver_generation" => 2
      })

    assert {:ok, runtime} =
             CodexRuntime.reconnect(principal, ctx.project["id"], ctx.runtime["id"], attrs)

    assert runtime["notification_gap"]
    assert Repo.get!(NativeRuntimeOperation, ticket["id"]).state == "uncertain"
    assert Repo.get!(NativeRuntimeOperation, unsent["id"]).state == "cancelled"

    assert {:error, %{code: :ownership_lost}} =
             CodexRuntime.settle(
               principal,
               ctx.project["id"],
               ctx.runtime["id"],
               ticket["id"],
               command(%{
                 "expected_version" => 3,
                 "dispatch_token" => ticket["dispatch_token"],
                 "native" => %{"id" => "old", "result" => %{}}
               })
             )
  end

  test "current credential, project role, lease and execution fence govern replay", ctx do
    attrs = native_attrs(ctx, %{"id" => "r1", "method" => "thread/list", "params" => %{}})

    assert {:ok, _} =
             CodexRuntime.prepare(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    Repo.get!(TaskAttempt, ctx.attempt["id"])
    |> Ecto.Changeset.change(lease_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, %{code: :ownership_lost}} =
             CodexRuntime.prepare(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)
  end

  test "other project workers can see safe history but cannot read or cancel another Agent's payload",
       ctx do
    other = agent_fixture()
    member_fixture(ctx.project, other, ["worker"])
    {principal, _, _} = connection_fixture(other)
    {:ok, operation} = prepare(ctx)
    assert {:ok, _} = CodexRuntime.get(principal, ctx.project["id"], ctx.runtime["id"])

    assert {:error, %{code: :forbidden}} =
             CodexRuntime.native_operation(
               principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"]
             )

    assert {:error, %{code: :forbidden}} =
             CodexRuntime.cancel(
               principal,
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"],
               command(%{"expected_version" => 1})
             )

    assert {:error, %{code: :forbidden}} =
             CodexRuntime.get(principal, project_fixture()["id"], ctx.runtime["id"])
  end

  defp reconnect_same_instance(ctx) do
    current = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, runtime} =
             CodexRuntime.reconnect(
               ctx.principal,
               ctx.project["id"],
               current.id,
               command(%{
                 "proof" => ctx.proof,
                 "expected_version" => current.version,
                 "instance_id" => current.instance_id,
                 "driver_generation" => current.driver_generation + 1
               })
             )

    %{ctx | runtime: runtime}
  end

  defp prepare(ctx, wire \\ %{"id" => "r1", "method" => "thread/list", "params" => %{}}),
    do:
      CodexRuntime.prepare(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        native_attrs(ctx, wire)
      )

  defp native_attrs(ctx, wire) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])
    command(%{"proof" => ctx.proof, "expected_version" => runtime.version, "native" => wire})
  end

  defp event_attrs(ctx, sequence, wire),
    do:
      native_attrs(ctx, wire)
      |> Map.merge(%{
        "instance_id" => ctx.runtime["instance_id"],
        "driver_generation" => ctx.runtime["driver_generation"],
        "source_sequence" => sequence
      })

  defp dispatch(ctx, operation),
    do:
      CodexRuntime.dispatch(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        operation["id"],
        %{"proof" => ctx.proof, "expected_version" => operation["version"]}
      )

  defp dispatch!(ctx, operation) do
    assert {:ok, ticket} = dispatch(ctx, operation)
    ticket
  end

  defp report(ctx, resolved),
    do:
      Attempts.report(
        ctx.principal,
        ctx.project["id"],
        ctx.attempt["id"],
        command(%{
          "expected_version" => ctx.attempt["version"],
          "proof" => ctx.proof,
          "outcome" => "succeeded",
          "effects_resolved" => resolved
        })
      )

  defp approval,
    do: %{
      "id" => "approval",
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "itemId" => "item",
        "startedAtMs" => 0
      }
    }

  defp turn_event(method, state),
    do: %{
      "method" => method,
      "params" => %{
        "threadId" => "thread",
        "turn" => %{"id" => "turn", "items" => [], "status" => state}
      }
    }
end
