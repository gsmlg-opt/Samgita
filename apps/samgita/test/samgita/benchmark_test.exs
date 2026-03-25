defmodule Samgita.BenchmarkTest do
  @moduledoc """
  Benchmark tests verifying PRD success criteria:
  - Task dispatch latency < 500ms
  - Memory retrieval (ETS cache hit) < 100ms
  - 10+ agents working simultaneously
  """
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Cache
  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Projects
  alias Samgita.Repo
  alias Samgita.Workers.AgentTaskWorker

  @tag :benchmark
  @task_dispatch_threshold_us 500_000
  @cache_hit_threshold_us 100_000

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
      {:ok, "mock response"}
    end)

    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Benchmark Test",
        git_url: "git@github.com:test/bench-#{System.unique_integer([:positive])}.git",
        status: :running
      })

    Cache.clear()

    on_exit(fn ->
      Sandbox.mode(Samgita.Repo, :manual)
    end)

    %{project: project}
  end

  defp create_task(project, attrs \\ %{}) do
    defaults = %{
      type: "eng-backend",
      project_id: project.id,
      status: :pending,
      payload: %{"action" => "build"}
    }

    %TaskSchema{}
    |> TaskSchema.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @tag :benchmark
  test "task dispatch latency < 500ms (Oban inline insert + execute)", %{project: project} do
    task = create_task(project)

    changeset =
      AgentTaskWorker.new(%{
        "task_id" => task.id,
        "project_id" => project.id,
        "agent_type" => "eng-backend"
      })

    {elapsed_us, _result} = :timer.tc(fn -> Oban.insert(changeset) end)

    assert elapsed_us < @task_dispatch_threshold_us,
           "Task dispatch took #{elapsed_us}us, expected < #{@task_dispatch_threshold_us}us (#{Float.round(elapsed_us / 1_000, 1)}ms vs 500ms limit)"
  end

  @tag :benchmark
  test "ETS cache hit retrieval < 100ms" do
    context = %{
      project_id: "bench-project",
      agents: ["eng-backend", "eng-frontend"],
      phase: :development,
      metadata: %{started_at: DateTime.utc_now()}
    }

    Cache.put("bench:project:context", context)

    {elapsed_us, result} = :timer.tc(fn -> Cache.get("bench:project:context") end)

    assert {:ok, ^context} = result

    assert elapsed_us < @cache_hit_threshold_us,
           "Cache hit took #{elapsed_us}us, expected < #{@cache_hit_threshold_us}us (#{Float.round(elapsed_us / 1_000, 1)}ms vs 100ms limit)"
  end

  @tag :benchmark
  test "ETS cache miss is also fast (baseline comparison)" do
    {miss_us, result} = :timer.tc(fn -> Cache.get("bench:nonexistent:key") end)

    assert result == :miss

    assert miss_us < @cache_hit_threshold_us,
           "Cache miss took #{miss_us}us, expected < #{@cache_hit_threshold_us}us"
  end

  @tag :benchmark
  test "10+ agents work simultaneously via Horde", %{project: project} do
    alias Samgita.Agent.Worker

    agent_types = [
      "eng-backend",
      "eng-frontend",
      "eng-database",
      "eng-api",
      "eng-qa",
      "eng-perf",
      "eng-infra",
      "ops-devops",
      "ops-sre",
      "ops-security",
      "data-eng",
      "data-analytics"
    ]

    # Spawn 12 agents into Horde.DynamicSupervisor
    agents =
      Enum.map(agent_types, fn type ->
        id = "bench-#{type}-#{System.unique_integer([:positive])}"

        {:ok, pid} =
          Horde.DynamicSupervisor.start_child(
            Samgita.AgentSupervisor,
            Worker.child_spec(id: id, agent_type: type, project_id: project.id)
          )

        {id, pid, type}
      end)

    # Verify all 12 are alive and registered
    assert length(agents) == 12

    for {_id, pid, _type} <- agents do
      assert Process.alive?(pid)
      assert {:idle, _} = Worker.get_state(pid)
    end

    # Assign tasks concurrently to all agents
    caller = self()

    tasks =
      Enum.map(agents, fn {id, pid, type} ->
        task = %{
          id: "bench-task-#{id}",
          type: "implement",
          payload: %{"description" => "Benchmark task for #{type}"}
        }

        Worker.assign_task(pid, task, caller)
        {id, task}
      end)

    # Collect completion messages from all 12 agents
    completed =
      Enum.reduce(1..12, [], fn _, acc ->
        receive do
          {:task_completed, task_id, result} -> [{task_id, result} | acc]
        after
          30_000 -> acc
        end
      end)

    assert length(completed) == 12,
           "Expected 12 completions, got #{length(completed)}"

    # Clean up
    for {_id, pid, _type} <- agents do
      if Process.alive?(pid), do: :gen_statem.stop(pid)
    end
  end
end
