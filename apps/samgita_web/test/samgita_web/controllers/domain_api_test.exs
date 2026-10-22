defmodule SamgitaWeb.DomainAPITest do
  use SamgitaWeb.ConnCase, async: false

  import Samgita.DomainFixtures

  alias Samgita.{Agents, Principal, Tasks}

  setup %{conn: conn} do
    previous = Application.get_env(:samgita, :api_keys, [])
    Application.put_env(:samgita, :api_keys, ["phase3-operator-key"])
    on_exit(fn -> Application.put_env(:samgita, :api_keys, previous) end)

    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json")}
  end

  test "management routes require the configured operator key", %{conn: conn} do
    assert conn |> get("/api/projects") |> json_response(401)

    response = conn |> operator() |> get("/api/projects") |> json_response(200)
    assert is_list(response["data"])
  end

  test "neutral Project creation uses stable IDs and validates stale writes", %{conn: conn} do
    attrs = command(%{"name" => "Neutral project"})
    created = conn |> operator() |> post("/api/projects", attrs) |> json_response(201)
    project = created["data"]
    assert {:ok, _} = Ecto.UUID.cast(project["id"])
    assert project["name"] == "Neutral project"

    updated =
      conn
      |> operator()
      |> patch(
        "/api/projects/#{project["id"]}",
        command(%{"name" => "Updated", "expected_version" => project["version"]})
      )
      |> json_response(200)

    assert updated["data"]["id"] == project["id"]

    conn
    |> operator()
    |> patch(
      "/api/projects/#{project["id"]}",
      command(%{"name" => "Stale", "expected_version" => project["version"]})
    )
    |> json_response(409)
  end

  test "credential writes never return plaintext or stored credential digests", %{conn: conn} do
    agent = agent_fixture()
    raw = String.duplicate("credential-only-in-request-", 3)

    response =
      conn
      |> operator()
      |> post(
        "/api/agents/#{agent["id"]}/credentials",
        command(%{"credential" => raw, "expected_version" => agent["version"]})
      )

    assert json_response(response, 201)["data"]
    assert get_resp_header(response, "cache-control") == ["no-store"]
    refute response.resp_body =~ raw
    refute response.resp_body =~ "credential_digest"

    shown = conn |> operator() |> get("/api/agents/#{agent["id"]}") |> json_response(200)
    refute Jason.encode!(shown) =~ raw
    refute Jason.encode!(shown) =~ "credential_digest"
  end

  test "operator registers a neutral Agent and grants explicit membership", %{conn: conn} do
    project = project_fixture()

    created =
      conn
      |> operator()
      |> post(
        "/api/agents",
        command(%{
          "name" => "Ordinary Codex implementation",
          "advertised_capabilities" => ["sessions.v1"],
          "approved_capabilities" => ["sessions.v1"]
        })
      )
      |> json_response(201)

    agent = created["data"]
    assert {:ok, _} = Ecto.UUID.cast(agent["id"])

    conn
    |> operator()
    |> post(
      "/api/projects/#{project["id"]}/members",
      command(%{
        "agent_id" => agent["id"],
        "roles" => ["observer"],
        "expected_version" => project["version"]
      })
    )
    |> json_response(200)

    credential = credential_fixture(agent)
    {_principal, connection, _credential} = connection_fixture(agent, credential)

    conn
    |> machine(credential, connection)
    |> get("/api/agent/projects/#{project["id"]}/context")
    |> json_response(200)
  end

  test "machine identity is required even when operator keys are empty", %{conn: conn} do
    Application.put_env(:samgita, :api_keys, [])

    conn
    |> post("/api/agent/connect", command())
    |> json_response(401)

    conn
    |> put_req_header("authorization", "Bearer invalid-credential")
    |> post("/api/agent/connect", command())
    |> json_response(401)

    conn
    |> put_req_header("authorization", "bearer invalid-credential")
    |> post("/api/agents", command(%{"name" => "Cannot bypass operator authority"}))
    |> json_response(403)
  end

  test "machine connects from its credential and cannot post a different identity", %{conn: conn} do
    agent = agent_fixture()
    other = agent_fixture()
    credential = credential_fixture(agent)

    connected =
      conn
      |> put_req_header("authorization", "bearer " <> credential)
      |> post("/api/agent/connect", command(%{"agent_id" => other["id"]}))
      |> json_response(201)

    assert connected["data"]["agent_id"] == agent["id"]
    refute Jason.encode!(connected) =~ credential

    conn
    |> put_req_header("authorization", "Bearer " <> credential)
    |> get("/api/agent/projects")
    |> json_response(401)
  end

  test "machine reads require current connection and explicit Project membership", %{conn: conn} do
    project = project_fixture()
    hidden = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["observer"])
    {_principal, connection, credential} = connection_fixture(agent)

    response =
      conn
      |> machine(credential, connection)
      |> get("/api/agent/projects/#{project["id"]}/context")
      |> json_response(200)

    assert is_map(response["data"])
    assert Map.has_key?(response["data"], "allowed_operations")

    conn
    |> machine(credential, connection)
    |> get("/api/agent/projects/#{hidden["id"]}/context")
    |> json_response(403)
  end

  test "manager Project writes and repository associations follow advertised allowed operations",
       %{
         conn: conn
       } do
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["manager"])
    {_principal, connection, credential} = connection_fixture(agent)
    prefix = "/api/agent/projects/#{project["id"]}"

    context =
      conn
      |> machine(credential, connection)
      |> get(prefix <> "/context")
      |> json_response(200)

    assert "project.update" in context["data"]["allowed_operations"]
    assert "repository.associate" in context["data"]["allowed_operations"]

    updated =
      conn
      |> machine(credential, connection)
      |> patch(
        prefix,
        command(%{
          "expected_version" => context["data"]["project"]["version"],
          "description" => "Managed by an ordinary registered Agent"
        })
      )
      |> json_response(200)

    associated =
      conn
      |> machine(credential, connection)
      |> post(
        prefix <> "/repositories",
        command(%{
          "expected_version" => updated["data"]["version"],
          "kind" => "git",
          "display_name" => "Reference source",
          "url" => "https://github.com/gsmlg-opt/reference.git"
        })
      )
      |> json_response(201)

    assert associated["data"]["project_id"] == project["id"]

    listed =
      conn
      |> machine(credential, connection)
      |> get(prefix <> "/repositories?limit=1&offset=0")
      |> json_response(200)

    assert length(listed["data"]) == 1
    assert listed["limit"] == 1

    paused =
      conn
      |> machine(credential, connection)
      |> post(
        prefix <> "/transition",
        command(%{
          "expected_version" => associated["data"]["project_version"],
          "state" => "paused"
        })
      )
      |> json_response(200)

    assert paused["data"]["state"] == "paused"
    assert paused["data"]["id"] == project["id"]
  end

  test "Project scoped Task routes reject cross Project IDs", %{conn: conn} do
    project = project_fixture()
    other = project_fixture()

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Scoped work"}))

    conn
    |> operator()
    |> get("/api/projects/#{other["id"]}/tasks/#{task["id"]}")
    |> json_response(404)

    conn
    |> operator()
    |> patch(
      "/api/projects/#{other["id"]}/tasks/#{task["id"]}",
      command(%{"title" => "Wrong scope", "expected_version" => task["version"]})
    )
    |> json_response(404)

    assert {:ok, unchanged} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert unchanged["title"] == "Scoped work"
  end

  test "command replay preserves one Task and rejects changed semantics", %{conn: conn} do
    project = project_fixture()
    other = project_fixture()
    attrs = command(%{"title" => "One task", "project_id" => other["id"]})
    path = "/api/projects/#{project["id"]}/tasks"

    first = conn |> operator() |> post(path, attrs) |> json_response(201)
    replay = conn |> operator() |> post(path, attrs) |> json_response(201)
    assert first == replay
    assert first["data"]["project_id"] == project["id"]

    conn
    |> operator()
    |> post(path, %{attrs | "title" => "Changed semantics"})
    |> json_response(409)
  end

  test "observer cannot create Tasks or use operator registration", %{conn: conn} do
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["observer"])
    {_principal, connection, credential} = connection_fixture(agent)

    conn
    |> machine(credential, connection)
    |> post(
      "/api/agent/projects/#{project["id"]}/tasks",
      command(%{"title" => "Forbidden work"})
    )
    |> json_response(403)

    conn
    |> machine(credential, connection)
    |> post("/api/agents", command(%{"name" => "Untrusted registration"}))
    |> json_response(401)
  end

  test "registered capabilities grant neither Project roles nor membership administration", %{
    conn: conn
  } do
    project = project_fixture()

    agent =
      agent_fixture(%{
        "advertised_capabilities" => ["sessions.v1", "project_events.v1"],
        "approved_capabilities" => ["sessions.v1", "project_events.v1"]
      })

    {_principal, connection, credential} = connection_fixture(agent)

    conn
    |> machine(credential, connection)
    |> get("/api/agent/projects/#{project["id"]}/context")
    |> json_response(403)

    conn
    |> machine(credential, connection)
    |> post(
      "/api/projects/#{project["id"]}/members",
      command(%{
        "agent_id" => agent["id"],
        "roles" => ["manager"],
        "expected_version" => project["version"]
      })
    )
    |> json_response(401)

    member_fixture(project, agent, ["worker"])

    conn
    |> machine(credential, connection)
    |> post(
      "/api/agent/projects/#{project["id"]}/tasks",
      command(%{"title" => "Worker cannot create manager work"})
    )
    |> json_response(403)

    conn
    |> machine(credential, connection)
    |> post(
      "/api/projects/#{project["id"]}/members",
      command(%{"agent_id" => agent["id"], "roles" => ["manager"]})
    )
    |> json_response(401)
  end

  test "replaced connections and revoked credentials reject machine reads", %{conn: conn} do
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {_principal, previous, credential} = connection_fixture(agent)
    {_principal, current, _credential} = connection_fixture(agent, credential)

    conn
    |> machine(credential, previous)
    |> get("/api/agent/projects/#{project["id"]}/context")
    |> json_response(401)

    conn
    |> machine(credential, previous)
    |> post(
      "/api/agent/projects/#{project["id"]}/tasks",
      command(%{"title" => "Stale connection cannot write"})
    )
    |> json_response(401)

    conn
    |> machine(credential, current)
    |> get("/api/agent/projects/#{project["id"]}/context")
    |> json_response(200)

    {:ok, principal} = Agents.authenticate(credential)
    {:ok, current_agent} = Agents.get(Principal.operator(), agent["id"])

    assert {:ok, _} =
             Agents.revoke_credential(
               Principal.operator(),
               agent["id"],
               command(%{
                 "credential_id" => principal.credential_id,
                 "expected_version" => current_agent["version"]
               })
             )

    conn
    |> machine(credential, current)
    |> get("/api/agent/projects/#{project["id"]}/context")
    |> json_response(401)
  end

  test "malformed IDs and unsupported states fail safely; pagination stays bounded", %{conn: conn} do
    conn |> operator() |> get("/api/projects/not-a-uuid") |> json_response(404)

    default_page =
      conn |> operator() |> get("/api/projects?limit=invalid") |> json_response(200)

    assert default_page["limit"] == 50
    assert default_page["offset"] == 0

    bounded_page =
      conn |> operator() |> get("/api/projects?limit=999999&offset=-1") |> json_response(200)

    assert bounded_page["limit"] == 100
    assert bounded_page["offset"] == 0

    project = project_fixture()

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Reviewed work"}))

    conn
    |> operator()
    |> post(
      "/api/projects/#{project["id"]}/tasks/#{task["id"]}/transition",
      command(%{"state" => "accepted", "expected_version" => task["version"]})
    )
    |> json_response(409)
  end

  test "execution submits for separate review and acceptance; proof is an explicit secret read",
       %{
         conn: conn
       } do
    project = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {_principal, connection, credential} = connection_fixture(agent)
    prefix = "/api/agent/projects/#{project["id"]}"

    created =
      conn
      |> machine(credential, connection)
      |> post(prefix <> "/tasks", command(%{"title" => "Agent owned execution"}))
      |> json_response(201)

    task = created["data"]

    session =
      conn
      |> machine(credential, connection)
      |> post(prefix <> "/sessions", command(%{"external_id" => "api-execution"}))
      |> json_response(201)
      |> Map.fetch!("data")

    authority = conn |> operator() |> get("/api/platform") |> json_response(200)

    closed =
      conn
      |> operator()
      |> post(
        "/api/platform/close",
        command(%{
          "expected_version" => authority["data"]["version"],
          "reason" => "Establish isolated API lifecycle gate"
        })
      )
      |> json_response(200)

    assert closed["data"]["owner"] == "none"
    assert closed["data"]["admission_open"] == false

    conn
    |> machine(credential, connection)
    |> post(
      prefix <> "/tasks/#{task["id"]}/claim",
      command(%{"expected_version" => task["version"], "session_id" => session["id"]})
    )
    |> json_response(409)

    conn
    |> operator()
    |> post(
      "/api/platform/activate",
      command(%{
        "expected_version" => closed["data"]["version"],
        "evidence" => %{
          "legacy_fenced" => true,
          "effects_resolved" => true,
          "reference" => "isolated-api-test"
        }
      })
    )
    |> json_response(200)

    claimed =
      conn
      |> machine(credential, connection)
      |> post(
        prefix <> "/tasks/#{task["id"]}/claim",
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )
      |> json_response(201)

    attempt = claimed["data"]
    refute Map.has_key?(attempt, "proof")
    assert {:ok, leased_task} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert leased_task["state"] == "open"

    secret =
      conn
      |> machine(credential, connection)
      |> get(prefix <> "/attempts/#{attempt["id"]}/proof")

    proof = json_response(secret, 200)["data"]["proof"]
    assert is_binary(proof)
    assert get_resp_header(secret, "cache-control") == ["no-store"]

    started =
      conn
      |> machine(credential, connection)
      |> post(
        prefix <> "/attempts/#{attempt["id"]}/start",
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )
      |> json_response(200)

    assert {:ok, running_task} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert running_task["state"] == "in_progress"

    reported =
      conn
      |> machine(credential, connection)
      |> post(
        prefix <> "/attempts/#{attempt["id"]}/report",
        command(%{
          "expected_version" => started["data"]["version"],
          "proof" => proof,
          "outcome" => "succeeded",
          "result" => %{"summary" => "Execution finished"},
          "effects_resolved" => true
        })
      )
      |> json_response(200)

    refute Jason.encode!(reported) =~ proof
    assert {:ok, submitted} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert submitted["state"] == "awaiting_review"

    for kind <- ["review", "acceptance"] do
      {:ok, current} = Tasks.get(Principal.operator(), project["id"], task["id"])

      conn
      |> operator()
      |> post(
        "/api/projects/#{project["id"]}/tasks/#{task["id"]}/decisions",
        command(%{
          "expected_version" => current["version"],
          "kind" => kind,
          "verdict" => "approve"
        })
      )
      |> json_response(200)
    end

    assert {:ok, accepted} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert accepted["state"] == "accepted"
  end

  defp operator(conn), do: put_req_header(conn, "x-api-key", "phase3-operator-key")

  defp machine(conn, credential, connection) do
    conn
    |> put_req_header("authorization", "Bearer " <> credential)
    |> put_req_header("x-agent-connection", connection["id"])
  end
end
