defmodule Samgita.BenchmarkTest do
  @moduledoc """
  Benchmark tests verifying PRD success criteria:
  - Task dispatch latency < 500ms
  - Memory retrieval (ETS cache hit) < 100ms
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
end
