defmodule Samgita.CodexRuntimeToolRetirementTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias Samgita.{Agents, Attempts, CodexRuntime, Principal, Tasks}

  alias Samgita.Domain.{
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
        command(%{"title" => "Native tool retirement"})
      )

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

    {:ok, runtime} =
      CodexRuntime.bind(
        principal,
        project["id"],
        command(%{
          "proof" => proof,
          "expected_version" => attempt["version"],
          "attempt_id" => attempt["id"],
          "runtime_ref" => Ecto.UUID.generate(),
          "instance_id" => Ecto.UUID.generate(),
          "driver_generation" => 1
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

  @tag :retirement_regression
  test "matching terminal dynamic item durably retires an unanswered interaction", ctx do
    event = record!(ctx, dynamic_request("dynamic"))
    record!(ctx, completed_item())
    current = Repo.get!(NativeRuntimeEvent, event["id"])
    assert current.state == "terminal_observed"
    assert current.version == event["version"] + 1
    assert {:error, %{code: :conflict}} = reply(ctx, current)

    refute Repo.exists?(
             from o in NativeRuntimeOperation, where: o.runtime_id == ^ctx.runtime["id"]
           )

    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
    assert Repo.get!(TaskAttempt, ctx.attempt["id"]).state == "running"
    refute CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  test "terminal turns cancel only unsent prepared replies and cannot restore dispatch through receipt replay",
       ctx do
    for status <- ["completed", "interrupted", "failed"] do
      wire = dynamic_request("dynamic-#{status}", status)
      event = record!(ctx, wire)
      attrs = reply_attrs(ctx, event, wire["id"])
      assert {:ok, operation} = reply(ctx, event, attrs)
      record!(ctx, completed_turn(status, status))
      stored = Repo.get!(NativeRuntimeOperation, operation["id"])
      assert stored.state == "cancelled"
      assert stored.version == operation["version"] + 1
      assert stored.dispatch_token_digest == nil
      assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "terminal_observed"
      assert {:error, %{code: :conflict}} = dispatch(ctx, stored)
      assert {:ok, ^operation} = reply(ctx, event, attrs)
      assert {:error, %{code: :stale_version}} = dispatch(ctx, operation)
    end

    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
  end

  test "matching item retirement checks exact thread turn call type and terminal status", ctx do
    event = record!(ctx, dynamic_request("dynamic"))

    for wire <- [
          put_in(completed_item(), ["params", "threadId"], "other"),
          put_in(completed_item(), ["params", "turnId"], "other"),
          put_in(completed_item(), ["params", "item", "id"], "other"),
          put_in(completed_item(), ["params", "item", "status"], "inProgress"),
          put_in(completed_item(), ["params", "item"], %{
            "id" => "call",
            "type" => "agentMessage",
            "text" => "Synthetic completion"
          }),
          put_in(completed_turn(), ["params", "threadId"], "other"),
          completed_turn("completed", "other"),
          completed_turn("inProgress")
        ] do
      record!(ctx, wire)
      assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "pending"
    end

    assert {:ok, _} = reply(ctx, event)
  end

  test "dynamic terminal evidence does not retire user input or another dynamic turn", ctx do
    input = record!(ctx, user_input())
    other = record!(ctx, dynamic_request("other-dynamic", "other-turn"))
    target = record!(ctx, dynamic_request("target"))
    record!(ctx, completed_turn())
    assert Repo.get!(NativeRuntimeEvent, target["id"]).state == "terminal_observed"
    assert Repo.get!(NativeRuntimeEvent, input["id"]).state == "pending"
    assert Repo.get!(NativeRuntimeEvent, other["id"]).state == "pending"
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  test "terminal evidence preserves all dispatched or ambiguous reply states and effect holds",
       ctx do
    for state <- ["in_flight", "sent_unconfirmed", "uncertain"] do
      event = record!(ctx, dynamic_request("dynamic-#{state}", state))
      assert {:ok, operation} = reply(ctx, event)
      assert {:ok, ticket} = dispatch(ctx, operation)

      if state != "in_flight" do
        assert {:ok, _} =
                 CodexRuntime.settle(
                   ctx.principal,
                   ctx.project["id"],
                   ctx.runtime["id"],
                   ticket["id"],
                   command(%{
                     "expected_version" => ticket["version"],
                     "dispatch_token" => ticket["dispatch_token"],
                     "delivery_outcome" => state
                   })
                 )
      end

      before_operation = Repo.get!(NativeRuntimeOperation, operation["id"])
      before_event = Repo.get!(NativeRuntimeEvent, event["id"])
      record!(ctx, completed_item(state))
      record!(ctx, completed_turn("interrupted", state))
      after_operation = Repo.get!(NativeRuntimeOperation, operation["id"])
      after_event = Repo.get!(NativeRuntimeEvent, event["id"])
      assert after_operation.state == state
      assert after_operation.version == before_operation.version
      assert after_event.state == before_event.state
      assert after_event.version == before_event.version
      assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
    end

    assert Repo.get!(Task, ctx.task["id"]).state == "in_progress"
  end

  test "a previously cancelled unsent response can retire without rewriting its operation", ctx do
    event = record!(ctx, dynamic_request("dynamic"))
    assert {:ok, operation} = reply(ctx, event)

    assert {:ok, cancelled} =
             CodexRuntime.cancel(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               operation["id"],
               command(%{"expected_version" => operation["version"]})
             )

    record!(ctx, completed_item())
    assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "terminal_observed"
    stored = Repo.get!(NativeRuntimeOperation, operation["id"])
    assert stored.state == "cancelled" and stored.version == cancelled["version"]
  end

  test "duplicate terminal events preserve retirement identity and versions", ctx do
    event = record!(ctx, dynamic_request("dynamic"))
    attrs = event_attrs(ctx, completed_item())

    assert {:ok, terminal} =
             CodexRuntime.record_event(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    retired = Repo.get!(NativeRuntimeEvent, event["id"])
    assert retired.state == "terminal_observed"

    assert {:ok, ^terminal} =
             CodexRuntime.record_event(ctx.principal, ctx.project["id"], ctx.runtime["id"], attrs)

    record!(ctx, completed_item())
    assert Repo.get!(NativeRuntimeEvent, event["id"]).version == retired.version
  end

  test "current generation terminal evidence cannot retire an earlier generation", ctx do
    old = record!(ctx, dynamic_request("same-native-id"))
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, current} =
             CodexRuntime.reconnect(
               ctx.principal,
               ctx.project["id"],
               runtime.id,
               command(%{
                 "expected_version" => runtime.version,
                 "proof" => ctx.proof,
                 "instance_id" => runtime.instance_id,
                 "driver_generation" => 2
               })
             )

    ctx = %{ctx | runtime: current}
    fresh = record!(ctx, dynamic_request("same-native-id"))
    record!(ctx, completed_item())
    assert Repo.get!(NativeRuntimeEvent, old["id"]).state == "stale"
    assert Repo.get!(NativeRuntimeEvent, fresh["id"]).state == "terminal_observed"
    assert CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  @tag :retirement_reconnect_regression
  test "reconnect preserves terminal evidence for a proved-unsent retired interaction", ctx do
    event = record!(ctx, dynamic_request("retired-before-reconnect"))
    record!(ctx, completed_item())
    assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "terminal_observed"
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, _} =
             CodexRuntime.reconnect(
               ctx.principal,
               ctx.project["id"],
               runtime.id,
               command(%{
                 "expected_version" => runtime.version,
                 "proof" => ctx.proof,
                 "instance_id" => runtime.instance_id,
                 "driver_generation" => 2
               })
             )

    assert Repo.get!(NativeRuntimeEvent, event["id"]).state == "terminal_observed"
  end

  test "terminal retirement scans encrypted candidates beyond one bounded database batch", ctx do
    for index <- 1..129 do
      request = put_in(dynamic_request("batch-#{index}"), ["params", "callId"], "call-#{index}")
      event = record!(ctx, request)
      assert {:ok, operation} = reply(ctx, event)

      assert {:ok, _} =
               CodexRuntime.cancel(
                 Principal.operator(),
                 ctx.project["id"],
                 ctx.runtime["id"],
                 operation["id"],
                 command(%{"expected_version" => operation["version"]})
               )
    end

    record!(ctx, completed_turn())

    assert Repo.aggregate(
             from(e in NativeRuntimeEvent,
               where: e.runtime_id == ^ctx.runtime["id"] and e.state == "terminal_observed"
             ),
             :count
           ) == 129

    refute CodexRuntime.unresolved_effects?(ctx.attempt["id"])
  end

  defp record!(ctx, wire) do
    assert {:ok, event} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               ctx.runtime["id"],
               event_attrs(ctx, wire)
             )

    event
  end

  defp event_attrs(ctx, wire) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    command(%{
      "proof" => ctx.proof,
      "expected_version" => runtime.version,
      "native" => wire,
      "instance_id" => runtime.instance_id,
      "driver_generation" => runtime.driver_generation,
      "source_sequence" => runtime.source_sequence + 1
    })
  end

  defp reply(ctx, event, attrs \\ nil) do
    attrs = attrs || reply_attrs(ctx, event, native_id(ctx, event))

    CodexRuntime.reply(
      Principal.operator(),
      ctx.project["id"],
      ctx.runtime["id"],
      event_id(event),
      attrs
    )
  end

  defp reply_attrs(_ctx, event, id),
    do:
      command(%{
        "expected_version" => event_version(event),
        "native" => %{"id" => id, "result" => %{"success" => true, "contentItems" => []}}
      })

  defp native_id(ctx, event) do
    assert {:ok, payload} =
             CodexRuntime.native_event(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               event_id(event)
             )

    payload["native"]["id"]
  end

  defp event_id(%NativeRuntimeEvent{id: id}), do: id
  defp event_id(event), do: event["id"]
  defp event_version(%NativeRuntimeEvent{version: version}), do: version
  defp event_version(event), do: event["version"]

  defp dispatch(ctx, %NativeRuntimeOperation{} = operation),
    do: dispatch(ctx, %{"id" => operation.id, "version" => operation.version})

  defp dispatch(ctx, operation),
    do:
      CodexRuntime.dispatch(
        ctx.principal,
        ctx.project["id"],
        ctx.runtime["id"],
        operation["id"],
        %{"proof" => ctx.proof, "expected_version" => operation["version"]}
      )

  defp dynamic_request(id, turn \\ "turn"),
    do: %{
      "id" => id,
      "method" => "item/tool/call",
      "params" => %{
        "threadId" => "thread",
        "turnId" => turn,
        "callId" => "call",
        "namespace" => nil,
        "tool" => "fixture",
        "arguments" => %{}
      }
    }

  defp user_input,
    do: %{
      "id" => "input",
      "method" => "item/tool/requestUserInput",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "itemId" => "question",
        "questions" => [],
        "isBlocking" => true,
        "autoResolutionMs" => nil
      }
    }

  defp completed_item(turn \\ "turn"),
    do: %{
      "method" => "item/completed",
      "params" => %{
        "threadId" => "thread",
        "turnId" => turn,
        "completedAtMs" => 1,
        "item" => %{
          "id" => "call",
          "type" => "dynamicToolCall",
          "namespace" => nil,
          "tool" => "fixture",
          "arguments" => %{},
          "status" => "failed",
          "contentItems" => [],
          "success" => false,
          "durationMs" => 1
        }
      }
    }

  defp completed_turn(status \\ "completed", turn \\ "turn"),
    do: %{
      "method" => "turn/completed",
      "params" => %{
        "threadId" => "thread",
        "turn" => %{"id" => turn, "items" => [], "status" => status}
      }
    }
end
