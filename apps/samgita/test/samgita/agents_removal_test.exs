defmodule Samgita.AgentsRemovalTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, CodexHosts, FakeCodexServer, Management, Principal, Tasks}
  alias Samgita.CodexHosts.Runtime
  alias Samgita.Domain.{Agent, CodexHost, CommandReceipt, DomainEvent, ProjectAgent, TaskAttempt}

  test "removal hides an Agent from current lists and records one replayable audit event" do
    agent = agent_fixture(%{"name" => "Retired machine"})
    keep = agent_fixture(%{"name" => "Keep this machine"})
    attrs = command(%{"expected_version" => agent["version"]})

    assert {:ok, removed} = Agents.remove(Principal.operator(), agent["id"], attrs)
    assert removed["removed_at"]
    assert removed["enabled"] == false
    assert removed["version"] == agent["version"] + 1
    assert {:ok, ^removed} = Agents.remove(Principal.operator(), agent["id"], attrs)
    assert {:ok, ^removed} = Agents.get(Principal.operator(), agent["id"])

    assert {:ok, %{"data" => listed}} = Agents.list(Principal.operator())
    refute Enum.any?(listed, &(&1["id"] == agent["id"]))
    assert Enum.any?(listed, &(&1["id"] == keep["id"]))
    assert {:ok, %{"data" => current, "total" => total}} = Management.agents(Principal.operator())
    refute Enum.any?(current, &(&1["id"] == agent["id"]))
    assert total == length(current)
    assert {:ok, %{"counts" => %{"agents" => ^total}}} = Management.overview(Principal.operator())

    receipt = Repo.get_by!(CommandReceipt, command_id: attrs["command_id"])
    assert [event_id] = receipt.event_ids
    assert Repo.get!(DomainEvent, event_id).type == "agent.removed"

    assert Repo.aggregate(
             from(e in DomainEvent,
               where: e.type == "agent.removed" and e.resource_id == ^agent["id"]
             ),
             :count
           ) == 1
  end

  test "removal preserves resolved Attempts, Tasks, membership and historical detail" do
    agent = agent_fixture()
    {project, task, attempt} = attempt_fixture(agent, "succeeded", true)
    {:ok, current} = Agents.get(Principal.operator(), agent["id"])

    assert {:ok, removed} =
             Agents.remove(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => current["version"]})
             )

    assert Repo.get!(TaskAttempt, attempt.id) == attempt
    assert {:ok, retained} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert retained["assignee_agent_id"] == agent["id"]
    assert Repo.get_by!(ProjectAgent, agent_id: agent["id"], project_id: project["id"])
    assert {:ok, %{"agent" => historical}} = Management.agent(Principal.operator(), agent["id"])
    assert historical["removed_at"] == removed["removed_at"]

    assert {:ok, %{"agent_choices" => choices}} =
             Management.project(Principal.operator(), project["id"])

    refute Enum.any?(choices, &(&1["id"] == agent["id"]))
  end

  test "active or unresolved execution prevents removal without changing the Agent" do
    for {state, resolved} <- [{"leased", true}, {"running", true}, {"expired", false}] do
      agent = agent_fixture()
      {_project, _task, _attempt} = attempt_fixture(agent, state, resolved)
      {:ok, current} = Agents.get(Principal.operator(), agent["id"])

      assert {:error, %{code: :conflict, details: %{reason: "unresolved_execution"}}} =
               Agents.remove(
                 Principal.operator(),
                 agent["id"],
                 command(%{"expected_version" => current["version"]})
               )

      assert {:ok, ^current} = Agents.get(Principal.operator(), agent["id"])
    end
  end

  test "stale removal leaves the registration and its host unchanged" do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "test"})

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{"agent_id" => agent["id"], "transport" => "local"})
      )

    assert {:error, %{code: :stale_version}} =
             Agents.remove(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => 99})
             )

    assert Repo.get!(Agent, agent["id"]).enabled
    assert Repo.get!(CodexHost, host["id"]).version == host["version"]
  end

  test "a removed registration cannot be edited back into the current catalog" do
    agent = agent_fixture()

    {:ok, removed} =
      Agents.remove(
        Principal.operator(),
        agent["id"],
        command(%{"expected_version" => agent["version"]})
      )

    assert {:error, %{code: :invalid_transition}} =
             Agents.update(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => removed["version"], "enabled" => true})
             )
  end

  test "removal closes its live Codex connection and excludes the host from discovery" do
    previous = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(previous, :enabled, true))
    server = FakeCodexServer.start()

    on_exit(fn ->
      Application.put_env(:samgita, :codex_hosts, previous)
      FakeCodexServer.stop(server)
    end)

    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "test"})

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{
          "agent_id" => agent["id"],
          "transport" => "websocket",
          "url" => server.url
        })
      )

    Phoenix.PubSub.subscribe(Samgita.PubSub, Runtime.topic())

    {:ok, _} =
      CodexHosts.enable(
        Principal.operator(),
        host["id"],
        command(%{"expected_version" => host["version"]})
      )

    host_id = host["id"]

    on_exit(fn ->
      if pid = Runtime.whereis(host_id),
        do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)
    end)

    assert_receive {:codex_host_status, ^host_id, %{"state" => "connected"}}, 3_000

    assert {:ok, _} =
             Agents.remove(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => agent["version"]})
             )

    assert Runtime.status(host_id) == %{"state" => "stopped"}
    assert Runtime.whereis(host_id) == nil
    refute Repo.get!(CodexHost, host_id).enabled
    refute host_id in CodexHosts.enabled_ids()
    assert {:ok, hosts} = CodexHosts.list(Principal.operator())
    refute Enum.any?(hosts, &(&1["id"] == host_id))

    assert {:ok, %{"same_machine_as" => []}} =
             CodexHosts.check_new(Principal.operator(), %{
               "transport" => "websocket",
               "url" => server.url
             })

    host = Repo.get!(CodexHost, host_id)

    assert {:error, %{code: :invalid_transition}} =
             CodexHosts.enable(
               Principal.operator(),
               host_id,
               command(%{"expected_version" => host.version})
             )
  end

  defp attempt_fixture(agent, state, resolved) do
    project = project_fixture()
    member_fixture(project, agent)
    {machine, connection, _} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        machine,
        project["id"],
        command(%{"external_id" => "synthetic-removal-history"})
      )

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Retained work"}))

    task = assign_fixture(project, task, agent)
    now = DateTime.utc_now()

    attempt =
      Repo.insert!(%TaskAttempt{
        task_id: task["id"],
        project_id: project["id"],
        agent_id: agent["id"],
        session_id: session["id"],
        connection_id: connection["id"],
        connection_generation: connection["generation"],
        number: 1,
        state: state,
        fence: 1,
        execution_epoch: 1,
        proof_key_id: "synthetic-fixture",
        lease_expires_at: DateTime.add(now, 120),
        start_deadline: DateTime.add(now, 30),
        execution_deadline: DateTime.add(now, 900),
        effects_resolved: resolved
      })

    {project, task, attempt}
  end
end
