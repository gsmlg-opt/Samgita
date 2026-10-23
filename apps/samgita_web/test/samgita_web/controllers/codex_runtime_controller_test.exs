defmodule SamgitaWeb.CodexRuntimeControllerTest do
  use SamgitaWeb.ConnCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Principal, Tasks}

  setup %{conn: conn} do
    activate_fixture()
    project = project_fixture()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.163.0"})
    member_fixture(project, agent, ["worker"])
    {principal, connection, credential} = connection_fixture(agent)

    {:ok, session} =
      Agents.open_session(
        principal,
        project["id"],
        command(%{"external_id" => Ecto.UUID.generate()})
      )

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Native API"}))

    {:ok, attempt} =
      Attempts.claim(
        principal,
        project["id"],
        task["id"],
        command(%{"expected_version" => 1, "session_id" => session["id"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, project["id"], attempt["id"])

    {:ok, attempt} =
      Attempts.start(
        principal,
        project["id"],
        attempt["id"],
        command(%{"expected_version" => 1, "proof" => proof})
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> credential)
      |> put_req_header("x-agent-connection", connection["id"])

    attrs =
      command(%{
        "expected_version" => attempt["version"],
        "proof" => proof,
        "attempt_id" => attempt["id"],
        "runtime_ref" => Ecto.UUID.generate(),
        "instance_id" => Ecto.UUID.generate(),
        "driver_generation" => 1
      })

    prefix = "/api/agent/projects/#{project["id"]}/codex-runtimes"
    response = post(conn, prefix, attrs)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    runtime = json_response(response, 201)["data"]

    %{
      conn: conn,
      prefix: prefix <> "/" <> runtime["id"],
      proof: proof,
      runtime: runtime,
      project: project,
      agent: agent
    }
  end

  test "programmatic native operations persist and repeated dispatch cannot send again", ctx do
    wire = %{"id" => "api-native", "method" => "thread/list", "params" => %{}}

    attrs =
      command(%{
        "expected_version" => ctx.runtime["version"],
        "proof" => ctx.proof,
        "native" => wire
      })

    response = post(ctx.conn, ctx.prefix <> "/operations", attrs)
    operation = json_response(response, 201)["data"]
    refute Map.has_key?(operation, "native")
    duplicate = post(ctx.conn, ctx.prefix <> "/operations", attrs) |> json_response(201)
    assert duplicate["data"]["id"] == operation["id"]
    native = get(ctx.conn, ctx.prefix <> "/operations/#{operation["id"]}/native")
    assert get_resp_header(native, "cache-control") == ["no-store"]
    assert json_response(native, 200)["data"]["request"] == wire

    path = ctx.prefix <> "/operations/#{operation["id"]}/dispatch"
    attrs = %{"expected_version" => operation["version"], "proof" => ctx.proof}
    ticket = post(ctx.conn, path, attrs) |> json_response(200) |> Map.fetch!("data")
    assert ticket["native"] == wire
    assert is_binary(ticket["dispatch_token"])
    repeated = post(ctx.conn, path, attrs)
    assert get_resp_header(repeated, "cache-control") == ["no-store"]
    assert json_response(repeated, 409)["errors"]["code"] == "stale_version"

    settled =
      post(
        ctx.conn,
        ctx.prefix <> "/operations/#{operation["id"]}/settle",
        command(%{
          "expected_version" => ticket["version"],
          "dispatch_token" => ticket["dispatch_token"],
          "native" => %{"id" => "api-native", "result" => %{"data" => []}}
        })
      )
      |> json_response(200)

    assert settled["data"]["state"] == "completed"
  end

  test "another member gets safe metadata and cannot read native payloads or cross project scopes",
       ctx do
    other = agent_fixture()
    member_fixture(ctx.project, other, ["observer"])
    {_principal, connection, credential} = connection_fixture(other)

    conn =
      ctx.conn
      |> put_req_header("authorization", "Bearer " <> credential)
      |> put_req_header("x-agent-connection", connection["id"])

    assert get(conn, ctx.prefix) |> json_response(200)

    response =
      post(
        conn,
        ctx.prefix <> "/operations",
        command(%{
          "expected_version" => 1,
          "proof" => ctx.proof,
          "native" => %{"id" => 1, "method" => "thread/list", "params" => %{}}
        })
      )

    assert json_response(response, 403)["errors"]["code"] == "forbidden"
    assert get_resp_header(response, "cache-control") == ["no-store"]
    hidden = "/api/agent/projects/#{project_fixture()["id"]}/codex-runtimes/#{ctx.runtime["id"]}"
    assert get(conn, hidden) |> json_response(403)
  end

  test "supported request logging filters complete native subtrees and ticket secrets", ctx do
    canary = "synthetic-api-native-canary"

    attrs =
      command(%{
        "expected_version" => 1,
        "proof" => ctx.proof,
        "native" => %{
          "id" => "canary",
          "method" => "thread/start",
          "params" => %{"model" => canary}
        }
      })

    logs =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        assert post(ctx.conn, ctx.prefix <> "/operations", attrs) |> json_response(201)
      end)

    refute logs =~ canary
    refute logs =~ ctx.proof
  end
end
