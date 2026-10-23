defmodule Samgita.Events.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures
  import Samgita.CoordinationFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{Commands, Error, EventDelivery, Events, Principal, Projects, Repo}
  alias Samgita.Domain.{EventAcknowledgement, EventDeliveryAttempt}
  alias Samgita.Domain.EventDelivery, as: Delivery

  test "independent claimers allocate one handler, concurrent settlements commit one result" do
    {delivery, claim} =
      Sandbox.unboxed_run(Repo, fn ->
        {_, _, _, _, delivery} = delivery_fixture()
        {delivery, nil}
      end)

    results =
      race([
        fn -> EventDelivery.claim(delivery.id) end,
        fn -> EventDelivery.claim(delivery.id) end
      ])

    assert Enum.count(results, &match?({:ok, %{action: "receive"}}, &1)) == 1

    claim =
      Enum.find_value(results, fn
        {:ok, %{action: _} = claim} -> claim
        _ -> nil
      end) || claim

    result = {:ok, acknowledge(claim)}

    settlements =
      race([
        fn -> EventDelivery.settle(delivery.id, claim.token, result) end,
        fn -> EventDelivery.settle(delivery.id, claim.token, result) end
      ])

    assert Enum.count(settlements, &match?({:ok, %{"state" => "accepted"}}, &1)) == 1
    assert Enum.count(settlements, &match?({:error, %Error{code: :ownership_lost}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(
               from(a in EventAcknowledgement, where: a.delivery_id == ^delivery.id),
               :count
             ) == 1

      refute Repo.exists?(
               from a in EventDeliveryAttempt,
                 where: a.delivery_id == ^delivery.id and a.state == "started"
             )
    end)
  end

  test "processing report races network settlement without leaving an active stale handler" do
    {p, actor, delivery, claim, attrs} =
      Sandbox.unboxed_run(Repo, fn ->
        {p, a, _, _, d} = delivery_fixture()
        {actor, _, _} = connection_fixture(a)
        {:ok, claim} = EventDelivery.claim(d.id)
        current = Repo.get!(Delivery, d.id)

        attrs =
          command(%{
            "expected_version" => current.version,
            "operation_id" => d.operation_id,
            "fence" => current.fence,
            "processing_status" => "completed",
            "decision_id" => Ecto.UUID.generate()
          })

        {p, actor, d, claim, attrs}
      end)

    results =
      race([
        fn -> EventDelivery.report(actor, p["id"], delivery.id, attrs) end,
        fn -> EventDelivery.settle(delivery.id, claim.token, {:ok, acknowledge(claim)}) end
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.count(
             results,
             &match?(
               {:error, %Error{code: code}} when code in [:ownership_lost, :stale_version],
               &1
             )
           ) == 1

    Sandbox.unboxed_run(Repo, fn ->
      refute Repo.exists?(
               from a in EventDeliveryAttempt,
                 where: a.delivery_id == ^delivery.id and a.state == "started"
             )

      assert Repo.get!(Delivery, delivery.id).state in ["accepted", "completed"]
    end)
  end

  test "cancellation racing a result never leaves executable ownership" do
    {p, d, claim, attrs} =
      Sandbox.unboxed_run(Repo, fn ->
        {p, _, _, _, d} = delivery_fixture()
        {:ok, claim} = EventDelivery.claim(d.id)
        current = Repo.get!(Delivery, d.id)

        {p, d, claim,
         command(%{
           "expected_version" => current.version,
           "action" => "cancel",
           "reason" => "race cancellation"
         })}
      end)

    results =
      race([
        fn -> EventDelivery.recover(Principal.operator(), p["id"], d.id, attrs) end,
        fn -> EventDelivery.settle(d.id, claim.token, {:ok, acknowledge(claim)}) end
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      current = Repo.get!(Delivery, d.id)
      assert current.state in ["cancelled", "accepted"]
      refute current.lease_id

      assert {:error, %Error{code: :ownership_lost}} =
               EventDelivery.settle(d.id, claim.token, {:ok, acknowledge(claim)})
    end)
  end

  test "a killed worker after persistence recovers only through a status query" do
    {event, d} =
      Sandbox.unboxed_run(Repo, fn ->
        {_, _, _, event, d} = delivery_fixture()
        {event, d}
      end)

    caller = self()

    {worker, monitor} =
      spawn_monitor(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Process.put(:crash_owner, caller)

          EventDelivery.dispatch(d.id,
            connector: Samgita.CoordinationFixtures.CrashBeforeSendConnector
          )
        end)
      end)

    assert_receive {:before_wire_send, ^worker, original, operation}, 5000
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 5000

    Sandbox.unboxed_run(Repo, fn ->
      now = DateTime.add(DateTime.utc_now(), 61)
      Process.put(:fake_status_result, :not_found)

      assert {:ok, %{"state" => "uncertain"}} =
               EventDelivery.dispatch(d.id,
                 connector: Samgita.CoordinationFixtures.FakeConnector,
                 now: now,
                 settled_at: now
               )

      assert_receive {:fake_status, _, id, ^operation}
      assert id == event["id"]
      assert original["created_at"] == event["created_at"]
      refute_receive {:fake_receive, _, _, _}
    end)
  end

  test "outbox Agent references cannot deadlock an Agent lock waiting for the Project" do
    {p, a} =
      Sandbox.unboxed_run(Repo, fn ->
        {p, a, _} = routing_fixture()
        {p, a}
      end)

    caller = self()

    writer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Commands.run(
            Principal.operator(),
            p["id"],
            command(),
            [operation: "test.fk_order"],
            fn ctx ->
              %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
              send(caller, {:project_held, self(), backend})

              receive do
                :append ->
                  Events.append!(p["id"], "project.updated", ctx, "project", p["id"])
                  %{"appended" => true}
              after
                5000 -> flunk("project barrier timeout")
              end
            end
          )
        end)
      end)

    assert_receive {:project_held, first, first_backend}, 5000

    member =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Commands.system(nil, [a["id"]], fn _ ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(caller, {:agent_held, backend})
            {:ok, current} = Projects.get(Principal.operator(), p["id"])

            Projects.put_member(
              Principal.operator(),
              p["id"],
              command(%{
                "expected_version" => current["version"],
                "agent_id" => a["id"],
                "roles" => ["manager"]
              })
            )
          end)
        end)
      end)

    assert_receive {:agent_held, second_backend}, 5000
    refute first_backend == second_backend
    send(first, :append)
    assert {:ok, %{"appended" => true}} = Task.await(writer, 10_000)
    assert {:ok, {:ok, _}} = Task.await(member, 10_000)

    Sandbox.unboxed_run(Repo, fn ->
      for d <- Repo.all(from d in Delivery, where: d.project_id == ^p["id"]) do
        assert {:ok, _} =
                 EventDelivery.dispatch(d.id,
                   connector: Samgita.CoordinationFixtures.FakeConnector
                 )
      end
    end)
  end

  defp race(functions) do
    caller = self()

    workers = Enum.map(functions, &start_barrier_worker(caller, &1))

    backends =
      for _ <- workers do
        assert_receive {:ready, worker, pid}, 5000
        {worker, pid}
      end

    assert length(Enum.uniq_by(backends, &elem(&1, 1))) == length(functions)
    Enum.each(backends, fn {worker, _} -> send(worker, :go) end)
    Enum.map(workers, &Task.await(&1, 10_000))
  end

  defp start_barrier_worker(caller, function) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> run_after_barrier(caller, function) end) end)
  end

  defp run_after_barrier(caller, function) do
    %{rows: [[pid]]} = Repo.query!("SELECT pg_backend_pid()")
    send(caller, {:ready, self(), pid})

    receive do
      :go -> function.()
    after
      5000 -> flunk("concurrency barrier timed out")
    end
  end
end
