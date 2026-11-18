defmodule SamgitaWeb.AgentsIngressLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures

  test "inbound connection requests have an empty state", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/agents")
    assert has_element?(view, "#agent-connection-requests")
    assert has_element?(view, "#agent-requests-empty")
  end

  test "inbound mode removes the outbound address fields", %{conn: conn} do
    agent = agent_fixture(%{"endpoint_metadata" => %{"transport" => "inbound_websocket"}})
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    assert has_element?(
             view,
             "select[name='agent[endpoint_transport]'] option[value='inbound_websocket'][selected]"
           )

    refute has_element?(view, "input[name='agent[endpoint_url]']")
    refute has_element?(view, "input[name='agent[credential_ref]']")
  end
end
