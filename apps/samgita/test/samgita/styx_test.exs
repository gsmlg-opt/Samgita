defmodule Samgita.StyxTest do
  use Samgita.DataCase, async: false

  alias Samgita.Workers.{EventDeliveryWorker, ScheduleTickWorker}

  test "job insertion participates in the domain Repo transaction" do
    delivery_id = Ecto.UUID.generate()

    assert {:error, :rollback_probe} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        Styx.insert(EventDeliveryWorker.new(%{"delivery_id" => delivery_id}))

               Repo.rollback(:rollback_probe)
             end)

    refute Repo.exists?(from j in Styx.Job, where: j.args == ^%{"delivery_id" => delivery_id})

    assert {:ok, job} =
             Repo.transaction(fn ->
               Styx.insert!(EventDeliveryWorker.new(%{"delivery_id" => delivery_id}))
             end)

    assert Repo.get!(Styx.Job, job.id).args == %{"delivery_id" => delivery_id}
  end

  test "duplicate delivery wakeups collapse while distinct deliveries remain distinct" do
    id = Ecto.UUID.generate()
    other_id = Ecto.UUID.generate()
    assert {:ok, first} = Styx.insert(EventDeliveryWorker.new(%{"delivery_id" => id}))
    assert {:ok, duplicate} = Styx.insert(EventDeliveryWorker.new(%{"delivery_id" => id}))
    assert duplicate.id == first.id
    assert duplicate.conflict?
    assert {:ok, other} = Styx.insert(EventDeliveryWorker.new(%{"delivery_id" => other_id}))
    assert other.id != first.id
  end

  test "schedule wakeups leave quarantined jobs unchanged" do
    quarantined =
      Styx.Job.new(%{"historical" => "retain"},
        worker: "Samgita.Workers.BootstrapWorker",
        queue: "agent_tasks",
        priority: 0,
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
      )
      |> Repo.insert!()
      |> Repo.reload!()

    assert {:ok, current} = Styx.insert(ScheduleTickWorker.new(%{}))
    assert Repo.get!(Styx.Job, current.id).queue == "hub_schedules"
    assert Repo.get!(Styx.Job, quarantined.id) == quarantined

    jobs = Samgita.Platform.legacy_jobs()

    assert %{
             "id" => quarantined.id,
             "worker" => quarantined.worker,
             "queue" => quarantined.queue,
             "state" => quarantined.state,
             "store" => "styx_jobs"
           } in jobs

    refute Enum.any?(jobs, &(&1["id"] == current.id))
  end

  test "only the four existing queues and three periodic scanners are configured" do
    config = Application.fetch_env!(:samgita, Styx)

    assert config[:queues] ==
             [hub_events: 10, hub_schedules: 1, hub_maintenance: 1, hub_github: 2]

    assert Enum.map(config[:cron][:crontab], &elem(&1, 1)) == [
             ScheduleTickWorker,
             Samgita.Workers.CoordinationMaintenanceWorker,
             Samgita.Workers.GitHubMaintenanceWorker
           ]

    for service <- [:pruner, :lifeline, :reindexer], do: assert(config[service] == false)
    assert Styx.config().testing == :manual
    assert Styx.config().queues == []
    assert Styx.config().plugins == []
    assert Styx.config().stager == false
  end
end
