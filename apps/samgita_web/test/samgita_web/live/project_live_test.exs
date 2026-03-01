defmodule SamgitaWeb.ProjectLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  defp create_project(attrs \\ %{}) do
    defaults = %{
      name: "Live Test",
      git_url: "git@github.com:test/live-#{System.unique_integer([:positive])}.git",
      prd_content: "# Test PRD"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end

  defp create_prd(project, attrs \\ %{}) do
    defaults = %{
      project_id: project.id,
      title: "Test PRD",
      content: "# Test Content",
      status: :approved
    }

    {:ok, prd} = Samgita.Prds.create_prd(Map.merge(defaults, attrs))
    prd
  end

  defp setup_running_project_with_prd(attrs \\ %{}) do
    project = create_project(Map.merge(%{status: :running}, attrs))
    prd = create_prd(project, %{status: :in_progress})
    {:ok, project} = Projects.update_project(project, %{active_prd_id: prd.id})
    {project, prd}
  end

  test "renders project detail", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Live Test"
    assert html =~ "bootstrap"
    assert html =~ "perpetual"
  end

  test "shows start button for pending project with selected PRD", %{conn: conn} do
    project = create_project(%{status: :pending})
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    # Start button not visible without selecting a PRD
    refute has_element?(view, "button", "Start")

    # Select the PRD
    render_click(view, "select_prd", %{"id" => prd.id})
    assert has_element?(view, "button", "Start")
  end

  test "redirects on 404", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/projects/#{Ecto.UUID.generate()}")
  end

  test "shows pause and stop buttons for running project with active PRD", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Pause")
    assert has_element?(view, "button", "Stop")
  end

  test "shows resume button for paused project with active PRD", %{conn: conn} do
    project = create_project(%{status: :paused})
    prd = create_prd(project, %{status: :in_progress})
    {:ok, project} = Projects.update_project(project, %{active_prd_id: prd.id})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Resume")
  end

  test "shows empty state when no PRD selected", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Select a PRD to view its execution workspace"
  end

  test "selecting PRD shows execution workspace", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    html = render_click(view, "select_prd", %{"id" => prd.id})

    assert html =~ prd.title
    assert html =~ "Tasks"
    assert html =~ "Activity Log"
  end

  test "start transitions project to running", %{conn: conn} do
    project = create_project(%{status: :pending})
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    render_click(view, "select_prd", %{"id" => prd.id})
    html = render_click(view, "start")
    assert html =~ "running"
    assert html =~ "Pause"
  end

  test "pause transitions running project to paused", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "pause")
    assert html =~ "paused"
    assert html =~ "Resume"
  end

  test "resume transitions paused project to running", %{conn: conn} do
    project = create_project(%{status: :paused})
    prd = create_prd(project, %{status: :in_progress})
    {:ok, _project} = Projects.update_project(project, %{active_prd_id: prd.id})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "resume")
    assert html =~ "running"
    assert html =~ "Pause"
  end

  test "stop transitions running project to completed", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    render_click(view, "stop")
    html = render(view)
    assert html =~ "completed"
    refute has_element?(view, "button", "Pause")
    refute has_element?(view, "button", "Stop")
  end

  test "restart restarts running project", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "restart")
    assert html =~ "running"
  end

  test "terminate marks project as failed", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    render_click(view, "terminate")
    html = render(view)
    assert html =~ "failed"
  end

  test "displays dashboard link", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, ~s|a[href="/"]|, "Dashboard")
  end

  test "shows git URL", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ project.git_url
  end

  test "displays phase progress bar", %{conn: conn} do
    project = create_project(%{phase: :development})
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "bootstrap"
    assert html =~ "perpetual"
  end

  test "handles phase_changed message", %{conn: conn} do
    project = create_project(%{phase: :bootstrap})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:phase_changed, project.id, :development})

    html = render(view)
    assert html =~ "development"
  end

  test "handles agent_state_changed message shows active agents", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-1", :act})

    html = render(view)
    assert html =~ "agent-1"
    assert html =~ "act"
  end

  test "handles agent_spawned message", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_spawned, "agent-new", "eng-backend"})

    html = render(view)
    assert html =~ "agent-new"
  end

  test "handles task_completed message", %{conn: conn} do
    project = create_project()

    {:ok, task} =
      Projects.create_task(project.id, %{
        type: "test_task",
        priority: 5,
        payload: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    send(view.pid, {:task_completed, task})

    # Should not crash
    html = render(view)
    assert html =~ project.name
  end

  test "handles unknown messages gracefully", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:unknown_event, "data"})

    # Should not crash
    html = render(view)
    assert html =~ project.name
  end

  test "multiple agent state changes update grid", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-a", :reason})
    send(view.pid, {:agent_state_changed, "agent-b", :verify})

    html = render(view)
    assert html =~ "agent-a"
    assert html =~ "agent-b"
    assert html =~ "Active Agents"
  end

  test "agent state change updates existing agent", %{conn: conn} do
    {project, _prd} = setup_running_project_with_prd()

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-x", :reason})
    html = render(view)
    assert html =~ "reason"

    send(view.pid, {:agent_state_changed, "agent-x", :act})
    html = render(view)
    assert html =~ "act"
  end

  test "failed project can show start button with PRD selected", %{conn: conn} do
    project = create_project(%{status: :failed})
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    refute has_element?(view, "button", "Start")

    render_click(view, "select_prd", %{"id" => prd.id})
    assert has_element?(view, "button", "Start")
  end

  test "auto-selects PRD from active_prd_id on mount", %{conn: conn} do
    {project, prd} = setup_running_project_with_prd()

    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ prd.title
    assert html =~ "Activity Log"
  end

  test "shows activity log section when PRD selected", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    html = render_click(view, "select_prd", %{"id" => prd.id})
    assert html =~ "Activity Log"
    assert html =~ "0 events"
    assert html =~ "No activity yet"
  end

  test "activity log renders entries", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    render_click(view, "select_prd", %{"id" => prd.id})

    entry = %{
      id: System.unique_integer([:positive, :monotonic]),
      timestamp: DateTime.utc_now(),
      source: :agent,
      source_id: "test-agent",
      stage: :act,
      message: "Executing test task",
      output: nil
    }

    send(view.pid, {:activity_log, entry})
    html = render(view)

    assert html =~ "test-agent"
    assert html =~ "Executing test task"
    assert html =~ "1 events"
  end

  test "activity log shows expandable output", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    render_click(view, "select_prd", %{"id" => prd.id})

    entry = %{
      id: System.unique_integer([:positive, :monotonic]),
      timestamp: DateTime.utc_now(),
      source: :agent,
      source_id: "agent-1",
      stage: :act,
      message: "Claude returned result",
      output: "Some CLI output here"
    }

    send(view.pid, {:activity_log, entry})
    html = render(view)

    assert html =~ "output"
    assert html =~ "Some CLI output here"
  end

  test "activity log count increments with multiple entries", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    render_click(view, "select_prd", %{"id" => prd.id})

    for i <- 1..3 do
      entry = %{
        id: System.unique_integer([:positive, :monotonic]),
        timestamp: DateTime.utc_now(),
        source: :orchestrator,
        source_id: "orchestrator",
        stage: :phase_change,
        message: "Event #{i}",
        output: nil
      }

      send(view.pid, {:activity_log, entry})
    end

    html = render(view)
    assert html =~ "3 events"
  end

  test "delete PRD clears selection if deleted PRD was selected", %{conn: conn} do
    project = create_project()
    prd = create_prd(project)

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    render_click(view, "select_prd", %{"id" => prd.id})

    render_click(view, "delete_prd", %{"id" => prd.id})
    html = render(view)
    assert html =~ "Select a PRD to view its execution workspace"
  end

  test "PRD list shows PRD cards", %{conn: conn} do
    project = create_project()
    _prd = create_prd(project, %{title: "My Feature PRD"})

    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "My Feature PRD"
    assert html =~ "approved"
  end
end
