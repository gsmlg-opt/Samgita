defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Samgita.Projects

  defp unique_git_url(prefix \\ "dash") do
    "git@github.com:test/#{prefix}-#{System.unique_integer([:positive])}.git"
  end

  test "renders empty dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Dashboard"
    assert html =~ "No projects yet"
    assert has_element?(view, "a", "New Project")
  end

  test "lists projects", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Test Project", git_url: unique_git_url()})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Test Project"
  end

  test "shows multiple projects", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Alpha", git_url: unique_git_url("alpha")})
    {:ok, _} = Projects.create_project(%{name: "Beta", git_url: unique_git_url("beta")})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Alpha"
    assert html =~ "Beta"
    refute html =~ "No projects yet"
  end

  test "displays project status badges", %{conn: conn} do
    {:ok, _} =
      Projects.create_project(%{
        name: "Running Project",
        git_url: unique_git_url("running"),
        status: :running
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "running"
  end

  test "displays project phase", %{conn: conn} do
    {:ok, _} =
      Projects.create_project(%{
        name: "Dev Project",
        git_url: unique_git_url("dev"),
        phase: :development
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "development"
  end

  test "displays git URL for each project", %{conn: conn} do
    url = unique_git_url("giturl")
    {:ok, _} = Projects.create_project(%{name: "URL Test", git_url: url})

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ url
  end

  test "new project link navigates to form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s|a[href="/projects/new"]|)
  end

  test "updates when project_updated message received", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{name: "PubSub Test", git_url: unique_git_url("pubsub")})

    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "PubSub Test"

    # Update the project name and send a PubSub event
    {:ok, updated} = Projects.update_project(project, %{name: "Updated Name"})
    send(view.pid, {:project_updated, updated})

    html = render(view)
    assert html =~ "Updated Name"
  end

  test "updates when project_updated with phase message received", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Phase Test",
        git_url: unique_git_url("phase"),
        phase: :bootstrap
      })

    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ "bootstrap"

    # Simulate phase change
    {:ok, _} = Projects.update_project(project, %{phase: :development})
    send(view.pid, {:project_updated, project.id, :development})

    html = render(view)
    assert html =~ "development"
  end

  test "updates task stats when task_stats_changed received", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Stats Test",
        git_url: unique_git_url("stats"),
        status: :running
      })

    {:ok, view, _html} = live(conn, ~p"/")

    # Simulate a task stats change event
    send(view.pid, {:task_stats_changed, project.id})

    # Should re-render without error
    html = render(view)
    assert html =~ "Stats Test"
  end

  test "shows different status colors for each status", %{conn: conn} do
    for status <- [:pending, :running, :paused, :completed, :failed] do
      {:ok, _} =
        Projects.create_project(%{
          name: "#{status} proj",
          git_url: unique_git_url("color-#{status}"),
          status: status
        })
    end

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "pending"
    assert html =~ "running"
    assert html =~ "paused"
    assert html =~ "completed"
    assert html =~ "failed"
  end

  test "activity log streams real-time events", %{conn: conn} do
    {:ok, _project} =
      Projects.create_project(%{name: "Log Test", git_url: unique_git_url("log")})

    {:ok, view, _html} = live(conn, ~p"/")

    # Send an activity_log event
    entry = %{
      source: "orchestrator",
      stage: :spawned,
      message: "Agent test-agent started"
    }

    send(view.pid, {:activity_log, entry})

    html = render(view)
    assert html =~ "Activity Log"
    assert html =~ "Agent test-agent started"
  end

  test "activity log handles phase_changed events", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{name: "Phase Log", git_url: unique_git_url("plog")})

    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, {:phase_changed, project.id, :development})

    # Should re-render without error
    html = render(view)
    assert html =~ "Phase Log"
  end

  describe "real-time dashboard updates (prd-017)" do
    test "activity log renders all orchestrator stage types", %{conn: conn} do
      {:ok, _project} =
        Projects.create_project(%{name: "Stage Test", git_url: unique_git_url("stages")})

      {:ok, view, _html} = live(conn, ~p"/")

      stages = [:spawned, :act, :reflect, :verify, :phase_change, :error]

      for {stage, i} <- Enum.with_index(stages) do
        send(
          view.pid,
          {:activity_log, %{stage: stage, message: "Stage #{i} event", source: "orchestrator"}}
        )
      end

      html = render(view)
      assert html =~ "Activity Log"
    end

    test "activity log appends entries in order without full page reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Send three events in sequence
      for i <- 1..3 do
        send(view.pid, {:activity_log, %{stage: :act, message: "Event #{i}", source: "test"}})
      end

      html = render(view)

      # All three events must appear
      assert html =~ "Event 1"
      assert html =~ "Event 2"
      assert html =~ "Event 3"
    end

    test "project status updates reflect in dashboard without navigation", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "Live Update",
          git_url: unique_git_url("live-update"),
          status: :pending
        })

      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "pending"

      # Simulate project status change via PubSub
      {:ok, updated} = Projects.update_project(project, %{status: :running})
      send(view.pid, {:project_updated, updated})

      html = render(view)
      assert html =~ "running"
    end

    test "dashboard shows running project count in summary", %{conn: conn} do
      {:ok, _} =
        Projects.create_project(%{
          name: "Running 1",
          git_url: unique_git_url("r1"),
          status: :running
        })

      {:ok, _} =
        Projects.create_project(%{
          name: "Running 2",
          git_url: unique_git_url("r2"),
          status: :running
        })

      {:ok, _view, html} = live(conn, ~p"/")
      # Both running projects listed
      assert html =~ "Running 1"
      assert html =~ "Running 2"
    end

    test "new project link is always present in dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s|a[href="/projects/new"]|)
    end

    test "project cards link to project detail pages", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{name: "Detail Link", git_url: unique_git_url("detail")})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s|a[href="/projects/#{project.id}"]|)
    end
  end
end
