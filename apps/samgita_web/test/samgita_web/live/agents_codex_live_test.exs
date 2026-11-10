defmodule SamgitaWeb.AgentsCodexLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Samgita.{FakeCodexServer, Repo}
  alias Samgita.Domain.{Agent, CodexHost}

  setup do
    identity = %{"installationId" => "mac-install", "serverName" => "mbp", "status" => "disabled"}

    # Stands in for the Codex daemon's control socket on this computer, which
    # the daemon publishes as a symlink to its runtime directory.
    id = System.unique_integer([:positive])
    target = Path.join(System.tmp_dir!(), "sgc-#{id}.sock")
    socket = Path.join(System.tmp_dir!(), "sgc-#{id}.link")

    server =
      FakeCodexServer.start(unix: target, results: %{"remoteControl/status/read" => identity})

    File.ln_s!(target, socket)

    previous = Application.get_env(:samgita, :codex_hosts)

    Application.put_env(
      :samgita,
      :codex_hosts,
      previous |> Keyword.put(:enabled, true) |> Keyword.put(:local_socket, socket)
    )

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      Application.put_env(:samgita, :codex_hosts, previous)
      FakeCodexServer.stop(server)
      File.rm(socket)
      File.rm(target)
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

  defp add(view, attrs) do
    view |> form("#agent-add", agent: Map.take(attrs, ["kind", "location"])) |> render_change()
    view |> form("#agent-add", agent: attrs) |> render_submit()
  end

  test "Codex on this computer connects to its daemon socket; the list stops and starts it", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/agents")
    refute has_element?(view, "#agent-add input[name='agent[address]']")
    add(view, %{"kind" => "codex", "location" => "local", "name" => "Codex local"})

    assert_redirect(view, ~p"/agents")
    {:ok, view, _} = live(conn, ~p"/agents")
    agent = Repo.get_by!(Agent, name: "Codex local")
    assert agent.runtime_driver == "codex"
    host = Repo.get_by!(CodexHost, agent_id: agent.id)
    assert host.enabled
    assert {host.transport, host.url, host.ssh_host} == {"local", nil, nil}

    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 1 end)
    await(fn -> has_element?(view, "#agents-list .agent-state", "connected") end)
    assert has_element?(view, "#agents-list", "mbp")

    view |> element("#agent-stop-#{host.id}") |> render_click()
    refute Repo.get!(CodexHost, host.id).enabled
    assert has_element?(view, "#agent-start-#{host.id}")

    view |> element("#agent-start-#{host.id}") |> render_click()
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 2 end)
  end

  test "Codex on another computer is added by SSH host with the operator's SSH config", %{
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

    add(view, %{
      "kind" => "codex",
      "location" => "ssh",
      "name" => "Raven",
      "address" => "gao@raven"
    })

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

  test "an invalid SSH host shows an error and creates nothing", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/agents")

    add(view, %{
      "kind" => "codex",
      "location" => "ssh",
      "name" => "Broken",
      "address" => "http://x"
    })

    assert has_element?(view, "#agent-error")
    refute Repo.get_by(Agent, name: "Broken")
    assert Repo.aggregate(CodexHost, :count) == 0
  end

  test "one machine is one Agent: a duplicate add warns first and the list flags it", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/agents")
    add(view, %{"kind" => "codex", "location" => "local", "name" => "Mac"})

    assert_redirect(view, ~p"/agents")
    agent = Repo.get_by!(Agent, name: "Mac")
    host = Repo.get_by!(CodexHost, agent_id: agent.id)
    await(fn -> Repo.get!(CodexHost, host.id).installation_id == "mac-install" end)

    {:ok, view, _} = live(conn, ~p"/agents")
    add(view, %{"kind" => "codex", "location" => "local", "name" => "Mac again"})

    assert has_element?(view, "#agent-warning", "already added as Mac")
    refute Repo.get_by(Agent, name: "Mac again")

    view |> form("#agent-add") |> render_submit()
    assert_redirect(view, ~p"/agents")
    assert Repo.get_by(Agent, name: "Mac again")

    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, ".agent-duplicate", "Same machine as Mac again")
    assert has_element?(view, ".agent-duplicate", "Same machine as Mac")
  end
end
