defmodule SamgitaWeb.CoordinationAPITest do
  use SamgitaWeb.ConnCase, async: false
  import Samgita.DomainFixtures
  import Samgita.CoordinationFixtures
  alias Samgita.Domain.EventDelivery, as: Delivery
  alias Samgita.{EventDelivery, Repo}

  setup do
    previous = Application.get_env(:samgita, :api_keys)
    Application.put_env(:samgita, :api_keys, ["coordination-operator"])
    on_exit(fn -> Application.put_env(:samgita, :api_keys, previous) end)
    :ok
  end

  test "operator event/external/schedule APIs preserve credentials and validate source facts", %{
    conn: conn
  } do
    {p, _, _} = routing_fixture()
    path = "/api/projects/#{p["id"]}"
    assert get(conn, path <> "/events") |> json_response(401)
    conn = operator(conn)
    attrs = command(%{"payload" => %{"reason" => "manual request"}})
    response = post(conn, path <> "/events/trigger", attrs) |> json_response(201)
    assert response["data"]["type"] == "manual.triggered"

    external =
      command(%{
        "source" => "trusted-operator-ingress",
        "external_id" => "upstream-1",
        "payload" => %{"subject" => "external fact"}
      })

    first = post(conn, path <> "/events/external", external) |> json_response(201)

    second =
      post(
        conn,
        path <> "/events/external",
        Map.put(external, "command_id", Ecto.UUID.generate())
      )
      |> json_response(201)

    assert first["data"]["id"] == second["data"]["id"]

    assert post(conn, path <> "/events/trigger", command(%{"payload" => %{"labels" => [<<0>>]}}))
           |> json_response(400)

    assert post(
             conn,
             path <> "/events/trigger",
             command(%{"payload" => %{"credential" => "never-store"}})
           )
           |> json_response(400)

    schedule =
      post(
        conn,
        path <> "/schedules",
        command(%{"expression" => "*/5 * * * *", "payload" => %{"check" => "project status"}})
      )
      |> json_response(201)

    assert schedule["data"]["timezone"] == "Etc/UTC"
    assert schedule["data"]["event_type"] == "schedule.check"
    deliveries = get(conn, path <> "/deliveries") |> json_response(200)
    refute inspect(deliveries) =~ "credential_ref"
    refute inspect(deliveries) =~ "lease_id"
    assert get(conn, path <> "/event-routing") |> json_response(200)
  end

  test "machine event operations require current identity, role, ownership and correct Project",
       %{conn: conn} do
    {p, a, _, _, d} = delivery_fixture()
    {actor, connection, token} = connection_fixture(a)

    machine =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("x-agent-connection", connection["id"])

    path = "/api/agent/projects/#{p["id"]}"
    assert get(conn, path <> "/events") |> json_response(401)
    assert get(machine, path <> "/events") |> json_response(200)
    {:ok, claim} = EventDelivery.claim(d.id)
    current = Repo.get!(Delivery, d.id)

    attrs =
      command(%{
        "expected_version" => current.version,
        "operation_id" => current.operation_id,
        "fence" => claim.token.fence,
        "decision_id" => Ecto.UUID.generate(),
        "processing_status" => "completed",
        "result" => %{"summary" => "no task acceptance"}
      })

    reported = post(machine, path <> "/deliveries/#{d.id}/report", attrs) |> json_response(200)
    assert reported["data"]["state"] == "completed"
    refute Map.has_key?(reported["data"], "lease_id")
    assert {:ok, _} = EventDelivery.get(actor, p["id"], d.id)
    other = project_fixture()
    assert get(machine, "/api/agent/projects/#{other["id"]}/events") |> json_response(403)

    assert post(
             machine,
             path <> "/deliveries/#{d.id}/report",
             Map.put(attrs, "command_id", Ecto.UUID.generate())
           )
           |> json_response(409)

    weak = agent_fixture()
    member_fixture(p, weak, ["observer"])
    {_, weak_connection, weak_token} = connection_fixture(weak)

    weak_conn =
      conn
      |> put_req_header("authorization", "Bearer " <> weak_token)
      |> put_req_header("x-agent-connection", weak_connection["id"])

    assert post(weak_conn, path <> "/events/trigger", command()) |> json_response(403)
  end

  defp operator(conn), do: put_req_header(conn, "x-api-key", "coordination-operator")
end
