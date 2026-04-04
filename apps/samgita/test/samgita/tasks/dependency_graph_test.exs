defmodule Samgita.Tasks.DependencyGraphTest do
  use ExUnit.Case, async: true

  alias Samgita.Tasks.DependencyGraph

  defp make_task(id, deps \\ [], duration \\ 10) do
    %{id: id, depends_on_ids: deps, estimated_duration_minutes: duration}
  end

  describe "build/1" do
    test "builds graph from tasks with no dependencies" do
      tasks = [make_task("a"), make_task("b")]
      graph = DependencyGraph.build(tasks)
      assert MapSet.size(graph.nodes) == 2
    end

    test "builds graph with dependencies" do
      tasks = [make_task("a"), make_task("b", ["a"])]
      graph = DependencyGraph.build(tasks)
      assert MapSet.member?(graph.edges["b"], "a")
    end

    test "ignores dependencies on unknown nodes" do
      tasks = [make_task("a", ["unknown"])]
      graph = DependencyGraph.build(tasks)
      assert MapSet.size(graph.edges["a"]) == 0
    end
  end

  describe "validate/1" do
    test "valid linear chain" do
      tasks = [make_task("a"), make_task("b", ["a"]), make_task("c", ["b"])]
      graph = DependencyGraph.build(tasks)
      assert {:ok, sorted} = DependencyGraph.validate(graph)
      assert length(sorted) == 3
      assert Enum.find_index(sorted, &(&1 == "a")) < Enum.find_index(sorted, &(&1 == "b"))
      assert Enum.find_index(sorted, &(&1 == "b")) < Enum.find_index(sorted, &(&1 == "c"))
    end

    test "valid diamond dependency" do
      tasks = [
        make_task("a"),
        make_task("b", ["a"]),
        make_task("c", ["a"]),
        make_task("d", ["b", "c"])
      ]

      graph = DependencyGraph.build(tasks)
      assert {:ok, sorted} = DependencyGraph.validate(graph)
      assert length(sorted) == 4
      assert hd(sorted) == "a"
      assert List.last(sorted) == "d"
    end

    test "detects simple cycle" do
      tasks = [make_task("a", ["b"]), make_task("b", ["a"])]
      graph = DependencyGraph.build(tasks)
      assert {:error, {:cycle, nodes}} = DependencyGraph.validate(graph)
      assert length(nodes) == 2
    end

    test "detects cycle in larger graph" do
      tasks = [
        make_task("a"),
        make_task("b", ["a"]),
        make_task("c", ["b"]),
        make_task("b2", ["c"])
      ]

      # b2 depends on c, c depends on b, but b doesn't depend on b2 — no cycle
      graph = DependencyGraph.build(tasks)
      assert {:ok, _sorted} = DependencyGraph.validate(graph)
    end

    test "empty graph is valid" do
      graph = DependencyGraph.build([])
      assert {:ok, []} = DependencyGraph.validate(graph)
    end

    test "single node is valid" do
      graph = DependencyGraph.build([make_task("a")])
      assert {:ok, ["a"]} = DependencyGraph.validate(graph)
    end

    test "disjoint subgraphs" do
      tasks = [make_task("a"), make_task("b", ["a"]), make_task("x"), make_task("y", ["x"])]
      graph = DependencyGraph.build(tasks)
      assert {:ok, sorted} = DependencyGraph.validate(graph)
      assert length(sorted) == 4
    end
  end

  describe "compute_waves/1" do
    test "single wave for independent tasks" do
      tasks = [make_task("a"), make_task("b"), make_task("c")]
      graph = DependencyGraph.build(tasks)
      waves = DependencyGraph.compute_waves(graph)
      assert is_map(waves)
      assert Map.keys(waves) == [0]
      assert length(waves[0]) == 3
    end

    test "two waves for linear chain" do
      tasks = [make_task("a"), make_task("b", ["a"])]
      graph = DependencyGraph.build(tasks)
      waves = DependencyGraph.compute_waves(graph)
      assert waves[0] == ["a"]
      assert waves[1] == ["b"]
    end

    test "diamond produces 3 waves" do
      tasks = [
        make_task("a"),
        make_task("b", ["a"]),
        make_task("c", ["a"]),
        make_task("d", ["b", "c"])
      ]

      graph = DependencyGraph.build(tasks)
      waves = DependencyGraph.compute_waves(graph)
      assert "a" in waves[0]
      assert "b" in waves[1]
      assert "c" in waves[1]
      assert "d" in waves[2]
    end

    test "returns error for cyclic graph" do
      tasks = [make_task("a", ["b"]), make_task("b", ["a"])]
      graph = DependencyGraph.build(tasks)
      assert {:error, {:cycle, _}} = DependencyGraph.compute_waves(graph)
    end
  end

  describe "critical_path/1" do
    test "single task" do
      graph = DependencyGraph.build([make_task("a", [], 10)])
      assert {["a"], 10} = DependencyGraph.critical_path(graph)
    end

    test "linear chain sums durations" do
      tasks = [make_task("a", [], 10), make_task("b", ["a"], 20), make_task("c", ["b"], 5)]
      graph = DependencyGraph.build(tasks)
      assert {path, 35} = DependencyGraph.critical_path(graph)
      assert path == ["a", "b", "c"]
    end

    test "diamond picks longest branch" do
      tasks = [
        make_task("a", [], 10),
        make_task("b", ["a"], 20),
        make_task("c", ["a"], 5),
        make_task("d", ["b", "c"], 10)
      ]

      graph = DependencyGraph.build(tasks)
      {path, total} = DependencyGraph.critical_path(graph)
      # a(10) + b(20) + d(10)
      assert total == 40
      assert "a" in path
      assert "b" in path
      assert "d" in path
    end

    test "empty graph" do
      graph = DependencyGraph.build([])
      assert {[], 0} = DependencyGraph.critical_path(graph)
    end
  end

  describe "unblocked_tasks/2" do
    test "root tasks are unblocked when nothing completed" do
      tasks = [make_task("a"), make_task("b", ["a"])]
      graph = DependencyGraph.build(tasks)
      assert DependencyGraph.unblocked_tasks(graph, []) == ["a"]
    end

    test "dependent unblocked after dependency completes" do
      tasks = [make_task("a"), make_task("b", ["a"]), make_task("c", ["a", "b"])]
      graph = DependencyGraph.build(tasks)
      assert DependencyGraph.unblocked_tasks(graph, ["a"]) == ["b"]
    end

    test "task with multiple deps unblocked only when all complete" do
      tasks = [make_task("a"), make_task("b"), make_task("c", ["a", "b"])]
      graph = DependencyGraph.build(tasks)
      assert "c" not in DependencyGraph.unblocked_tasks(graph, ["a"])
      assert "c" in DependencyGraph.unblocked_tasks(graph, ["a", "b"])
    end

    test "completed tasks not included in unblocked" do
      tasks = [make_task("a"), make_task("b")]
      graph = DependencyGraph.build(tasks)
      assert DependencyGraph.unblocked_tasks(graph, ["a"]) == ["b"]
    end
  end
end
