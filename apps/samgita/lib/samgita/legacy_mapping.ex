defmodule Samgita.LegacyMapping do
  @moduledoc "Resumable, secret-free previews of preserved rows. No execution or automatic adoption."
  import Ecto.Query
  import Ecto.Changeset
  alias Ecto.Adapters.SQL
  alias Samgita.{Commands, Params, Repo, Repositories}
  alias Samgita.Domain.{MigrationMapping, ProjectRepository, Repository}
  @project_neutral ~w(description state version event_sequence migration_metadata)
  @task_neutral ~w(title description state version adopted execution_hold required_capabilities migration_metadata accepted_at fence_counter)
  @projects %{
    "pending" => "active",
    "running" => "active",
    "paused" => "paused",
    "completed" => "archived",
    "failed" => "paused"
  }
  @tasks %{
    "pending" => "open",
    "blocked" => "blocked",
    "assigned" => "blocked",
    "running" => "blocked",
    "completed" => "awaiting_review",
    "failed" => "failed",
    "dead_letter" => "failed",
    "skipped" => "cancelled"
  }

  def preview(principal) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)

      %{
        "data" => rows(),
        "historical_only" =>
          ~w(agent_runs artifacts memories snapshots prds chat_messages features notifications task_dependencies agent_messages sm_memories sm_prd_executions sm_thinking_chains),
        "artifact_scope_conflicts" => artifact_conflicts()
      }
    end)
  end

  def apply(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "migration.map", authority_write: true],
      fn ctx ->
        Commands.operator!(principal)

        if ctx.authority.owner != "none" || ctx.authority.admission_open,
          do: Commands.fail!(:execution_closed)

        data = Enum.map(rows(), &map_source!/1)

        %{"data" => data}
      end
    )
  end

  defp map_source!(row) do
    mapping =
      Repo.get_by(MigrationMapping,
        source_table: row["source_table"],
        source_id: row["source_id"]
      )

    cond do
      mapping && mapping.source_digest != row["source_digest"] ->
        changed_source!(row, mapping)

      mapping ->
        public(mapping)

      true ->
        target = if row["status"] == "ready", do: map_row!(row), else: nil
        if !target, do: mark_conflict!(row)

        mapping =
          %MigrationMapping{}
          |> change(
            source_table: row["source_table"],
            source_id: row["source_id"],
            source_digest: row["source_digest"],
            target_id: target,
            status: if(target, do: "mapped", else: "conflict"),
            details: row["details"]
          )
          |> Repo.insert!()

        public(mapping)
    end
  end

  defp changed_source!(row, mapping) do
    hold_source_change!(row)
    details = Map.put(mapping.details, "observed_source_digest", row["source_digest"])

    mapping =
      if mapping.status == "source_changed" && mapping.details == details do
        mapping
      else
        mapping
        |> change(status: "source_changed", details: details)
        |> Repo.update!()
      end

    public(mapping)
  end

  @doc false
  def validate_task!(task) do
    mapping = Repo.get_by(MigrationMapping, source_table: "tasks", source_id: task.id)

    if !mapping || mapping.status != "mapped",
      do: Commands.fail!(:conflict, %{reason: "mapping_review_required"})

    %{rows: [[source]]} =
      SQL.query!(
        Repo,
        "SELECT to_jsonb(t) - $1::text[] FROM tasks t WHERE id = $2::uuid",
        [@task_neutral, Ecto.UUID.dump!(task.id)]
      )

    if source_digest(source) != mapping.source_digest,
      do: Commands.fail!(:conflict, %{reason: "source_changed"})

    :ok
  end

  defp rows do
    projects = raw("projects", @project_neutral)
    tasks = raw("tasks", @task_neutral)
    tasks_by_id = Map.new(tasks, &{&1["id"], &1})

    edges =
      Repo.all(
        from e in "task_dependencies",
          select: {type(e.task_id, :string), type(e.depends_on_id, :string)}
      )

    graph =
      Map.new(tasks, fn task ->
        dependencies = for {id, dep} <- edges, id == task["id"], do: dep

        refs =
          ([task["parent_task_id"]] ++ (task["depends_on_ids"] || []) ++ dependencies)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {task["id"], refs}
      end)

    aliases = Enum.frequencies_by(projects, fn p -> Repositories.normalize(p["git_url"]) end)

    project_rows =
      Enum.filter(projects, &unmapped_or_recorded?("projects", &1["id"]))
      |> Enum.map(fn p ->
        url = Repositories.normalize(p["git_url"])

        details = %{
          "state" => @projects[p["status"]],
          "url_class" => url_class(url),
          "ambiguous_alias" => url != :invalid && Map.get(aliases, url, 0) > 1
        }

        mapping_row("projects", p, details, @projects[p["status"]] != nil)
      end)

    task_rows =
      Enum.filter(tasks, &unmapped_or_recorded?("tasks", &1["id"]))
      |> Enum.map(fn task ->
        refs = graph[task["id"]]
        edge_ids = for {id, dep} <- edges, id == task["id"], do: dep

        conflict = relationship_conflict?(task, refs, edge_ids, tasks_by_id, graph)

        details = %{
          "state" => @tasks[task["status"]],
          "relationship_conflict" => conflict,
          "requires_reconciliation" => task["status"] in ~w(assigned running),
          "legacy_status" => task["status"]
        }

        mapping_row("tasks", task, details, @tasks[task["status"]] != nil && !conflict)
      end)

    project_rows ++ task_rows
  end

  defp relationship_conflict?(task, refs, edge_ids, tasks_by_id, graph) do
    Enum.sort(edge_ids) != Enum.sort(task["depends_on_ids"] || []) ||
      Enum.any?(refs, fn ref ->
        foreign_reference?(tasks_by_id[ref], task)
      end) || cycle?(task["id"], graph, MapSet.new(), MapSet.new())
  end

  defp foreign_reference?(nil, _), do: true
  defp foreign_reference?(referenced, task), do: referenced["project_id"] != task["project_id"]

  defp raw(table, excluded) do
    %{rows: rows} =
      SQL.query!(
        Repo,
        "SELECT to_jsonb(t) - $1::text[] FROM " <> table <> " t ORDER BY id",
        [excluded]
      )

    Enum.map(rows, &hd/1)
  end

  defp unmapped_or_recorded?("projects", id),
    do:
      Repo.exists?(from p in "projects", where: p.id == type(^id, :binary_id) and is_nil(p.state)) ||
        Repo.exists?(
          from m in MigrationMapping, where: m.source_table == "projects" and m.source_id == ^id
        )

  defp unmapped_or_recorded?("tasks", id),
    do:
      Repo.exists?(from t in "tasks", where: t.id == type(^id, :binary_id) and is_nil(t.state)) ||
        Repo.exists?(
          from m in MigrationMapping, where: m.source_table == "tasks" and m.source_id == ^id
        )

  defp mapping_row(table, raw, details, known),
    do: %{
      "source_table" => table,
      "source_id" => raw["id"],
      "source_digest" => source_digest(raw),
      "status" => if(known, do: "ready", else: "conflict"),
      "details" => Map.put(details, "source_updated_at", raw["updated_at"])
    }

  defp source_digest(raw), do: Commands.digest(Map.delete(raw, "updated_at"))

  defp hold_source_change!(%{"source_table" => "tasks", "source_id" => id}) do
    Repo.update_all(from(t in "tasks", where: t.id == type(^id, :binary_id)),
      set: [execution_hold: true]
    )
  end

  defp hold_source_change!(_), do: :ok

  defp mark_conflict!(%{"source_table" => "tasks", "source_id" => id, "details" => details}) do
    Repo.update_all(from(t in "tasks", where: t.id == type(^id, :binary_id)),
      set: [migration_metadata: details, execution_hold: true]
    )
  end

  defp mark_conflict!(_), do: :ok

  defp map_row!(%{"source_table" => "projects", "source_id" => id, "details" => details}) do
    Repo.update_all(from(p in "projects", where: p.id == type(^id, :binary_id)),
      set: [state: details["state"], migration_metadata: details]
    )

    %{rows: [[url]]} =
      SQL.query!(Repo, "SELECT git_url FROM projects WHERE id = $1::uuid", [
        Ecto.UUID.dump!(id)
      ])

    if Repositories.normalize(url) != :invalid do
      repository =
        %Repository{}
        |> change(
          kind: if(details["url_class"] == "local", do: "local", else: "git"),
          verification: "unverified"
        )
        |> Repo.insert!()

      Repositories.add_alias!(repository.id, url, "legacy_git_url")

      %ProjectRepository{}
      |> change(project_id: id, repository_id: repository.id, primary: true)
      |> Repo.insert!()
    end

    id
  end

  defp map_row!(%{"source_table" => "tasks", "source_id" => id, "details" => details}) do
    hold = details["requires_reconciliation"] || details["relationship_conflict"]

    Repo.update_all(from(t in "tasks", where: t.id == type(^id, :binary_id)),
      set: [
        state: details["state"],
        adopted: false,
        execution_hold: hold,
        migration_metadata: details
      ]
    )

    id
  end

  defp cycle?(id, graph, path, done) do
    cond do
      MapSet.member?(path, id) ->
        true

      MapSet.member?(done, id) ->
        false

      true ->
        Enum.any?(
          Map.get(graph, id, []),
          &cycle?(&1, graph, MapSet.put(path, id), MapSet.put(done, id))
        )
    end
  end

  defp url_class(:invalid), do: "unresolved"
  defp url_class("local:" <> _), do: "local"
  defp url_class(_), do: "remote_unverified"

  defp public(mapping),
    do: %{
      "source_table" => mapping.source_table,
      "source_id" => mapping.source_id,
      "source_digest" => mapping.source_digest,
      "status" => mapping.status,
      "target_id" => mapping.target_id,
      "details" => mapping.details
    }

  defp artifact_conflicts do
    Repo.aggregate(
      from(a in "artifacts",
        join: t in "tasks",
        on: a.task_id == t.id,
        where: a.project_id != t.project_id
      ),
      :count
    )
  end
end
