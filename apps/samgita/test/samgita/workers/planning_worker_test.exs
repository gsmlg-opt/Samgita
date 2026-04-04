defmodule Samgita.Workers.PlanningWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Projects
  alias Samgita.Workers.PlanningWorker

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
      {:ok, "mock response"}
    end)

    Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)

    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Planning Test",
        git_url: "https://github.com/test/planning-#{System.unique_integer([:positive])}"
      })

    %{project: project}
  end

  describe "perform/1" do
    test "research sub_phase creates research tasks", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{"project_id" => project.id, "sub_phase" => "research"}
               })

      tasks = Projects.list_tasks(project.id)
      assert tasks != []
      assert Enum.all?(tasks, fn t -> t.type == "research" end)
    end

    test "architecture sub_phase creates architecture tasks", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{"project_id" => project.id, "sub_phase" => "architecture"}
               })

      tasks = Projects.list_tasks(project.id)
      assert Enum.any?(tasks, fn t -> t.type == "architecture" end)
    end

    test "draft sub_phase creates draft tasks", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{"project_id" => project.id, "sub_phase" => "draft"}
               })

      tasks = Projects.list_tasks(project.id)
      assert Enum.any?(tasks, fn t -> t.type == "draft" end)
    end

    test "review sub_phase creates review tasks under max iterations", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "sub_phase" => "review",
                   "iteration" => 0
                 }
               })

      tasks = Projects.list_tasks(project.id)
      assert Enum.any?(tasks, fn t -> t.type == "review" end)
    end

    test "review sub_phase finalizes at max iterations", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "sub_phase" => "review",
                   "iteration" => 3
                 }
               })

      # No review tasks created at max iterations
      tasks = Projects.list_tasks(project.id)
      refute Enum.any?(tasks, fn t -> t.type == "review" end)
    end

    test "revise sub_phase creates revise tasks", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "sub_phase" => "revise",
                   "iteration" => 0
                 }
               })

      tasks = Projects.list_tasks(project.id)
      assert Enum.any?(tasks, fn t -> t.type == "revise" end)
    end

    test "entry point without sub_phase starts research", %{project: project} do
      assert :ok =
               PlanningWorker.perform(%Oban.Job{
                 args: %{"project_id" => project.id}
               })

      tasks = Projects.list_tasks(project.id)
      assert Enum.any?(tasks, fn t -> t.type == "research" end)
    end

    test "unknown sub_phase returns error", %{project: project} do
      assert {:error, "Unknown sub_phase: bogus"} =
               PlanningWorker.perform(%Oban.Job{
                 args: %{"project_id" => project.id, "sub_phase" => "bogus"}
               })
    end
  end
end
