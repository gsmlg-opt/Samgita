defmodule Samgita.Attempts do
  @moduledoc "Database-owned execution leases; reports never grant management acceptance."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, LegacyMapping, Params, Projection, Repo}
  alias Samgita.Domain.{Agent, ExecutionSession, Task, TaskAttempt}
  @active ~w(leased running)

  def claim(principal, project_id, task_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "attempt.claim:" <> to_string(task_id), roles: ["worker"], execution: true],
      fn ctx -> claim_task!(ctx, project_id, task_id, attrs) end
    )
  end

  defp claim_task!(ctx, project_id, task_id, attrs) do
    Commands.connection!(ctx)
    Commands.require_hub!(ctx)
    task = lock_task!(project_id, task_id)
    Commands.expect!(task, attrs)

    validate_claim_task!(ctx, task)

    agent = Repo.get!(Agent, ctx.principal.agent_id)
    validate_capabilities!(agent, task)

    ensure_capacity!(agent)

    if Repo.exists?(from a in TaskAttempt, where: a.task_id == ^task.id and a.state in ^@active),
      do: Commands.fail!(:conflict)

    session = session!(ctx, attrs["session_id"])
    key_id = signing_key!()
    now = DateTime.utc_now()

    number =
      (Repo.one(from a in TaskAttempt, where: a.task_id == ^task.id, select: max(a.number)) ||
         0) + 1

    fence = task.fence_counter + 1

    attempt = %TaskAttempt{
      task_id: task.id,
      project_id: project_id,
      agent_id: agent.id,
      session_id: session.id,
      connection_id: ctx.principal.connection_id,
      connection_generation: ctx.principal.generation,
      number: number,
      state: "leased",
      fence: fence,
      execution_epoch: ctx.authority.epoch,
      proof_key_id: key_id,
      lease_expires_at: DateTime.add(now, 120, :second),
      start_deadline: DateTime.add(now, 30, :second),
      execution_deadline: DateTime.add(now, 900, :second)
    }

    attempt =
      attempt
      |> change()
      |> unique_constraint(:task_id, name: :one_active_attempt_per_task)
      |> unique_constraint([:task_id, :number])
      |> Commands.insert!()

    current_task =
      task |> change(fence_counter: fence, version: task.version + 1) |> Commands.update!()

    event!(ctx, attempt, "attempt.claimed", nil, task, current_task)
    Projection.attempt(attempt)
  end

  defp validate_claim_task!(ctx, task) do
    if Map.has_key?(task.migration_metadata || %{}, "source_updated_at"),
      do: LegacyMapping.validate_task!(task)

    if ctx.project.state != "active" || task.state != "open" || !task.adopted ||
         task.execution_hold,
       do: Commands.fail!(:invalid_transition)
  end

  defp validate_capabilities!(agent, task) do
    required = task.required_capabilities || []

    if !Enum.all?(
         required,
         &(&1 in agent.approved_capabilities && &1 in agent.advertised_capabilities)
       ),
       do: Commands.fail!(:forbidden)
  end

  defp ensure_capacity!(agent) do
    used =
      Repo.aggregate(
        from(a in TaskAttempt,
          where: a.agent_id == ^agent.id and (a.state in ^@active or not a.effects_resolved)
        ),
        :count
      )

    if used >= agent.capacity, do: Commands.fail!(:capacity_exceeded)
  end

  def start(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "start", fn ctx, task, attempt, attrs ->
      if ctx.project.state != "active", do: Commands.fail!(:invalid_transition)
      owner!(ctx, attempt, attrs["proof"])

      if attempt.state != "leased" || task.state != "open" || expired?(attempt.start_deadline),
        do: Commands.fail!(:ownership_lost)

      previous = attempt

      attempt =
        attempt |> change(state: "running", version: attempt.version + 1) |> Commands.update!()

      current_task =
        task |> change(state: "in_progress", version: task.version + 1) |> Commands.update!()

      event!(ctx, attempt, "attempt.started", previous, task, current_task)
      Projection.attempt(attempt)
    end)
  end

  def renew(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "renew", fn ctx, task, attempt, attrs ->
      owner!(ctx, attempt, attrs["proof"])

      if attempt.state == "leased" && expired?(attempt.start_deadline),
        do: Commands.fail!(:ownership_lost)

      lease = earlier(DateTime.add(DateTime.utc_now(), 120, :second), attempt.execution_deadline)

      previous = attempt

      attempt =
        attempt
        |> change(
          lease_expires_at: lease,
          proof_key_id: signing_key!(),
          version: attempt.version + 1
        )
        |> Commands.update!()

      event!(ctx, attempt, "attempt.renewed", previous, task, task)
      Projection.attempt(attempt)
    end)
  end

  @doc "Append bounded progress evidence without completing execution or renewing ownership."
  def progress(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "progress", fn ctx, _task, attempt, attrs ->
      owner!(ctx, attempt, attrs["proof"])
      if attempt.state != "running", do: Commands.fail!(:invalid_transition)
      payload = Map.get(attrs, "payload", %{})

      if Events.validate_payload(payload) != :ok || !evidence?(payload["summary"]),
        do: Commands.fail!(:invalid, %{field: "payload.summary"})

      current = attempt |> change(version: attempt.version + 1) |> Commands.update!()

      Events.append!(project_id, "attempt.progress", ctx, "attempt", id, %{
        "task_id" => current.task_id,
        "summary" => payload["summary"],
        "status" => payload["status"]
      })

      Projection.attempt(current)
    end)
  end

  def report(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "report", fn ctx, task, attempt, attrs ->
      owner!(ctx, attempt, attrs["proof"])
      if attempt.state != "running", do: Commands.fail!(:invalid_transition)

      if attrs["outcome"] not in ~w(succeeded failed) || !is_map(Map.get(attrs, "result", %{})) ||
           !is_boolean(attrs["effects_resolved"]),
         do: Commands.fail!(:invalid)

      resolved = attrs["effects_resolved"]

      previous = attempt

      attempt =
        attempt
        |> change(
          state: attrs["outcome"],
          outcome: %{"status" => attrs["outcome"], "result" => Map.get(attrs, "result", %{})},
          terminal_at: DateTime.utc_now(),
          effects_resolved: resolved,
          version: attempt.version + 1
        )
        |> Commands.update!()

      state =
        cond do
          !resolved -> "blocked"
          attempt.state == "succeeded" -> "awaiting_review"
          true -> "failed"
        end

      current_task =
        task
        |> change(state: state, execution_hold: !resolved, version: task.version + 1)
        |> Commands.update!()

      event!(ctx, attempt, "attempt.reported", previous, task, current_task)
      Projection.attempt(attempt)
    end)
  end

  def rebind(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "rebind", fn ctx, task, attempt, attrs ->
      Commands.connection!(ctx)
      Commands.require_hub!(ctx)

      if !rebindable?(ctx, attempt), do: Commands.fail!(:ownership_lost)

      if attempt.state == "leased" && expired?(attempt.start_deadline),
        do: Commands.fail!(:ownership_lost)

      if !valid_proof?(attempt, attrs["proof"], :current), do: Commands.fail!(:ownership_lost)
      if attempt.connection_id == ctx.principal.connection_id, do: Commands.fail!(:conflict)
      session = session!(ctx, attempt.session_id, false)

      session
      |> change(connection_id: ctx.principal.connection_id, version: session.version + 1)
      |> Commands.update!()

      fence = task.fence_counter + 1

      previous = attempt

      attempt =
        attempt
        |> change(
          connection_id: ctx.principal.connection_id,
          connection_generation: ctx.principal.generation,
          fence: fence,
          proof_key_id: signing_key!(),
          lease_expires_at:
            earlier(DateTime.add(DateTime.utc_now(), 120, :second), attempt.execution_deadline),
          version: attempt.version + 1
        )
        |> Commands.update!()

      current_task =
        task |> change(fence_counter: fence, version: task.version + 1) |> Commands.update!()

      event!(ctx, attempt, "attempt.rebound", previous, task, current_task)
      Projection.attempt(attempt)
    end)
  end

  def resolve(principal, project_id, id, attrs) do
    command(principal, project_id, id, attrs, "resolve", fn ctx, task, attempt, attrs ->
      if attrs["effects_resolved"] != true || !evidence?(attrs["evidence_ref"]),
        do: Commands.fail!(:invalid)

      former_owner!(ctx, attempt, attrs["proof"])

      if attempt.effects_resolved, do: Commands.fail!(:conflict)
      now = DateTime.utc_now()

      previous = attempt

      attempt =
        attempt
        |> change(
          effects_resolved: true,
          resolution_evidence: %{"evidence_ref" => attrs["evidence_ref"]},
          state: if(attempt.state in @active, do: "released", else: attempt.state),
          terminal_at: attempt.terminal_at || now,
          version: attempt.version + 1
        )
        |> Commands.update!()

      state = if task.state == "in_progress", do: "blocked", else: task.state

      held =
        Repo.exists?(
          from a in TaskAttempt, where: a.task_id == ^task.id and not a.effects_resolved
        )

      current_task =
        task
        |> change(state: state, execution_hold: held, version: task.version + 1)
        |> Commands.update!()

      event!(ctx, attempt, "attempt.effects_resolved", previous, task, current_task)
      Projection.attempt(attempt)
    end)
  end

  def expire(principal, attrs) do
    attrs = Params.strings(attrs)

    command(principal, attrs["project_id"], attrs["attempt_id"], attrs, "expire", fn ctx,
                                                                                     task,
                                                                                     attempt,
                                                                                     _attrs ->
      Commands.operator!(ctx.principal)

      due =
        expired?(attempt.lease_expires_at) || expired?(attempt.execution_deadline) ||
          (attempt.state == "leased" && expired?(attempt.start_deadline))

      if attempt.state not in @active || !due, do: Commands.fail!(:invalid_transition)

      previous = attempt

      attempt =
        attempt
        |> change(state: "expired", terminal_at: DateTime.utc_now(), version: attempt.version + 1)
        |> Commands.update!()

      current_task =
        task
        |> change(state: "blocked", execution_hold: true, version: task.version + 1)
        |> Commands.update!()

      event!(ctx, attempt, "attempt.expired", previous, task, current_task)
      Projection.attempt(attempt)
    end)
  end

  @doc "Derives the current owner's proof; never store this result in a command receipt."
  def proof(principal, project_id, id) do
    Commands.read(principal, project_id, ["worker"], fn ctx ->
      {_, attempt} = lock_attempt!(project_id, id)
      owner!(ctx, attempt, nil, false)
      key = lease_key!(attempt.proof_key_id)
      payload = attempt |> proof_claims() |> Jason.encode!() |> Base.url_encode64(padding: false)
      signed = "v1." <> attempt.proof_key_id <> "." <> payload
      mac = :crypto.mac(:hmac, :sha256, key, signed) |> Base.url_encode64(padding: false)
      %{"attempt_id" => attempt.id, "proof" => signed <> "." <> mac}
    end)
  end

  defp command(principal, project_id, id, attrs, operation, callback) do
    attrs = Params.strings(attrs)

    ids =
      if Params.uuid?(id) do
        case Repo.get(TaskAttempt, id) do
          nil -> []
          attempt -> [attempt.agent_id]
        end
      else
        []
      end

    Commands.run(
      principal,
      project_id,
      attrs,
      [
        operation: "attempt." <> operation <> ":" <> to_string(id),
        roles: ["worker"],
        agent_ids: ids,
        execution: operation not in ["resolve", "expire"]
      ],
      fn ctx ->
        {task, attempt} = lock_attempt!(project_id, id)
        Commands.expect!(attempt, attrs)
        callback.(ctx, task, attempt, attrs)
      end
    )
  end

  defp lock_task!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from t in Task, where: t.project_id == ^project_id and t.id == ^id, lock: "FOR UPDATE"
    ) || Commands.fail!(:not_found)
  end

  defp lock_attempt!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    existing =
      Repo.get_by(TaskAttempt, id: id, project_id: project_id) || Commands.fail!(:not_found)

    task = lock_task!(project_id, existing.task_id)
    attempt = Repo.one!(from a in TaskAttempt, where: a.id == ^id, lock: "FOR UPDATE")
    {task, attempt}
  end

  defp session!(ctx, id, current_connection \\ true) do
    if !Params.uuid?(id), do: Commands.fail!(:invalid)

    session =
      Repo.get_by(ExecutionSession,
        id: id,
        project_id: ctx.project.id,
        agent_id: ctx.principal.agent_id
      ) || Commands.fail!(:not_found)

    if session.state != "open" ||
         (current_connection && session.connection_id != ctx.principal.connection_id),
       do: Commands.fail!(:ownership_lost)

    session
  end

  defp owner!(ctx, attempt, proof, require_proof \\ true) do
    Commands.connection!(ctx)
    Commands.require_hub!(ctx)

    if ctx.project.state == "archived" || attempt.agent_id != ctx.principal.agent_id ||
         !current_connection?(ctx, attempt) || !current_execution?(ctx, attempt),
       do: Commands.fail!(:ownership_lost)

    session!(ctx, attempt.session_id)

    if require_proof && !valid_proof?(attempt, proof, :current),
      do: Commands.fail!(:ownership_lost)
  end

  defp rebindable?(ctx, attempt) do
    ctx.principal.agent_id == attempt.agent_id &&
      ctx.authority.epoch == attempt.execution_epoch &&
      attempt.state in @active && !expired?(attempt.lease_expires_at) &&
      !expired?(attempt.execution_deadline)
  end

  defp former_owner!(%{principal: %{kind: :operator}}, _, _), do: :ok

  defp former_owner!(ctx, attempt, proof) do
    if ctx.principal.agent_id != attempt.agent_id || !valid_proof?(attempt, proof, :former),
      do: Commands.fail!(:ownership_lost)
  end

  defp current_connection?(ctx, attempt) do
    attempt.connection_id == ctx.principal.connection_id &&
      attempt.connection_generation == ctx.principal.generation
  end

  defp current_execution?(ctx, attempt) do
    attempt.execution_epoch == ctx.authority.epoch && attempt.state in @active &&
      !expired?(attempt.lease_expires_at) && !expired?(attempt.execution_deadline)
  end

  defp proof_claims(attempt) do
    %{
      "attempt_id" => attempt.id,
      "project_id" => attempt.project_id,
      "task_id" => attempt.task_id,
      "agent_id" => attempt.agent_id,
      "session_id" => attempt.session_id,
      "connection_id" => attempt.connection_id,
      "generation" => attempt.connection_generation,
      "fence" => attempt.fence,
      "epoch" => attempt.execution_epoch,
      "key_id" => attempt.proof_key_id,
      "lease_expires_at" => DateTime.to_unix(attempt.lease_expires_at, :microsecond),
      "start_deadline" => DateTime.to_unix(attempt.start_deadline, :microsecond),
      "execution_deadline" => DateTime.to_unix(attempt.execution_deadline, :microsecond)
    }
  end

  defp valid_proof?(attempt, proof, mode) when is_binary(proof) and byte_size(proof) <= 4_000 do
    with ["v1", key_id, payload, signature] <- String.split(proof, "."),
         key when is_binary(key) <-
           Map.get(Application.get_env(:samgita, :lease_keys, %{}), key_id),
         {:ok, signature} <- Base.url_decode64(signature, padding: false),
         expected = :crypto.mac(:hmac, :sha256, key, "v1." <> key_id <> "." <> payload),
         true <-
           byte_size(expected) == byte_size(signature) && :crypto.hash_equals(expected, signature),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} when is_map(claims) <- Jason.decode(json),
         true <- claims["key_id"] == key_id do
      current = proof_claims(attempt)

      if mode == :current do
        claims == current
      else
        immutable = ~w(attempt_id project_id task_id agent_id session_id epoch execution_deadline)

        Map.take(claims, immutable) == Map.take(current, immutable) &&
          is_integer(claims["fence"]) && claims["fence"] > 0 && claims["fence"] <= attempt.fence
      end
    else
      _ -> false
    end
  end

  defp valid_proof?(_, _, _), do: false

  defp signing_key! do
    id = Application.get_env(:samgita, :lease_key_id)

    if !is_binary(id) || !Regex.match?(~r/\A[A-Za-z0-9_-]{1,100}\z/, id),
      do: Commands.fail!(:execution_closed)

    lease_key!(id)
    id
  end

  defp lease_key!(id) do
    key = Map.get(Application.get_env(:samgita, :lease_keys, %{}), id)
    if !is_binary(key) || byte_size(key) < 32, do: Commands.fail!(:execution_closed)
    key
  end

  defp event!(ctx, attempt, type, previous, task_before, task_after),
    do:
      Events.append!(
        attempt.project_id,
        type,
        ctx,
        "attempt",
        attempt.id,
        %{
          "task_id" => attempt.task_id,
          "state" => attempt.state,
          "fence" => attempt.fence,
          "task_before" => Events.snapshot(task_before),
          "task_after" => Events.snapshot(task_after)
        },
        previous: previous,
        current: attempt
      )

  defp expired?(time), do: DateTime.compare(time, DateTime.utc_now()) != :gt
  defp earlier(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)

  defp evidence?(value),
    do: is_binary(value) && String.trim(value) != "" && byte_size(value) <= 4_000
end
