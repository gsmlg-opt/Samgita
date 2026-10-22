defmodule Samgita.Events.DeliveryTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  import Samgita.CoordinationFixtures
  alias Samgita.CoordinationFixtures.FakeConnector
  alias Samgita.Connector.Failure
  alias Samgita.{Agents, Commands, Error, EventDelivery, Events, Platform, Principal, Repo, Tasks}

  alias Samgita.Domain.{
    CommandReceipt,
    DomainEvent,
    EventAcknowledgement,
    EventDeliveryAttempt,
    EventRecoveryAction,
    TaskAttempt
  }

  alias Samgita.Domain.EventDelivery, as: Delivery

  test "commit-before-send survives a lost wakeup, duplicate dispatch changes no work state" do
    {p, a, _s, event, delivery} = delivery_fixture()
    # Simulate a lost durable-job wakeup, retaining the authoritative outbox row.
    Repo.delete_all(
      from j in Oban.Job, where: fragment("?->>'delivery_id'", j.args) == ^delivery.id
    )

    assert {:ok, 1} = EventDelivery.maintain()

    assert [_] =
             Repo.all(
               from j in Oban.Job, where: fragment("?->>'delivery_id'", j.args) == ^delivery.id
             )

    assert {:ok, %{"state" => "accepted", "accepted_at" => accepted}} =
             EventDelivery.dispatch(delivery.id, connector: FakeConnector)

    assert accepted
    assert_receive {:fake_receive, agent_id, wire, operation}
    assert agent_id == a["id"]
    assert wire["event_id"] == event["id"]
    assert wire["created_at"] == event["created_at"]
    assert operation == delivery.operation_id

    assert {:ok, %{"state" => "accepted"}} =
             EventDelivery.dispatch(delivery.id, connector: FakeConnector)

    refute_receive {:fake_receive, _, _, _}
    refute Repo.exists?(from a in TaskAttempt, where: a.project_id == ^p["id"])
    refute Repo.exists?(from t in Samgita.Domain.Task, where: t.project_id == ^p["id"])
  end

  test "lost ACK reconnects with a status query, never another receive" do
    {_, _, _, event, d} = delivery_fixture()
    Process.put(:fake_receive_result, {:error, Failure.new(:ambiguous, :ambiguous_disconnect)})
    now = DateTime.utc_now()

    assert {:ok, %{"state" => "reconciling", "remote_outcome_uncertain" => true}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: now, settled_at: now)

    assert_receive {:fake_receive, _, wire, operation}
    later = DateTime.add(now, 10)

    assert {:ok, %{"state" => "accepted", "remote_outcome_uncertain" => false}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: later, settled_at: later)

    assert_receive {:fake_status, _, id, ^operation}
    assert id == event["id"]
    assert wire["event_id"] == id
    refute_receive {:fake_receive, _, _, _}

    assert Repo.aggregate(from(a in EventAcknowledgement, where: a.delivery_id == ^d.id), :count) ==
             1
  end

  test "transport receipt is not durable acceptance or work completion" do
    {_, _, _, _, d} = delivery_fixture()
    Process.put(:fake_receive_result, :received)
    assert {:ok, result} = EventDelivery.dispatch(d.id, connector: FakeConnector)
    assert result["state"] == "reconciling"
    assert result["transport_received_at"]
    refute result["accepted_at"]
    refute result["completed_at"]

    assert Repo.aggregate(from(a in EventAcknowledgement, where: a.delivery_id == ^d.id), :count) ==
             1
  end

  test "ambiguous not-found without idempotency guarantees stops for explicit recovery" do
    {p, _, _, event, d} = delivery_fixture()
    now = DateTime.utc_now()
    Process.put(:fake_receive_result, {:error, Failure.new(:ambiguous, :timeout)})
    Process.put(:fake_status_result, :not_found)

    assert {:ok, _} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: now, settled_at: now)

    later = DateTime.add(now, 10)

    assert {:ok, %{"state" => "uncertain"} = uncertain} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: later, settled_at: later)

    attrs =
      command(%{
        "expected_version" => uncertain["version"],
        "action" => "redeliver",
        "reason" => "operator review",
        "evidence_ref" => "review/1"
      })

    assert {:error, %Error{code: :conflict}} =
             EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs)

    attrs = Map.put(attrs, "risk_acknowledged", true)

    assert {:ok, %{"state" => "pending"}} =
             EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs)

    assert Repo.aggregate(from(a in EventRecoveryAction, where: a.delivery_id == ^d.id), :count) ==
             1

    assert Repo.get!(DomainEvent, event["id"]).created_at |> DateTime.to_iso8601() ==
             event["created_at"]

    assert Repo.get!(Delivery, d.id).operation_id == d.operation_id
  end

  test "verified idempotency permits same-operation redelivery after status not-found" do
    {_, _, _, event, d} = delivery_fixture(idempotent: true)
    now = DateTime.utc_now()
    Process.put(:fake_receive_result, {:error, Failure.new(:ambiguous, :timeout)})
    Process.put(:fake_status_result, :not_found)

    assert {:ok, _} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: now, settled_at: now)

    assert_receive {:fake_receive, _, first, operation}
    later = DateTime.add(now, 10)

    assert {:ok, %{"state" => "retry_wait"}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: later, settled_at: later)

    Process.put(:fake_receive_result, :durable)
    later = DateTime.add(now, 30)

    assert {:ok, %{"state" => "accepted"}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: later, settled_at: later)

    assert_receive {:fake_receive, _, second, ^operation}
    assert first["event_id"] == second["event_id"]
    assert second["event_id"] == event["id"]
    assert first["created_at"] == second["created_at"]
    refute first["delivery_attempt_id"] == second["delivery_attempt_id"]
  end

  test "unavailable Agent and 429 use bounded backoff; exhaustion dead-letters" do
    {_, _, _, _, d} = delivery_fixture()
    Repo.update!(change(d, max_attempts: 2))
    now = DateTime.utc_now()
    Process.put(:fake_receive_result, {:error, Failure.http(429, [{"retry-after", "120"}])})

    assert {:ok, first} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: now, settled_at: now)

    assert first["state"] == "retry_wait"
    refute first["accepted_at"]
    assert first["last_error_class"] == "retryable"
    assert {:ok, due, _} = DateTime.from_iso8601(first["next_attempt_at"])
    assert DateTime.diff(due, now) == 120

    assert {:ok, _} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: DateTime.add(now, 60))

    assert_receive {:fake_receive, _, _, _}
    refute_receive {:fake_receive, _, _, _}
    Process.put(:fake_receive_result, {:error, Failure.new(:retryable, :remote_unavailable)})

    assert {:ok, last} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: due, settled_at: due)

    assert last["state"] == "dead_letter"
    assert last["attempt_count"] == 2
    assert is_nil(last["next_attempt_at"])
  end

  test "permanent and authentication failures remain distinct and do not count as delivery" do
    for {error, expected} <- [
          {Failure.new(:permanent, :unsupported_capability), "dead_letter"},
          {Failure.new(:authentication, :unauthorized), "authentication_failed"}
        ] do
      {_, _, _, _, d} = delivery_fixture()
      Process.put(:fake_receive_result, {:error, error})
      assert {:ok, result} = EventDelivery.dispatch(d.id, connector: FakeConnector)
      assert result["state"] == expected
      refute result["accepted_at"]
    end
  end

  test "renewal extends a bounded lease, expired handler cannot settle after reassignment" do
    {_, _, _, _, d} = delivery_fixture()
    now = DateTime.utc_now()
    assert {:ok, first} = EventDelivery.claim(d.id, now: now)

    assert {:ok, %{expires_at: renewed}} =
             EventDelivery.renew(d.id, first.token, now: DateTime.add(now, 30))

    assert DateTime.diff(renewed, now) == 90

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.settle(d.id, first.token, {:ok, acknowledge(first)},
               now: DateTime.add(now, 91)
             )

    assert {:ok, second} = EventDelivery.claim(d.id, now: DateTime.add(now, 91))
    assert second.action == "status"
    assert second.token.fence > first.token.fence

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.settle(d.id, first.token, {:ok, acknowledge(first)},
               now: DateTime.add(now, 92)
             )

    assert {:ok, %{"state" => "accepted"}} =
             EventDelivery.settle(
               d.id,
               second.token,
               {:ok, Map.delete(acknowledge(second), "delivery_attempt_id")},
               now: DateTime.add(now, 92)
             )

    assert Enum.map(
             Repo.all(
               from a in EventDeliveryAttempt, where: a.delivery_id == ^d.id, order_by: a.number
             ),
             & &1.state
           ) == ["unknown", "acknowledged"]
  end

  test "cancellation fences an in-flight handler and records unknown remote effects" do
    {p, _, _, _, d} = delivery_fixture()
    assert {:ok, claim} = EventDelivery.claim(d.id)
    current = Repo.get!(Delivery, d.id)

    attrs =
      command(%{
        "expected_version" => current.version,
        "action" => "cancel",
        "reason" => "operator cancellation"
      })

    assert {:ok, result} = EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs)
    assert result["state"] == "cancelled"
    assert result["remote_outcome_uncertain"]
    assert {:ok, ^result} = EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs)

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.settle(d.id, claim.token, {:ok, acknowledge(claim)})

    assert Repo.aggregate(from(a in EventRecoveryAction, where: a.delivery_id == ^d.id), :count) ==
             1
  end

  test "authority closure fences handlers; endpoint and credential-reference changes cannot redirect" do
    {p, a, _, _, d} = delivery_fixture()
    assert {:ok, claim} = EventDelivery.claim(d.id)
    {:ok, authority} = Platform.status(Principal.operator())

    assert {:ok, _} =
             Platform.close(
               Principal.operator(),
               command(%{"expected_version" => authority["version"], "reason" => "stop"})
             )

    assert Repo.get!(Delivery, d.id).state == "reconciling"

    assert {:error, %Error{code: :execution_closed}} =
             EventDelivery.settle(d.id, claim.token, {:ok, acknowledge(claim)})

    activate_fixture()
    {:ok, current} = Agents.get(Principal.operator(), a["id"])

    assert {:ok, _} =
             Agents.update(
               Principal.operator(),
               a["id"],
               command(%{
                 "expected_version" => current["version"],
                 "credential_ref" => "new-target-secret-reference"
               })
             )

    assert {:ok, %{"state" => "uncertain", "last_error_code" => "target_changed"}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector)

    assert {:ok, %{"data" => [_]}} = EventDelivery.list(Principal.operator(), p["id"])
    refute_receive {:fake_receive, _, _, _}
  end

  test "domain change, event, delivery and enqueue failure roll back together" do
    {p, _, _} = routing_fixture()
    attrs = command()
    before_jobs = Repo.aggregate(Oban.Job, :count)

    assert {:error, %Error{code: :enqueue_failed}} =
             Commands.run(
               Principal.operator(),
               p["id"],
               attrs,
               [operation: "test.enqueue_failure"],
               fn ctx ->
                 ctx.project |> change(name: "must roll back") |> Repo.update!()
                 event = Events.append!(p["id"], "project.updated", ctx, "project", p["id"])
                 delivery = Repo.get_by!(Delivery, event_id: event.id)
                 Events.enqueue!(delivery, fn _ -> {:error, :database_unavailable} end)
               end
             )

    refute Repo.get_by(DomainEvent, command_id: attrs["command_id"])
    refute Repo.get_by(CommandReceipt, command_id: attrs["command_id"])
    assert Repo.aggregate(Oban.Job, :count) == before_jobs
    refute Repo.get!(Samgita.Domain.Project, p["id"]).name == "must roll back"
  end

  test "external source IDs deduplicate facts and reject conflicting payloads" do
    {p, _, _} = routing_fixture()

    attrs = %{
      "source" => "upstream",
      "external_id" => "delivery-01",
      "payload" => %{"subject" => "issue changed"}
    }

    assert {:ok, first} = Events.external(Principal.operator(), p["id"], command(attrs))
    assert {:ok, ^first} = Events.external(Principal.operator(), p["id"], command(attrs))
    assert Repo.aggregate(from(d in Delivery, where: d.event_id == ^first["id"]), :count) == 1

    assert {:error, %Error{code: :conflict}} =
             Events.external(
               Principal.operator(),
               p["id"],
               command(Map.put(attrs, "payload", %{"subject" => "conflict"}))
             )

    assert {:error, %Error{code: :invalid}} =
             Events.external(
               Principal.operator(),
               p["id"],
               command(Map.put(attrs, "payload", %{"token" => "never-persist"}))
             )
  end

  test "reporting completion never satisfies task review or acceptance and expires stale reporters" do
    {p, a, _, _, d} = delivery_fixture()
    {actor, _, _} = connection_fixture(a)

    {:ok, task} =
      Tasks.create(Principal.operator(), p["id"], command(%{"title" => "unchanged work"}))

    {:ok, claim} = EventDelivery.claim(d.id)
    current = Repo.get!(Delivery, d.id)

    attrs =
      command(%{
        "expected_version" => current.version,
        "operation_id" => d.operation_id,
        "fence" => current.fence,
        "processing_status" => "completed",
        "decision_id" => Ecto.UUID.generate(),
        "result" => %{"summary" => "event considered"}
      })

    assert {:ok, %{"state" => "completed"}} = EventDelivery.report(actor, p["id"], d.id, attrs)

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.settle(d.id, claim.token, {:ok, acknowledge(claim)})

    refute Repo.exists?(
             from a in EventDeliveryAttempt,
               where: a.delivery_id == ^d.id and a.state == "started"
           )

    assert Repo.get!(Samgita.Domain.Task, task["id"]).state == task["state"]

    {:ok, event} = Events.trigger(Principal.operator(), p["id"], command())
    expired = Repo.get_by!(Delivery, event_id: event["id"])
    {:ok, claim} = EventDelivery.claim(expired.id)

    Repo.get!(Delivery, expired.id)
    |> change(lease_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    current = Repo.get!(Delivery, expired.id)

    attrs =
      Map.merge(
        attrs,
        command(%{
          "expected_version" => current.version,
          "operation_id" => current.operation_id,
          "fence" => claim.token.fence
        })
      )

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.report(actor, p["id"], expired.id, attrs)
  end

  test "project cursor refuses gaps and cross-project reads/reports are denied" do
    {p, a, s, event, d} = delivery_fixture()
    {actor, _, _} = connection_fixture(a)

    assert {:error, %Error{code: :conflict}} =
             Events.ack_cursor(actor, p["id"], s["id"], command(%{"cursor" => event["sequence"]}))

    assert {:ok, _} = EventDelivery.dispatch(d.id, connector: FakeConnector)

    assert {:ok, %{"cursor" => cursor}} =
             Events.ack_cursor(actor, p["id"], s["id"], command(%{"cursor" => event["sequence"]}))

    assert cursor == event["sequence"]

    assert {:ok, %{"cursor" => ^cursor}} =
             Events.ack_cursor(actor, p["id"], s["id"], command(%{"cursor" => cursor}))

    other = project_fixture()
    assert {:error, %Error{code: :forbidden}} = Events.read(actor, other["id"])

    assert {:error, %Error{code: :not_found}} =
             EventDelivery.get(Principal.operator(), other["id"], d.id)

    assert {:ok, %{"data" => events, "high_watermark" => watermark}} =
             Events.read(actor, p["id"], %{"after" => 0, "limit" => 100})

    assert List.last(events)["sequence"] == watermark
  end

  test "redelivering accepted non-idempotent work requires explicit risk and preserves evidence" do
    {p, a, _, _, d} = delivery_fixture()
    {actor, _, _} = connection_fixture(a)
    {:ok, claim} = EventDelivery.claim(d.id)
    current = Repo.get!(Delivery, d.id)

    {:ok, completed} =
      EventDelivery.report(
        actor,
        p["id"],
        d.id,
        command(%{
          "expected_version" => current.version,
          "fence" => claim.token.fence,
          "operation_id" => d.operation_id,
          "decision_id" => Ecto.UUID.generate(),
          "processing_status" => "completed",
          "result" => %{"summary" => "preserve processing evidence"}
        })
      )

    attrs =
      command(%{
        "expected_version" => completed["version"],
        "action" => "redeliver",
        "reason" => "explicit replay",
        "evidence_ref" => "review/2"
      })

    assert {:error, %Error{code: :conflict}} =
             EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs)

    assert {:ok, _} =
             EventDelivery.recover(
               Principal.operator(),
               p["id"],
               d.id,
               Map.put(attrs, "risk_acknowledged", true)
             )

    assert {:ok, current} = EventDelivery.dispatch(d.id, connector: FakeConnector)
    assert current["result"]["summary"] == "preserve processing evidence"
    assert {:ok, details} = EventDelivery.get(Principal.operator(), p["id"], d.id)

    assert Enum.any?(
             details["acknowledgements"],
             &(&1["result"]["summary"] == "preserve processing evidence")
           )
  end

  test "retarget replay selects a new subscription without rewriting the original event/delivery" do
    {p, a, _, event, d} = delivery_fixture()
    {:ok, old_claim} = EventDelivery.claim(d.id)

    second =
      agent_fixture(%{
        "endpoint_metadata" => %{
          "transport" => "websocket",
          "url" => "ws://127.0.0.1:9998/app-server"
        }
      })

    member_fixture(p, second)
    {:ok, project} = Samgita.Projects.get(Principal.operator(), p["id"])

    {:ok, subscription} =
      Events.configure(
        Principal.operator(),
        p["id"],
        command(%{"expected_version" => project["version"], "agent_id" => second["id"]})
      )

    attrs =
      command(%{
        "subscription_id" => subscription["id"],
        "expected_subscription_revision" => subscription["revision"],
        "source_delivery_id" => d.id,
        "reason" => "approved routing change",
        "evidence_ref" => "remote/review"
      })

    assert {:error, %Error{code: :conflict}} =
             Events.redeliver(Principal.operator(), p["id"], event["id"], attrs)

    assert {:ok, replay} =
             Events.redeliver(
               Principal.operator(),
               p["id"],
               event["id"],
               Map.put(attrs, "risk_acknowledged", true)
             )

    assert replay["event_id"] == event["id"]
    assert replay["agent_id"] == second["id"]
    refute replay["operation_id"] == d.operation_id
    assert Repo.get!(Delivery, d.id).agent_id == a["id"]

    assert {:error, %Error{code: :ownership_lost}} =
             EventDelivery.settle(d.id, old_claim.token, {:ok, acknowledge(old_claim)})

    assert Repo.get!(DomainEvent, event["id"]).created_at |> DateTime.to_iso8601() ==
             event["created_at"]

    assert Repo.get_by!(EventRecoveryAction, delivery_id: replay["id"]).previous_delivery_id ==
             d.id
  end

  test "a paused Project permits read-only reconciliation without reopening receives" do
    {p, _, _, _, d} = delivery_fixture()
    now = DateTime.utc_now()
    Process.put(:fake_receive_result, {:error, Failure.new(:ambiguous, :timeout)})

    assert {:ok, _} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: now, settled_at: now)

    assert_receive {:fake_receive, _, _, _}
    {:ok, current} = Samgita.Projects.get(Principal.operator(), p["id"])

    {:ok, _} =
      Samgita.Projects.transition(
        Principal.operator(),
        p["id"],
        command(%{"expected_version" => current["version"], "state" => "paused"})
      )

    later = DateTime.add(now, 10)

    assert {:ok, %{"state" => "accepted"}} =
             EventDelivery.dispatch(d.id, connector: FakeConnector, now: later, settled_at: later)

    assert_receive {:fake_status, _, _, _}
    refute_receive {:fake_receive, _, _, _}
  end
end
