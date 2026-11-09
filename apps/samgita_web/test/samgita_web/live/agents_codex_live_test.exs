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

    agent = Repo.get_by!(Agent, name: "Codex local")
    assert agent.runtime_driver == "codex"
    host = Repo.get_by!(CodexHost, agent_id: agent.id)
    assert host.enabled
    assert host.url == server.url

    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 1 end)
    await(fn -> render(view) =~ "connected" end)

    view |> element("#agent-stop-#{host.id}") |> render_click()
    refute Repo.get!(CodexHost, host.id).enabled
    assert has_element?(view, "#agent-start-#{host.id}")

    view |> element("#agent-start-#{host.id}") |> render_click()
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 2 end)
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
end
