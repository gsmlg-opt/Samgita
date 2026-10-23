defmodule SamgitaWeb.RestartReconcileTest do
  use ExUnit.Case, async: false
  @moduletag :e2e
  import Ecto.Query
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL.Sandbox

  alias Samgita.{
    Agents,
    Attempts,
    EventDelivery,
    Events,
    Management,
    Platform,
    Principal,
    Projects,
    Repo,
    Tasks
  }

  alias Samgita.Domain.{DomainEvent, TaskAttempt}
  alias Samgita.Domain.EventDelivery, as: Delivery
  alias SamgitaWeb.FakeAgent

  test "application and fake-host restart reconcile lost ACKs and preserve execution holds" do
    database = Repo.config()[:database]

    assert String.starts_with?(database, "samgita_redesign_"),
           "restart qualification requires an explicit scratch database"

    previous =
      Map.new([:event_destinations, :event_credentials], &{&1, Application.get_env(:samgita, &1)})

    on_exit(fn ->
      Application.ensure_all_started(:samgita)
      Sandbox.mode(Repo, :manual)

      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:samgita, key),
          else: Application.put_env(:samgita, key, value)
      end)
    end)

    path = Path.join(System.tmp_dir!(), "samgita-restart-#{Ecto.UUID.generate()}.json")
    # Retain the fsynced synthetic journal referenced by committed resolution evidence.

    fake = start_supervised!({FakeAgent, journal: path, token: "restart-service-token"})
    url = FakeAgent.url(fake)
    port = URI.parse(url).port

    {p, a, actor, attempt, proof, d} =
      committed(fn ->
        activate_fixture()
        p = project_fixture(%{"name" => "Restart qualification"})

        a =
          agent_fixture(%{
            "name" => "Restart Agent",
            "endpoint_metadata" => %{"url" => url, "transport" => "websocket"},
            "credential_ref" => "restart-service-v1"
          })

        member_fixture(p, a)
        {:ok, current} = Projects.get(Principal.operator(), p["id"])

        {:ok, _} =
          Events.configure(
            Principal.operator(),
            p["id"],
            command(%{
              "expected_version" => current["version"],
              "agent_id" => a["id"],
              "types" => ["manual.triggered"],
              "idempotency_guaranteed" => true
            })
          )

        {:ok, event} = Events.trigger(Principal.operator(), p["id"], command())
        d = Repo.get_by!(Delivery, event_id: event["id"])
        {actor, _, _} = connection_fixture(a)

        {:ok, session} =
          Agents.open_session(actor, p["id"], command(%{"external_id" => "restart-execution"}))

        {:ok, task} =
          Tasks.create(
            Principal.operator(),
            p["id"],
            command(%{"title" => "Remote simulation remains active"})
          )

        {:ok, leased} =
          Attempts.claim(
            actor,
            p["id"],
            task["id"],
            command(%{"expected_version" => task["version"], "session_id" => session["id"]})
          )

        {:ok, %{"proof" => proof}} = Attempts.proof(actor, p["id"], leased["id"])

        {:ok, running} =
          Attempts.start(
            actor,
            p["id"],
            leased["id"],
            command(%{"expected_version" => leased["version"], "proof" => proof})
          )

        {p, a, actor, running, proof, d}
      end)

    Application.put_env(:samgita, :event_destinations, %{
      a["id"] => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    Application.put_env(:samgita, :event_credentials, %{
      "restart-service-v1" => "restart-service-token"
    })

    assert FakeAgent.start_once(fake, attempt["id"]) == :started
    assert :ok = FakeAgent.lose_ack(fake, self())
    dispatch = Task.async(fn -> committed(fn -> EventDelivery.dispatch(d.id) end) end)
    assert_receive {:journal_committed_before_ack, socket, event_id}, 3_000
    Process.exit(socket, :kill)

    assert {:ok, %{"state" => "reconciling", "remote_outcome_uncertain" => true}} =
             Task.await(dispatch)

    assert event_id == d.event_id
    assert :ok = stop_supervised(FakeAgent)

    restarted =
      start_supervised!({FakeAgent, journal: path, token: "restart-service-token", port: port})

    assert FakeAgent.start_once(restarted, attempt["id"]) == :already_started

    # Real OTP application restart; PostgreSQL and the Agent's journal survive.
    assert :ok = Application.stop(:samgita)
    assert {:ok, _} = Application.ensure_all_started(:samgita)
    Sandbox.mode(Repo, :manual)

    committed(fn ->
      assert {:ok, _} = EventDelivery.maintain(now: DateTime.add(DateTime.utc_now(), 65))

      assert {:ok, %{"state" => "accepted", "remote_outcome_uncertain" => false}} =
               EventDelivery.dispatch(d.id, now: DateTime.add(DateTime.utc_now(), 65))

      assert Repo.get!(Delivery, d.id).operation_id == d.operation_id

      assert Repo.aggregate(
               from(x in Samgita.Domain.EventAcknowledgement, where: x.delivery_id == ^d.id),
               :count
             ) == 1

      assert {:ok, history} = Management.task(Principal.operator(), p["id"], attempt["task_id"])
      assert hd(history["attempts"])["state"] == "running"
      {:ok, authority} = Platform.status(Principal.operator())

      {:ok, closed} =
        Platform.close(
          Principal.operator(),
          command(%{
            "expected_version" => authority["version"],
            "reason" => "Local rollback rehearsal after simulated execution"
          })
        )

      assert closed["owner"] == "none"
      assert closed["epoch"] > authority["epoch"]

      assert {:error, %Samgita.Error{}} =
               Attempts.report(
                 actor,
                 p["id"],
                 attempt["id"],
                 command(%{
                   "expected_version" => attempt["version"],
                   "proof" => proof,
                   "outcome" => "succeeded",
                   "effects_resolved" => true
                 })
               )

      assert {:ok, held} = Management.task(Principal.operator(), p["id"], attempt["task_id"])
      assert held["task"]["execution_hold"]
      assert held["task"]["state"] == "blocked"

      assert {:error, %Samgita.Error{}} =
               Platform.activate(
                 Principal.operator(),
                 command(%{
                   "expected_version" => closed["version"],
                   "evidence" => %{
                     "legacy_fenced" => true,
                     "effects_resolved" => true,
                     "reference" => "cannot-clear-active-remote-effect"
                   }
                 })
               )
    end)

    snapshot = FakeAgent.snapshot(restarted)
    assert snapshot["calls"] == ["receive", "status"]
    # The simulated remote effect is still running. Closing Samgita didn't undo it.
    assert snapshot["starts"] == [attempt["id"]]
    assert snapshot["stops"] == %{}

    # Only this test-owned simulated effect is now explicitly stopped. The
    # durable journal is checked before the operator records cessation evidence.
    operation = attempt["id"]
    assert {:ok, evidence} = FakeAgent.stop_once(restarted, operation)
    assert {:ok, ^evidence} = FakeAgent.stop_once(restarted, operation)

    assert %{"stops" => %{^operation => ^evidence}} = path |> File.read!() |> Jason.decode!()
    resolve_fixture_effect(p, attempt, evidence)

    assert :already_started = FakeAgent.start_once(restarted, operation)
    assert FakeAgent.snapshot(restarted)["starts"] == [operation]
    assert FakeAgent.snapshot(restarted)["events"] == snapshot["events"]
    assert FakeAgent.snapshot(restarted)["calls"] == ["receive", "status"]
  end

  defp resolve_fixture_effect(project, attempt, evidence) do
    committed(fn ->
      project_id = project["id"]
      events = from e in DomainEvent, where: e.project_id == ^project_id, order_by: e.sequence
      history = Repo.all(from e in events, select: e.id)
      current = Repo.get!(TaskAttempt, attempt["id"])

      attrs =
        command(%{
          "expected_version" => current.version,
          "effects_resolved" => true,
          "evidence_ref" => evidence["evidence_ref"]
        })

      assert {:ok, resolved} =
               Attempts.resolve(Principal.operator(), project_id, current.id, attrs)

      assert {:ok, ^resolved} =
               Attempts.resolve(Principal.operator(), project_id, current.id, attrs)

      assert resolved["state"] == "expired"
      assert resolved["effects_resolved"]

      assert Repo.get!(TaskAttempt, current.id).resolution_evidence ==
               Map.take(evidence, ["evidence_ref"])

      assert {:ok, preserved} = Management.task(Principal.operator(), project_id, current.task_id)
      assert preserved["task"]["state"] == "blocked"
      refute preserved["task"]["execution_hold"]
      assert is_nil(preserved["task"]["accepted_at"])
      assert length(preserved["attempts"]) == 1
      assert Enum.take(Repo.all(from e in events, select: e.id), length(history)) == history

      assert Repo.aggregate(
               from(e in events, where: e.type == "attempt.effects_resolved"),
               :count
             ) ==
               1

      assert activate_fixture()["owner"] == "hub"
    end)
  end

  defp committed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
