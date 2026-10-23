defmodule Samgita.CodexRuntime.Authorization do
  @moduledoc false
  import Ecto.Query
  alias Samgita.{Attempts, Commands, Params, Repo}

  alias Samgita.Domain.{
    Agent,
    AgentConnection,
    AgentCredential,
    ExecutionSession,
    NativeRuntimeBinding,
    ProjectAgent,
    Task,
    TaskAttempt
  }

  def agent_ids(id) do
    record = if Params.uuid?(id), do: Repo.get(NativeRuntimeBinding, id)
    if record, do: [record.agent_id], else: []
  end

  def create_context(ctx, attempt_id, proof) do
    {task, attempt} = lock_attempt!(ctx.project.id, attempt_id)
    Attempts.authorize_runtime!(ctx, attempt, proof)
    current_task!(ctx, task, attempt)
    agent = Repo.get!(Agent, attempt.agent_id)

    if agent.runtime_driver != "codex" || agent.runtime_version != "0.163.0",
      do: Commands.fail!(:invalid, %{reason: "runtime_not_registered"})

    Map.merge(ctx, %{task: task, attempt: attempt})
  end

  def context(ctx, id, proof, opts \\ []) do
    record = scoped!(ctx.project.id, id)
    {task, attempt} = lock_attempt!(ctx.project.id, record.attempt_id)
    record = Repo.one!(from r in NativeRuntimeBinding, where: r.id == ^id, lock: "FOR UPDATE")

    owner!(ctx, attempt, record, proof, opts)
    agent = Repo.get!(Agent, attempt.agent_id)

    if agent.runtime_driver != record.driver || agent.runtime_version != record.driver_version,
      do: Commands.fail!(:ownership_lost)

    current_task!(ctx, task, attempt)
    if record.state != "open", do: Commands.fail!(:invalid_transition)
    same_binding!(record, attempt, Keyword.get(opts, :rebind, false))
    Map.merge(ctx, %{runtime: record, task: task, attempt: attempt})
  end

  def scoped!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.get_by(NativeRuntimeBinding, id: id, project_id: project_id) ||
      Commands.fail!(:not_found)
  end

  def payload_owner!(%{principal: %{kind: :operator}}, _), do: :ok

  def payload_owner!(ctx, runtime) do
    if ctx.principal.agent_id != runtime.agent_id, do: Commands.fail!(:forbidden)
  end

  defp lock_attempt!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    attempt =
      Repo.get_by(TaskAttempt, id: id, project_id: project_id) || Commands.fail!(:not_found)

    task =
      Repo.one!(from t in Task, where: t.id == ^attempt.task_id, lock: "FOR UPDATE")

    attempt = Repo.one!(from a in TaskAttempt, where: a.id == ^id, lock: "FOR UPDATE")
    {task, attempt}
  end

  defp current_task!(ctx, task, attempt) do
    if ctx.project.state == "archived" || task.state != "in_progress" || task.execution_hold ||
         attempt.state != "running" || task.fence_counter != attempt.fence ||
         attempt.execution_epoch != ctx.authority.epoch,
       do: Commands.fail!(:ownership_lost)
  end

  defp owner!(%{principal: %{kind: :operator}} = ctx, attempt, record, _proof, opts) do
    if !Keyword.get(opts, :operator_reply, false), do: Commands.fail!(:forbidden)
    Commands.require_hub!(ctx)
    agent = Repo.get!(Agent, record.agent_id)
    connection = Repo.get!(AgentConnection, attempt.connection_id)
    credential = Repo.get!(AgentCredential, connection.credential_id)
    member = Repo.get_by(ProjectAgent, project_id: ctx.project.id, agent_id: agent.id)
    session = Repo.get!(ExecutionSession, attempt.session_id)

    if !agent.enabled || credential.revoked_at || Commands.expired?(credential.expires_at) ||
         !member || !member.enabled || "worker" not in member.roles,
       do: Commands.fail!(:ownership_lost)

    valid_operator_connection!(agent, connection, attempt, session)
  end

  defp owner!(ctx, attempt, _record, proof, opts),
    do: Attempts.authorize_runtime!(ctx, attempt, proof, Keyword.get(opts, :require_proof, true))

  defp valid_operator_connection!(agent, connection, attempt, session) do
    if connection.state != "connected" || connection.generation != agent.generation ||
         Commands.expired?(connection.expires_at) ||
         attempt.connection_generation != connection.generation ||
         Commands.expired?(attempt.lease_expires_at) ||
         Commands.expired?(attempt.execution_deadline) ||
         session.state != "open" || session.connection_id != connection.id,
       do: Commands.fail!(:ownership_lost)
  end

  defp same_binding!(_runtime, _attempt, true), do: :ok

  defp same_binding!(runtime, attempt, false) do
    if runtime.connection_id != attempt.connection_id ||
         runtime.connection_generation != attempt.connection_generation ||
         runtime.fence != attempt.fence || runtime.execution_epoch != attempt.execution_epoch,
       do: Commands.fail!(:ownership_lost)
  end
end
