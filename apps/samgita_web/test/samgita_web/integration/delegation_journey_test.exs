defmodule SamgitaWeb.DelegationJourneyTest do
  @moduledoc """
  Design §10 outcome loop (A18, P8.5): a fake coordinator and a fake executor,
  each behind its own real authenticated WebSocket endpoint, delegate one
  GitHub issue through explicit assignment to an accepted Task.
  """
  use SamgitaWeb.ConnCase, async: false
  import Ecto.Query
  import Samgita.DomainFixtures, only: [command: 0, command: 1, activate_fixture: 0]
  alias Samgita.Domain.DomainEvent
  alias Samgita.Domain.EventDelivery, as: Delivery
  alias Samgita.{EventDelivery, Repo}
  alias SamgitaWeb.FakeAgent

  @coordinator_types ~w(github.issues task.assigned attempt.reported)

  setup do
    keys = [:api_keys, :event_destinations, :event_credentials, :github_secrets]
    old = Map.new(keys, &{&1, Application.get_env(:samgita, &1)})
    Application.put_env(:samgita, :api_keys, ["qualification-operator"])

    Application.put_env(:samgita, :github_secrets, %{
      "test-hook-v1" => Samgita.GitHubFixtures.secret()
    })

    on_exit(fn ->
      Enum.each(old, fn {k, v} ->
        if is_nil(v),
          do: Application.delete_env(:samgita, k),
          else: Application.put_env(:samgita, k, v)
      end)
    end)

    activate_fixture()

    agents =
      for role <- [:coordinator, :executor], into: %{} do
        path = Path.join(System.tmp_dir!(), "samgita-fake-#{role}-#{Ecto.UUID.generate()}.json")

        on_exit(fn ->
          File.rm(path)
          File.rm(path <> ".tmp")
        end)

        fake =
          start_supervised!({FakeAgent, journal: path, token: "#{role}-service-token"}, id: role)

        {role, fake}
      end

    %{fakes: agents}
  end

  test "issue event to coordinator, assignment, executor claim and report, reviewer acceptance",
       %{conn: conn, fakes: fakes} do
    op = put_req_header(conn, "x-api-key", "qualification-operator")

    coordinator = register(op, "Synapsis", fakes.coordinator, "coordinator")
    executor = register(op, "Codex", fakes.executor, "executor")

    Application.put_env(:samgita, :event_destinations, %{
      coordinator.agent["id"] => destination(fakes.coordinator),
      executor.agent["id"] => destination(fakes.executor)
    })

    Application.put_env(:samgita, :event_credentials, %{
      "coordinator-service-v1" => "coordinator-service-token",
      "executor-service-v1" => "executor-service-token"
    })

    project = post_data(op, "/api/projects", command(%{"name" => "Delegation journey"}))
    base = "/api/projects/#{project["id"]}"
    version = project["version"]
    version = member(op, base, coordinator.agent, ~w(manager reviewer), version)
    version = member(op, base, executor.agent, ~w(worker), version)

    routing =
      put(
        op,
        base <> "/event-routing",
        command(%{
          "agent_id" => coordinator.agent["id"],
          "expected_version" => version,
          "types" => @coordinator_types,
          "idempotency_guaranteed" => true
        })
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assignee =
      put(
        op,
        base <> "/event-routing/assignees",
        command(%{
          "agent_id" => executor.agent["id"],
          "expected_version" => routing["project_version"],
          "types" => ["task.assigned"],
          "idempotency_guaranteed" => true
        })
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert assignee["purpose"] == "assignee"

    # 1. A verified GitHub issue reaches only the coordinator over its WebSocket.
    {_p, gh_connection, _mapping} = Samgita.GitHubFixtures.mapping_fixture(project)
    {raw, signature} = Samgita.GitHubFixtures.signed(Samgita.GitHubFixtures.body_fixture())

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", "issues")
    |> put_req_header("x-github-delivery", Ecto.UUID.generate())
    |> put_req_header("x-hub-signature-256", signature)
    |> post("/api/github/webhooks/#{gh_connection.id}", raw)
    |> json_response(202)

    issue = event!(project, "github.issues")
    assert dispatch!(issue) == [coordinator.agent["id"]]
    assert received?(fakes.coordinator, issue)

    # 2. The coordinator decomposes the issue and assigns the child to Codex.
    coord = machine(conn, coordinator)
    coord_base = "/api/agent/projects/#{project["id"]}"
    parent = post_data(coord, coord_base <> "/tasks", command(%{"title" => "Fix issue"}))

    child =
      post_data(
        coord,
        coord_base <> "/tasks",
        command(%{"title" => "Implement fix", "parent_task_id" => parent["id"]})
      )

    assigned =
      post_data(
        coord,
        coord_base <> "/tasks/#{child["id"]}/assign",
        command(%{
          "expected_version" => child["version"],
          "assignee_agent_id" => executor.agent["id"]
        }),
        200
      )

    assignment = event!(project, "task.assigned")

    assert Enum.sort(dispatch!(assignment)) ==
             Enum.sort([coordinator.agent["id"], executor.agent["id"]])

    assert received?(fakes.executor, assignment)

    # 3. The executor finds its work, claims, starts and reports.
    exec = machine(conn, executor)

    assert [%{"id" => found}] =
             get(exec, coord_base <> "/tasks?assignee_agent_id=#{executor.agent["id"]}")
             |> json_response(200)
             |> Map.fetch!("data")

    assert found == child["id"]
    session = post_data(exec, coord_base <> "/sessions", command(%{"external_id" => "codex-1"}))

    attempt =
      post_data(
        exec,
        coord_base <> "/tasks/#{child["id"]}/claim",
        command(%{"expected_version" => assigned["version"], "session_id" => session["id"]})
      )

    proof =
      get(exec, coord_base <> "/attempts/#{attempt["id"]}/proof")
      |> json_response(200)
      |> get_in(["data", "proof"])

    running =
      post_data(
        exec,
        coord_base <> "/attempts/#{attempt["id"]}/start",
        command(%{"expected_version" => attempt["version"], "proof" => proof}),
        200
      )

    post_data(
      exec,
      coord_base <> "/attempts/#{attempt["id"]}/report",
      command(%{
        "expected_version" => running["version"],
        "proof" => proof,
        "outcome" => "succeeded",
        "effects_resolved" => true,
        "result" => %{"summary" => "PR opened by the executor"}
      }),
      200
    )

    # 4. The coordinator observes the outcome and, holding reviewer, accepts.
    reported = event!(project, "attempt.reported")
    assert dispatch!(reported) == [coordinator.agent["id"]]
    assert received?(fakes.coordinator, reported)

    pending = get(coord, coord_base <> "/tasks/#{child["id"]}") |> json_response(200)
    assert pending["data"]["state"] == "awaiting_review"

    reviewed =
      post_data(
        coord,
        coord_base <> "/tasks/#{child["id"]}/decisions",
        command(%{
          "expected_version" => pending["data"]["version"],
          "kind" => "review",
          "verdict" => "approve"
        }),
        200
      )

    accepted =
      post_data(
        coord,
        coord_base <> "/tasks/#{child["id"]}/decisions",
        command(%{
          "expected_version" => reviewed["version"],
          "kind" => "acceptance",
          "verdict" => "approve"
        }),
        200
      )

    assert accepted["state"] == "accepted"
  end

  defp register(op, name, fake, role) do
    agent =
      post_data(
        op,
        "/api/agents",
        command(%{
          "name" => name,
          "implementation" => "qualification-fake",
          "advertised_capabilities" => ["project_events.v1"],
          "approved_capabilities" => ["project_events.v1"],
          "endpoint_metadata" => %{"transport" => "websocket", "url" => FakeAgent.url(fake)},
          "credential_ref" => "#{role}-service-v1"
        })
      )

    token = String.duplicate("#{role}-machine-credential", 2)

    post_data(
      op,
      "/api/agents/#{agent["id"]}/credentials",
      command(%{"expected_version" => agent["version"], "credential" => token})
    )

    %{agent: agent, token: token}
  end

  defp destination(fake),
    do: %{url: FakeAgent.url(fake), addresses: [{127, 0, 0, 1}], allow_insecure: true}

  defp member(op, base, agent, roles, version) do
    post_data(
      op,
      base <> "/members",
      command(%{"agent_id" => agent["id"], "roles" => roles, "expected_version" => version}),
      200
    )
    |> Map.fetch!("project_version")
  end

  defp machine(conn, %{token: token}) do
    connection =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/agent/connect", command())
      |> json_response(201)
      |> Map.fetch!("data")

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("x-agent-connection", connection["id"])
  end

  defp event!(project, type),
    do:
      Repo.one!(
        from e in DomainEvent,
          where: e.project_id == ^project["id"] and e.type == ^type,
          order_by: [desc: e.sequence],
          limit: 1
      )

  # Dispatches every delivery of the event over the real WebSocket connector and
  # returns the Agents it reached.
  defp dispatch!(event) do
    for delivery <- Repo.all(from d in Delivery, where: d.event_id == ^event.id) do
      assert {:ok, %{"state" => "accepted"}} = EventDelivery.dispatch(delivery.id)
      delivery.agent_id
    end
  end

  defp received?(fake, event),
    do: Map.has_key?(FakeAgent.snapshot(fake)["events"], event.id)

  defp post_data(conn, path, attrs, status \\ 201),
    do: post(conn, path, attrs) |> json_response(status) |> Map.fetch!("data")
end
