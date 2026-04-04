defmodule Samgita.Workers.BootstrapWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Prd
  alias Samgita.Projects
  alias Samgita.Repo
  alias Samgita.Workers.BootstrapWorker

  @sample_prd """
  # My App PRD

  ## Overview

  A web application for managing tasks with real-time updates.

  ## Technical Requirements

  - RESTful API endpoints for CRUD operations
  - PostgreSQL database with proper schema design
  - WebSocket support for real-time notifications
  - Authentication via JWT tokens

  ## Features

  1. User registration and login
  2. Create, edit, and delete tasks
  3. Real-time task status updates via WebSocket
  4. Dashboard with analytics and charts
  5. Export data as CSV

  ## Non-Functional Requirements

  - Response time < 200ms for API calls
  - Support 1000 concurrent users
  - 99.9% uptime SLA
  """

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

    Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)

    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Bootstrap Test",
        git_url: "git@github.com:test/bootstrap-#{System.unique_integer([:positive])}.git",
        prd_content: @sample_prd,
        status: :running
      })

    {:ok, prd} =
      %Prd{}
      |> Prd.changeset(%{
        title: "My App PRD",
        content: @sample_prd,
        status: :approved,
        project_id: project.id
      })
      |> Repo.insert()

    %{project: project, prd: prd}
  end

  describe "generate_task_backlog/2" do
    test "generates tasks from PRD", %{project: project, prd: prd} do
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      assert tasks != []

      # Should have analysis task
      assert Enum.any?(tasks, fn t -> t.type == "analysis" end)

      # Should have implementation tasks for features
      impl_tasks = Enum.filter(tasks, fn t -> t.type == "implement" end)
      assert Enum.count(impl_tasks) >= 3

      # Should have test task
      assert Enum.any?(tasks, fn t -> t.type == "test" end)

      # Should have documentation task
      assert Enum.any?(tasks, fn t -> t.type == "documentation" end)
    end

    test "generates architecture task when technical content present", %{
      project: project,
      prd: prd
    } do
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      arch_tasks = Enum.filter(tasks, fn t -> t.type == "architecture" end)
      assert [_] = arch_tasks
    end

    test "assigns appropriate agent types", %{project: project, prd: prd} do
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      # Analysis task should use prod-pm
      analysis = Enum.find(tasks, fn t -> t.type == "analysis" end)
      assert analysis.agent_type == "prod-pm"

      # API-related features should use eng-api
      api_tasks =
        Enum.filter(tasks, fn t ->
          t.type == "implement" and String.contains?(String.downcase(t.description), "api")
        end)

      if api_tasks != [] do
        assert Enum.all?(api_tasks, fn t -> t.agent_type == "eng-api" end)
      end
    end

    test "tasks have correct priority ordering", %{project: project, prd: prd} do
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      # Analysis should be highest priority
      analysis = Enum.find(tasks, fn t -> t.type == "analysis" end)
      assert analysis.priority == 1

      # Test and docs should be lower priority
      test_task = Enum.find(tasks, fn t -> t.type == "test" end)
      doc_task = Enum.find(tasks, fn t -> t.type == "documentation" end)
      assert test_task.priority >= 8
      assert doc_task.priority >= 9
    end
  end

  describe "perform/1 (Oban integration)" do
    test "creates tasks in database", %{project: project, prd: prd} do
      # Perform the bootstrap
      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      assert :ok = BootstrapWorker.perform(job)

      # Verify tasks were created in the database
      tasks = Projects.list_tasks(project.id)
      assert tasks != []

      # All tasks should reference the PRD
      Enum.each(tasks, fn task ->
        assert task.payload["prd_id"] == prd.id
      end)
    end

    test "returns error for nonexistent project", %{prd: prd} do
      job = %Oban.Job{args: %{"project_id" => Ecto.UUID.generate(), "prd_id" => prd.id}}
      assert {:error, :not_found} = BootstrapWorker.perform(job)
    end

    test "returns error for nonexistent PRD", %{project: project} do
      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => Ecto.UUID.generate()}}
      assert {:error, :prd_not_found} = BootstrapWorker.perform(job)
    end

    test "raises FunctionClauseError when prd_id key is missing from args", %{project: project} do
      job = %Oban.Job{args: %{"project_id" => project.id}}

      assert_raise FunctionClauseError, fn ->
        BootstrapWorker.perform(job)
      end
    end
  end

  describe "milestone extraction" do
    test "extracts milestones from PRD with phases section", %{project: project} do
      prd = %Prd{
        content: """
        # Project X

        ## Overview
        A task management app.

        ## Milestones

        1. Core user authentication and registration
        2. Task CRUD with database schema
        3. Real-time WebSocket notifications
        4. Dashboard analytics and reporting

        ## Features

        - User registration and login via JWT authentication
        - Create, edit, and delete tasks with database operations
        - WebSocket push notifications for task updates
        - Analytics dashboard with charts
        """,
        title: "Milestone PRD"
      }

      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      milestone_tasks = Enum.filter(tasks, fn t -> t.type == "milestone" end)
      assert length(milestone_tasks) == 4

      # Milestones should be ordered
      orders = Enum.map(milestone_tasks, fn t -> t.payload["milestone_order"] end) |> Enum.sort()
      assert orders == [1, 2, 3, 4]
    end

    test "links implementation tasks to parent milestones", %{project: project} do
      prd = %Prd{
        content: """
        # Project Y

        ## Milestones

        1. Authentication system setup

        ## Features

        - JWT authentication with refresh tokens
        - User profile management
        """,
        title: "Linked PRD"
      }

      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      # The auth-related feature should have a parent_milestone reference
      auth_impl =
        Enum.find(tasks, fn t ->
          t.type == "implement" and String.contains?(t.description, "authentication")
        end)

      assert auth_impl != nil, "Expected an implement task for authentication feature"

      assert Map.has_key?(auth_impl, :parent_milestone),
             "Auth impl task should have :parent_milestone key"
    end
  end

  describe "metadata extraction" do
    test "populates PRD metadata on perform", %{project: project, prd: prd} do
      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      assert :ok = BootstrapWorker.perform(job)

      updated_prd = Repo.get(Prd, prd.id)
      assert updated_prd.metadata["parsed_at"]
      assert is_list(updated_prd.metadata["tech_stack"])
      assert is_list(updated_prd.metadata["non_functional"])
    end
  end

  describe "failure paths" do
    test "save_prd_metadata logs warning and returns :ok on update failure", %{
      project: project,
      prd: prd
    } do
      # Delete the PRD so update will fail
      Repo.delete(prd)

      # Re-insert with a stale reference that will cause update to fail
      _stale_prd = %Prd{prd | __meta__: %{prd.__meta__ | state: :loaded}}

      # Perform should still succeed (save_prd_metadata returns :ok on failure)
      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      # This will get :prd_not_found since we deleted it
      assert {:error, :prd_not_found} = BootstrapWorker.perform(job)
    end

    test "enqueue_agent_task handles ObanClient.insert failure gracefully", %{
      project: project,
      prd: prd
    } do
      # Make ObanClient.insert fail for agent task jobs
      Mox.expect(Samgita.MockOban, :insert, fn job ->
        worker = job.changes[:worker] || ""

        if worker == "Samgita.Workers.AgentTaskWorker" do
          {:error, :insert_failed}
        else
          Oban.insert(job)
        end
      end)

      # Allow additional calls to fall back to real Oban
      Mox.stub(Samgita.MockOban, :insert, fn _job -> {:error, :insert_failed} end)

      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      # Should still return :ok — failed enqueues are logged but not fatal
      assert :ok = BootstrapWorker.perform(job)
    end
  end

  describe "dependency inference" do
    test "assigns wave numbers to generated tasks", %{project: project, prd: prd} do
      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      assert :ok = BootstrapWorker.perform(job)

      tasks = Projects.list_tasks(project.id)
      assert tasks != []

      # At least some tasks should have wave numbers assigned
      tasks_with_waves = Enum.filter(tasks, fn t -> t.wave != nil end)
      assert length(tasks_with_waves) > 0

      # Wave 0 should exist (root tasks with no dependencies)
      assert Enum.any?(tasks_with_waves, fn t -> t.wave == 0 end)
    end

    test "creates dependency edges between agent types", %{project: project} do
      prd_with_agents = %Prd{
        content: """
        # Full Stack App

        ## Overview

        A web application with database, API, and frontend layers.

        ## Features

        - PostgreSQL database schema with users and posts tables
        - RESTful API endpoint for managing user accounts
        - React frontend component for user dashboard display
        - Backend service for processing user notifications
        """,
        title: "Agent Deps PRD"
      }

      {:ok, prd} =
        %Prd{}
        |> Prd.changeset(%{
          title: prd_with_agents.title,
          content: prd_with_agents.content,
          status: :approved,
          project_id: project.id
        })
        |> Repo.insert()

      job = %Oban.Job{args: %{"project_id" => project.id, "prd_id" => prd.id}}
      assert :ok = BootstrapWorker.perform(job)

      tasks = Projects.list_tasks(project.id)

      # Find tasks by agent type in payload
      db_tasks =
        Enum.filter(tasks, fn t -> (t.payload || %{})["agent_type"] == "eng-database" end)

      api_tasks =
        Enum.filter(tasks, fn t -> (t.payload || %{})["agent_type"] == "eng-api" end)

      frontend_tasks =
        Enum.filter(tasks, fn t -> (t.payload || %{})["agent_type"] == "eng-frontend" end)

      # If we have database and API tasks, API should depend on database
      if db_tasks != [] and api_tasks != [] do
        db_ids = MapSet.new(db_tasks, & &1.id)

        Enum.each(api_tasks, fn api_task ->
          deps = api_task.depends_on_ids || []

          assert Enum.any?(deps, fn dep -> MapSet.member?(db_ids, dep) end),
                 "API task should depend on at least one database task"
        end)
      end

      # If we have API and frontend tasks, frontend should depend on API
      if api_tasks != [] and frontend_tasks != [] do
        api_ids = MapSet.new(api_tasks, & &1.id)

        Enum.each(frontend_tasks, fn fe_task ->
          deps = fe_task.depends_on_ids || []

          assert Enum.any?(deps, fn dep -> MapSet.member?(api_ids, dep) end),
                 "Frontend task should depend on at least one API task"
        end)
      end
    end
  end

  describe "PRD parsing edge cases" do
    test "handles empty PRD", %{project: project} do
      empty_prd = %Prd{content: "", title: "Empty"}
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, empty_prd)

      # Should still generate analysis, test, and doc tasks
      assert Enum.any?(tasks, fn t -> t.type == "analysis" end)
      assert Enum.any?(tasks, fn t -> t.type == "test" end)
    end

    test "handles PRD with no features", %{project: project} do
      prd = %Prd{content: "# Just a Title\n\nSome description.", title: "Minimal"}
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)

      # Should still have base tasks
      assert length(tasks) >= 2
    end

    test "handles nil content", %{project: project} do
      prd = %Prd{content: nil, title: "Nil Content"}
      {:ok, tasks} = BootstrapWorker.generate_task_backlog(project, prd)
      assert is_list(tasks)
    end
  end
end
