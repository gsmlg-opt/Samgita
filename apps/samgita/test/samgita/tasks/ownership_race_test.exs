defmodule Samgita.OwnershipRaceTest do
  use ExUnit.Case, async: false
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{Agents, Attempts, Principal, Projects, Repo, Tasks}

  test "independent Project writes enforce the expected aggregate version" do
    project = Sandbox.unboxed_run(Repo, fn -> project_fixture() end)

    results =
      race(
        for name <- ["First writer", "Second writer"] do
          fn ->
            Projects.update(
              Principal.operator(),
              project["id"],
              command(%{"expected_version" => project["version"], "name" => name})
            )
          end
        end
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %{code: :stale_version}}, &1)) == 1
  end

  test "independent database transactions serialize Agent capacity across Tasks" do
    {project, principal, session, tasks} =
      Sandbox.unboxed_run(Repo, fn ->
        activate_fixture()
        project = project_fixture()
        agent = agent_fixture()
        member_fixture(project, agent, ["worker"])
        {principal, _, _} = connection_fixture(agent)

        {:ok, session} =
          Agents.open_session(
            principal,
            project["id"],
            command(%{"external_id" => Ecto.UUID.generate()})
          )

        tasks =
          for n <- 1..2 do
            {:ok, task} =
              Tasks.create(
                Principal.operator(),
                project["id"],
                command(%{"title" => "Race #{n}"})
              )

            task
          end

        {project, principal, session, tasks}
      end)

    results =
      race(
        Enum.map(tasks, fn task ->
          fn ->
            Attempts.claim(
              principal,
              project["id"],
              task["id"],
              command(%{"expected_version" => 1, "session_id" => session["id"]})
            )
          end
        end)
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %{code: :capacity_exceeded}}, &1)) == 1
    resolve_winners(project, results)
  end

  test "independent owners cannot claim the same Task twice" do
    {project, task, owners} =
      Sandbox.unboxed_run(Repo, fn ->
        activate_fixture()
        project = project_fixture()

        {:ok, task} =
          Tasks.create(
            Principal.operator(),
            project["id"],
            command(%{"title" => "One logical Task"})
          )

        owners =
          for _ <- 1..2 do
            agent = agent_fixture()
            member_fixture(project, agent, ["worker"])
            {principal, _, _} = connection_fixture(agent)

            {:ok, session} =
              Agents.open_session(
                principal,
                project["id"],
                command(%{"external_id" => Ecto.UUID.generate()})
              )

            {principal, session}
          end

        {project, task, owners}
      end)

    results =
      race(
        Enum.map(owners, fn {principal, session} ->
          fn ->
            Attempts.claim(
              principal,
              project["id"],
              task["id"],
              command(%{"expected_version" => 1, "session_id" => session["id"]})
            )
          end
        end)
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %{code: :stale_version}}, &1)) == 1
    resolve_winners(project, results)
  end

  defp race(commands) do
    caller = self()

    workers = Enum.map(commands, &start_barrier_worker(caller, &1))

    ready =
      for _ <- workers do
        assert_receive {:database_ready, pid, backend}, 5_000
        {pid, backend}
      end

    backends = Enum.map(ready, &elem(&1, 1))
    assert length(Enum.uniq(backends)) == length(workers)
    Enum.each(ready, fn {pid, _} -> send(pid, :go) end)
    Enum.map(workers, &Task.await(&1, 10_000))
  end

  defp start_barrier_worker(caller, command) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> run_after_barrier(caller, command) end) end)
  end

  defp run_after_barrier(caller, command) do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    send(caller, {:database_ready, self(), backend})

    receive do
      :go -> command.()
    after
      5_000 -> flunk("race barrier timed out")
    end
  end

  defp resolve_winners(project, results) do
    Sandbox.unboxed_run(Repo, fn ->
      for {:ok, attempt} <- results do
        assert {:ok, _} =
                 Attempts.resolve(
                   Principal.operator(),
                   project["id"],
                   attempt["id"],
                   command(%{
                     "expected_version" => attempt["version"],
                     "effects_resolved" => true,
                     "evidence_ref" => "isolated-race-no-execution"
                   })
                 )
      end
    end)
  end
end
