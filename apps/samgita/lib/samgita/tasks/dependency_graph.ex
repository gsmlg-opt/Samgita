defmodule Samgita.Tasks.DependencyGraph do
  @moduledoc """
  Pure-function module for task dependency DAG operations.

  Builds a directed acyclic graph from tasks and their `depends_on_ids`,
  validates for cycles, computes wave-based execution order, and
  calculates critical path.
  """

  @type task_id :: binary()
  @type graph :: %{
          nodes: MapSet.t(task_id),
          edges: %{task_id => MapSet.t(task_id)},
          reverse: %{task_id => MapSet.t(task_id)},
          durations: %{task_id => non_neg_integer()}
        }

  @doc """
  Build a graph from a list of tasks.
  Each task must have `id` and `depends_on_ids` fields.
  """
  def build(tasks) do
    nodes = MapSet.new(tasks, & &1.id)

    edges =
      Map.new(tasks, fn task ->
        deps =
          (task.depends_on_ids || [])
          |> Enum.filter(&MapSet.member?(nodes, &1))

        {task.id, MapSet.new(deps)}
      end)

    reverse =
      Enum.reduce(tasks, Map.new(tasks, &{&1.id, MapSet.new()}), fn task, acc ->
        Enum.reduce(task.depends_on_ids || [], acc, &add_reverse_edge(&1, &2, nodes, task.id))
      end)

    durations = Map.new(tasks, &{&1.id, &1.estimated_duration_minutes || 0})

    %{nodes: nodes, edges: edges, reverse: reverse, durations: durations}
  end

  defp add_reverse_edge(dep_id, acc, nodes, task_id) do
    if MapSet.member?(nodes, dep_id) do
      Map.update!(acc, dep_id, &MapSet.put(&1, task_id))
    else
      acc
    end
  end

  @doc """
  Validate the graph has no cycles using Kahn's algorithm.
  Returns `{:ok, topologically_sorted_ids}` or `{:error, {:cycle, remaining_node_ids}}`.
  """
  def validate(graph) do
    in_degrees =
      Map.new(graph.nodes, fn node ->
        {node, MapSet.size(Map.get(graph.edges, node, MapSet.new()))}
      end)

    queue =
      in_degrees
      |> Enum.filter(fn {_, deg} -> deg == 0 end)
      |> Enum.map(&elem(&1, 0))

    kahn_loop(queue, in_degrees, graph.reverse, [])
  end

  defp kahn_loop([], in_degrees, _reverse, sorted) do
    remaining =
      in_degrees
      |> Enum.filter(fn {_, deg} -> deg > 0 end)
      |> Enum.map(&elem(&1, 0))

    if remaining == [] do
      {:ok, Enum.reverse(sorted)}
    else
      {:error, {:cycle, remaining}}
    end
  end

  defp kahn_loop([node | rest], in_degrees, reverse, sorted) do
    dependents = Map.get(reverse, node, MapSet.new())

    {updated_degrees, new_zero} =
      Enum.reduce(dependents, {in_degrees, []}, fn dep, {degrees, zeros} ->
        new_deg = degrees[dep] - 1
        degrees = Map.put(degrees, dep, new_deg)
        if new_deg == 0, do: {degrees, [dep | zeros]}, else: {degrees, zeros}
      end)

    # Mark as processed
    updated_degrees = Map.put(updated_degrees, node, -1)
    kahn_loop(rest ++ new_zero, updated_degrees, reverse, [node | sorted])
  end

  @doc """
  Compute wave numbers via topological sort.
  Wave 0 = tasks with no dependencies. Wave N = max(wave of dependencies) + 1.
  Returns `%{wave_number => [task_ids]}`.
  """
  def compute_waves(graph) do
    case validate(graph) do
      {:ok, _sorted} ->
        waves = compute_wave_numbers(graph)

        waves
        |> Enum.group_by(fn {_id, wave} -> wave end, fn {id, _wave} -> id end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_wave_numbers(graph) do
    Enum.map(graph.nodes, fn node ->
      wave = compute_node_wave(node, graph, %{})
      {node, wave}
    end)
  end

  defp compute_node_wave(node, graph, memo) do
    if Map.has_key?(memo, node) do
      memo[node]
    else
      deps = Map.get(graph.edges, node, MapSet.new())

      if MapSet.size(deps) == 0 do
        0
      else
        max_dep_wave =
          deps
          |> Enum.map(&compute_node_wave(&1, graph, memo))
          |> Enum.max()

        max_dep_wave + 1
      end
    end
  end

  @doc """
  Compute the critical path (longest chain by estimated duration).
  Returns `{path_as_list_of_task_ids, total_minutes}`.
  """
  def critical_path(graph) do
    case validate(graph) do
      {:ok, sorted} ->
        {distances, predecessors} =
          Enum.reduce(sorted, {%{}, %{}}, &compute_node_distance(&1, &2, graph))

        build_critical_path(distances, predecessors)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_node_distance(node, {dist, pred}, graph) do
    deps = Map.get(graph.edges, node, MapSet.new())

    if MapSet.size(deps) == 0 do
      {Map.put(dist, node, graph.durations[node] || 0), pred}
    else
      {best_pred, best_dist} =
        deps
        |> Enum.map(fn dep -> {dep, Map.get(dist, dep, 0)} end)
        |> Enum.max_by(&elem(&1, 1))

      total = best_dist + (graph.durations[node] || 0)
      {Map.put(dist, node, total), Map.put(pred, node, best_pred)}
    end
  end

  defp build_critical_path(distances, predecessors) do
    if map_size(distances) == 0 do
      {[], 0}
    else
      {end_node, max_dist} = Enum.max_by(distances, &elem(&1, 1))
      path = reconstruct_path(end_node, predecessors)
      {path, max_dist}
    end
  end

  defp reconstruct_path(node, predecessors) do
    reconstruct_path(node, predecessors, [])
  end

  defp reconstruct_path(node, predecessors, acc) do
    case Map.get(predecessors, node) do
      nil -> [node | acc]
      pred -> reconstruct_path(pred, predecessors, [node | acc])
    end
  end

  @doc """
  Given a set of completed task IDs, return task IDs that are now unblocked
  (all their hard dependencies are in the completed set).
  """
  def unblocked_tasks(graph, completed_ids) do
    completed_set = MapSet.new(completed_ids)

    graph.nodes
    |> Enum.filter(fn node ->
      not MapSet.member?(completed_set, node) and
        MapSet.subset?(Map.get(graph.edges, node, MapSet.new()), completed_set)
    end)
  end
end
