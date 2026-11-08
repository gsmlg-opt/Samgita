defmodule SamgitaWeb.CodexHostLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  alias Samgita.{FakeCodexServer, Repo}
  alias Samgita.CodexHosts.Runtime
  alias Samgita.Domain.CodexHost

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

  test "the Codex host card appears only for Codex runtime Agents", %{conn: conn} do
    plain = agent_fixture(%{"name" => "Plain"})
    {:ok, view, _} = live(conn, ~p"/agents/#{plain["id"]}")
    refute has_element?(view, "#codex-host")

    codex = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    {:ok, view, _} = live(conn, ~p"/agents/#{codex["id"]}")
    assert has_element?(view, "#codex-host-form")
    refute has_element?(view, "#codex-host-enable")
  end

  test "operator configures, enables and watches a Codex host connect", %{
    conn: conn,
    server: server
  } do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    view
    |> form("#codex-host-form", codex_host: %{"url" => server.url, "token_ref" => ""})
    |> render_submit()

    host = Repo.get_by!(CodexHost, agent_id: agent["id"])
    assert host.url == server.url
    refute host.enabled
    assert has_element?(view, "#codex-host-state", "stopped")

    view |> element("#codex-host-enable") |> render_click()
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    await(fn -> render(view) =~ "connected" end)
    assert has_element?(view, "#codex-host-version", "0.167.0")
    assert has_element?(view, "#codex-host-reconnect")

    view |> element("#codex-host-disable") |> render_click()
    await(fn -> Runtime.whereis(host.id) == nil end)
    assert has_element?(view, "#codex-host-state", "stopped")
  end

  test "operator switches to SSH and saves daemon settings", %{conn: conn} do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")
    refute has_element?(view, "#codex-host-form textarea")

    view |> form("#codex-host-form", codex_host: %{"transport" => "ssh"}) |> render_change()
    assert has_element?(view, "#codex-host-form textarea")

    known_hosts =
      "codex.internal ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

    view
    |> form("#codex-host-form",
      codex_host: %{
        "transport" => "ssh",
        "ssh_host" => "codex.internal",
        "ssh_port" => "2222",
        "ssh_user" => "codex",
        "ssh_key_ref" => "codex/ssh-v1",
        "known_hosts" => known_hosts,
        "ensure_daemon" => "true"
      }
    )
    |> render_submit()

    host = Repo.get_by!(CodexHost, agent_id: agent["id"])
    assert host.transport == "ssh"
    assert host.ssh_host == "codex.internal"
    assert host.ssh_port == 2222
    assert host.ssh_key_ref == "codex/ssh-v1"
    assert host.ensure_daemon
    assert host.url == nil
  end

  test "invalid endpoints are reported without saving", %{conn: conn} do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    html =
      view
      |> form("#codex-host-form", codex_host: %{"url" => "http://codex.example/app-server"})
      |> render_submit()

    assert html =~ "Check these fields"
    refute Repo.get_by(CodexHost, agent_id: agent["id"])
  end

  test "operator REST API configures, enables and reports a host", %{conn: conn, server: server} do
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    conn = put_req_header(conn, "accept", "application/json")

    created =
      conn
      |> post(~p"/api/codex-hosts", %{
        "command_id" => Ecto.UUID.generate(),
        "agent_id" => agent["id"],
        "transport" => "websocket",
        "url" => server.url
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert created["enabled"] == false

    enabled =
      conn
      |> post(~p"/api/codex-hosts/#{created["id"]}/enable", %{
        "command_id" => Ecto.UUID.generate(),
        "expected_version" => created["version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert enabled["enabled"] == true
    assert_receive {:fake_codex, :request, "initialize"}, 3_000

    await(fn ->
      get(conn, ~p"/api/codex-hosts/#{created["id"]}")
      |> json_response(200)
      |> get_in(["data", "status", "state"]) == "connected"
    end)

    assert [%{"id" => id}] =
             get(conn, ~p"/api/codex-hosts") |> json_response(200) |> Map.fetch!("data")

    assert id == created["id"]

    assert conn
           |> post(~p"/api/codex-hosts/#{id}/reconnect", %{})
           |> json_response(202)
           |> get_in(["data", "id"]) == id
  end
end
