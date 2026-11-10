defmodule SamgitaWeb.AgentsCodexLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Samgita.{FakeCodexServer, Repo}
  alias Samgita.Domain.{Agent, CodexHost}

  setup do
    server = FakeCodexServer.start()
    previous = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(previous, :enabled, true))

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      Application.put_env(:samgita, :codex_hosts, previous)
      FakeCodexServer.stop(server)
    end)

    %{server: server}
  end

  defp await(fun, attempts \\ 60) do
    if fun.() do
      :ok
    else
      if attempts == 0, do: flunk("condition not reached")
      Process.sleep(50)
      await(fun, attempts - 1)
    end
  end

  test "adding a Codex Agent by address connects it; the list stops and starts it", %{
    conn: conn,
    server: server
  } do
    {:ok, view, _} = live(conn, ~p"/agents")

    view
    |> form("#agent-add",
      agent: %{"kind" => "codex", "name" => "Codex local", "address" => server.url}
    )
    |> render_submit()

    assert_redirect(view, ~p"/agents")
    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, "#agent-add-modal #agent-add")
    agent = Repo.get_by!(Agent, name: "Codex local")
    assert agent.runtime_driver == "codex"
    host = Repo.get_by!(CodexHost, agent_id: agent.id)
    assert host.enabled
    assert host.url == server.url

    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 1 end)
    await(fn -> has_element?(view, "#agents-list .agent-state", "connected") end)

    view |> element("#agent-stop-#{host.id}") |> render_click()
    refute Repo.get!(CodexHost, host.id).enabled
    assert has_element?(view, "#agent-start-#{host.id}")

    view |> element("#agent-start-#{host.id}") |> render_click()
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 2 end)
  end

  test "an SSH host address uses the operator's SSH config and starts the daemon", %{
    conn: conn
  } do
    # Stands in for an unreachable machine: the probe and connection fail fast.
    config = Application.get_env(:samgita, :codex_hosts)

    Application.put_env(
      :samgita,
      :codex_hosts,
      Keyword.put(config, :ssh_executable, System.find_executable("false"))
    )

    {:ok, view, _} = live(conn, ~p"/agents")

    view
    |> form("#agent-add",
      agent: %{"kind" => "codex", "name" => "Raven", "address" => "gao@raven"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/agents")
    agent = Repo.get_by!(Agent, name: "Raven")
    host = Repo.get_by!(CodexHost, agent_id: agent.id)

    assert {host.transport, host.ssh_host, host.ssh_user, host.ssh_port} ==
             {"ssh", "raven", "gao", nil}

    assert host.use_ssh_config and host.ensure_daemon and host.enabled
    assert host.url == nil and host.known_hosts == nil

    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, "#agents-list", "raven")
  end

  test "an invalid Codex address shows an error and creates nothing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/agents")

    view
    |> form("#agent-add",
      agent: %{"kind" => "codex", "name" => "Broken", "address" => "http://x"}
    )
    |> render_submit()

    assert has_element?(view, "#agent-error")
    refute Repo.get_by(Agent, name: "Broken")
    assert Repo.aggregate(CodexHost, :count) == 0
  end

  test "one machine is one Agent: a duplicate add warns first and the list flags it", %{
    conn: conn
  } do
    identity = %{
      "installationId" => "same-install",
      "serverName" => "mbp",
      "status" => "disabled"
    }

    first = FakeCodexServer.start(results: %{"remoteControl/status/read" => identity})
    second = FakeCodexServer.start(results: %{"remoteControl/status/read" => identity})

    on_exit(fn ->
      FakeCodexServer.stop(first)
      FakeCodexServer.stop(second)
    end)

    {:ok, view, _} = live(conn, ~p"/agents")

    view
    |> form("#agent-add", agent: %{"kind" => "codex", "name" => "Mac", "address" => first.url})
    |> render_submit()

    assert_redirect(view, ~p"/agents")
    host = Repo.get_by!(CodexHost, url: first.url)
    await(fn -> Repo.get!(CodexHost, host.id).installation_id == "same-install" end)

    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, "#agents-list", "mbp")
    refute render(view) =~ first.url

    view
    |> form("#agent-add",
      agent: %{"kind" => "codex", "name" => "Mac again", "address" => second.url}
    )
    |> render_submit()

    assert has_element?(view, "#agent-warning", "already added as Mac")
    refute Repo.get_by(Agent, name: "Mac again")

    view |> form("#agent-add") |> render_submit()
    assert_redirect(view, ~p"/agents")
    assert Repo.get_by(Agent, name: "Mac again")
    copy = Repo.get_by!(CodexHost, url: second.url)
    await(fn -> Repo.get!(CodexHost, copy.id).installation_id == "same-install" end)

    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, ".agent-duplicate", "Same machine as Mac again")
    assert has_element?(view, ".agent-duplicate", "Same machine as Mac")
  end
end
