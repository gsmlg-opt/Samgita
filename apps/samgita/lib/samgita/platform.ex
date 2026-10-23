defmodule Samgita.Platform do
  @moduledoc "Exclusive execution authority. Activation records evidence, never starts execution."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, Params, Projection, Repo}

  def status(principal) do
    Commands.read(principal, nil, [], fn ctx ->
      Commands.operator!(principal)
      Map.put(Projection.authority(ctx.authority), "legacy_jobs", legacy_jobs())
    end)
  end

  def activate(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "platform.activate", authority_write: true],
      fn ctx ->
        Commands.operator!(principal)
        Commands.expect!(ctx.authority, attrs)
        evidence = attrs["evidence"]

        if !activation_evidence?(evidence),
          do: Commands.fail!(:invalid)

        if ctx.authority.owner != "none" || legacy_jobs() != [],
          do: Commands.fail!(:execution_closed)

        if unresolved_state?(),
          do: Commands.fail!(:conflict, %{reason: "unmapped_or_unresolved_tasks"})

        keys = Application.get_env(:samgita, :lease_keys, %{})
        key_id = Application.get_env(:samgita, :lease_key_id)

        if !is_binary(keys[key_id]) || byte_size(keys[key_id]) < 32,
          do: Commands.fail!(:execution_closed, %{reason: "lease_key_required"})

        authority =
          ctx.authority
          |> change(
            owner: "hub",
            admission_open: true,
            epoch: ctx.authority.epoch + 1,
            version: ctx.authority.version + 1,
            evidence: Map.take(evidence, ~w(legacy_fenced effects_resolved reference))
          )
          |> Commands.update!()

        Events.append!(
          nil,
          "platform.activated",
          ctx,
          "platform",
          singleton_resource(),
          %{
            "epoch" => authority.epoch
          },
          previous: ctx.authority,
          current: authority
        )

        Projection.authority(authority)
      end
    )
  end

  defp activation_evidence?(evidence) when is_map(evidence) do
    evidence["legacy_fenced"] == true && evidence["effects_resolved"] == true &&
      is_binary(evidence["reference"]) && evidence["reference"] != ""
  end

  defp activation_evidence?(_), do: false

  defp unresolved_state? do
    Repo.exists?(from t in "tasks", where: is_nil(t.state) or t.execution_hold) ||
      Repo.exists?(
        from a in "task_attempts",
          where: a.state in ["leased", "running"] or not a.effects_resolved
      ) ||
      Repo.exists?(from m in Samgita.Domain.MigrationMapping, where: m.status != "mapped")
  end

  def close(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "platform.close", authority_write: true],
      fn ctx ->
        Commands.operator!(principal)
        Commands.expect!(ctx.authority, attrs)
        if !is_binary(attrs["reason"]) || attrs["reason"] == "", do: Commands.fail!(:invalid)
        # The exclusive authority lock excludes all command transactions while we
        # fence outstanding executions. Their unresolved effects still use capacity.
        hold_executions!(ctx)
        Samgita.EventDelivery.fence_all!()

        authority =
          ctx.authority
          |> change(
            owner: "none",
            admission_open: false,
            epoch: ctx.authority.epoch + 1,
            version: ctx.authority.version + 1,
            evidence: %{"reason" => attrs["reason"]}
          )
          |> Commands.update!()

        Events.append!(
          nil,
          "platform.closed",
          ctx,
          "platform",
          singleton_resource(),
          %{
            "epoch" => authority.epoch
          },
          previous: ctx.authority,
          current: authority
        )

        Projection.authority(authority)
      end
    )
  end

  def legacy_jobs do
    query =
      from j in "oban_jobs",
        where: j.state not in ["completed", "cancelled", "discarded"],
        order_by: j.id,
        select: %{id: j.id, worker: j.worker, queue: j.queue, state: j.state}

    # Only these exact worker/queue pairs belong to the new mode. Unknown jobs,
    # including historical hook/executor jobs, still block ownership activation.
    query =
      Enum.reduce(coordination_workers(), query, fn {worker, queue}, query ->
        where(query, [j], not (j.worker == ^worker and j.queue == ^queue))
      end)

    Repo.all(query)
    |> Enum.map(fn j -> Map.new(j, fn {k, v} -> {to_string(k), v} end) end)
  end

  def coordination_workers do
    [
      {"Samgita.Workers.EventDeliveryWorker", "hub_events"},
      {"Samgita.Workers.ScheduleTickWorker", "hub_schedules"},
      {"Samgita.Workers.CoordinationMaintenanceWorker", "hub_maintenance"},
      {"Samgita.Workers.AttemptExpiryWorker", "hub_maintenance"},
      {"Samgita.Workers.GitHubReconcileWorker", "hub_github"},
      {"Samgita.Workers.GitHubMaintenanceWorker", "hub_github"}
    ]
  end

  defp hold_executions!(ctx) do
    alias Samgita.Domain.{Agent, Project, Task, TaskAttempt}

    active =
      Repo.all(from a in TaskAttempt, where: a.state in ["leased", "running"], order_by: a.id)

    agent_ids = active |> Enum.map(& &1.agent_id) |> Enum.uniq()
    project_ids = active |> Enum.map(& &1.project_id) |> Enum.uniq()
    Repo.all(from a in Agent, where: a.id in ^agent_ids, order_by: a.id, lock: "FOR UPDATE")
    Repo.all(from p in Project, where: p.id in ^project_ids, order_by: p.id, lock: "FOR UPDATE")

    for attempt <- Enum.sort_by(active, & &1.task_id) do
      task = Repo.one!(from t in Task, where: t.id == ^attempt.task_id, lock: "FOR UPDATE")

      current_task =
        task
        |> change(
          state: "blocked",
          execution_hold: true,
          fence_counter: task.fence_counter + 1,
          version: task.version + 1
        )
        |> Commands.update!()

      current_attempt =
        attempt
        |> change(state: "expired", terminal_at: DateTime.utc_now(), version: attempt.version + 1)
        |> Commands.update!()

      Events.append!(
        task.project_id,
        "attempt.authority_lost",
        ctx,
        "attempt",
        attempt.id,
        %{
          "task_id" => task.id,
          "task_before" => Events.snapshot(task),
          "task_after" => Events.snapshot(current_task)
        },
        previous: attempt,
        current: current_attempt
      )
    end
  end

  defp singleton_resource, do: "00000000-0000-0000-0000-000000000001"
end
