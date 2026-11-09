defmodule SamgitaWeb.AgentsCodexProjectsLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  import Samgita.DomainFixtures
  alias Samgita.{CodexHosts, FakeCodexServer, Principal, Repo}
  alias Samgita.Domain.{CodexHost, DomainEvent}

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

  @created %{
    @project
    | "id" => "01a1a6d3-5ee4-74f3-9631-0e73f9335c80",
      "name" => "samgita",
      "roots" => [%{"path" => "/work/samgita"}]
  }

  setup do
    server =
      FakeCodexServer.start(
        results: %{
          "project/list" => %{"data" => [@project], "nextCursor" => nil},
          "project/create" => %{"project" => @created}
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

    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})

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

    assert_receive {:fake_codex, :params, "initialize", init}, 3_000
    assert init["capabilities"]["experimentalApi"] == true
    await(fn -> Repo.get!(CodexHost, host["id"]).generation == 1 end)
    %{agent: agent, host: host}
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

  test "a Codex Agent page lists the projects Codex reports and adds one", %{
    conn: conn,
    agent: agent,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")
    await(fn -> has_element?(view, "#codex-projects-list", "web-terminal") end)
    assert has_element?(view, "#codex-projects-list", "/work/web-terminal")

    command_id =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input[name='project[command_id]']")
      |> LazyHTML.attribute("value")
      |> List.first()

    view
    |> form("#codex-project-add", project: %{"name" => "samgita", "path" => "/work/samgita"})
    |> render_submit()

    assert_receive {:fake_codex, :params, "project/create", params}, 3_000

    assert params == %{
             "idempotencyKey" => command_id,
             "name" => "samgita",
             "roots" => [%{"path" => "/work/samgita"}]
           }

    assert Repo.exists?(
             from e in DomainEvent,
               where: e.type == "codex_host.project_created" and e.resource_id == ^host["id"]
           )
  end

  test "a relative folder is refused before contacting Codex", %{conn: conn, agent: agent} do
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    view
    |> form("#codex-project-add", project: %{"name" => "x", "path" => "relative/path"})
    |> render_submit()

    assert has_element?(view, "#codex-project-error")
    refute_received {:fake_codex, :params, "project/create", _}
  end
end
