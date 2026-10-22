defmodule Samgita.AttemptsTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Principal, Projects, Tasks}
  alias Samgita.Domain.{CommandReceipt, DecisionRecord, DomainEvent, Task, TaskAttempt}

  setup do
    activate_fixture()
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["worker"])
    {principal, _connection, _raw} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => Ecto.UUID.generate()})
      )

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Execution test"}))

    %{project: project, agent: agent, principal: principal, session: session, task: task}
  end

  test "claim/start/report/review/accept are separate and receipts never contain proofs", ctx do
    %{project: p, principal: principal, session: session, task: task} = ctx
    attrs = command(%{"session_id" => session["id"], "expected_version" => task["version"]})
    assert {:ok, attempt} = Attempts.claim(principal, p["id"], task["id"], attrs)
    assert attempt["state"] == "leased"
    assert Repo.get!(Task, task["id"]).state == "open"
    refute Map.has_key?(attempt, "proof")
    assert {:ok, %{"proof" => proof}} = Attempts.proof(principal, p["id"], attempt["id"])
    receipt = Repo.get_by!(CommandReceipt, command_id: attrs["command_id"])
    refute Jason.encode!(receipt.result) =~ proof

    assert {:ok, running} =
             Attempts.start(
               principal,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => 1, "proof" => proof})
             )

    assert Repo.get!(Task, task["id"]).state == "in_progress"

    report =
      command(%{
        "expected_version" => running["version"],
        "proof" => proof,
        "outcome" => "succeeded",
        "result" => %{"summary" => "Output"},
        "effects_resolved" => true
      })

    assert {:ok, completed} = Attempts.report(principal, p["id"], attempt["id"], report)
    assert completed["state"] == "succeeded"
    assert {:ok, ^completed} = Attempts.report(principal, p["id"], attempt["id"], report)
    report_receipt = Repo.get_by!(CommandReceipt, command_id: report["command_id"])
    assert [event_id] = report_receipt.event_ids
    event = Repo.get!(DomainEvent, event_id)
    assert event.before_state["state"] == "running"
    assert event.after_state == %{"state" => "succeeded", "version" => 3}
    assert event.data["task_before"]["state"] == "in_progress"
    assert event.data["task_after"]["state"] == "awaiting_review"
    refute Jason.encode!(event.data) =~ proof
    assert {:ok, awaiting} = Tasks.get(principal, p["id"], task["id"])
    assert awaiting["state"] == "awaiting_review"
    assert Repo.aggregate(from(d in DecisionRecord, where: d.task_id == ^task["id"]), :count) == 0

    assert {:error, %{code: :forbidden}} =
             Tasks.decide(
               principal,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => awaiting["version"],
                 "kind" => "acceptance",
                 "verdict" => "approve"
               })
             )

    op = Principal.operator()

    assert {:error, %{code: :invalid_transition}} =
             Tasks.decide(
               op,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => awaiting["version"],
                 "kind" => "acceptance",
                 "verdict" => "approve"
               })
             )

    assert {:ok, reviewed} =
             Tasks.decide(
               op,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => awaiting["version"],
                 "kind" => "review",
                 "verdict" => "approve"
               })
             )

    assert reviewed["state"] == "awaiting_review"

    assert {:ok, accepted} =
             Tasks.decide(
               op,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => reviewed["version"],
                 "kind" => "acceptance",
                 "verdict" => "approve"
               })
             )

    assert accepted["state"] == "accepted"
    assert accepted["accepted_at"] != nil
    assert Repo.get!(Task, task["id"]).status == "pending"
    assert {:error, %{code: :ownership_lost}} = Attempts.proof(principal, p["id"], attempt["id"])
    {replacement, _, _} = connection_fixture(ctx.agent)
    assert {:ok, ^completed} = Attempts.report(replacement, p["id"], attempt["id"], report)

    assert {:error, %{code: :unauthorized}} =
             Attempts.report(principal, p["id"], attempt["id"], report)
  end

  test "Agent capacity covers unknown effects and reopen cannot clear a hold", ctx do
    %{project: p, principal: principal, session: session, task: task} = ctx
    {attempt, proof} = claimed(ctx)

    {:ok, running} =
      Attempts.start(
        principal,
        p["id"],
        attempt["id"],
        command(%{"expected_version" => 1, "proof" => proof})
      )

    {:ok, failed} =
      Attempts.report(
        principal,
        p["id"],
        attempt["id"],
        command(%{
          "expected_version" => running["version"],
          "proof" => proof,
          "outcome" => "failed",
          "result" => %{},
          "effects_resolved" => false
        })
      )

    stored = Repo.get!(Task, task["id"])
    assert stored.execution_hold

    {:ok, reopened} =
      Tasks.transition(
        Principal.operator(),
        p["id"],
        task["id"],
        command(%{"expected_version" => stored.version, "state" => "open"})
      )

    assert reopened["execution_hold"]

    assert {:error, %{code: :invalid_transition}} =
             Attempts.claim(
               principal,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => reopened["version"],
                 "session_id" => session["id"]
               })
             )

    {:ok, other} =
      Tasks.create(Principal.operator(), p["id"], command(%{"title" => "Other work"}))

    assert {:error, %{code: :capacity_exceeded}} =
             Attempts.claim(
               principal,
               p["id"],
               other["id"],
               command(%{"expected_version" => 1, "session_id" => session["id"]})
             )

    assert {:ok, _resolved} =
             Attempts.resolve(
               principal,
               p["id"],
               failed["id"],
               command(%{
                 "expected_version" => failed["version"],
                 "proof" => proof,
                 "effects_resolved" => true,
                 "evidence_ref" => "cessation-observed"
               })
             )

    refute Repo.get!(Task, task["id"]).execution_hold

    assert {:ok, _} =
             Attempts.claim(
               principal,
               p["id"],
               other["id"],
               command(%{"expected_version" => 1, "session_id" => session["id"]})
             )
  end

  test "expiry creates a durable hold and no automatic retry", ctx do
    %{project: p, principal: principal, task: task} = ctx
    {attempt, _proof} = claimed(ctx)

    Repo.get!(TaskAttempt, attempt["id"])
    |> Ecto.Changeset.change(start_deadline: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:ok, expired} =
             Attempts.expire(
               Principal.operator(),
               command(%{
                 "project_id" => p["id"],
                 "attempt_id" => attempt["id"],
                 "expected_version" => 1
               })
             )

    assert expired["state"] == "expired"
    assert Repo.get!(Task, task["id"]).execution_hold
    assert Repo.aggregate(from(a in TaskAttempt, where: a.task_id == ^task["id"]), :count) == 1
    assert {:error, %{code: :ownership_lost}} = Attempts.proof(principal, p["id"], attempt["id"])
  end

  test "resolving one Attempt retains the Task hold for another unresolved execution", ctx do
    %{project: p, principal: principal, task: task} = ctx
    {attempt, proof} = claimed(ctx)
    stored = Repo.get!(TaskAttempt, attempt["id"])

    previous =
      Repo.insert!(%TaskAttempt{
        task_id: stored.task_id,
        project_id: stored.project_id,
        agent_id: stored.agent_id,
        session_id: stored.session_id,
        connection_id: stored.connection_id,
        connection_generation: stored.connection_generation,
        number: 0,
        state: "expired",
        fence: stored.fence,
        execution_epoch: stored.execution_epoch,
        proof_key_id: stored.proof_key_id,
        lease_expires_at: stored.lease_expires_at,
        start_deadline: stored.start_deadline,
        execution_deadline: stored.execution_deadline,
        terminal_at: DateTime.utc_now()
      })

    assert {:ok, _} =
             Attempts.resolve(
               principal,
               p["id"],
               attempt["id"],
               command(%{
                 "expected_version" => 1,
                 "proof" => proof,
                 "effects_resolved" => true,
                 "evidence_ref" => "current-owner-stopped"
               })
             )

    assert Repo.get!(Task, task["id"]).execution_hold

    assert {:ok, _} =
             Attempts.resolve(
               Principal.operator(),
               p["id"],
               previous.id,
               command(%{
                 "expected_version" => previous.version,
                 "effects_resolved" => true,
                 "evidence_ref" => "previous-owner-stopped"
               })
             )

    refute Repo.get!(Task, task["id"]).execution_hold
  end

  test "closing authority rejects execution receipt replay while effect resolution remains possible",
       ctx do
    %{project: p, principal: principal, session: session, task: task} = ctx
    claim = command(%{"expected_version" => task["version"], "session_id" => session["id"]})
    {:ok, attempt} = Attempts.claim(principal, p["id"], task["id"], claim)
    {:ok, %{"proof" => proof}} = Attempts.proof(principal, p["id"], attempt["id"])

    {:ok, running} =
      Attempts.start(
        principal,
        p["id"],
        attempt["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    report =
      command(%{
        "expected_version" => running["version"],
        "proof" => proof,
        "outcome" => "succeeded",
        "effects_resolved" => false
      })

    {:ok, terminal} = Attempts.report(principal, p["id"], attempt["id"], report)
    {:ok, authority} = Samgita.Platform.status(Principal.operator())

    assert {:ok, _} =
             Samgita.Platform.close(
               Principal.operator(),
               command(%{
                 "expected_version" => authority["version"],
                 "reason" => "receipt replay fencing"
               })
             )

    assert {:error, %{code: :execution_closed}} =
             Attempts.claim(principal, p["id"], task["id"], claim)

    assert {:error, %{code: :execution_closed}} =
             Attempts.report(principal, p["id"], attempt["id"], report)

    assert {:ok, _} =
             Attempts.resolve(
               principal,
               p["id"],
               attempt["id"],
               command(%{
                 "expected_version" => terminal["version"],
                 "proof" => proof,
                 "effects_resolved" => true,
                 "evidence_ref" => "closed-owner-stopped"
               })
             )
  end

  test "reconnect requires explicit rebind and the former proof cannot execute", ctx do
    %{project: p, principal: old, agent: agent} = ctx
    {attempt, old_proof} = claimed(ctx)
    {new, _, _} = connection_fixture(agent)

    assert {:error, %{code: :unauthorized}} =
             Attempts.start(
               old,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => 1, "proof" => old_proof})
             )

    assert {:error, %{code: :ownership_lost}} =
             Attempts.start(
               new,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => 1, "proof" => old_proof})
             )

    rebind_command = command(%{"expected_version" => 1, "proof" => old_proof})
    assert {:ok, rebound} = Attempts.rebind(new, p["id"], attempt["id"], rebind_command)
    assert {:ok, ^rebound} = Attempts.rebind(new, p["id"], attempt["id"], rebind_command)
    assert rebound["fence"] > attempt["fence"]

    assert {:error, %{code: :ownership_lost}} =
             Attempts.start(
               new,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => rebound["version"], "proof" => old_proof})
             )

    assert {:ok, %{"proof" => new_proof}} = Attempts.proof(new, p["id"], attempt["id"])

    assert {:ok, running} =
             Attempts.start(
               new,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => rebound["version"], "proof" => new_proof})
             )

    assert running["state"] == "running"
    assert {:ok, ^rebound} = Attempts.rebind(new, p["id"], attempt["id"], rebind_command)
    assert Repo.get!(TaskAttempt, attempt["id"]).version == running["version"]

    assert {:ok, resolved} =
             Attempts.resolve(
               new,
               p["id"],
               attempt["id"],
               command(%{
                 "expected_version" => running["version"],
                 "proof" => old_proof,
                 "effects_resolved" => true,
                 "evidence_ref" => "former-owner-stopped"
               })
             )

    assert resolved["state"] == "released"
  end

  test "claims require adoption, capabilities, current session and active authority", ctx do
    %{project: p, principal: principal, session: session, task: task} = ctx
    stored = Repo.get!(Task, task["id"])
    Repo.update!(Ecto.Changeset.change(stored, adopted: false))

    assert {:error, %{code: :invalid_transition}} =
             Attempts.claim(
               principal,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "session_id" => session["id"]})
             )

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Task, task["id"]),
        adopted: true,
        required_capabilities: ["not-approved"]
      )
    )

    assert {:error, %{code: :forbidden}} =
             Attempts.claim(
               principal,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "session_id" => session["id"]})
             )

    Repo.update!(Ecto.Changeset.change(Repo.get!(Task, task["id"]), required_capabilities: []))

    assert {:error, %{code: :not_found}} =
             Attempts.claim(
               principal,
               p["id"],
               task["id"],
               command(%{"expected_version" => 1, "session_id" => Ecto.UUID.generate()})
             )
  end

  test "source drift after historical adoption prevents a new claim", ctx do
    %{project: p, principal: principal, session: session} = ctx
    operator = Principal.operator()
    legacy = Repo.insert!(%Task{project_id: p["id"], type: "legacy", status: "pending"})
    {:ok, authority} = Samgita.Platform.status(operator)

    {:ok, _} =
      Samgita.Platform.close(
        operator,
        command(%{
          "expected_version" => authority["version"],
          "reason" => "isolated historical claim test"
        })
      )

    {:ok, _} = Samgita.LegacyMapping.apply(operator, command())

    {:ok, adopted} =
      Tasks.adopt(
        operator,
        p["id"],
        legacy.id,
        command(%{
          "expected_version" => 1,
          "title" => "Reviewed legacy work",
          "evidence_ref" => "review",
          "effects_resolved" => true,
          "content_reviewed" => true,
          "relationships_reviewed" => true
        })
      )

    activate_fixture()

    Repo.update_all(from(t in Task, where: t.id == ^legacy.id),
      set: [payload: %{"unexpected_source_write" => true}]
    )

    assert {:error, %{code: :conflict}} =
             Attempts.claim(
               principal,
               p["id"],
               legacy.id,
               command(%{"expected_version" => adopted["version"], "session_id" => session["id"]})
             )

    refute Repo.exists?(from a in TaskAttempt, where: a.task_id == ^legacy.id)
  end

  test "artifact references do not complete or accept a Task", ctx do
    %{project: p, principal: principal, task: task} = ctx
    {attempt, _proof} = claimed(ctx)
    current = Repo.get!(Task, task["id"])

    assert {:error, %{code: :invalid}} =
             Tasks.add_artifact(
               principal,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => current.version,
                 "attempt_id" => attempt["id"],
                 "kind" => "download",
                 "locator" => "https://user:secret@example.test/output?token=secret"
               })
             )

    assert {:error, %{code: :invalid}} =
             Tasks.add_artifact(
               principal,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => current.version,
                 "attempt_id" => attempt["id"],
                 "kind" => "output",
                 "locator" => "git:deadbeef",
                 "metadata" => %{"lease_proof" => "must-not-persist"}
               })
             )

    assert {:ok, artifact} =
             Tasks.add_artifact(
               principal,
               p["id"],
               task["id"],
               command(%{
                 "expected_version" => current.version,
                 "attempt_id" => attempt["id"],
                 "kind" => "git_commit",
                 "locator" => "git:deadbeef",
                 "digest" => "deadbeef"
               })
             )

    assert artifact["task_id"] == task["id"]
    assert Repo.get!(Task, task["id"]).state == "open"
    assert Repo.aggregate(from(d in DecisionRecord, where: d.task_id == ^task["id"]), :count) == 0
  end

  test "pausing blocks new starts while existing execution can renew and report", ctx do
    %{project: p, principal: principal, task: task} = ctx
    {attempt, proof} = claimed(ctx)

    {:ok, running} =
      Attempts.start(
        principal,
        p["id"],
        attempt["id"],
        command(%{"expected_version" => 1, "proof" => proof})
      )

    {:ok, project} = Projects.get(Principal.operator(), p["id"])

    assert {:ok, _} =
             Projects.transition(
               Principal.operator(),
               p["id"],
               command(%{"expected_version" => project["version"], "state" => "paused"})
             )

    assert {:ok, %{"proof" => ^proof}} = Attempts.proof(principal, p["id"], attempt["id"])

    assert {:ok, renewed} =
             Attempts.renew(
               principal,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => running["version"], "proof" => proof})
             )

    {:ok, %{"proof" => renewed_proof}} = Attempts.proof(principal, p["id"], attempt["id"])

    assert {:ok, _} =
             Attempts.report(
               principal,
               p["id"],
               attempt["id"],
               command(%{
                 "expected_version" => renewed["version"],
                 "proof" => renewed_proof,
                 "outcome" => "succeeded",
                 "effects_resolved" => true
               })
             )

    assert Repo.get!(Task, task["id"]).state == "awaiting_review"
  end

  test "reopening an active blocked Task invalidates ownership without clearing uncertainty",
       ctx do
    %{project: p, principal: principal, task: task} = ctx
    {attempt, proof} = claimed(ctx)

    {:ok, running} =
      Attempts.start(
        principal,
        p["id"],
        attempt["id"],
        command(%{"expected_version" => 1, "proof" => proof})
      )

    current = Repo.get!(Task, task["id"])

    {:ok, blocked} =
      Tasks.transition(
        Principal.operator(),
        p["id"],
        task["id"],
        command(%{"expected_version" => current.version, "state" => "blocked"})
      )

    assert {:ok, reopened} =
             Tasks.transition(
               Principal.operator(),
               p["id"],
               task["id"],
               command(%{"expected_version" => blocked["version"], "state" => "open"})
             )

    assert reopened["execution_hold"]
    assert Repo.get!(TaskAttempt, attempt["id"]).state == "cancelled"

    assert {:error, %{code: :stale_version}} =
             Attempts.report(
               principal,
               p["id"],
               attempt["id"],
               command(%{
                 "expected_version" => running["version"],
                 "proof" => proof,
                 "outcome" => "succeeded",
                 "effects_resolved" => true
               })
             )
  end

  test "lease-key rotation and lost renew responses preserve ownership without storing a proof",
       ctx do
    %{project: p, principal: principal} = ctx
    old_keys = Application.fetch_env!(:samgita, :lease_keys)
    old_id = Application.fetch_env!(:samgita, :lease_key_id)

    on_exit(fn ->
      Application.put_env(:samgita, :lease_keys, old_keys)
      Application.put_env(:samgita, :lease_key_id, old_id)
    end)

    {attempt, old_proof} = claimed(ctx)
    new_id = "rotation-test-v2"

    Application.put_env(
      :samgita,
      :lease_keys,
      Map.put(old_keys, new_id, :crypto.strong_rand_bytes(32))
    )

    Application.put_env(:samgita, :lease_key_id, new_id)
    attrs = command(%{"expected_version" => 1, "proof" => old_proof})
    assert {:ok, renewed} = Attempts.renew(principal, p["id"], attempt["id"], attrs)
    assert renewed["proof_key_id"] == new_id
    assert {:ok, ^renewed} = Attempts.renew(principal, p["id"], attempt["id"], attrs)
    assert Repo.get!(TaskAttempt, attempt["id"]).version == renewed["version"]
    {:ok, %{"proof" => current_proof}} = Attempts.proof(principal, p["id"], attempt["id"])
    refute current_proof == old_proof

    assert {:error, %{code: :ownership_lost}} =
             Attempts.start(
               principal,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => renewed["version"], "proof" => old_proof})
             )

    assert {:ok, running} =
             Attempts.start(
               principal,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => renewed["version"], "proof" => current_proof})
             )

    assert {:ok, ^renewed} = Attempts.renew(principal, p["id"], attempt["id"], attrs)
    assert Repo.get!(TaskAttempt, attempt["id"]).version == running["version"]
    receipt = Repo.get_by!(CommandReceipt, command_id: attrs["command_id"])
    refute Jason.encode!(receipt.result) =~ old_proof
    refute Jason.encode!(receipt.result) =~ current_proof

    evidence =
      command(%{
        "expected_version" => running["version"],
        "proof" => old_proof,
        "effects_resolved" => true,
        "evidence_ref" => "old-key-effect-cessation"
      })

    keys = Application.fetch_env!(:samgita, :lease_keys)
    Application.put_env(:samgita, :lease_keys, Map.delete(keys, old_id))

    assert {:error, %{code: :ownership_lost}} =
             Attempts.resolve(principal, p["id"], attempt["id"], evidence)

    Application.put_env(:samgita, :lease_keys, keys)

    assert {:ok, %{"state" => "released"}} =
             Attempts.resolve(principal, p["id"], attempt["id"], evidence)
  end

  test "renewal cannot extend the fixed execution deadline", ctx do
    %{project: p, principal: principal} = ctx
    {attempt, _} = claimed(ctx)
    deadline = DateTime.add(DateTime.utc_now(), 10, :second)

    Repo.get!(TaskAttempt, attempt["id"])
    |> Ecto.Changeset.change(execution_deadline: deadline)
    |> Repo.update!()

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, p["id"], attempt["id"])

    assert {:ok, renewed} =
             Attempts.renew(
               principal,
               p["id"],
               attempt["id"],
               command(%{"expected_version" => 1, "proof" => proof})
             )

    assert renewed["lease_expires_at"] == renewed["execution_deadline"]
  end

  defp claimed(ctx) do
    {:ok, attempt} =
      Attempts.claim(
        ctx.principal,
        ctx.project["id"],
        ctx.task["id"],
        command(%{"expected_version" => ctx.task["version"], "session_id" => ctx.session["id"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(ctx.principal, ctx.project["id"], attempt["id"])
    {attempt, proof}
  end
end
