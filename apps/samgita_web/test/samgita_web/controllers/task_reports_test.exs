defmodule SamgitaWeb.TaskReportsTest do
  use SamgitaWeb.ConnCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts}

  setup %{conn: conn} do
    activate_fixture()
    project = project_fixture()
    coordinator = agent_fixture(%{"name" => "Report coordinator"})
    executor = agent_fixture(%{"name" => "Report executor"})
    member_fixture(project, coordinator, ~w(manager reviewer))
    member_fixture(project, executor, ~w(worker))
    {_, coordinator_connection, coordinator_token} = connection_fixture(coordinator)
    {executor_actor, executor_connection, executor_token} = connection_fixture(executor)

    {:ok, session} =
      Agents.open_session(
        executor_actor,
        project["id"],
        command(%{"external_id" => "functional-report-session"})
      )

    %{
      coordinator: machine(conn, coordinator_connection, coordinator_token),
      executor: machine(conn, executor_connection, executor_token),
      executor_actor: executor_actor,
      executor_id: executor["id"],
      base: "/api/agent/projects/#{project["id"]}",
      project_id: project["id"],
      session_id: session["id"]
    }
  end

  test "a coordinator reads an unreported Task with an empty report", ctx do
    task = create_task(ctx)
    current = task_data(ctx, task["id"])
    assert Map.has_key?(current, "latest_report")
    assert current["latest_report"] == nil
    assert current["artifact_references"] == []
  end

  test "a coordinator reads the executor's successful report and separate artifact references",
       ctx do
    task = create_task(ctx)
    running = start_attempt(ctx, task)
    current = task_data(ctx, task["id"])

    artifact =
      post_data(
        ctx.executor,
        ctx.base <> "/tasks/#{task["id"]}/artifacts",
        command(%{
          "expected_version" => current["version"],
          "attempt_id" => running["id"],
          "kind" => "report",
          "locator" => "artifact://functional-result"
        }),
        201
      )

    result = %{
      "summary" => "Implemented the requested behavior",
      "status" => "checks passed",
      "reference" => "artifact://functional-result"
    }

    reported = report(ctx, running, "succeeded", result)
    current = task_data(ctx, task["id"])
    report = current["latest_report"]
    assert current["state"] == "awaiting_review"
    assert report["attempt_id"] == reported["id"]
    assert report["task_id"] == task["id"]
    assert report["agent_id"] == ctx.executor_id
    assert report["number"] == 1
    assert report["state"] == "succeeded"
    assert report["effects_resolved"]
    assert is_binary(report["terminal_at"])
    assert report["outcome"] == %{"status" => "succeeded", "result" => result}
    assert [%{"id" => artifact_id, "attempt_id" => attempt_id}] = current["artifact_references"]
    assert artifact_id == artifact["id"]
    assert attempt_id == reported["id"]
  end

  test "a coordinator reads failure details and matches reports across a running retry", ctx do
    task = create_task(ctx)
    running = start_attempt(ctx, task)
    failed = report(ctx, running, "failed", %{"summary" => "The functional check failed"})
    current = task_data(ctx, task["id"])
    assert current["state"] == "failed"
    assert current["latest_report"]["attempt_id"] == failed["id"]

    assert current["latest_report"]["outcome"] == %{
             "status" => "failed",
             "result" => %{"summary" => "The functional check failed"}
           }

    reopened =
      post_data(
        ctx.coordinator,
        ctx.base <> "/tasks/#{task["id"]}/transition",
        command(%{"expected_version" => current["version"], "state" => "open"})
      )

    retry = start_attempt(ctx, reopened)
    current = task_data(ctx, task["id"])
    assert current["state"] == "in_progress"
    assert current["latest_report"]["attempt_id"] == failed["id"]

    succeeded = report(ctx, retry, "succeeded", %{"summary" => "The retry passed"})
    current = task_data(ctx, task["id"])
    assert current["latest_report"]["attempt_id"] == succeeded["id"]
    assert current["latest_report"]["number"] == 2
    assert current["latest_report"]["outcome"]["result"]["summary"] == "The retry passed"

    delayed_report =
      ctx.coordinator
      |> get(ctx.base <> "/attempts/#{failed["id"]}/report")
      |> json_response(200)
      |> Map.fetch!("data")

    assert delayed_report["attempt_id"] == failed["id"]
    assert delayed_report["outcome"]["result"]["summary"] == "The functional check failed"
  end

  test "report reads project only supported bounded text from existing result maps", ctx do
    task = create_task(ctx)
    running = start_attempt(ctx, task)

    report(ctx, running, "failed", %{
      "summary" => "A retained report summary",
      "status" => ["old", "structured", "status"],
      "reference" => String.duplicate("x", 2_001),
      "details" => %{"unstructured" => true}
    })

    current = task_data(ctx, task["id"])

    assert current["latest_report"]["outcome"] == %{
             "status" => "failed",
             "result" => %{"summary" => "A retained report summary"}
           }

    assert Enum.sort(Map.keys(current["latest_report"])) ==
             ~w(agent_id attempt_id effects_resolved number outcome state task_id terminal_at)
  end

  defp create_task(ctx),
    do:
      post_data(ctx.coordinator, ctx.base <> "/tasks", command(%{"title" => "Report task"}), 201)

  defp start_attempt(ctx, task) do
    assigned =
      post_data(
        ctx.coordinator,
        ctx.base <> "/tasks/#{task["id"]}/assign",
        command(%{
          "expected_version" => task["version"],
          "assignee_agent_id" => ctx.executor_id
        })
      )

    attempt =
      post_data(
        ctx.executor,
        ctx.base <> "/tasks/#{task["id"]}/claim",
        command(%{"expected_version" => assigned["version"], "session_id" => ctx.session_id}),
        201
      )

    {:ok, %{"proof" => proof}} =
      Attempts.proof(ctx.executor_actor, ctx.project_id, attempt["id"])

    running =
      post_data(
        ctx.executor,
        ctx.base <> "/attempts/#{attempt["id"]}/start",
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    Map.put(running, "proof", proof)
  end

  defp report(ctx, running, outcome, result),
    do:
      post_data(
        ctx.executor,
        ctx.base <> "/attempts/#{running["id"]}/report",
        command(%{
          "expected_version" => running["version"],
          "proof" => running["proof"],
          "outcome" => outcome,
          "effects_resolved" => true,
          "result" => result
        })
      )

  defp task_data(ctx, task_id),
    do:
      get(ctx.coordinator, ctx.base <> "/tasks/#{task_id}")
      |> json_response(200)
      |> Map.fetch!("data")

  defp machine(conn, connection, token),
    do:
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("x-agent-connection", connection["id"])

  defp post_data(conn, path, attrs, status \\ 200),
    do: post(conn, path, attrs) |> json_response(status) |> Map.fetch!("data")
end
