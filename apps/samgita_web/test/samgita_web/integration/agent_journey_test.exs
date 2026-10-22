defmodule SamgitaWeb.AgentJourneyTest do
  use SamgitaWeb.ConnCase, async: false
  import Ecto.Query
  import Samgita.DomainFixtures, only: [command: 0, command: 1, activate_fixture: 0]
  alias Samgita.Domain.EventDelivery, as: Delivery
  alias Samgita.{EventDelivery, Management, Principal, Repo}
  alias SamgitaWeb.FakeAgent

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
    path = Path.join(System.tmp_dir!(), "samgita-fake-#{Ecto.UUID.generate()}.json")

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> ".tmp")
    end)

    fake = start_supervised!({FakeAgent, journal: path, token: "qualification-service-token"})
    %{fake: fake}
  end

  for name <- ["Synapsis", "Orion"] do
    @agent_name name
    test "signed fact to reviewed acceptance using ordinary #{@agent_name} identity", %{
      conn: conn,
      fake: fake
    } do
      op = put_req_header(conn, "x-api-key", "qualification-operator")
      url = FakeAgent.url(fake)

      agent =
        post_data(
          op,
          "/api/agents",
          command(%{
            "name" => @agent_name,
            "implementation" => "qualification-fake",
            "advertised_capabilities" => ["project_events.v1"],
            "approved_capabilities" => ["project_events.v1"],
            "endpoint_metadata" => %{"transport" => "websocket", "url" => url},
            "credential_ref" => "qualification-service-v1"
          })
        )

      token = String.duplicate("fake-machine-credential", 2)

      post_data(
        op,
        "/api/agents/#{agent["id"]}/credentials",
        command(%{"expected_version" => agent["version"], "credential" => token})
      )

      Application.put_env(:samgita, :event_destinations, %{
        agent["id"] => %{url: url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
      })

      Application.put_env(:samgita, :event_credentials, %{
        "qualification-service-v1" => "qualification-service-token"
      })

      project =
        post_data(op, "/api/projects", command(%{"name" => "Persisted #{@agent_name} journey"}))

      base = "/api/projects/#{project["id"]}"

      member =
        post_data(
          op,
          base <> "/members",
          command(%{
            "agent_id" => agent["id"],
            "roles" => ~w(manager worker reviewer),
            "expected_version" => project["version"]
          }),
          200
        )

      association =
        post_data(
          op,
          base <> "/repositories",
          command(%{
            "kind" => "git",
            "display_name" => "owner/source",
            "url" => "https://github.test/owner/source.git",
            "expected_version" => member["project_version"]
          })
        )

      routing =
        put(
          op,
          base <> "/event-routing",
          command(%{
            "agent_id" => agent["id"],
            "expected_version" => association["project_version"],
            "types" => ["github.issues"],
            "idempotency_guaranteed" => true
          })
        )
        |> json_response(200)

      assert routing["data"]["agent_id"] == agent["id"]

      {_p, gh_connection, _mapping} = Samgita.GitHubFixtures.mapping_fixture(project)
      {raw, signature} = Samgita.GitHubFixtures.signed(Samgita.GitHubFixtures.body_fixture())
      source_id = Ecto.UUID.generate()

      hook =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-github-event", "issues")
        |> put_req_header("x-github-delivery", source_id)
        |> put_req_header("x-hub-signature-256", signature)

      first = post(hook, "/api/github/webhooks/#{gh_connection.id}", raw) |> json_response(202)
      again = post(hook, "/api/github/webhooks/#{gh_connection.id}", raw) |> json_response(200)
      assert first["id"] == again["id"]
      assert again["duplicate"]
      [delivery] = Repo.all(from(d in Delivery, where: d.project_id == ^project["id"]))

      # Actual authenticated WebSocket protocol traffic, not a connector stub.
      assert {:ok, %{"state" => "accepted", "accepted_at" => accepted}} =
               EventDelivery.dispatch(delivery.id)

      assert accepted
      assert %{"events" => events} = FakeAgent.snapshot(fake)
      assert map_size(events) == 1

      assert Repo.aggregate(
               from(t in Samgita.Domain.Task, where: t.project_id == ^project["id"]),
               :count
             ) == 0

      connection =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/agent/connect", command())
        |> json_response(201)
        |> Map.fetch!("data")

      machine =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> put_req_header("x-agent-connection", connection["id"])

      machine_base = "/api/agent/projects/#{project["id"]}"
      current_delivery = Repo.get!(Delivery, delivery.id)
      decision_id = Ecto.UUID.generate()

      report =
        post_data(
          machine,
          machine_base <> "/deliveries/#{delivery.id}/report",
          command(%{
            "expected_version" => current_delivery.version,
            "operation_id" => delivery.operation_id,
            "fence" => current_delivery.fence,
            "decision_id" => decision_id,
            "processing_status" => "completed",
            "result" => %{"summary" => "Agent chose a bounded task"}
          }),
          200
        )

      assert report["state"] == "completed"
      history = get(op, base <> "/deliveries/#{delivery.id}") |> json_response(200)
      assert Enum.any?(history["data"]["acknowledgements"], &(&1["decision_id"] == decision_id))

      task =
        post_data(machine, machine_base <> "/tasks", command(%{"title" => "Agent-planned task"}))

      child =
        post_data(
          machine,
          machine_base <> "/tasks",
          command(%{"title" => "Delegated child", "parent_task_id" => task["id"]})
        )

      assert child["parent_task_id"] == task["id"]

      session =
        post_data(
          machine,
          machine_base <> "/sessions",
          command(%{"external_id" => "journal-thread-1"})
        )

      claim_attrs =
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})

      attempt = post_data(machine, machine_base <> "/tasks/#{task["id"]}/claim", claim_attrs)
      replay = post_data(machine, machine_base <> "/tasks/#{task["id"]}/claim", claim_attrs)
      assert replay == attempt

      proof =
        get(machine, machine_base <> "/attempts/#{attempt["id"]}/proof")
        |> json_response(200)
        |> get_in(["data", "proof"])

      assert FakeAgent.start_once(fake, attempt["id"]) == :started
      assert FakeAgent.start_once(fake, attempt["id"]) == :already_started

      running =
        post_data(
          machine,
          machine_base <> "/attempts/#{attempt["id"]}/start",
          command(%{"expected_version" => attempt["version"], "proof" => proof}),
          200
        )

      progressing =
        post_data(
          machine,
          machine_base <> "/attempts/#{attempt["id"]}/progress",
          command(%{
            "expected_version" => running["version"],
            "proof" => proof,
            "payload" => %{
              "summary" => "Simulated execution produced evidence",
              "status" => "working"
            }
          }),
          200
        )

      current_task =
        get(machine, machine_base <> "/tasks/#{task["id"]}")
        |> json_response(200)
        |> Map.fetch!("data")

      artifact =
        post_data(
          machine,
          machine_base <> "/tasks/#{task["id"]}/artifacts",
          command(%{
            "expected_version" => current_task["version"],
            "attempt_id" => attempt["id"],
            "kind" => "test-report",
            "locator" => "artifact:qualification/report",
            "digest" => "sha256:fake"
          })
        )

      assert artifact["attempt_id"] == attempt["id"]

      post_data(
        machine,
        machine_base <> "/attempts/#{attempt["id"]}/report",
        command(%{
          "expected_version" => progressing["version"],
          "proof" => proof,
          "outcome" => "succeeded",
          "effects_resolved" => true,
          "result" => %{"summary" => "Simulation finished"}
        }),
        200
      )

      pending =
        get(machine, machine_base <> "/tasks/#{task["id"]}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert pending["state"] == "awaiting_review"

      assert post(
               machine,
               machine_base <> "/tasks/#{task["id"]}/decisions",
               command(%{
                 "expected_version" => pending["version"],
                 "kind" => "acceptance",
                 "verdict" => "approve"
               })
             )
             |> json_response(409)

      reviewed =
        post_data(
          op,
          base <> "/tasks/#{task["id"]}/decisions",
          command(%{
            "expected_version" => pending["version"],
            "kind" => "review",
            "verdict" => "approve",
            "summary" => "Evidence meets project review policy"
          }),
          200
        )

      accepted_task =
        post_data(
          op,
          base <> "/tasks/#{task["id"]}/decisions",
          command(%{
            "expected_version" => reviewed["version"],
            "kind" => "acceptance",
            "verdict" => "approve",
            "summary" => "Operator accepts the reviewed evidence"
          }),
          200
        )

      assert accepted_task["state"] == "accepted"
      assert {:ok, detail} = Management.task(Principal.operator(), project["id"], task["id"])

      assert detail["totals"] == %{
               "attempts" => 1,
               "artifacts" => 1,
               "children" => 1,
               "decisions" => 2,
               "progress" => 1
             }

      refute inspect(detail) =~ token
      refute inspect(detail) =~ proof
      assert detail["task"]["id"] == task["id"]
    end
  end

  defp post_data(conn, path, attrs, status \\ 201),
    do: post(conn, path, attrs) |> json_response(status) |> Map.fetch!("data")
end
