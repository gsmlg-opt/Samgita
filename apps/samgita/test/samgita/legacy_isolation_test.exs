defmodule Samgita.LegacyIsolationTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Error, Platform, Principal, Repo}

  test "registration is inert and only new coordination queues and cron are enabled" do
    before_children = Supervisor.which_children(Samgita.Supervisor) |> Enum.map(&elem(&1, 0))
    before_jobs = Repo.aggregate(Oban.Job, :count)
    agent_fixture(%{"implementation" => "Synapsis"})

    assert Supervisor.which_children(Samgita.Supervisor) |> Enum.map(&elem(&1, 0)) ==
             before_children

    assert Repo.aggregate(Oban.Job, :count) == before_jobs
    config = Application.fetch_env!(:samgita, Oban)

    assert Keyword.keys(config[:queues]) |> Enum.sort() ==
             ~w(hub_events hub_maintenance hub_schedules)a

    assert [{Oban.Plugins.Cron, cron}] = config[:plugins]

    assert Enum.map(cron[:crontab], &elem(&1, 1)) == [
             Samgita.Workers.ScheduleTickWorker,
             Samgita.Workers.CoordinationMaintenanceWorker
           ]

    for module <- [
          Samgita.Project.Recovery,
          Samgita.Project.Orchestrator,
          Samgita.Agent.Worker,
          Samgita.Workers.BootstrapWorker,
          Samgita.Workers.PlanningWorker
        ] do
      refute Code.ensure_loaded?(module)
    end
  end

  test "retained legacy jobs deny activation without being run, rewritten or cancelled" do
    {:ok, authority} = Platform.status(Principal.operator())

    {:ok, closed} =
      Platform.close(
        Principal.operator(),
        command(%{"expected_version" => authority["version"], "reason" => "isolated-test"})
      )

    job =
      Repo.insert!(
        Ecto.Changeset.change(%Oban.Job{},
          worker: "Samgita.Workers.BootstrapWorker",
          queue: "agent_tasks",
          state: "scheduled",
          args: %{"historical" => "preserve"},
          scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
        )
      )

    attrs =
      command(%{
        "expected_version" => closed["version"],
        "evidence" => %{
          "legacy_fenced" => true,
          "effects_resolved" => true,
          "reference" => "test"
        }
      })

    assert {:error, %Error{code: :execution_closed}} =
             Platform.activate(Principal.operator(), attrs)

    assert Repo.get!(Oban.Job, job.id).args == job.args
    assert Repo.get!(Oban.Job, job.id).state == "scheduled"
  end
end
