defmodule SamgitaWeb.GitHubControllerTest do
  use SamgitaWeb.ConnCase, async: false
  import Ecto.Query
  import Samgita.DomainFixtures
  alias Samgita.{GitHub, GitHubFixtures, Principal, Repo}
  alias Samgita.Domain.{DomainEvent, GitHubSync}

  @key "github-api-operator"
  @private "private-material-never-in-response"

  setup %{conn: conn} do
    previous =
      Map.new(
        [:api_keys, :github_client, :github_secrets],
        &{&1, Application.fetch_env(:samgita, &1)}
      )

    Application.put_env(:samgita, :api_keys, [@key])
    Application.put_env(:samgita, :github_client, GitHubFixtures.FakeClient)

    Application.put_env(:samgita, :github_secrets, %{
      "test-hook-v1" => GitHubFixtures.secret(),
      "test-key-v1" => @private
    })

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:samgita, key, value)
          :error -> Application.delete_env(:samgita, key)
        end
      end
    end)

    n = System.unique_integer([:positive])
    {:ok, conn: %{conn | remote_ip: {127, 44, rem(div(n, 256), 256), rem(n, 256)}}}
  end

  test "connection management requires the operator key and returns metadata only", %{conn: conn} do
    attrs =
      command(%{
        "host" => "github.test",
        "app_id" => "10",
        "installation_id" => "20",
        "private_key_ref" => "test-key-v1",
        "webhook_secret_ref" => "test-hook-v1"
      })

    assert conn |> post("/api/github/connections", attrs) |> json_response(401)
    response = conn |> operator() |> post("/api/github/connections", attrs)
    connection = json_response(response, 200)
    assert connection["installation_id"] == "20"
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert_safe(response)
    listed = conn |> operator() |> get("/api/github/connections")
    assert Enum.any?(json_response(listed, 200)["data"], &(&1["id"] == connection["id"]))
    assert_safe(listed)

    agent = agent_fixture()
    {_, agent_connection, credential} = connection_fixture(agent)
    machine = machine(conn, credential, agent_connection)
    assert machine |> post("/api/github/connections", command(attrs)) |> json_response(401)
    assert machine |> get("/api/github/connections") |> json_response(401)
  end

  test "operator verifies an explicit repository association and controls reconciliation", %{
    conn: conn
  } do
    project = project_fixture()
    connection = GitHubFixtures.connection_fixture()
    prefix = prefix(project)

    attrs =
      command(%{
        "connection_id" => connection.id,
        "external_id" => "30",
        "expected_version" => project["version"]
      })

    response = conn |> operator() |> post(prefix, attrs)
    mapping = json_response(response, 200)
    assert mapping["project_id"] == project["id"]
    assert mapping["repository"]["external_id"] == "30"
    assert mapping["repository"]["state"] == "verified"
    assert_safe(response)
    listed = conn |> operator() |> get(prefix <> "?limit=1&offset=0") |> json_response(200)
    assert length(listed["data"]) == 1
    assert hd(listed["data"])["id"] == mapping["id"]
    assert listed["limit"] == 1

    reconciled =
      conn
      |> operator()
      |> post(
        prefix <> "/#{mapping["id"]}/reconcile",
        command(%{"expected_version" => mapping["version"]})
      )
      |> json_response(200)

    assert length(reconciled["syncs"]) == 4
    assert Enum.all?(reconciled["syncs"], &(&1["state"] == "pending"))

    disabled =
      conn
      |> operator()
      |> patch(
        prefix <> "/#{mapping["id"]}",
        command(%{"expected_version" => mapping["version"], "enabled" => false})
      )
      |> json_response(200)

    assert disabled["enabled"] == false

    assert conn
           |> operator()
           |> post(
             prefix <> "/#{mapping["id"]}/reconcile",
             command(%{"expected_version" => disabled["version"]})
           )
           |> json_response(403)
  end

  test "Agent reads require its current connection and membership; capabilities grant no scope",
       %{conn: conn} do
    {project, _, mapping} = GitHubFixtures.mapping_fixture()
    other = project_fixture()
    agent = agent_fixture()
    member_fixture(project, agent, ["observer"])
    {_, agent_connection, credential} = connection_fixture(agent)
    machine = machine(conn, credential, agent_connection)
    path = agent_prefix(project)
    assert conn |> get(path) |> json_response(401)
    response = machine |> get(path)
    assert [%{"id" => id}] = json_response(response, 200)["data"]
    assert id == mapping["id"]
    assert_safe(response, credential)
    facts = machine |> get(path <> "/#{id}/facts")
    assert json_response(facts, 200)["input_trust"] == "untrusted"
    assert get_resp_header(facts, "cache-control") == ["no-store"]
    assert_safe(facts, credential)
    assert machine |> get(agent_prefix(other)) |> json_response(403)
    assert machine |> post(prefix(project), command(%{})) |> json_response(401)

    {_, replacement, _} = connection_fixture(agent, credential)
    assert machine |> get(path) |> json_response(401)
    assert conn |> machine(credential, replacement) |> get(path) |> json_response(200)
  end

  test "mapping and evidence reads reject IDs from a different Project", %{conn: conn} do
    {project, connection, mapping} = GitHubFixtures.mapping_fixture()
    other = project_fixture()
    assert {:ok, receipt} = GitHubFixtures.ingest(connection)
    right = prefix(project) <> "/#{mapping["id"]}"
    wrong = prefix(other) <> "/#{mapping["id"]}"
    evidence = conn |> operator() |> get(right <> "/deliveries/#{receipt["id"]}")
    assert json_response(evidence, 200)
    assert evidence.resp_body =~ "Untrusted source text"
    assert evidence.resp_body =~ "untrusted"
    assert get_resp_header(evidence, "cache-control") == ["no-store"]
    assert_safe(evidence)
    assert conn |> operator() |> get(wrong <> "/facts") |> json_response(404)

    assert conn
           |> operator()
           |> get(wrong <> "/deliveries/#{receipt["id"]}")
           |> json_response(404)

    assert conn
           |> operator()
           |> get(right <> "/deliveries/#{Ecto.UUID.generate()}")
           |> json_response(404)

    agent = agent_fixture()
    member_fixture(project, agent, ["observer"])
    {_, agent_connection, credential} = connection_fixture(agent)
    machine = machine(conn, credential, agent_connection)

    assert machine
           |> get(agent_prefix(project) <> "/#{mapping["id"]}/deliveries/#{receipt["id"]}")
           |> json_response(200)

    assert machine
           |> get(agent_prefix(other) <> "/#{mapping["id"]}/deliveries/#{receipt["id"]}")
           |> json_response(403)
  end

  test "immutable observations remain readable after the current source text changes", %{
    conn: conn
  } do
    {project, _, mapping} = GitHubFixtures.mapping_fixture()
    github_id = mapping["repository"]["id"]

    sync =
      Repo.one!(
        from s in GitHubSync, where: s.github_repository_id == ^github_id and s.kind == "issues"
      )

    result = {:ok, %{items: [GitHubFixtures.issue_fixture()], next_page: nil}}

    assert {:ok, _} =
             GitHub.Reconciliation.run(sync.id,
               client: GitHubFixtures.FakeClient,
               fetch_result: result
             )

    event =
      Repo.one!(
        from e in DomainEvent,
          where: e.project_id == ^project["id"] and e.type == "github.reconciled"
      )

    observation_id = event.data["untrusted_input_ref"]
    assert is_binary(observation_id)
    path = prefix(project) <> "/#{mapping["id"]}/observations/#{observation_id}"
    first = conn |> operator() |> get(path)
    assert json_response(first, 200)
    assert first.resp_body =~ "Untrusted source text"
    assert get_resp_header(first, "cache-control") == ["no-store"]
    assert_safe(first)

    assert {:ok, _} =
             GitHub.reconcile(
               Principal.operator(),
               project["id"],
               mapping["id"],
               command(%{"expected_version" => mapping["version"]})
             )

    changed =
      GitHubFixtures.issue_fixture(%{
        "body" => "Later source text",
        "updated_at" => "2026-10-23T00:00:00Z"
      })

    assert {:ok, _} =
             GitHub.Reconciliation.run(sync.id,
               client: GitHubFixtures.FakeClient,
               fetch_result: {:ok, %{items: [changed], next_page: nil}}
             )

    old = conn |> operator() |> get(path)
    assert json_response(old, 200) == json_response(first, 200)
    refute old.resp_body =~ "Later source text"

    agent = agent_fixture()
    member_fixture(project, agent, ["observer"])
    {_, agent_connection, credential} = connection_fixture(agent)
    machine = machine(conn, credential, agent_connection)

    response =
      machine |> get(agent_prefix(project) <> "/#{mapping["id"]}/observations/#{observation_id}")

    assert json_response(response, 200)
    assert_safe(response, credential)
    other = project_fixture()

    assert conn
           |> operator()
           |> get(prefix(other) <> "/#{mapping["id"]}/observations/#{observation_id}")
           |> json_response(404)

    assert machine
           |> get(agent_prefix(other) <> "/#{mapping["id"]}/observations/#{observation_id}")
           |> json_response(403)
  end

  defp prefix(project), do: "/api/projects/#{project["id"]}/github/repositories"
  defp agent_prefix(project), do: "/api/agent/projects/#{project["id"]}/github/repositories"
  defp operator(conn), do: put_req_header(conn, "x-api-key", @key)

  defp machine(conn, credential, connection) do
    conn
    |> put_req_header("authorization", "Bearer " <> credential)
    |> put_req_header("x-agent-connection", connection["id"])
  end

  defp assert_safe(conn, credential \\ nil) do
    refute conn.resp_body =~ GitHubFixtures.secret()
    refute conn.resp_body =~ @private
    refute conn.resp_body =~ "credential_digest"
    refute conn.resp_body =~ "Bearer "
    if credential, do: refute(conn.resp_body =~ credential)
  end
end
