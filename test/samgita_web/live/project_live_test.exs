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

  test "renders project detail", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Live Test"
    assert html =~ "bootstrap"
    assert html =~ "Phase Progress"
  end

  test "shows start button for pending project", %{conn: conn} do
    project = create_project(%{status: :pending})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Start")
  end

  test "redirects on 404", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/projects/#{Ecto.UUID.generate()}")
  end

  test "shows pause button for running project", %{conn: conn} do
    project = create_project(%{status: :running})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Pause")
  end

  test "shows resume button for paused project", %{conn: conn} do
    project = create_project(%{status: :paused})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    assert has_element?(view, "button", "Resume")
  end

  test "displays task count section", %{conn: conn} do
    project = create_project()
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Tasks"
    assert html =~ "No tasks yet"
  end

  test "start transitions project to running", %{conn: conn} do
    project = create_project(%{status: :pending})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "start")
    assert html =~ "running"
    assert html =~ "Pause"
  end

  test "pause transitions running project to paused", %{conn: conn} do
    project = create_project(%{status: :running})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "pause")
    assert html =~ "paused"
    assert html =~ "Resume"
  end

  test "resume transitions paused project to running", %{conn: conn} do
    project = create_project(%{status: :paused})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    html = render_click(view, "resume")
    assert html =~ "running"
    assert html =~ "Pause"
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

  test "shows status section with correct fields", %{conn: conn} do
    project = create_project(%{status: :running})
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Status"
    assert html =~ "Phase"
    assert html =~ "Agents"
    assert html =~ "Tasks"
  end

  test "displays phase progress bar", %{conn: conn} do
    project = create_project(%{phase: :development})
    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "Phase Progress"
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

  test "handles agent_state_changed message", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-1", :act})

    html = render(view)
    assert html =~ "agent-1"
    assert html =~ "act"
  end

  test "handles agent_spawned message", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_spawned, "agent-new", "eng-backend"})

    html = render(view)
    assert html =~ "agent-new"
  end

  test "handles task_completed message refreshes tasks", %{conn: conn} do
    project = create_project()

    {:ok, task} =
      Projects.create_task(project.id, %{
        type: "test_task",
        priority: 5,
        payload: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    send(view.pid, {:task_completed, task})

    html = render(view)
    assert html =~ "test_task"
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
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-a", :reason})
    send(view.pid, {:agent_state_changed, "agent-b", :verify})

    html = render(view)
    assert html =~ "agent-a"
    assert html =~ "agent-b"
    assert html =~ "Active Agents"
  end

  test "agent state change updates existing agent", %{conn: conn} do
    project = create_project()
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")

    send(view.pid, {:agent_state_changed, "agent-x", :reason})
    html = render(view)
    assert html =~ "reason"

    send(view.pid, {:agent_state_changed, "agent-x", :act})
    html = render(view)
    assert html =~ "act"
  end

  test "shows tasks when they exist", %{conn: conn} do
    project = create_project()

    {:ok, _} =
      Projects.create_task(project.id, %{
        type: "build",
        priority: 1,
        payload: %{}
      })

    {:ok, _view, html} = live(conn, ~p"/projects/#{project}")
    assert html =~ "build"
    assert html =~ "Priority: 1"
    refute html =~ "No tasks yet"
  end

  test "does not show start button for failed project", %{conn: conn} do
    project = create_project(%{status: :failed})
    {:ok, view, _html} = live(conn, ~p"/projects/#{project}")
    refute has_element?(view, "button", "Start")
    refute has_element?(view, "button", "Pause")
    refute has_element?(view, "button", "Resume")
  end
end
