defmodule SamgitaWeb.AgentsRemovalLiveTest do
  use SamgitaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures

  alias Samgita.{Agents, CodexHosts, Principal, Repo}
  alias Samgita.Domain.{Agent, CodexHost}

  test "the list confirms removal and keeps the Agent's historical detail", %{conn: conn} do
    agent = agent_fixture(%{"name" => "Retiring Agent"})
    {:ok, view, _} = live(conn, ~p"/agents")

    assert has_element?(view, "#agent-remove-#{agent["id"]}[command='show-modal']", "Remove")

    assert has_element?(
             view,
             "#confirm-dialog-agent-remove-#{agent["id"]}",
             "Task and Attempt history is kept"
           )

    view |> element("#agent-remove-#{agent["id"]}-confirm") |> render_click()

    refute has_element?(view, "#agents-list a[href='/agents/#{agent["id"]}']")
    assert Repo.get!(Agent, agent["id"]).removed_at

    {:ok, history, _} = live(conn, ~p"/agents/#{agent["id"]}?section=general")
    assert has_element?(history, "#agent-removed", "Removed")
    assert has_element?(history, "h1", "Retiring Agent")
    refute has_element?(history, "#agent-update")
    refute has_element?(history, "#agent-remove")
  end

  test "removing a Codex Agent from General disables its host and returns to the list", %{
    conn: conn
  } do
    agent =
      agent_fixture(%{
        "name" => "Old Codex host",
        "runtime_driver" => "codex",
        "runtime_version" => SamgitaProtocolCodex.source()["version"]
      })

    assert {:ok, host} =
             CodexHosts.configure(
               Principal.operator(),
               command(%{"agent_id" => agent["id"], "transport" => "local"})
             )

    assert {:ok, _} =
             CodexHosts.enable(
               Principal.operator(),
               host["id"],
               command(%{"expected_version" => host["version"]})
             )

    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}?section=general")
    assert has_element?(view, "#agent-remove[command='show-modal']", "Remove Agent")
    view |> element("#agent-remove-confirm") |> render_click()
    assert_redirect(view, ~p"/agents")
    refute Repo.get!(CodexHost, host["id"]).enabled

    {:ok, history, _} = live(conn, ~p"/agents/#{agent["id"]}")
    assert has_element?(history, "#agent-removed")
    refute has_element?(history, "#codex-host-enable")
    refute has_element?(history, "#codex-host-disable")
    refute has_element?(history, "#codex-host-reconnect")
    refute has_element?(history, "#codex-host-form")
  end

  test "a stale removal shows the conflict and retains the Agent", %{conn: conn} do
    agent = agent_fixture()
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}?section=general")

    assert {:ok, _} =
             Agents.update(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => agent["version"], "name" => "New name"})
             )

    view |> element("#agent-remove-confirm") |> render_click()
    assert has_element?(view, "#agent-error", "This record changed")
    refute Repo.get!(Agent, agent["id"]).removed_at
  end

  test "removing the final row on the last page returns to a populated page", %{conn: conn} do
    for i <- 1..26, do: agent_fixture(%{"name" => "Paged Agent #{i}"})
    {:ok, view, _} = live(conn, ~p"/agents?offset=25")

    view |> element("#agents-list button[id$='-confirm']") |> render_click()

    assert_patch(view, ~p"/agents?offset=0")
    assert has_element?(view, "#agents-list tbody tr")
    assert render(view) =~ "25 registered"
  end

  test "a connection status refresh shows an Agent removed from another page", %{conn: conn} do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "test"})

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{"agent_id" => agent["id"], "transport" => "local"})
      )

    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}?section=connection")

    {:ok, _} =
      Agents.remove(
        Principal.operator(),
        agent["id"],
        command(%{"expected_version" => agent["version"]})
      )

    send(view.pid, {:codex_host_status, host["id"], %{"state" => "stopped"}})

    assert has_element?(view, "#agent-removed")
    refute has_element?(view, "#codex-host-form")
    refute has_element?(view, "#agent-remove")
    refute has_element?(view, "#agent-sections a", "Connection")
    assert has_element?(view, "#section-overview:not([hidden])")
  end
end
