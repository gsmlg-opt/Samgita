defmodule Samgita.SecurityRaceTest do
  use ExUnit.Case, async: false
  import Samgita.DomainFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{Agents, Attempts, Error, Platform, Principal, Repo, Tasks}

  test "credential revocation serializes with a claim and later writes are denied" do
    {project, agent, principal, session, task, current} =
      Sandbox.unboxed_run(Repo, fn ->
        activate_fixture()
        {p, a, actor, session, task} = work()
        {:ok, current} = Agents.get(Principal.operator(), a["id"])
        {p, a, actor, session, task, current}
      end)

    results =
      race([
        fn ->
          Attempts.claim(
            principal,
            project["id"],
            task["id"],
            command(%{"expected_version" => task["version"], "session_id" => session["id"]})
          )
        end,
        fn ->
          Agents.revoke_credential(
            Principal.operator(),
            agent["id"],
            command(%{
              "expected_version" => current["version"],
              "credential_id" => principal.credential_id
            })
          )
        end
      ])

    assert {:ok, _} = Enum.at(results, 1)

    Sandbox.unboxed_run(Repo, fn ->
      assert {:error, %Error{code: :unauthorized}} =
               Tasks.get(principal, project["id"], task["id"])

      case hd(results) do
        {:ok, attempt} ->
          assert {:error, %Error{code: :unauthorized}} =
                   Attempts.proof(principal, project["id"], attempt["id"])

          assert {:ok, _} =
                   Attempts.resolve(
                     Principal.operator(),
                     project["id"],
                     attempt["id"],
                     command(%{
                       "expected_version" => attempt["version"],
                       "effects_resolved" => true,
                       "evidence_ref" => "isolated-no-execution-started"
                     })
                   )

        {:error, %Error{code: :unauthorized}} ->
          :ok
      end
    end)
  end

  test "authority closure and start cannot leave unfenced active ownership" do
    {project, principal, task, attempt, proof, authority} =
      Sandbox.unboxed_run(Repo, fn ->
        authority = activate_fixture()
        {p, _, actor, session, t} = work()

        {:ok, a} =
          Attempts.claim(
            actor,
            p["id"],
            t["id"],
            command(%{"expected_version" => t["version"], "session_id" => session["id"]})
          )

        {:ok, proof} = Attempts.proof(actor, p["id"], a["id"])
        {p, actor, t, a, proof["proof"], authority}
      end)

    results =
      race([
        fn ->
          Attempts.start(
            principal,
            project["id"],
            attempt["id"],
            command(%{"expected_version" => attempt["version"], "proof" => proof})
          )
        end,
        fn ->
          Platform.close(
            Principal.operator(),
            command(%{
              "expected_version" => authority["version"],
              "reason" => "isolated-authority-race"
            })
          )
        end
      ])

    assert {:ok, _} = Enum.at(results, 1)

    assert match?({:ok, _}, hd(results)) ||
             match?({:error, %Error{code: :execution_closed}}, hd(results))

    Sandbox.unboxed_run(Repo, fn ->
      a = Repo.get!(Samgita.Domain.TaskAttempt, attempt["id"])
      assert a.state == "expired"
      refute a.effects_resolved
      {:ok, held} = Tasks.get(Principal.operator(), project["id"], task["id"])
      assert held["execution_hold"]

      assert {:ok, _} =
               Attempts.resolve(
                 Principal.operator(),
                 project["id"],
                 a.id,
                 command(%{
                   "expected_version" => a.version,
                   "effects_resolved" => true,
                   "evidence_ref" => "isolated-runtime-absent"
                 })
               )

      activate_fixture()
    end)
  end

  defp work do
    p = project_fixture()
    a = agent_fixture()
    member_fixture(p, a)
    {actor, _, _} = connection_fixture(a)

    {:ok, session} =
      Agents.open_session(actor, p["id"], command(%{"external_id" => Ecto.UUID.generate()}))

    {:ok, task} = Tasks.create(actor, p["id"], command(%{"title" => "concurrent authorization"}))
    {p, a, actor, session, task}
  end

  defp race(commands) do
    parent = self()

    jobs =
      Enum.map(commands, fn command ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend]]} = Ecto.Adapters.SQL.query!(Repo, "SELECT pg_backend_pid()", [])
            send(parent, {:ready, self(), backend})

            receive do
              :go -> command.()
            after
              5_000 -> flunk("concurrency barrier timed out")
            end
          end)
        end)
      end)

    backends =
      Enum.map(jobs, fn job ->
        receive do
          {:ready, pid, backend} when pid == job.pid -> backend
        after
          5_000 -> flunk("database checkout timed out")
        end
      end)

    assert length(Enum.uniq(backends)) == length(commands)
    Enum.each(jobs, &send(&1.pid, :go))
    Enum.map(jobs, &Task.await(&1, 10_000))
  end
end
