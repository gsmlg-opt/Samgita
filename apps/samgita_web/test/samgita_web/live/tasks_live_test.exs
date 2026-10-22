defmodule SamgitaWeb.TasksLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Attempts, Principal, Repo, Tasks}
  alias Samgita.Domain.{ArtifactReference, DecisionRecord, Task, TaskAttempt}
  alias SamgitaWeb.ProjectsLive.Support, as: UI

  setup do
    activate_fixture()
    project = project_fixture()

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Reviewable work"}))

    %{project: project, task: task}
  end

  test "Task disclosures retain editable forms through changes validation and saves", %{
    conn: conn,
    project: p,
    task: t
  } do
    {:ok, view, _} = live(conn, task_path(p, t))

    for name <- ~w(task transition artifact) do
      view |> element("##{name}-section > summary") |> render_click()
      assert has_element?(view, "##{name}-section[open]")
    end

    view |> form("#task-form", task: %{title: "Visible draft"}) |> render_change()

    for name <- ~w(task transition artifact),
        do: assert(has_element?(view, "##{name}-section[open]"))

    view |> form("#artifact-form", artifact: %{kind: "report", locator: ""}) |> render_submit()
    assert has_element?(view, "#artifact-section[open] [role=alert]", "invalid")

    view
    |> form("#artifact-form", artifact: %{kind: "report", locator: "artifact://visible"})
    |> render_submit()

    assert has_element?(view, "#artifact-section[open]")
    assert has_element?(view, "#task-artifacts code", "artifact://visible")
    view |> element("#artifact-section > summary") |> render_click()
    refute has_element?(view, "#artifact-section[open]")
    view |> form("#transition-form", transition: %{state: "blocked"}) |> render_change()
    refute has_element?(view, "#artifact-section[open]")
    render_patch(view, task_path(p, t) <> "?offset=25")
    assert has_element?(view, "#task-section[open]")
    GenServer.stop(view.pid)
    {:ok, reconnected, _} = live(conn, task_path(p, t))
    refute has_element?(reconnected, "#task-section[open]")
  end

  test "Task edits persist and repeated submissions replay the receipt", %{
    conn: conn,
    project: p,
    task: t
  } do
    {:ok, view, _} = live(conn, task_path(p, t))

    attrs =
      Map.merge(hidden(view, "task"), %{
        "title" => "Edited persisted title",
        "description" => "Kept across reload"
      })

    render_submit(view, "save:task", %{"task" => attrs})
    render_submit(view, "save:task", %{"task" => attrs})
    assert {:ok, current} = Tasks.get(Principal.operator(), p["id"], t["id"])
    assert current["version"] == t["version"] + 1
    assert current["title"] == "Edited persisted title"
    {:ok, reconnected, _} = live(conn, task_path(p, t))
    assert has_element?(reconnected, "h1", "Edited persisted title")
    assert has_element?(reconnected, "p", "Kept across reload")
  end

  test "rejected transitions retain target and leave persisted state unchanged", %{
    conn: conn,
    project: p,
    task: t
  } do
    {:ok, view, _} = live(conn, task_path(p, t))
    view |> form("#transition-form", transition: %{state: "accepted"}) |> render_submit()
    assert has_element?(view, "[role=alert]", "invalid transition")
    assert has_element?(view, "input[name='transition[state]'][value='accepted']")
    assert Repo.get!(Task, t["id"]).state == "open"
    view |> form("#transition-form", transition: %{state: "blocked"}) |> render_submit()
    assert Repo.get!(Task, t["id"]).state == "blocked"
    assert has_element?(view, "#task-state", "blocked")
    {:ok, refreshed, _} = live(conn, task_path(p, t))
    assert has_element?(refreshed, "#task-state", "blocked")
  end

  test "stale edits never overwrite current Task data", %{conn: conn, project: p, task: t} do
    {:ok, view, _} = live(conn, task_path(p, t))

    assert {:ok, _} =
             Tasks.update(
               Principal.operator(),
               p["id"],
               t["id"],
               command(%{"expected_version" => t["version"], "title" => "Other operator"})
             )

    view |> form("#task-form", task: %{title: "Keep stale draft"}) |> render_submit()
    assert has_element?(view, "[role=alert]", "stale version")
    assert has_element?(view, "input[name='task[title]'][value='Keep stale draft']")
    assert Repo.get!(Task, t["id"]).title == "Other operator"
  end

  test "successful execution needs explicit review and a separate acceptance", %{
    conn: conn,
    project: p,
    task: t
  } do
    {principal, running, proof} = running_attempt(p, t)

    assert {:ok, progress} =
             Attempts.progress(
               principal,
               p["id"],
               running["id"],
               command(%{
                 "expected_version" => running["version"],
                 "proof" => proof,
                 "payload" => %{"summary" => "Validated the change"}
               })
             )

    assert {:ok, _} =
             Attempts.report(
               principal,
               p["id"],
               running["id"],
               command(%{
                 "expected_version" => progress["version"],
                 "proof" => proof,
                 "outcome" => "succeeded",
                 "effects_resolved" => true,
                 "result" => %{
                   "summary" => "Implementation complete <script>alert(1)</script>",
                   "private_detail" => "not-part-of-operator-summary"
                 }
               })
             )

    {:ok, view, html} = live(conn, task_path(p, t))
    assert has_element?(view, "#task-state", "awaiting_review")
    assert has_element?(view, "#task-progress", "Validated the change")

    assert has_element?(
             view,
             ".attempt-outcome-summary",
             "Implementation complete <script>alert(1)</script>"
           )

    assert has_element?(view, "p", "Reported outcome: succeeded")
    refute has_element?(view, ".attempt-outcome-summary script")
    refute html =~ "not-part-of-operator-summary"
    assert has_element?(view, "#review-form")
    refute has_element?(view, "#acceptance-form")
    refute html =~ proof
    assert Repo.aggregate(from(d in DecisionRecord, where: d.task_id == ^t["id"]), :count) == 0

    view
    |> form("#review-form", review: %{verdict: "approve", summary: "Reviewed output"})
    |> render_submit()

    assert Repo.get!(Task, t["id"]).state == "awaiting_review"
    assert has_element?(view, "#acceptance-form")

    attrs =
      Map.merge(hidden(view, "acceptance"), %{
        "verdict" => "approve",
        "summary" => "Accepted by operator"
      })

    render_submit(view, "save:acceptance", %{"acceptance" => attrs})
    render_submit(view, "save:acceptance", %{"acceptance" => attrs})
    assert Repo.get!(Task, t["id"]).state == "accepted"
    assert Repo.aggregate(from(d in DecisionRecord, where: d.task_id == ^t["id"]), :count) == 2
    {:ok, refreshed, _} = live(conn, task_path(p, t))
    assert has_element?(refreshed, "#task-state", "accepted")
    assert has_element?(refreshed, "#task-decisions", "Reviewed output")
    assert has_element?(refreshed, "#task-decisions", "Accepted by operator")
  end

  test "interruption and reconnect retain execution uncertainty without another attempt", %{
    conn: conn,
    project: p,
    task: t
  } do
    {_principal, attempt, proof} = running_attempt(p, t)
    {:ok, current} = Tasks.get(Principal.operator(), p["id"], t["id"])

    assert {:ok, _} =
             Tasks.transition(
               Principal.operator(),
               p["id"],
               t["id"],
               command(%{"expected_version" => current["version"], "state" => "blocked"})
             )

    {:ok, blocked} = Tasks.get(Principal.operator(), p["id"], t["id"])

    assert {:ok, _} =
             Tasks.transition(
               Principal.operator(),
               p["id"],
               t["id"],
               command(%{"expected_version" => blocked["version"], "state" => "open"})
             )

    {:ok, view, html} = live(conn, task_path(p, t))
    assert has_element?(view, "#task-hold", "Execution hold")
    assert has_element?(view, "#attempt-#{attempt["id"]}", "Remote effects unresolved")
    refute html =~ proof
    {:ok, reconnected, _} = live(conn, task_path(p, t))
    assert has_element?(reconnected, "#task-hold")
    assert Repo.aggregate(from(a in TaskAttempt, where: a.task_id == ^t["id"]), :count) == 1
    assert Repo.get!(TaskAttempt, attempt["id"]).state == "cancelled"
    refute has_element?(reconnected, "button", "Start")
  end

  test "artifact locators are escaped text and never executable links", %{
    conn: conn,
    project: p,
    task: t
  } do
    {:ok, view, _} = live(conn, task_path(p, t))

    view
    |> form("#artifact-form",
      artifact: %{kind: "report", locator: "javascript:alert(1)", digest: "sha256:example"}
    )
    |> render_submit()

    assert Repo.aggregate(from(a in ArtifactReference, where: a.task_id == ^t["id"]), :count) == 1
    assert has_element?(view, "#task-artifacts code", "javascript:alert(1)")
    refute has_element?(view, "a[href='javascript:alert(1)']")
    assert Repo.get!(Task, t["id"]).state == "open"
  end

  test "cross-project IDs are rejected without rendering another project's Task", %{
    conn: conn,
    task: t
  } do
    other = project_fixture(%{"name" => "Other scope"})
    {:ok, view, _} = live(conn, task_path(other, t))
    assert has_element?(view, "[role=alert]", "not found")
    refute has_element?(view, "h1", t["title"])
  end

  test "restricted legacy provenance stays readable without raw historical payload", %{
    conn: conn,
    project: p,
    task: t
  } do
    Repo.get!(Task, t["id"])
    |> Ecto.Changeset.change(
      adopted: false,
      type: "legacy_task",
      status: "completed",
      payload: %{"secret" => "historical-private-payload"}
    )
    |> Repo.update!()

    {:ok, view, html} = live(conn, task_path(p, t))
    assert has_element?(view, "#task-legacy", "legacy_task")
    assert has_element?(view, "#task-legacy", "completed")
    refute html =~ "historical-private-payload"
    refute has_element?(view, "#acceptance-form")
  end

  test "current review authorization is independent of paginated decision history", %{
    conn: conn,
    project: p,
    task: t
  } do
    {principal, running, proof} = running_attempt(p, t)

    {:ok, _} =
      Attempts.report(
        principal,
        p["id"],
        running["id"],
        command(%{
          "expected_version" => running["version"],
          "proof" => proof,
          "outcome" => "succeeded",
          "effects_resolved" => true
        })
      )

    {:ok, current} = Tasks.get(Principal.operator(), p["id"], t["id"])

    {:ok, _} =
      Tasks.decide(
        Principal.operator(),
        p["id"],
        t["id"],
        command(%{
          "expected_version" => current["version"],
          "kind" => "review",
          "verdict" => "approve"
        })
      )

    {:ok, view, _} = live(conn, task_path(p, t) <> "?offset=25")
    refute has_element?(view, "#task-decisions li")
    assert has_element?(view, "#acceptance-form")
  end

  defp running_attempt(p, t) do
    a = agent_fixture()
    member_fixture(p, a, ~w(worker reviewer))
    {principal, _, _} = connection_fixture(a)

    {:ok, session} =
      Agents.open_session(principal, p["id"], command(%{"external_id" => Ecto.UUID.generate()}))

    {:ok, attempt} =
      Attempts.claim(
        principal,
        p["id"],
        t["id"],
        command(%{"session_id" => session["id"], "expected_version" => t["version"]})
      )

    {:ok, %{"proof" => proof}} = Attempts.proof(principal, p["id"], attempt["id"])

    {:ok, running} =
      Attempts.start(
        principal,
        p["id"],
        attempt["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    {principal, running, proof}
  end

  defp task_path(p, t), do: "/projects/#{p["id"]}/tasks/#{t["id"]}"

  defp hidden(view, name) do
    view
    |> element("##{name}-form")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[type=hidden]")
    |> LazyHTML.to_tree()
    |> Enum.map(fn {"input", attributes, _} ->
      attrs = Map.new(attributes)

      {attrs["name"] |> String.replace_prefix(name <> "[", "") |> String.trim_trailing("]"),
       attrs["value"]}
    end)
    |> Map.new()
  end

  test "recovered Task edit preserves the original version and cannot silently become another command",
       %{conn: conn, project: p, task: t} do
    {:ok, view, _} = live(conn, task_path(p, t))

    values =
      Map.merge(hidden(view, "task"), %{
        "title" => "Unknown-result edit",
        "description" => "Original request",
        "parent_task_id" => "",
        "required_capabilities" => ""
      })

    assert {:ok, changed} =
             Tasks.update(
               Principal.operator(),
               p["id"],
               t["id"],
               UI.attrs(values)
             )

    GenServer.stop(view.pid)
    {:ok, recovered, _} = live(conn, task_path(p, t))
    render_change(recovered, "change:task", %{"task" => values})
    assert has_element?(recovered, "#task-section[open]")
    assert hidden(recovered, "task") == Map.take(values, ~w(command_id expected_version))
    assert Repo.get!(Task, t["id"]).version == changed["version"]
    altered = Map.put(values, "title", "Different unknown-result edit")
    render_change(recovered, "change:task", %{"task" => altered})
    assert hidden(recovered, "task")["command_id"] == values["command_id"]
    render_submit(recovered, "save:task", %{"task" => altered})
    assert has_element?(recovered, "[role=alert]", "command_id_reused")
    assert Repo.get!(Task, t["id"]).title == "Unknown-result edit"
    render_submit(recovered, "save:task", %{"task" => values})
    assert Repo.get!(Task, t["id"]).version == changed["version"]
  end
end
