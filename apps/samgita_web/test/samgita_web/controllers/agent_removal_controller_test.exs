defmodule SamgitaWeb.AgentRemovalControllerTest do
  use SamgitaWeb.ConnCase, async: false

  import Samgita.DomainFixtures

  alias Samgita.Repo
  alias Samgita.Domain.Agent

  setup %{conn: conn} do
    previous = Application.get_env(:samgita, :api_keys, [])
    Application.put_env(:samgita, :api_keys, ["agent-removal-functional-key"])
    on_exit(fn -> Application.put_env(:samgita, :api_keys, previous) end)

    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json")
       |> put_req_header("x-api-key", "agent-removal-functional-key")}
  end

  test "DELETE archives the Agent, replays its receipt and preserves detail reads", %{conn: conn} do
    agent = agent_fixture()
    attrs = command(%{"expected_version" => agent["version"]})
    path = ~p"/api/agents/#{agent["id"]}"

    removed = conn |> delete(path, attrs) |> json_response(200) |> Map.fetch!("data")
    assert removed["id"] == agent["id"]
    assert removed["removed_at"]
    refute removed["enabled"]
    assert Repo.get!(Agent, agent["id"])

    assert conn |> delete(path, attrs) |> json_response(200) |> Map.fetch!("data") == removed
    assert conn |> get(path) |> json_response(200) |> Map.fetch!("data") == removed

    listed = conn |> get(~p"/api/agents") |> json_response(200) |> Map.fetch!("data")
    refute Enum.any?(listed, &(&1["id"] == agent["id"]))
  end
end
