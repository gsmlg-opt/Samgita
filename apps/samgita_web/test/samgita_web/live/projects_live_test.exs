defmodule SamgitaWeb.ProjectsLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures

  alias Samgita.{
    EventDelivery,
    Events,
    GitHubFixtures,
    Principal,
    Projects,
    Repo,
    Repositories,
    Schedules,
    Tasks
  }

  alias Samgita.Domain.Project
  alias SamgitaWeb.ProjectsLive.Support, as: UI

  test "routing without an Agent is a field error and leaves the Project unchanged", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    view
    |> form("#routing-form", routing: %{agent_id: "", types: "manual.triggered"})
    |> render_submit()

    assert has_element?(view, "#routing-section[open] [role=alert]", "invalid")
    assert has_element?(view, "input[name='routing[agent_id]'][aria-invalid='true']")
    assert {:ok, %{"subscription" => nil}} = Events.routing(Principal.operator(), p["id"])
    assert {:ok, current} = Projects.get(Principal.operator(), p["id"])
    assert current["version"] == p["version"]
  end

  test "Project disclosures stay expanded through changes validation and saves", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")
    sections = ~w(state repository choices member routing task schedule)

    for name <- sections do
      refute has_element?(view, "##{name}-section[open]")
      view |> element("##{name}-section > summary") |> render_click()
      assert has_element?(view, "##{name}-section[open]")
    end

    view |> form("#task-form", task: %{title: "Draft task"}) |> render_change()

    for name <- sections, do: assert(has_element?(view, "##{name}-section[open]"))

    view |> form("#task-form", task: %{title: ""}) |> render_submit()
    assert has_element?(view, "#task-section[open] [role=alert]", "invalid")
    view |> form("#task-form", task: %{title: "Visible saved task"}) |> render_submit()
    assert has_element?(view, "#task-section[open]")

    assert {:ok, %{"data" => [%{"title" => "Visible saved task"}]}} =
             Tasks.list(Principal.operator(), p["id"])

    view |> element("#repository-section > summary") |> render_click()
    refute has_element?(view, "#repository-section[open]")
    view |> form("#event-form", event: %{payload: "{}"}) |> render_change()
    refute has_element?(view, "#repository-section[open]")

    render_patch(view, "/projects/#{p["id"]}?offset=25")
    assert has_element?(view, "#task-section[open]")
    GenServer.stop(view.pid)
    {:ok, reconnected, _} = live(conn, "/projects/#{p["id"]}")
    refute has_element?(reconnected, "#task-section[open]")

    other = project_fixture()
    render_patch(reconnected, "/projects/#{other["id"]}")
    refute has_element?(reconnected, "#task-section[open]")
    assert has_element?(reconnected, "h1", other["name"])
  end

  test "creates a persisted neutral project without PRD or git URL", %{conn: conn} do
    offset = Repo.aggregate(Project, :count)
    {:ok, view, _} = live(conn, "/projects?offset=#{offset}")
    assert has_element?(view, "#projects-empty")
    assert has_element?(view, "#project-form button[type=submit]", "Create project")

    view
    |> form("#project-form",
      project: %{name: "Independent work", description: "No repository needed"}
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    {:ok, detail, _} = live(conn, path)
    assert has_element?(detail, "h1", "Independent work")
    assert {:ok, project} = Projects.get(Principal.operator(), List.last(String.split(path, "/")))
    assert project["git_url"] == nil
    assert project["description"] == "No repository needed"
  end

  test "rejected create preserves values with visible field validation", %{conn: conn} do
    baseline = Repo.aggregate(Project, :count)
    {:ok, view, _} = live(conn, "/projects")

    view
    |> form("#project-form", project: %{name: "", description: "Keep this draft"})
    |> render_submit()

    assert has_element?(view, "[role=alert]", "invalid")
    assert has_element?(view, "textarea[name='project[description]']", "Keep this draft")
    assert Repo.aggregate(Project, :count) == baseline
  end

  test "task creation is idempotent and survives navigation and reconnect", %{conn: conn} do
    p = project_fixture()
    {:ok, parent} = Tasks.create(Principal.operator(), p["id"], command(%{"title" => "Parent"}))
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    attrs =
      Map.merge(hidden(view, "task"), %{
        "title" => "Persisted child",
        "parent_task_id" => parent["id"]
      })

    render_submit(view, "save:task", %{"task" => attrs})
    render_submit(view, "save:task", %{"task" => attrs})
    assert {:ok, %{"data" => tasks}} = Tasks.list(Principal.operator(), p["id"])
    assert [child] = Enum.filter(tasks, &(&1["title"] == "Persisted child"))
    assert child["parent_task_id"] == parent["id"]
    {:ok, reconnected, _} = live(conn, "/projects/#{p["id"]}")

    assert has_element?(
             reconnected,
             "a[href='/projects/#{p["id"]}/tasks/#{child["id"]}']",
             "Persisted child"
           )

    reconnected
    |> element("a[href='/projects/#{p["id"]}/tasks/#{child["id"]}']")
    |> render_click()

    assert_redirect(reconnected, "/projects/#{p["id"]}/tasks/#{child["id"]}")
  end

  test "stale project edit keeps submitted text and rejects overwrite", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    assert {:ok, _} =
             Projects.update(
               Principal.operator(),
               p["id"],
               command(%{"name" => "Concurrent edit", "expected_version" => p["version"]})
             )

    view
    |> form("#project-form",
      project: %{name: "Stale edit", description: "Preserve rejected values"}
    )
    |> render_submit()

    assert has_element?(view, "[role=alert]", "stale version")
    assert has_element?(view, "input[name='project[name]'][value='Stale edit']")
    assert {:ok, %{"name" => "Concurrent edit"}} = Projects.get(Principal.operator(), p["id"])
    {:ok, fresh, _} = live(conn, "/projects/#{p["id"]}")
    assert has_element?(fresh, "h1", "Concurrent edit")
  end

  test "membership repository association and routing are real commands", %{conn: conn} do
    p = project_fixture()
    a = agent_fixture(%{"name" => "Operator-selected Agent"})
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    view
    |> form("#member-form",
      member: %{agent_id: a["id"], roles: "manager, worker", enabled: "true"}
    )
    |> render_submit()

    assert has_element?(view, "li", "Operator-selected Agent")

    view
    |> form("#routing-form",
      routing: %{agent_id: a["id"], types: "", idempotency_guaranteed: "false"}
    )
    |> render_submit()

    assert {:ok, routing} = Events.routing(Principal.operator(), p["id"])
    assert routing["agent_id"] == a["id"]

    view
    |> form("#repository-form",
      repository: %{kind: "local", display_name: "Docs", role: "documentation", primary: "false"}
    )
    |> render_submit()

    assert {:ok, %{"data" => [repository]}} = Repositories.list(Principal.operator(), p["id"])
    assert repository["repository"]["display_name"] == "Docs"
  end

  test "schedule create edit disable and malformed payload validation persist", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")
    view |> form("#schedule-form", schedule: %{payload: "not json"}) |> render_submit()
    assert has_element?(view, "[role=alert]", "invalid")
    assert has_element?(view, "textarea[name='schedule[payload]']", "not json")

    view
    |> form("#schedule-form",
      schedule: %{
        expression: "*/15 * * * *",
        timezone: "Etc/UTC",
        event_type: "schedule.check",
        payload: "{}",
        enabled: "true"
      }
    )
    |> render_submit()

    assert {:ok, %{"data" => [schedule]}} = Schedules.list(Principal.operator(), p["id"])

    view
    |> element("button[phx-click='edit_schedule'][phx-value-id='#{schedule["id"]}']")
    |> render_click()

    view
    |> form("#schedule-form", schedule: %{expression: "*/30 * * * *", enabled: "false"})
    |> render_submit()

    assert {:ok, %{"data" => [updated]}} = Schedules.list(Principal.operator(), p["id"])
    assert updated["enabled"] == false
    assert updated["expression"] == "*/30 * * * *"
    assert updated["revision"] == schedule["revision"] + 1
  end

  test "manual events preserve source identity on repeated submission", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")
    attrs = Map.merge(hidden(view, "event"), %{"payload" => ~s({"summary":"Operator request"})})
    render_submit(view, "save:event", %{"event" => attrs})
    render_submit(view, "save:event", %{"event" => attrs})
    assert {:ok, %{"data" => events}} = Events.read(Principal.operator(), p["id"])
    assert 1 == Enum.count(events, &(&1["type"] == "manual.triggered"))
    assert has_element?(view, "li", "manual.triggered")
    assert has_element?(view, "pre", "Operator request")
    assert has_element?(view, "p", "Source: manual")
  end

  test "GitHub mappings render approved read-only repository evidence", %{conn: conn} do
    p = project_fixture()
    {_project, _connection, mapping} = GitHubFixtures.mapping_fixture(p)
    {:ok, view, html} = live(conn, "/projects/#{p["id"]}")
    assert has_element?(view, "#github-mappings", mapping["repository"]["full_name"])
    assert has_element?(view, "#github-mappings", "Read-only integration evidence")
    refute html =~ "test-key-v1"
    refute html =~ "test-hook-v1"
    refute has_element?(view, "button", "Merge")
  end

  test "delivery cancellation requires a reason and preserves recovery history", %{conn: conn} do
    p = project_fixture()
    a = agent_fixture()
    member_fixture(p, a, ["manager"])
    {:ok, current} = Projects.get(Principal.operator(), p["id"])

    {:ok, _} =
      Events.configure(
        Principal.operator(),
        p["id"],
        command(%{"agent_id" => a["id"], "expected_version" => current["version"]})
      )

    {:ok, _} =
      Events.trigger(
        Principal.operator(),
        p["id"],
        command(%{"payload" => %{"summary" => "Recovery test"}})
      )

    {:ok, %{"data" => [delivery]}} = EventDelivery.list(Principal.operator(), p["id"])
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    view
    |> element("button[phx-click='delivery'][phx-value-id='#{delivery["id"]}']")
    |> render_click()

    view
    |> form("#recovery-form",
      recovery: %{action: "cancel", reason: "", evidence_ref: "operator://investigation"}
    )
    |> render_submit()

    assert has_element?(view, "[role=alert]", "invalid")

    assert has_element?(view, "#recovery-section[open]")

    assert has_element?(
             view,
             "input[name='recovery[evidence_ref]'][value='operator://investigation']"
           )

    attrs =
      Map.merge(hidden(view, "recovery"), %{
        "action" => "cancel",
        "reason" => "Operator stopped delivery",
        "evidence_ref" => "operator://investigation",
        "risk_acknowledged" => "false"
      })

    render_submit(view, "save:recovery", %{"recovery" => attrs})
    render_submit(view, "save:recovery", %{"recovery" => attrs})
    assert {:ok, result} = EventDelivery.get(Principal.operator(), p["id"], delivery["id"])
    assert result["state"] == "cancelled"
    assert [action] = result["recovery_actions"]
    assert action["reason"] == "Operator stopped delivery"
    assert has_element?(view, "#delivery-detail", "Operator stopped delivery")
    assert has_element?(view, "#recovery-section[open]")

    view
    |> form("#project-form", project: %{description: "Still manageable after recovery"})
    |> render_submit()

    assert has_element?(view, "#recovery-form")
    {:ok, fresh, _} = live(conn, "/projects/#{p["id"]}")

    fresh
    |> element("button[phx-click='delivery'][phx-value-id='#{delivery["id"]}']")
    |> render_click()

    assert has_element?(fresh, "#delivery-detail", "Operator stopped delivery")
  end

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

  test "recovered form changes retain unknown submission identity until receipt reconciliation",
       %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")

    values =
      Map.merge(hidden(view, "task"), %{
        "title" => "Recovered task",
        "description" => "Unsure whether response arrived",
        "parent_task_id" => "",
        "required_capabilities" => ""
      })

    render_change(view, "change:task", %{"task" => values})
    assert hidden(view, "task")["command_id"] == values["command_id"]

    # Commit the exact request, then lose the LiveView before its caller observes a result.
    assert {:ok, _} =
             Tasks.create(
               Principal.operator(),
               p["id"],
               UI.attrs(values)
             )

    GenServer.stop(view.pid)
    {:ok, recovered, _} = live(conn, "/projects/#{p["id"]}")
    render_change(recovered, "change:task", %{"task" => values})
    assert has_element?(recovered, "#task-section[open]")
    assert hidden(recovered, "task")["command_id"] == values["command_id"]
    assert {:ok, %{"data" => [_]}} = Tasks.list(Principal.operator(), p["id"])
    render_submit(recovered, "save:task", %{"task" => values})
    assert {:ok, %{"data" => [_]}} = Tasks.list(Principal.operator(), p["id"])

    # A new edit after observed success is a deliberate new operation.
    render_change(recovered, "change:task", %{"task" => Map.put(values, "title", "Next task")})
    refute hidden(recovered, "task")["command_id"] == values["command_id"]
    recovered |> form("#task-form", task: %{title: "Next task"}) |> render_submit()
    assert {:ok, %{"data" => tasks}} = Tasks.list(Principal.operator(), p["id"])
    assert length(tasks) == 2
  end

  test "removed schedule selection is a visible error without losing the Project", %{conn: conn} do
    p = project_fixture()
    {:ok, view, _} = live(conn, "/projects/#{p["id"]}")
    html = render_click(view, "edit_schedule", %{"id" => Ecto.UUID.generate()})
    assert html =~ "Schedule not found"
    assert has_element?(view, "h1", p["name"])
  end

  test "delivery selection and unknown recovery identity survive reconnect without replay", %{
    conn: conn
  } do
    p = project_fixture()
    a = agent_fixture()
    member_fixture(p, a, ["manager"])
    {:ok, current} = Projects.get(Principal.operator(), p["id"])

    {:ok, _} =
      Events.configure(
        Principal.operator(),
        p["id"],
        command(%{"agent_id" => a["id"], "expected_version" => current["version"]})
      )

    {:ok, _} = Events.trigger(Principal.operator(), p["id"], command())
    {:ok, %{"data" => [delivery]}} = EventDelivery.list(Principal.operator(), p["id"])
    selected_path = "/projects/#{p["id"]}?delivery_id=#{delivery["id"]}"
    {:ok, view, _} = live(conn, selected_path)
    assert has_element?(view, "#delivery-detail", delivery["id"])

    values =
      Map.merge(hidden(view, "recovery"), %{
        "action" => "cancel",
        "reason" => "Recovery request whose response was lost",
        "evidence_ref" => "operator://recovery-evidence",
        "risk_acknowledged" => "false"
      })

    render_change(view, "change:recovery", %{"recovery" => values})

    assert {:ok, _} =
             EventDelivery.recover(
               Principal.operator(),
               p["id"],
               delivery["id"],
               UI.attrs(values)
             )

    GenServer.stop(view.pid)
    {:ok, recovered, _} = live(conn, selected_path)
    render_change(recovered, "change:recovery", %{"recovery" => values})
    assert has_element?(recovered, "#recovery-section[open]")

    assert hidden(recovered, "recovery") ==
             Map.take(values, ~w(command_id expected_version delivery_id))

    assert has_element?(recovered, "textarea[name='recovery[reason]']", values["reason"])

    assert has_element?(
             recovered,
             "input[name='recovery[evidence_ref]'][value='operator://recovery-evidence']"
           )

    assert {:ok, current} = EventDelivery.get(Principal.operator(), p["id"], delivery["id"])
    assert current["state"] == "cancelled"
    assert length(current["recovery_actions"]) == 1

    render_change(recovered, "change:recovery", %{
      "recovery" => Map.put(values, "action", "redeliver")
    })

    assert {:ok, %{"state" => "cancelled"}} =
             EventDelivery.get(Principal.operator(), p["id"], delivery["id"])

    render_submit(recovered, "save:recovery", %{"recovery" => values})
    assert {:ok, final} = EventDelivery.get(Principal.operator(), p["id"], delivery["id"])
    assert length(final["recovery_actions"]) == 1

    other = project_fixture()
    {:ok, wrong_scope, _} = live(conn, "/projects/#{other["id"]}?delivery_id=#{delivery["id"]}")
    refute has_element?(wrong_scope, "#recovery-form")
  end
end
