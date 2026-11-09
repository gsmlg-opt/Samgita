defmodule SamgitaWeb.CodexLiveTest do
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

  test "an operator adds a Codex by URL, watches it connect, stops and starts it", %{
    conn: conn,
    server: server
  } do
    {:ok, view, _} = live(conn, ~p"/codex")
    assert has_element?(view, "#codex-empty")

    view
    |> form("#codex-add", codex: %{"name" => "Codex local", "url" => server.url})
    |> render_submit()

    agent = Repo.get_by!(Agent, name: "Codex local")
    assert agent.runtime_driver == "codex"
    host = Repo.get_by!(CodexHost, agent_id: agent.id)
    assert host.enabled
    assert host.url == server.url

    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> render(view) =~ "connected" end)
    assert has_element?(view, "#codex-stop-#{host.id}")
    await(fn -> Repo.get!(CodexHost, host.id).generation == 1 end)

    view |> element("#codex-stop-#{host.id}") |> render_click()
    refute Repo.get!(CodexHost, host.id).enabled
    assert has_element?(view, "#codex-start-#{host.id}")

    view |> element("#codex-start-#{host.id}") |> render_click()
    assert Repo.get!(CodexHost, host.id).enabled
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> Repo.get!(CodexHost, host.id).generation == 2 end)
  end

  test "an invalid URL shows an error and creates no connection", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/codex")

    view
    |> form("#codex-add", codex: %{"name" => "Broken", "url" => "http://127.0.0.1:1"})
    |> render_submit()

    assert has_element?(view, "#codex-error")
    assert Repo.aggregate(CodexHost, :count) == 0
    refute Repo.get_by(Agent, name: "Broken")
  end
end
