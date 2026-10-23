defmodule Samgita.SchedulesTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.Domain.{DomainEvent, Schedule, ScheduleOccurrence}
  alias Samgita.{Error, Principal, Schedules}

  test "update receipts bind the canonical schedule target and preserve same-target retries" do
    project = project_fixture()
    first = create_schedule(project)
    second = create_schedule(project)
    attrs = command(%{"expected_version" => 1, "enabled" => false})
    operator = Principal.operator()

    assert {:ok, updated} = Schedules.update(operator, project["id"], first["id"], attrs)
    assert {:ok, ^updated} = Schedules.update(operator, project["id"], first["id"], attrs)

    assert {:ok, ^updated} =
             Schedules.update(operator, project["id"], String.upcase(first["id"]), attrs)

    assert {:error, %Error{code: :conflict}} =
             Schedules.update(operator, project["id"], second["id"], attrs)

    assert Repo.get!(Schedule, second["id"]).version == 1
    assert Repo.get!(Schedule, second["id"]).enabled

    for changed <- [Map.put(attrs, "enabled", true), Map.put(attrs, "expected_version", 2)] do
      assert {:error, %Error{code: :conflict}} =
               Schedules.update(operator, project["id"], first["id"], changed)
    end

    assert {:error, %Error{code: :stale_version}} =
             Schedules.update(
               operator,
               project["id"],
               first["id"],
               command(%{"expected_version" => 1})
             )

    for target <- [Ecto.UUID.generate(), second["id"]] do
      assert {:error, %Error{code: :not_found}} =
               Schedules.update(
                 operator,
                 project_fixture()["id"],
                 target,
                 command(%{"expected_version" => 1})
               )
    end

    outsider = agent_fixture()
    {principal, _, _} = connection_fixture(outsider)

    assert {:error, %Error{code: :forbidden}} =
             Schedules.update(principal, project["id"], first["id"], attrs)
  end

  test "pre-target receipts replay only when stored evidence proves their original target" do
    project = project_fixture()
    first = create_schedule(project)
    second = create_schedule(project)
    attrs = command(%{"expected_version" => 1, "enabled" => false})

    assert {:ok, updated} =
             Schedules.update(Principal.operator(), project["id"], first["id"], attrs)

    digest =
      Samgita.Commands.digest({"schedule.update", project["id"], Map.delete(attrs, "command_id")})

    receipt = Repo.get_by!(Samgita.Domain.CommandReceipt, command_id: attrs["command_id"])
    receipt |> change(request_digest: digest) |> Repo.update!()

    assert {:ok, ^updated} =
             Schedules.update(Principal.operator(), project["id"], first["id"], attrs)

    assert {:error, %Error{code: :conflict}} =
             Schedules.update(Principal.operator(), project["id"], second["id"], attrs)

    assert {:error, %Error{code: :conflict}} =
             Schedules.update(Principal.operator(), project["id"], nil, attrs)

    assert Repo.get!(Schedule, second["id"]).version == 1
    assert Repo.get!(Schedule, first["id"]).version == 2

    receipt
    |> change(
      request_digest: digest,
      result: Map.put(updated, "project_id", Ecto.UUID.generate())
    )
    |> Repo.update!()

    assert {:error, %Error{code: :conflict}} =
             Schedules.update(Principal.operator(), project["id"], first["id"], attrs)

    receipt |> change(request_digest: digest, result: %{}) |> Repo.update!()

    assert {:error, %Error{code: :conflict}} =
             Schedules.update(Principal.operator(), project["id"], first["id"], attrs)

    assert Repo.get!(Schedule, first["id"]).version == 2
  end

  test "a schedule emits stable occurrences and a restart does not create more logical events" do
    activate_fixture()
    project = project_fixture()
    schedule = create_schedule(project, "*/2 * * * *")

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:05:00Z])
    first = occurrences(schedule)

    assert Enum.map(first, &DateTime.to_iso8601(&1.due_at)) == [
             "2026-10-22T00:02:00.000000Z",
             "2026-10-22T00:04:00.000000Z"
           ]

    events = Enum.map(first, &Repo.get!(DomainEvent, &1.event_id))
    assert Enum.all?(events, &(&1.type == "schedule.check"))
    assert Enum.all?(events, &(&1.project_id == project["id"]))
    assert Enum.all?(events, &(&1.resource_type == "schedule"))
    assert Enum.all?(events, &(&1.data["payload"] == %{"reason" => "periodic inspection"}))

    assert Repo.aggregate(
             from(t in Samgita.Domain.Task, where: t.project_id == ^project["id"]),
             :count
           ) == 0

    assert Repo.aggregate(
             from(a in Samgita.Domain.TaskAttempt, where: a.project_id == ^project["id"]),
             :count
           ) == 0

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:05:00Z])
    assert Enum.map(occurrences(schedule), & &1.event_id) == Enum.map(first, & &1.event_id)

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:06:00Z])
    assert length(occurrences(schedule)) == 3
  end

  test "missed runs catch up with bounded scans and visible durable backlog" do
    activate_fixture()
    project = project_fixture()
    schedule = create_schedule(project)

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:06:00Z], max_minutes: 2)
    assert length(occurrences(schedule)) == 2
    assert Repo.get!(Schedule, schedule["id"]).scanned_through == ~U[2026-10-22 00:02:00.000000Z]

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:06:00Z], max_occurrences: 1)
    assert length(occurrences(schedule)) == 3
    assert Repo.get!(Schedule, schedule["id"]).scanned_through == ~U[2026-10-22 00:03:00.000000Z]

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:06:00Z])
    assert length(occurrences(schedule)) == 6
    assert {:ok, %{"data" => [visible]}} = Schedules.list(Principal.operator(), project["id"])
    assert visible["scanned_through"] == "2026-10-22T00:06:00.000000Z"
    assert visible["timezone"] == "Etc/UTC"
  end

  test "disabling and changing revisions preserve history and require an explicit new cursor" do
    activate_fixture()
    project = project_fixture()
    schedule = create_schedule(project)
    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:02:00Z])
    initial_ids = Enum.map(occurrences(schedule), & &1.event_id)

    attrs =
      command(%{
        "expected_version" => 1,
        "enabled" => false,
        "start_at" => "2026-10-22T00:02:00Z"
      })

    assert {:ok, disabled} =
             Schedules.update(Principal.operator(), project["id"], schedule["id"], attrs)

    assert disabled["revision"] == 2

    assert {:ok, ^disabled} =
             Schedules.update(Principal.operator(), project["id"], schedule["id"], attrs)

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:05:00Z])
    assert Enum.map(occurrences(schedule), & &1.event_id) == initial_ids

    assert {:error, %Error{code: :stale_version}} =
             Schedules.update(
               Principal.operator(),
               project["id"],
               schedule["id"],
               command(%{"expected_version" => 1, "enabled" => true})
             )

    assert {:ok, enabled} =
             Schedules.update(
               Principal.operator(),
               project["id"],
               schedule["id"],
               command(%{
                 "expected_version" => 2,
                 "enabled" => true,
                 "start_at" => "2026-10-22T00:04:00Z"
               })
             )

    assert enabled["revision"] == 3
    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:05:00Z])
    assert Enum.map(occurrences(schedule), & &1.revision) == [1, 1, 3]
    assert Enum.take(Enum.map(occurrences(schedule), & &1.event_id), 2) == initial_ids
  end

  test "the repeated DST local minute is two absolute occurrences and a nonexistent minute is skipped" do
    activate_fixture()
    project = project_fixture()

    fallback =
      create_schedule(project, "30 1 * * *", %{
        "timezone" => "America/New_York",
        "start_at" => "2026-11-01T05:29:00Z"
      })

    assert {:ok, _} = Schedules.tick(now: ~U[2026-11-01 06:30:00Z])

    assert Enum.map(occurrences(fallback), & &1.due_at) == [
             ~U[2026-11-01 05:30:00.000000Z],
             ~U[2026-11-01 06:30:00.000000Z]
           ]

    spring =
      create_schedule(project, "30 2 * * *", %{
        "timezone" => "America/New_York",
        "start_at" => "2026-03-08T06:59:00Z"
      })

    assert {:ok, _} = Schedules.tick(now: ~U[2026-03-08 08:00:00Z])
    assert occurrences(spring) == []
    assert Repo.get!(Schedule, spring["id"]).scanned_through == ~U[2026-03-08 08:00:00.000000Z]
  end

  test "closed authority and inactive Projects emit nothing" do
    project = project_fixture()
    schedule = create_schedule(project)
    {:ok, authority} = Samgita.Platform.status(Principal.operator())

    assert {:ok, _} =
             Samgita.Platform.close(
               Principal.operator(),
               command(%{
                 "expected_version" => authority["version"],
                 "reason" => "scheduler boundary"
               })
             )

    assert {:ok, %{"closed" => true}} = Schedules.tick(now: ~U[2026-10-22 00:03:00Z])
    assert occurrences(schedule) == []
    activate_fixture()

    assert {:ok, _} =
             Samgita.Projects.transition(
               Principal.operator(),
               project["id"],
               command(%{"expected_version" => project["version"], "state" => "paused"})
             )

    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:03:00Z])
    assert occurrences(schedule) == []
  end

  test "schedule configuration is operator-only, Project-scoped and validates source metadata" do
    project = project_fixture()
    other = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {principal, _, _} = connection_fixture(agent)

    assert {:error, %Error{code: :forbidden}} =
             Schedules.create(principal, project["id"], command(%{"expression" => "* * * * *"}))

    schedule = create_schedule(project)

    assert {:error, %Error{code: :not_found}} =
             Schedules.update(
               Principal.operator(),
               other["id"],
               schedule["id"],
               command(%{"expected_version" => 1, "enabled" => false})
             )

    for bad <- [
          %{"expression" => "@reboot"},
          %{"expression" => "* * * * * *"},
          %{"expression" => "99 * * * *"},
          %{"timezone" => "Mars/Olympus"},
          %{"event_type" => "task.accepted"},
          %{"payload" => %{"credential" => "must never be stored"}},
          %{"start_at" => "not-a-timestamp"}
        ] do
      assert {:error, %Error{code: :invalid}} =
               Schedules.create(
                 Principal.operator(),
                 project["id"],
                 command(Map.merge(%{"expression" => "* * * * *"}, bad))
               )
    end

    assert {:ok, %{"data" => [_]}} = Schedules.list(principal, project["id"])
    assert {:error, %Error{code: :forbidden}} = Schedules.list(principal, other["id"])
  end

  test "schedule Task references stay in the Project during configuration and emission" do
    activate_fixture()
    project = project_fixture()
    other = project_fixture()

    {:ok, local} =
      Samgita.Tasks.create(Principal.operator(), project["id"], command(%{"title" => "local"}))

    {:ok, foreign} =
      Samgita.Tasks.create(Principal.operator(), other["id"], command(%{"title" => "foreign"}))

    for invalid_id <- [foreign["id"], Ecto.UUID.generate(), "not-a-uuid"] do
      assert {:error, %Error{code: :not_found}} =
               Schedules.create(
                 Principal.operator(),
                 project["id"],
                 command(%{"expression" => "* * * * *", "payload" => %{"task_id" => invalid_id}})
               )
    end

    schedule = create_schedule(project, "* * * * *", %{"payload" => %{"task_id" => local["id"]}})
    assert {:ok, _} = Schedules.tick(now: ~U[2026-10-22 00:01:00Z])
    [occurrence] = occurrences(schedule)
    event = Repo.get!(DomainEvent, occurrence.event_id)
    assert Samgita.Events.envelope(event, Ecto.UUID.generate())["task_ref"] == local["id"]

    assert {:error, %Error{code: :not_found}} =
             Schedules.update(
               Principal.operator(),
               project["id"],
               schedule["id"],
               command(%{"expected_version" => 1, "payload" => %{"task_id" => foreign["id"]}})
             )

    assert Repo.get!(Schedule, schedule["id"]).payload == %{"task_id" => local["id"]}

    # An invalid imported configuration must fail atomically rather than emit a
    # misleading Task reference. Normal APIs cannot create this state.
    Repo.update_all(from(s in Schedule, where: s.id == ^schedule["id"]),
      set: [payload: %{"task_id" => foreign["id"]}]
    )

    assert {:error, %Error{code: :not_found}} = Schedules.tick(now: ~U[2026-10-22 00:02:00Z])
    assert Enum.map(occurrences(schedule), & &1.id) == [occurrence.id]
    assert Repo.get!(Schedule, schedule["id"]).scanned_through == ~U[2026-10-22 00:01:00.000000Z]
  end

  defp create_schedule(project, expression \\ "* * * * *", attrs \\ %{}) do
    defaults = %{
      "expression" => expression,
      "start_at" => "2026-10-22T00:00:00Z",
      "payload" => %{"reason" => "periodic inspection"}
    }

    {:ok, schedule} =
      Schedules.create(Principal.operator(), project["id"], command(Map.merge(defaults, attrs)))

    schedule
  end

  defp occurrences(schedule) do
    Repo.all(
      from o in ScheduleOccurrence, where: o.schedule_id == ^schedule["id"], order_by: o.due_at
    )
  end
end

defmodule Samgita.ScheduleRaceTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.{DomainEvent, ScheduleOccurrence}
  alias Samgita.{Principal, Repo, Schedules}

  test "independent scanner transactions serialize the durable cursor and occurrence identity" do
    schedule =
      Sandbox.unboxed_run(Repo, fn ->
        activate_fixture()
        project = project_fixture()

        {:ok, schedule} =
          Schedules.create(
            Principal.operator(),
            project["id"],
            command(%{"expression" => "* * * * *", "start_at" => "2030-01-01T00:00:00Z"})
          )

        schedule
      end)

    owner = self()

    workers =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(owner, {:scheduler_ready, self(), backend})

            receive do
              :go -> Schedules.tick(now: ~U[2030-01-01 00:02:00Z])
            after
              5_000 -> flunk("scanner race barrier timed out")
            end
          end)
        end)
      end

    ready =
      for _ <- workers do
        assert_receive {:scheduler_ready, pid, backend}, 5_000
        {pid, backend}
      end

    assert length(Enum.uniq_by(ready, &elem(&1, 1))) == 2
    Enum.each(ready, fn {pid, _} -> send(pid, :go) end)
    assert Enum.all?(Enum.map(workers, &Task.await(&1, 10_000)), &match?({:ok, _}, &1))

    Sandbox.unboxed_run(Repo, fn ->
      occurrences =
        Repo.all(from o in ScheduleOccurrence, where: o.schedule_id == ^schedule["id"])

      assert length(occurrences) == 2
      assert Enum.uniq(Enum.map(occurrences, & &1.event_id)) |> length() == 2

      assert Repo.aggregate(
               from(e in DomainEvent,
                 where: e.resource_id == ^schedule["id"] and e.type == "schedule.check"
               ),
               :count
             ) == 2

      assert {:ok, _} =
               Schedules.update(
                 Principal.operator(),
                 schedule["project_id"],
                 schedule["id"],
                 command(%{"expected_version" => 1, "enabled" => false})
               )
    end)
  end
end
