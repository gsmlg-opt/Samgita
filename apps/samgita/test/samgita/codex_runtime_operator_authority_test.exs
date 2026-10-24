defmodule Samgita.CodexRuntimeOperatorAuthorityTest do
  use Samgita.DataCase, async: false

  import Samgita.DomainFixtures

  alias Samgita.{Agents, Attempts, CodexRuntime, Error, Principal, Tasks}

  alias Samgita.Domain.{
    Agent,
    AgentConnection,
    AgentCredential,
    CommandReceipt,
    DomainEvent,
    ExecutionSession,
    NativeRuntimeBinding,
    NativeRuntimeEvent,
    NativeRuntimeLink,
    NativeRuntimeOperation,
    ProjectAgent,
    Task,
    TaskAttempt
  }

  setup do
    activate_fixture()
    project = project_fixture()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.163.0"})
    member = member_fixture(project, agent, ["worker"])
    {principal, connection, _credential} = connection_fixture(agent)

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
        command(%{"title" => "Operator reply authority fixture"})
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

    wire = %{
      "id" => "operator-authority-approval",
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "threadId" => "operator-authority-thread",
        "turnId" => "operator-authority-turn",
        "itemId" => "operator-authority-item",
        "startedAtMs" => 0
      }
    }

    {:ok, event} =
      CodexRuntime.record_event(
        principal,
        project["id"],
        runtime["id"],
        command(%{
          "proof" => proof,
          "expected_version" => runtime["version"],
          "instance_id" => runtime["instance_id"],
          "driver_generation" => runtime["driver_generation"],
          "source_sequence" => 1,
          "native" => wire
        })
      )

    assert event["state"] == "pending"
    assert event["kind"] == "server_request"
    assert event["method"] == wire["method"]

    reply =
      command(%{
        "expected_version" => event["version"],
        "native" => %{"id" => wire["id"], "result" => %{"decision" => "accept"}}
      })

    %{
      project: project,
      agent: agent,
      member: member,
      principal: principal,
      connection: connection,
      session: session,
      task: task,
      attempt: attempt,
      runtime: runtime,
      event: event,
      reply: reply
    }
  end

  test "operator reply rejects a revoked owning Agent credential", ctx do
    replace!(AgentCredential, ctx.principal.credential_id, revoked_at: DateTime.utc_now())
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an expired owning Agent credential", ctx do
    replace!(AgentCredential, ctx.principal.credential_id, expires_at: past())
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a disabled Project membership", ctx do
    replace!(ProjectAgent, ctx.member["id"], enabled: false)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects membership that no longer has the worker role", ctx do
    replace!(ProjectAgent, ctx.member["id"], roles: ["observer"])
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a Task execution hold", ctx do
    replace!(Task, ctx.task["id"], execution_hold: true)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a Task that is no longer in progress", ctx do
    replace!(Task, ctx.task["id"], state: "blocked")
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an advanced Task execution fence", ctx do
    task = Repo.get!(Task, ctx.task["id"])
    replace!(Task, task.id, fence_counter: task.fence_counter + 1)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a closed execution session", ctx do
    replace!(ExecutionSession, ctx.session["id"], state: "closed")
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an expired owning Agent connection", ctx do
    replace!(AgentConnection, ctx.connection["id"], expires_at: past())
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a changed owning Agent connection generation", ctx do
    connection = Repo.get!(AgentConnection, ctx.connection["id"])
    replace!(AgentConnection, connection.id, generation: connection.generation + 1)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects removal of registered native driver metadata", ctx do
    # The database permits only the exact registered pair or two null values.
    replace!(Agent, ctx.agent["id"], runtime_driver: nil, runtime_version: nil)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a disabled owning Agent", ctx do
    replace!(Agent, ctx.agent["id"], enabled: false)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects a disconnected owning Agent connection", ctx do
    replace!(AgentConnection, ctx.connection["id"], state: "disconnected")
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an expired Attempt lease", ctx do
    replace!(TaskAttempt, ctx.attempt["id"], lease_expires_at: past())
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an expired execution deadline", ctx do
    replace!(TaskAttempt, ctx.attempt["id"], execution_deadline: past())
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an Attempt connection generation mismatch", ctx do
    attempt = Repo.get!(TaskAttempt, ctx.attempt["id"])
    replace!(TaskAttempt, attempt.id, connection_generation: attempt.connection_generation + 1)
    assert_rejected_without_effects(ctx)
  end

  test "operator reply rejects an execution session bound to another connection", ctx do
    other_agent = agent_fixture()
    {_principal, other_connection, _credential} = connection_fixture(other_agent)
    refute other_connection["id"] == ctx.connection["id"]
    replace!(ExecutionSession, ctx.session["id"], connection_id: other_connection["id"])
    assert_rejected_without_effects(ctx)
  end

  defp assert_rejected_without_effects(ctx) do
    # Capture after the intentional authority mutation, so rejection must not
    # rewrite it or change any journal/domain records or enqueue new jobs.
    before = snapshot(ctx)
    assert before.operations == []
    assert before.event.state == "pending"
    assert before.dispatched_events == 0
    refute Repo.exists?(from r in CommandReceipt, where: r.command_id == ^ctx.reply["command_id"])

    # An identical rejected command must remain rejected; it cannot become a
    # successful receipt replay on the second submission.
    for _submission <- 1..2 do
      assert CodexRuntime.reply(
               Principal.operator(),
               ctx.project["id"],
               ctx.runtime["id"],
               ctx.event["id"],
               ctx.reply
             ) == {:error, Error.new(:ownership_lost)}

      assert snapshot(ctx) == before

      refute Repo.exists?(
               from r in CommandReceipt, where: r.command_id == ^ctx.reply["command_id"]
             )
    end
  end

  defp snapshot(ctx) do
    %{
      agent: Repo.get!(Agent, ctx.agent["id"]),
      credential: Repo.get!(AgentCredential, ctx.principal.credential_id),
      membership: Repo.get!(ProjectAgent, ctx.member["id"]),
      connection: Repo.get!(AgentConnection, ctx.connection["id"]),
      session: Repo.get!(ExecutionSession, ctx.session["id"]),
      task: Repo.get!(Task, ctx.task["id"]),
      attempt: Repo.get!(TaskAttempt, ctx.attempt["id"]),
      runtime: Repo.get!(NativeRuntimeBinding, ctx.runtime["id"]),
      event: Repo.get!(NativeRuntimeEvent, ctx.event["id"]),
      operations:
        Repo.all(
          from o in NativeRuntimeOperation,
            where: o.runtime_id == ^ctx.runtime["id"],
            order_by: o.id
        ),
      native_events:
        Repo.all(
          from e in NativeRuntimeEvent, where: e.runtime_id == ^ctx.runtime["id"], order_by: e.id
        ),
      native_links:
        Repo.all(
          from l in NativeRuntimeLink, where: l.runtime_id == ^ctx.runtime["id"], order_by: l.id
        ),
      domain_events:
        Repo.all(from e in DomainEvent, where: e.project_id == ^ctx.project["id"], order_by: e.id),
      dispatched_events:
        Repo.aggregate(
          from(e in DomainEvent,
            where: e.project_id == ^ctx.project["id"] and e.type == "native_operation.dispatched"
          ),
          :count
        ),
      receipt_count: Repo.aggregate(CommandReceipt, :count),
      job_count: Repo.aggregate(Oban.Job, :count)
    }
  end

  defp replace!(schema, id, attrs), do: schema |> Repo.get!(id) |> change(attrs) |> Repo.update!()
  defp past, do: DateTime.add(DateTime.utc_now(), -60, :second)
end
