defmodule SamgitaWeb.ProjectsCodexLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  alias Samgita.{CodexHosts, FakeCodexServer, Principal, Repo}
  alias Samgita.Domain.CodexHost

  @project %{
    "id" => "01a067b6-f44c-7903-a1ea-d9056d99cd00",
    "name" => "web-terminal",
    "roots" => [%{"path" => "/work/web-terminal"}],
    "metadata" => %{},
    "position" => 0,
    "createdAt" => 1_788_446_438,
    "updatedAt" => 1_788_446_438,
    "recencyAt" => nil
  }

  @thread %{
    "id" => "01a1b6e1-7bd1-7f12-b25c-32c2ca5553cb",
    "name" => "Fix terminal sessions",
    "preview" => "fix it",
    "cwd" => "/work/web-terminal",
    "updatedAt" => 1_794_119_417,
    "status" => %{"type" => "notLoaded"},
    "cliVersion" => "0.167.0",
    "createdAt" => 1_794_119_000,
    "ephemeral" => false,
    "modelProvider" => "openai",
    "projectId" => nil,
    "sessionId" => "01a1b6e1-7bd1-7f12-b25c-32c2ca5553cb",
    "source" => "vscode",
    "turns" => []
  }

  setup do
    server =
      FakeCodexServer.start(
        results: %{
          "project/list" => %{"data" => [@project], "nextCursor" => nil},
          "thread/list" => %{"data" => [@thread], "nextCursor" => nil},
          "remoteControl/status/read" => %{
            "installationId" => "install-1",
            "serverName" => "mbp",
            "status" => "disabled"
          }
        }
      )

    previous = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(previous, :enabled, true))

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      Application.put_env(:samgita, :codex_hosts, previous)
      FakeCodexServer.stop(server)
    end)

    agent =
      agent_fixture(%{
        "name" => "Laptop",
        "runtime_driver" => "codex",
        "runtime_version" => "0.167.0"
      })

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{"agent_id" => agent["id"], "transport" => "websocket", "url" => server.url})
      )

    {:ok, _} =
      CodexHosts.enable(
        Principal.operator(),
        host["id"],
        command(%{"expected_version" => host["version"]})
      )

    await(fn -> Repo.get!(CodexHost, host["id"]).generation == 1 end)
    %{host: host}
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

  test "Projects shows hosts, their Codex projects and each project's sessions", %{
    conn: conn,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/projects")
    assert has_element?(view, "#codex-host-#{host["id"]}", "Laptop")
    assert has_element?(view, "#codex-host-#{host["id"]}", "mbp")
    await(fn -> has_element?(view, "#codex-project-#{@project["id"]}", "web-terminal") end)
    refute has_element?(view, "#codex-session-#{@thread["id"]}")

    view |> element("#codex-project-#{@project["id"]} button") |> render_click()
    assert_receive {:fake_codex, :params, "thread/list", params}, 3_000
    assert params["cwd"] == ["/work/web-terminal"]
    assert params["sortKey"] == "updated_at"

    await(fn ->
      has_element?(view, "#codex-session-#{@thread["id"]}", "Fix terminal sessions")
    end)

    assert has_element?(view, "#codex-session-#{@thread["id"]}", "idle")

    view |> element("#codex-project-#{@project["id"]} button") |> render_click()
    refute has_element?(view, "#codex-session-#{@thread["id"]}")
  end
end
