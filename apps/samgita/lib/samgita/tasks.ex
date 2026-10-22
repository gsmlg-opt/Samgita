defmodule Samgita.Tasks do
  @moduledoc "Authorized logical work, explicit review and acceptance, and output references."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, LegacyMapping, Params, Projection, Repo, TaskTransitions}
  alias Samgita.Domain.{ArtifactReference, DecisionRecord, Task, TaskAttempt}
  @read_roles ~w(observer worker manager reviewer)

  def create(principal, project_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.create", roles: ["manager"]],
      fn ctx ->
        writable_project!(ctx)
        parent!(project_id, attrs["parent_task_id"], nil)

        task = %Task{
          project_id: project_id,
          type: "task",
          status: "pending",
          state: "open",
          adopted: true
        }

        task = task |> editable(attrs) |> validate_required([:title]) |> Commands.insert!()
        Events.append!(project_id, "task.created", ctx, "task", task.id, %{}, current: task)
        Projection.task(task)
      end
    )
  end

  def update(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.update:" <> to_string(id), roles: ["manager"]],
      fn ctx ->
        writable_project!(ctx)
        task = lock!(project_id, id)
        Commands.expect!(task, attrs)
        preserve_parent!(task, attrs)
        previous = task
        if task.state in ~w(in_progress accepted), do: Commands.fail!(:invalid_transition)

        if Repo.exists?(
             from a in TaskAttempt,
               where: a.task_id == ^task.id and a.state in ["leased", "running"]
           ),
           do: Commands.fail!(:invalid_transition)

        if Map.has_key?(attrs, "parent_task_id"),
          do: parent!(project_id, attrs["parent_task_id"], task.id)

        task =
          task
          |> editable(attrs)
          |> validate_required([:title])
          |> put_change(:version, task.version + 1)
          |> Commands.update!()

        Events.append!(project_id, "task.updated", ctx, "task", task.id, %{},
          previous: previous,
          current: task
        )

        Projection.task(task)
      end
    )
  end

  def get(principal, project_id, id) do
    Commands.read(principal, project_id, @read_roles, fn _ctx ->
      task = scoped!(project_id, id)

      decisions =
        Repo.all(
          from d in DecisionRecord,
            where: d.task_id == ^task.id,
            order_by: [desc: d.inserted_at],
            limit: 100
        )

      artifacts =
        Repo.all(
          from a in ArtifactReference,
            where: a.task_id == ^task.id,
            order_by: [desc: a.inserted_at],
            limit: 100
        )

      Projection.task(task)
      |> Map.put("decisions", Enum.map(decisions, &Projection.decision/1))
      |> Map.put("artifact_references", Enum.map(artifacts, &Projection.artifact/1))
    end)
  end

  def list(principal, project_id, params \\ %{}) do
    {limit, offset} = Params.page(params)

    Commands.read(principal, project_id, @read_roles, fn _ctx ->
      tasks =
        Repo.all(
          from t in Task,
            where: t.project_id == ^project_id,
            order_by: [desc: t.inserted_at, asc: t.id],
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(tasks, &Projection.task/1), "limit" => limit, "offset" => offset}
    end)
  end

  def transition(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)
    agent_ids = ownership_agents(project_id, id)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.transition:" <> to_string(id), roles: ["manager"], agent_ids: agent_ids],
      fn ctx ->
        writable_project!(ctx)
        ensure_discovered!(ctx, id, agent_ids)
        task = lock!(project_id, id)
        Commands.expect!(task, attrs)

        previous = task

        case TaskTransitions.validate(task.state, attrs["state"]) do
          :ok -> :ok
          {:error, code} -> Commands.fail!(String.to_existing_atom(code))
        end

        active =
          Repo.all(
            from a in TaskAttempt,
              where: a.task_id == ^task.id and a.state in ["leased", "running"],
              order_by: a.id,
              lock: "FOR UPDATE"
          )

        invalidating = attrs["state"] in ~w(open cancelled) && active != []

        if invalidating do
          for attempt <- active do
            closed =
              attempt
              |> change(
                state: "cancelled",
                terminal_at: DateTime.utc_now(),
                version: attempt.version + 1
              )
              |> Commands.update!()

            Events.append!(
              project_id,
              "attempt.closed",
              ctx,
              "attempt",
              attempt.id,
              %{
                "task_id" => task.id,
                "reason" => "management_transition"
              },
              previous: attempt,
              current: closed
            )
          end
        end

        # Reopening is a management action; it cannot resolve a remote effect.
        task =
          task
          |> change(
            state: attrs["state"],
            version: task.version + 1,
            accepted_at: nil,
            execution_hold: task.execution_hold || invalidating,
            fence_counter: task.fence_counter + if(invalidating, do: 1, else: 0)
          )
          |> Commands.update!()

        Events.append!(
          project_id,
          "task.transitioned",
          ctx,
          "task",
          task.id,
          %{
            "state" => task.state
          },
          previous: previous,
          current: task
        )

        Projection.task(task)
      end
    )
  end

  def adopt(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)
    agent_ids = ownership_agents(project_id, id)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.adopt:" <> to_string(id), roles: ["manager"], agent_ids: agent_ids],
      fn ctx ->
        writable_project!(ctx)
        ensure_discovered!(ctx, id, agent_ids)
        task = lock!(project_id, id)
        Commands.expect!(task, attrs)
        if task.adopted, do: Commands.fail!(:conflict)
        previous = task
        LegacyMapping.validate_task!(task)
        preserve_parent!(task, attrs)

        if attrs["effects_resolved"] != true || attrs["content_reviewed"] != true ||
             attrs["relationships_reviewed"] != true || !nonempty?(attrs["evidence_ref"]),
           do: Commands.fail!(:invalid)

        if task.state not in ~w(open blocked awaiting_review failed cancelled),
          do: Commands.fail!(:invalid_transition)

        if task.execution_hold, do: Commands.operator!(ctx.principal)

        if Repo.exists?(
             from a in TaskAttempt,
               where:
                 a.task_id == ^task.id and
                   (a.state in ["leased", "running"] or not a.effects_resolved)
           ),
           do: Commands.fail!(:conflict)

        if task.migration_metadata["relationship_conflict"], do: Commands.fail!(:invalid)
        changeset = task |> editable(attrs) |> validate_required([:title])
        reviewed = apply_changes(changeset)
        parent!(project_id, reviewed.parent_task_id, task.id)
        relationship_checks!(reviewed)

        metadata =
          (task.migration_metadata || %{})
          |> Map.put("adoption_evidence_ref", attrs["evidence_ref"])
          |> Map.put("requires_reconciliation", false)

        task =
          changeset
          |> change(
            adopted: true,
            execution_hold: false,
            version: task.version + 1,
            migration_metadata: metadata
          )
          |> Commands.update!()

        Events.append!(project_id, "task.adopted", ctx, "task", task.id, %{},
          previous: previous,
          current: task
        )

        Projection.task(task)
      end
    )
  end

  def decide(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.decide:" <> to_string(id), roles: ["reviewer"]],
      fn ctx ->
        writable_project!(ctx)
        task = lock!(project_id, id)
        Commands.expect!(task, attrs)

        previous = task

        if task.state != "awaiting_review" || task.execution_hold || !task.adopted,
          do: Commands.fail!(:invalid_transition)

        kind = attrs["kind"]
        verdict = attrs["verdict"]

        if kind not in ~w(review acceptance) || verdict not in ~w(approve reject),
          do: Commands.fail!(:invalid)

        if kind == "acceptance" && verdict == "approve" do
          review =
            Repo.one(
              from d in DecisionRecord,
                where: d.task_id == ^id and d.kind == "review",
                order_by: [desc: d.inserted_at, desc: d.id],
                limit: 1
            )

          if !review || review.verdict != "approve" ||
               review.metadata["task_version"] != task.version - 1,
             do: Commands.fail!(:invalid_transition)
        end

        attempt = latest_attempt(task.id)

        decision = %DecisionRecord{
          project_id: project_id,
          task_id: task.id,
          attempt_id: attempt && attempt.id,
          author_agent_id: ctx.principal.agent_id,
          kind: kind,
          verdict: verdict,
          summary: attrs["summary"],
          metadata: %{"task_version" => task.version}
        }

        decision =
          decision |> change() |> validate_length(:summary, max: 4_000) |> Commands.insert!()

        state =
          cond do
            verdict == "reject" -> "open"
            kind == "acceptance" -> "accepted"
            true -> "awaiting_review"
          end

        accepted_at = if state == "accepted", do: DateTime.utc_now(), else: nil

        task =
          task
          |> change(state: state, accepted_at: accepted_at, version: task.version + 1)
          |> Commands.update!()

        Events.append!(
          project_id,
          "task.decision_recorded",
          ctx,
          "task",
          task.id,
          %{
            "decision_id" => decision.id,
            "kind" => kind,
            "verdict" => verdict
          },
          previous: previous,
          current: task
        )

        Projection.task(task) |> Map.put("decision", Projection.decision(decision))
      end
    )
  end

  def add_artifact(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "task.artifact:" <> to_string(id), roles: ~w(worker manager)],
      fn ctx ->
        writable_project!(ctx)
        task = lock!(project_id, id)
        Commands.expect!(task, attrs)

        attempt =
          if attrs["attempt_id"] do
            if !Params.uuid?(attrs["attempt_id"]), do: Commands.fail!(:invalid)

            Repo.get_by(TaskAttempt,
              id: attrs["attempt_id"],
              project_id: project_id,
              task_id: task.id
            ) || Commands.fail!(:not_found)
          end

        if ctx.principal.kind == :agent do
          member =
            Repo.get_by!(Samgita.Domain.ProjectAgent,
              project_id: project_id,
              agent_id: ctx.principal.agent_id
            )

          if "manager" not in member.roles &&
               (!attempt || attempt.agent_id != ctx.principal.agent_id),
             do: Commands.fail!(:forbidden)
        end

        artifact = %ArtifactReference{
          project_id: project_id,
          task_id: task.id,
          attempt_id: attempt && attempt.id,
          created_by_agent_id: ctx.principal.agent_id
        }

        if !safe_locator?(attrs["locator"]) || !safe_metadata?(Map.get(attrs, "metadata", %{})),
          do: Commands.fail!(:invalid)

        artifact =
          artifact
          |> cast(attrs, [:kind, :locator, :digest, :metadata])
          |> validate_required([:kind, :locator])
          |> validate_length(:kind, max: 100)
          |> validate_length(:locator, max: 4_000)
          |> validate_length(:digest, max: 256)
          |> Commands.insert!()

        current = task |> change(version: task.version + 1) |> Commands.update!()

        Events.append!(
          project_id,
          "task.artifact_added",
          ctx,
          "task",
          task.id,
          %{
            "artifact_reference_id" => artifact.id
          },
          previous: task,
          current: current
        )

        Projection.artifact(artifact)
      end
    )
  end

  defp preserve_parent!(task, attrs) do
    if Map.has_key?(attrs, "parent_task_id") && attrs["parent_task_id"] != task.parent_task_id &&
         (!task.adopted || Map.has_key?(task.migration_metadata || %{}, "source_updated_at") ||
            Repo.exists?(
              from m in Samgita.Domain.MigrationMapping,
                where: m.source_table == "tasks" and m.source_id == ^task.id
            )) do
      Commands.fail!(:invalid, %{
        fields: ["parent_task_id"],
        reason: "historical_reference_frozen"
      })
    end
  end

  defp editable(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :parent_task_id, :required_capabilities])
    |> validate_length(:title, max: 500)
    |> validate_length(:description, max: 100_000)
    |> validate_change(:required_capabilities, fn :required_capabilities, values ->
      if is_list(values) && length(values) <= 64 && Enum.all?(values, &nonempty?/1),
        do: [],
        else: [required_capabilities: "is invalid"]
    end)
    |> foreign_key_constraint(:parent_task_id)
    |> foreign_key_constraint(:project_id)
  end

  defp scoped!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)
    Repo.get_by(Task, id: id, project_id: project_id) || Commands.fail!(:not_found)
  end

  defp lock!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from t in Task, where: t.id == ^id and t.project_id == ^project_id, lock: "FOR UPDATE"
    ) || Commands.fail!(:not_found)
  end

  defp parent!(_project_id, nil, _child), do: :ok

  defp parent!(project_id, parent_id, child),
    do: walk_parent!(project_id, parent_id, MapSet.new(), child)

  defp walk_parent!(_project_id, nil, _seen, _child), do: :ok

  defp walk_parent!(project_id, parent_id, seen, child) do
    if parent_id == child || MapSet.member?(seen, parent_id),
      do: Commands.fail!(:invalid, %{field: "parent_task_id"})

    parent = scoped!(project_id, parent_id)
    walk_parent!(project_id, parent.parent_task_id, MapSet.put(seen, parent_id), child)
  end

  defp relationship_checks!(task) do
    dependency_walk!(task, MapSet.new(), MapSet.new())
  end

  defp dependency_walk!(task, visiting, done) do
    cond do
      MapSet.member?(visiting, task.id) ->
        Commands.fail!(:invalid, %{reason: "dependency_cycle"})

      MapSet.member?(done, task.id) ->
        done

      true ->
        edge_ids =
          Repo.all(
            from d in "task_dependencies",
              where: d.task_id == type(^task.id, :binary_id),
              select: type(d.depends_on_id, :binary_id)
          )

        if Enum.sort(edge_ids) != Enum.sort(task.depends_on_ids || []),
          do: Commands.fail!(:invalid, %{reason: "dependency_conflict"})

        visiting = MapSet.put(visiting, task.id)

        adjacent =
          Enum.uniq(edge_ids ++ if(task.parent_task_id, do: [task.parent_task_id], else: []))

        done =
          Enum.reduce(adjacent, done, fn id, acc ->
            dependency_walk!(scoped!(task.project_id, id), visiting, acc)
          end)

        MapSet.put(done, task.id)
    end
  end

  defp writable_project!(%{project: %{state: state}}) when state not in ["active", "paused"],
    do: Commands.fail!(:invalid_transition)

  defp writable_project!(_), do: :ok

  defp ownership_agents(project_id, id) do
    if Params.uuid?(project_id) && Params.uuid?(id) do
      Repo.all(
        from a in TaskAttempt,
          where:
            a.project_id == ^project_id and a.task_id == ^id and
              (a.state in ["leased", "running"] or not a.effects_resolved),
          select: a.agent_id,
          distinct: true
      )
    else
      []
    end
  end

  defp ensure_discovered!(ctx, id, discovered) do
    locked = [ctx.principal.agent_id | discovered]

    if Enum.any?(ownership_agents(ctx.project.id, id), &(&1 not in locked)),
      do: Commands.fail!(:conflict, %{reason: "ownership_changed_retry"})
  end

  defp safe_locator?(locator) when is_binary(locator) do
    uri = URI.parse(locator)

    String.trim(locator) != "" && byte_size(locator) <= 4_000 &&
      uri.userinfo == nil && uri.query == nil && uri.fragment == nil
  end

  defp safe_locator?(_), do: false

  defp safe_metadata?(metadata) when is_map(metadata) and not is_struct(metadata) do
    case Jason.encode(metadata) do
      {:ok, json} -> byte_size(json) <= 16_384 && safe_value?(metadata, 0)
      _ -> false
    end
  end

  defp safe_metadata?(_), do: false

  defp safe_value?(_value, depth) when depth > 8, do: false

  defp safe_value?(value, depth) when is_map(value) do
    map_size(value) <= 100 &&
      Enum.all?(value, fn {key, item} ->
        is_binary(key) &&
          !Regex.match?(
            ~r/(api[_-]?key|authorization|credential|password|proof|secret|token)/i,
            key
          ) && safe_value?(item, depth + 1)
      end)
  end

  defp safe_value?(value, depth) when is_list(value),
    do: length(value) <= 100 && Enum.all?(value, &safe_value?(&1, depth + 1))

  defp safe_value?(value, _depth),
    do: is_binary(value) || is_number(value) || is_boolean(value) || is_nil(value)

  defp latest_attempt(task_id),
    do:
      Repo.one(
        from a in TaskAttempt, where: a.task_id == ^task_id, order_by: [desc: a.number], limit: 1
      )

  defp nonempty?(value),
    do: is_binary(value) && byte_size(String.trim(value)) > 0 && byte_size(value) <= 4_000
end
