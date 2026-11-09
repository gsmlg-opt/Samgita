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
          "project/create" => %{"project" => @created},
          "fs/readDirectory" => %{
            "entries" => [
              %{"fileName" => ".cache", "isDirectory" => true, "isFile" => false},
              %{"fileName" => "samgita", "isDirectory" => true, "isFile" => false},
              %{"fileName" => "notes.txt", "isDirectory" => false, "isFile" => true},
              %{"fileName" => "Apps", "isDirectory" => true, "isFile" => false}
            ]
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

    # The picker starts at the user's home (parent of the reported Codex home).
    view |> element("#project-add-open") |> render_click()
    assert_receive {:fake_codex, :params, "fs/readDirectory", %{"path" => "/fake"}}, 3_000
    await(fn -> has_element?(view, "#folder-list", "samgita") end)
    html = view |> element("#folder-list") |> render()
    refute html =~ "notes.txt"
    assert :binary.match(html, "Apps") < :binary.match(html, "samgita")
    assert :binary.match(html, "samgita") < :binary.match(html, ".cache")

    view |> element("#folder-list button", "samgita") |> render_click()
    assert_receive {:fake_codex, :params, "fs/readDirectory", %{"path" => "/fake/samgita"}}, 3_000
    view |> element("#folder-use") |> render_click()

    assert_receive {:fake_codex, :params, "project/create", params}, 3_000
    assert %{"name" => "samgita", "roots" => [%{"path" => "/fake/samgita"}]} = params
    assert is_binary(params["idempotencyKey"])

    assert Repo.exists?(
             from e in DomainEvent,
               where: e.type == "codex_host.project_created" and e.resource_id == ^host["id"]
           )
  end

  test "a relative folder path is refused before contacting Codex", %{
    conn: conn,
    agent: agent
  } do
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}?section=projects")
    view |> element("#folder-path-form") |> render_submit(%{"path" => "relative/path"})
    assert has_element?(view, "#folder-error")
    refute_received {:fake_codex, :params, "fs/readDirectory", _}
  end

  test "the Agent page shows one settings section at a time", %{conn: conn, agent: agent} do
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")
    assert has_element?(view, "#agent-section-overview[aria-current=page]")
    refute has_element?(view, "#section-overview[hidden]")
    assert has_element?(view, "#section-projects[hidden]")
    assert has_element?(view, "#section-connection[hidden]")
    refute has_element?(view, "#section-credentials")

    view |> element("#agent-section-projects") |> render_click()
    assert_patch(view, ~p"/agents/#{agent["id"]}?section=projects")
    refute has_element?(view, "#section-projects[hidden]")
    assert has_element?(view, "#section-overview[hidden]")

    {:ok, direct, _} = live(conn, ~p"/agents/#{agent["id"]}?section=connection")
    refute has_element?(direct, "#section-connection[hidden]")
    assert has_element?(direct, "#codex-host-form")
  end
end
