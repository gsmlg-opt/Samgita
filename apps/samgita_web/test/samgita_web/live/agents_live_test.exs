defmodule SamgitaWeb.AgentsLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  import ExUnit.CaptureLog
  import Ecto.Query
  alias Samgita.{Agents, Principal, Repo}
  alias Samgita.Domain.{Agent, AgentCredential, CommandReceipt, DomainEvent}

  test "registers a persisted neutral identity and replays the submitted command after reconnect",
       %{conn: conn} do
    baseline_count = Repo.aggregate(Agent, :count)
    {:ok, view, _} = live(conn, ~p"/agents")
    command_id = input(view, "agent[command_id]")
    name = "Neutral Agent #{Ecto.UUID.generate()}"

    params = %{
      "name" => name,
      "implementation" => "",
      "capacity" => "2",
      "enabled" => "true",
      "advertised_capabilities" => [],
      "approved_capabilities" => [],
      "protocol" => "samgita",
      "protocol_version" => "1.0",
      "endpoint_url" => "",
      "endpoint_transport" => "",
      "credential_ref" => "",
      "command_id" => command_id
    }

    view |> form("#agent-register", agent: params) |> render_submit()
    assert [agent] = Repo.all(from(a in Agent, where: a.name == ^name))
    assert_redirect(view, ~p"/agents/#{agent.id}")
    assert agent.capacity == 2
    assert agent.approved_capabilities == []

    {:ok, retry, _} = live(conn, ~p"/agents")
    render_change(retry, "change", %{"agent" => params})
    assert input(retry, "agent[command_id]") == command_id
    render_submit(retry, "register", %{"agent" => params})
    assert_redirect(retry, ~p"/agents/#{agent.id}")
    assert Repo.aggregate(Agent, :count) == baseline_count + 1

    {:ok, conflicting, _} = live(conn, ~p"/agents")
    changed = Map.put(params, "name", "Different recovered intent")
    render_change(conflicting, "change", %{"agent" => changed})
    conflicting |> form("#agent-register", agent: changed) |> render_submit()
    assert has_element?(conflicting, "#agent-error", "conflicts")
    assert Repo.aggregate(Agent, :count) == baseline_count + 1

    {:ok, detail, _} = live(conn, ~p"/agents/#{agent.id}")
    assert has_element?(detail, "h1", name)
    assert has_element?(detail, "#agent-status", "offline")
    assert has_element?(detail, "#agent-status", "Health unverified")
  end

  test "approval and enablement changes persist and identical submissions do not increment twice",
       %{conn: conn} do
    agent = agent_fixture()
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    params = %{
      "name" => "Paused Agent",
      "implementation" => "",
      "capacity" => "3",
      "enabled" => "false",
      "advertised_capabilities" => ["sessions.v1"],
      "approved_capabilities" => ["sessions.v1"],
      "protocol" => "samgita",
      "protocol_version" => "1.0",
      "endpoint_url" => "",
      "endpoint_transport" => "",
      "credential_ref" => "",
      "command_id" => input(view, "agent[command_id]"),
      "expected_version" => input(view, "agent[expected_version]")
    }

    view |> form("#agent-update", agent: params) |> render_submit()
    assert has_element?(view, "#agent-status", "disabled")
    assert {:ok, updated} = Agents.get(Principal.operator(), agent["id"])
    assert updated["approved_capabilities"] == ["sessions.v1"]
    assert updated["capacity"] == 3
    refute updated["enabled"]
    render_submit(view, "save", %{"agent" => params})
    assert {:ok, ^updated} = Agents.get(Principal.operator(), agent["id"])

    {:ok, refreshed, _} = live(conn, ~p"/agents/#{agent["id"]}")
    render_change(refreshed, "change", %{"agent" => params})
    assert input(refreshed, "agent[command_id]") == params["command_id"]
    assert input(refreshed, "agent[expected_version]") == params["expected_version"]
    render_submit(refreshed, "save", %{"agent" => params})
    assert {:ok, ^updated} = Agents.get(Principal.operator(), agent["id"])
    assert has_element?(refreshed, "h1", "Paused Agent")
    assert has_element?(refreshed, "#agent-update input[name='agent[capacity]'][value='3']")
  end

  test "endpoint configuration persists only safe descriptors and a credential reference", %{
    conn: conn
  } do
    agent = agent_fixture()
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    view
    |> form("#agent-update",
      agent: %{
        endpoint_url: "wss://agent.example/app-server",
        endpoint_transport: "websocket",
        credential_ref: "agent-machine-v1"
      }
    )
    |> render_submit()

    assert {:ok, updated} = Agents.get(Principal.operator(), agent["id"])

    assert updated["endpoint_metadata"] == %{
             "url" => "wss://agent.example/app-server",
             "transport" => "websocket"
           }

    assert has_element?(
             view,
             "input[name='agent[endpoint_url]'][value='wss://agent.example/app-server']"
           )

    assert has_element?(view, "input[name='agent[credential_ref]'][value='agent-machine-v1']")

    html =
      view
      |> form("#agent-update",
        agent: %{endpoint_url: "wss://user:must-not-echo@agent.example/app-server"}
      )
      |> render_submit()

    assert has_element?(view, "#agent-error", "endpoint metadata")
    refute html =~ "must-not-echo"
    assert {:ok, ^updated} = Agents.get(Principal.operator(), agent["id"])
  end

  test "shows named invalid fields and stale-version conflicts without overwriting a newer record",
       %{conn: conn} do
    agent = agent_fixture()
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")
    view |> form("#agent-update", agent: %{name: ""}) |> render_submit()
    assert has_element?(view, "#agent-error", "name")

    assert {:ok, changed} =
             Agents.update(
               Principal.operator(),
               agent["id"],
               command(%{"expected_version" => agent["version"], "name" => "Changed elsewhere"})
             )

    view |> form("#agent-update", agent: %{name: "Stale edit"}) |> render_submit()
    assert has_element?(view, "#agent-error", "This record changed")
    assert {:ok, ^changed} = Agents.get(Principal.operator(), agent["id"])
  end

  test "credentials are write-only, cleared even on failure, idempotent and revocable", %{
    conn: conn
  } do
    agent = agent_fixture()
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")
    raw = "operator-supplied-machine-credential-unique"

    params = %{
      "credential" => raw,
      "reference" => "test-machine-v1",
      "expires_at" => "",
      "command_id" => input(view, "credential[command_id]"),
      "expected_version" => input(view, "credential[expected_version]")
    }

    logs =
      capture_log(fn ->
        html = view |> form("#agent-credential", credential: params) |> render_submit()
        refute html =~ raw
        assert has_element?(view, "input[name='credential[credential]'][value='']")
        render_submit(view, "put_credential", %{"credential" => params})
      end)

    refute logs =~ raw
    agent_id = agent["id"]
    assert [credential] = Repo.all(from(c in AgentCredential, where: c.agent_id == ^agent_id))
    assert credential.digest == :crypto.hash(:sha256, raw)
    command_id = params["command_id"]
    assert [receipt] = Repo.all(from(r in CommandReceipt, where: r.command_id == ^command_id))
    assert [event] = Repo.all(from(e in DomainEvent, where: e.command_id == ^command_id))
    refute Jason.encode!(receipt.result) =~ raw
    refute Jason.encode!(event.data) =~ raw
    assert has_element?(view, "#credential-#{credential.id}", "test-machine-v1")
    view |> form("#revoke-#{credential.id}") |> render_submit()
    assert Repo.get!(AgentCredential, credential.id).revoked_at
    assert has_element?(view, "#credential-#{credential.id}", "Revoked")

    view |> form("#agent-credential", credential: %{credential: "too-short"}) |> render_submit()
    assert has_element?(view, "#agent-error", "credential")
    assert has_element?(view, "input[name='credential[credential]'][value='']")
  end

  test "memberships and recorded sessions remain visible with honest connection evidence", %{
    conn: conn
  } do
    project = project_fixture(%{"name" => "Agent Project"})
    agent = agent_fixture()
    member_fixture(project, agent)
    {principal, _connection, _raw} = connection_fixture(agent)

    assert {:ok, _} =
             Agents.open_session(
               principal,
               project["id"],
               command(%{"external_id" => "external-session"})
             )

    {:ok, view, html} = live(conn, ~p"/agents/#{agent["id"]}")
    assert has_element?(view, "a[href='/projects/#{project["id"]}']", "Agent Project")
    assert html =~ "external-session"
    assert has_element?(view, "#agent-status", "connected")
    assert has_element?(view, "#agent-status", "Health unverified")
    refute html =~ "Healthy"
  end

  test "Agent list paginates persisted registrations and unknown detail is a visible error", %{
    conn: conn
  } do
    for i <- 1..26, do: agent_fixture(%{"name" => "Agent #{i}"})
    total = Repo.aggregate(Agent, :count)
    {:ok, view, _} = live(conn, ~p"/agents")

    assert view
           |> element("#agents-list")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("tbody tr")
           |> Enum.count() == 25

    view |> element("a", "Next") |> render_click()
    assert_patch(view, ~p"/agents?offset=25")

    assert view
           |> element("#agents-list")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("tbody tr")
           |> Enum.count() == min(total - 25, 25)

    last_offset = div(total - 1, 25) * 25
    {:ok, last, _} = live(conn, ~p"/agents?offset=#{last_offset}")

    assert last
           |> element("#agents-list")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("tbody tr")
           |> Enum.count() == total - last_offset

    refute has_element?(last, "a", "Next")

    {:ok, empty, _} = live(conn, ~p"/agents?offset=#{total}")
    assert has_element?(empty, "#agents-empty", "No Agents on this page")
    refute has_element?(empty, "#agents-list")

    {:ok, missing, _} = live(conn, ~p"/agents/#{Ecto.UUID.generate()}")
    assert has_element?(missing, "[role='alert']", "Agent not found")
  end

  defp input(view, name) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[name='#{name}']")
    |> LazyHTML.attribute("value")
    |> List.first()
  end
end
