defmodule Samgita.EventDelivery do
  @moduledoc """
  Durable, at-least-once notification delivery. No operation here claims or executes a Task.

  A lease fences the local network handler, not remote effects. Lost replies require a status
  query using the original operation/event IDs; a non-idempotent unknown outcome stops for review.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Events, Params, Projection, Repo}
  alias Samgita.Connector.Failure

  alias Samgita.Domain.{
    Agent,
    DomainEvent,
    EventAcknowledgement,
    EventDelivery,
    EventDeliveryAttempt,
    EventRecoveryAction,
    Project,
    ProjectAgent
  }

  @ready ~w(pending retry_wait reconciling)
  @terminal ~w(completed dead_letter authentication_failed cancelled uncertain legacy_unreviewed)
  @final_processing ~w(completed failed rejected)
  @lease_seconds 60

  def dispatch(id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    connector = Keyword.get(opts, :connector, Samgita.Connectors.AppServer)

    with {:ok, claim} <- claim(id, now: now) do
      case claim do
        %{action: _action} ->
          # Network I/O runs after the claim transaction releases all locks.
          outcome = send_claim(claim, connector)

          settle(id, claim.token, outcome,
            now: Keyword.get(opts, :settled_at, DateTime.utc_now())
          )

        %{result: result} ->
          {:ok, result}
      end
    end
  end

  defp send_claim(%{action: "receive"} = claim, connector),
    do: connector.receive_event(claim.target, claim.event, claim.operation_id)

  defp send_claim(%{action: "status"} = claim, connector),
    do: connector.status(claim.target, claim.event["event_id"], claim.operation_id)

  def claim(id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    system(id, fn ctx, delivery, subscription ->
      Commands.require_hub!(ctx)
      delivery = expire_locked(delivery, now)
      # Pausing/archiving closes receives, but must not require reopening work
      # admissions merely to reconcile a read-only status query.
      if ctx.project.state != "active" && delivery.state != "reconciling",
        do: Commands.fail!(:execution_closed)

      cond do
        delivery.state not in @ready ->
          %{result: project(delivery)}

        delivery.next_attempt_at && DateTime.compare(delivery.next_attempt_at, now) == :gt ->
          %{result: project(delivery)}

        !target_current?(delivery, subscription) ->
          %{result: block_target!(delivery, now)}

        delivery.cycle_attempt_count >= delivery.max_attempts ->
          %{result: exhaust!(delivery, now)}

        true ->
          claim_locked!(ctx, delivery, now)
      end
    end)
  end

  defp claim_locked!(ctx, delivery, now) do
    action = if delivery.state == "reconciling", do: "status", else: "receive"
    fence = delivery.fence + 1
    lease_id = Ecto.UUID.generate()

    attempt =
      %EventDeliveryAttempt{}
      |> change(
        delivery_id: delivery.id,
        number: delivery.attempt_count + 1,
        action: action,
        fence: fence,
        lease_id: lease_id,
        execution_epoch: ctx.authority.epoch,
        started_at: now
      )
      |> Commands.insert!()

    current =
      delivery
      |> change(
        state: "delivering",
        fence: fence,
        lease_id: lease_id,
        lease_expires_at: DateTime.add(now, @lease_seconds),
        next_attempt_at: DateTime.add(now, @lease_seconds),
        execution_epoch: ctx.authority.epoch,
        last_attempt_id: attempt.id,
        attempt_count: attempt.number,
        cycle_attempt_count: delivery.cycle_attempt_count + 1,
        version: delivery.version + 1
      )
      |> Commands.update!()

    agent = Repo.get!(Agent, current.agent_id)
    event = Repo.get!(DomainEvent, current.event_id)

    %{
      action: action,
      token: token(current),
      operation_id: current.operation_id,
      event: Events.envelope(event, attempt.id),
      target: %{
        agent_id: agent.id,
        endpoint_metadata: agent.endpoint_metadata,
        credential_ref: agent.credential_ref
      }
    }
  end

  def renew(id, proof, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    system(id, fn ctx, delivery, subscription ->
      owner!(ctx, delivery, subscription, proof, now)
      attempt = Repo.get!(EventDeliveryAttempt, delivery.last_attempt_id)
      deadline = DateTime.add(attempt.started_at, 300)
      expires = min_time(DateTime.add(now, @lease_seconds), deadline)
      if DateTime.compare(expires, now) != :gt, do: Commands.fail!(:ownership_lost)

      current =
        delivery
        |> change(lease_expires_at: expires, version: delivery.version + 1)
        |> Commands.update!()

      %{token: token(current), expires_at: expires}
    end)
  end

  def settle(id, proof, outcome, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    system(id, fn ctx, delivery, subscription ->
      owner!(ctx, delivery, subscription, proof, now)
      attempt = Repo.get!(EventDeliveryAttempt, delivery.last_attempt_id)

      current =
        case normalize_outcome(outcome, delivery, attempt) do
          {:ok, result} -> acknowledge!(delivery, attempt, result, now, attempt.action)
          {:error, %Failure{} = error} -> failed!(delivery, subscription, attempt, error, now)
        end

      project(current)
    end)
  end

  def list(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, ~w(observer worker manager reviewer), fn _ ->
      {limit, offset} = Params.page(params)

      data =
        Repo.all(
          from(d in EventDelivery,
            where: d.project_id == ^project_id,
            order_by: [desc: d.inserted_at, desc: d.id],
            limit: ^limit,
            offset: ^offset
          )
        )

      %{"data" => Enum.map(data, &project/1), "limit" => limit, "offset" => offset}
    end)
  end

  def get(principal, project_id, id) do
    Commands.read(principal, project_id, ~w(observer worker manager reviewer), fn _ ->
      delivery = scoped!(project_id, id)

      attempts =
        Repo.all(
          from(a in EventDeliveryAttempt,
            where: a.delivery_id == ^id,
            order_by: [desc: a.number],
            limit: 100
          )
        )

      actions =
        Repo.all(
          from(a in EventRecoveryAction,
            where: a.delivery_id == ^id,
            order_by: [desc: a.inserted_at],
            limit: 100
          )
        )

      acknowledgements =
        Repo.all(
          from(a in EventAcknowledgement,
            where: a.delivery_id == ^id,
            order_by: [desc: a.recorded_at],
            limit: 100
          )
        )

      project(delivery)
      |> Map.put(
        "attempts",
        Enum.map(
          attempts,
          &Projection.fields(
            &1,
            ~w(id number action fence state error_class error_code started_at finished_at)a
          )
        )
      )
      |> Map.put(
        "recovery_actions",
        Enum.map(
          actions,
          &Projection.fields(
            &1,
            ~w(id previous_delivery_id command_id action reason evidence_ref risk_acknowledged previous_state resulting_state inserted_at)a
          )
        )
      )
      |> Map.put(
        "acknowledgements",
        Enum.map(
          acknowledgements,
          &Projection.fields(
            &1,
            ~w(id attempt_id source acceptance processing_status decision_id result recorded_at)a
          )
        )
      )
    end)
  end

  @doc "Record processing evidence only. Task review/acceptance stays in the Task context."
  def report(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    command(principal, project_id, id, attrs, "report", fn ctx, delivery, subscription ->
      if principal.kind != :agent || principal.agent_id != delivery.agent_id,
        do: Commands.fail!(:forbidden)

      Commands.require_hub!(ctx)
      Commands.expect!(delivery, attrs)

      require_report_owner!(ctx, delivery, subscription, attrs)
      validate_report!(attrs)

      result = %{
        "event_id" => delivery.event_id,
        "acceptance" => "durable",
        "processing_status" => attrs["processing_status"]
      }

      result = Map.merge(result, Map.take(attrs, ~w(decision_id result)))
      current = acknowledge!(delivery, nil, result, DateTime.utc_now(), "report")
      project(current)
    end)
  end

  defp require_report_owner!(ctx, delivery, subscription, attrs) do
    if !target_current?(delivery, subscription) || delivery.state in @terminal ||
         delivery.state not in ~w(delivering accepted reconciling) ||
         delivery.execution_epoch != ctx.authority.epoch || stale_report_lease?(delivery) ||
         attrs["operation_id"] != delivery.operation_id || attrs["fence"] != delivery.fence,
       do: Commands.fail!(:ownership_lost)
  end

  defp stale_report_lease?(delivery),
    do: delivery.state == "delivering" && Commands.expired?(delivery.lease_expires_at)

  defp validate_report!(attrs) do
    if attrs["processing_status"] not in @final_processing || !Params.uuid?(attrs["decision_id"]) ||
         Events.validate_payload(attrs["result"] || %{}) != :ok,
       do: Commands.fail!(:invalid)
  end

  @doc "Explicit operator recovery. Administrative redelivery keeps event/time/operation identity."
  def recover(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    command(principal, project_id, id, attrs, "recover", fn ctx, delivery, subscription ->
      Commands.operator!(principal)
      Commands.expect!(delivery, attrs)
      reason = attrs["reason"]
      evidence = attrs["evidence_ref"]

      validate_recovery_evidence!(reason, evidence)

      now = DateTime.utc_now()

      current = recover_locked!(attrs["action"], ctx, delivery, subscription, attrs, now)

      %EventRecoveryAction{}
      |> change(
        delivery_id: id,
        command_id: ctx.command_id,
        action: attrs["action"],
        reason: reason,
        evidence_ref: evidence,
        risk_acknowledged: attrs["risk_acknowledged"] == true,
        previous_state: delivery.state,
        resulting_state: current.state
      )
      |> Commands.insert!()

      if current.state in @ready, do: Events.enqueue!(current)
      project(current)
    end)
  end

  defp validate_recovery_evidence!(reason, evidence) do
    if !is_binary(reason) || byte_size(reason) not in 1..2000 ||
         (evidence && (!is_binary(evidence) || byte_size(evidence) not in 1..2000)),
       do: Commands.fail!(:invalid)
  end

  defp recover_locked!("cancel", _ctx, delivery, _subscription, _attrs, now) do
    if delivery.state == "cancelled", do: Commands.fail!(:invalid_transition)
    finish_attempt!(delivery, now, "cancelled", nil, nil)

    delivery
    |> change(
      state: "cancelled",
      remote_outcome_uncertain:
        delivery.remote_outcome_uncertain ||
          delivery.state in ~w(delivering accepted reconciling),
      fence: delivery.fence + 1,
      lease_id: nil,
      lease_expires_at: nil,
      next_attempt_at: nil,
      version: delivery.version + 1
    )
    |> Commands.update!()
  end

  defp recover_locked!(action, ctx, delivery, subscription, attrs, now)
       when action in ~w(redeliver reconcile) do
    Commands.require_hub!(ctx)

    if !target_current?(delivery, subscription),
      do: Commands.fail!(:conflict, %{reason: "target_changed_requires_new_subscription"})

    if delivery.state == "delivering",
      do: Commands.fail!(:conflict, %{reason: "handler_still_leased"})

    if !is_binary(attrs["evidence_ref"]) || attrs["evidence_ref"] == "",
      do: Commands.fail!(:invalid, %{field: "evidence_ref"})

    require_redelivery_risk!(action, delivery, subscription, attrs)

    if !delivery.operation_id,
      do: Commands.fail!(:conflict, %{reason: "legacy_translation_required"})

    delivery
    |> change(
      state: if(action == "reconcile", do: "reconciling", else: "pending"),
      next_attempt_at: now,
      fence: delivery.fence + 1,
      lease_id: nil,
      lease_expires_at: nil,
      cycle_attempt_count: 0,
      version: delivery.version + 1
    )
    |> Commands.update!()
  end

  defp recover_locked!(_, _, _, _, _, _), do: Commands.fail!(:invalid)

  defp require_redelivery_risk!(action, delivery, subscription, attrs) do
    if action == "redeliver" && delivery.attempt_count > 0 &&
         !subscription.idempotency_guaranteed && attrs["risk_acknowledged"] != true,
       do: Commands.fail!(:conflict, %{reason: "remote_outcome_uncertain"})
  end

  @doc "Bounded repair of missed wakeups and expired handlers; no Task execution is retried."
  def maintain(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    limit = Keyword.get(opts, :limit, 100) |> max(1) |> min(100)

    candidates = maintenance_candidates(now, limit)

    Enum.reduce_while(candidates, {:ok, 0}, fn id, {:ok, count} ->
      case system(id, &maintain_locked!(&1, &2, &3, now)) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, %{code: :execution_closed}} -> {:halt, {:ok, count}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp maintenance_candidates(now, limit) do
    Repo.all(
      from(d in EventDelivery,
        join: p in Project,
        on: p.id == d.project_id,
        where:
          (d.state in ^@ready and d.next_attempt_at <= ^now and
             (p.state == "active" or d.state == "reconciling")) or
            (d.state == "delivering" and d.lease_expires_at <= ^now),
        # Successful wakeup checks rotate to the back of the bounded scan even
        # when the job has not run. next_attempt_at remains the delivery deadline.
        order_by: [asc: d.updated_at, asc: d.id],
        limit: ^limit,
        select: d.id
      )
    )
  end

  defp maintain_locked!(ctx, delivery, _subscription, now) do
    Commands.require_hub!(ctx)
    delivery = expire_locked(delivery, now)

    if delivery.state in @ready &&
         (ctx.project.state == "active" || delivery.state == "reconciling"),
       do: Events.enqueue!(delivery)

    delivery |> change(updated_at: DateTime.utc_now()) |> Commands.update!()
    :ok
  end

  @doc false
  def fence_all! do
    if !Repo.in_transaction?(), do: raise("authority fencing requires a transaction")
    now = DateTime.utc_now()

    for delivery <-
          Repo.all(
            from(d in EventDelivery,
              where: d.state == "delivering",
              order_by: d.id,
              lock: "FOR UPDATE"
            )
          ) do
      expire_locked(delivery, now, true)
    end

    :ok
  end

  def project(r),
    do:
      Projection.fields(
        r,
        ~w(id project_id agent_id event_id subscription_id subscription_revision operation_id state version attempt_count cycle_attempt_count max_attempts next_attempt_at fence last_error_class last_error_code transport_received_at accepted_at completed_at processing_status remote_outcome_uncertain result inserted_at updated_at)a
      )

  defp system(id, callback) do
    with {:ok, initial} <- lookup(id) do
      Commands.system(initial.project_id, [initial.agent_id], fn ctx ->
        subscription = Events.subscription!(initial.project_id, initial.subscription_id)
        delivery = scoped!(initial.project_id, id)
        callback.(ctx, delivery, subscription)
      end)
    end
  end

  defp command(principal, project_id, id, attrs, operation, callback) do
    with {:ok, initial} <- lookup(id) do
      Commands.run(
        principal,
        project_id,
        attrs,
        [
          operation: "delivery.#{operation}:#{id}",
          roles: ["manager"],
          agent_ids: [initial.agent_id]
        ],
        fn ctx ->
          subscription = Events.subscription!(project_id, initial.subscription_id)
          callback.(ctx, scoped!(project_id, id), subscription)
        end
      )
    end
  end

  defp lookup(id) do
    if Params.uuid?(id) do
      case Repo.get(EventDelivery, id) do
        nil -> {:error, Samgita.Error.new(:not_found)}
        delivery -> {:ok, delivery}
      end
    else
      {:error, Samgita.Error.new(:not_found)}
    end
  end

  defp scoped!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from(d in EventDelivery,
        where: d.id == ^id and d.project_id == ^project_id,
        lock: "FOR UPDATE"
      )
    ) || Commands.fail!(:not_found)
  end

  defp target_current?(delivery, subscription) do
    agent = Repo.get(Agent, delivery.agent_id)

    member =
      Repo.get_by(ProjectAgent, project_id: delivery.project_id, agent_id: delivery.agent_id)

    current_subscription?(delivery, subscription) && responsible_agent?(agent, member) &&
      delivery.target_digest == subscription.target_digest &&
      delivery.target_digest == Events.target_digest(agent)
  end

  defp current_subscription?(delivery, subscription),
    do:
      subscription.enabled && subscription.purpose == "responsible" &&
        subscription.revision == delivery.subscription_revision &&
        subscription.agent_id == delivery.agent_id

  defp responsible_agent?(agent, member),
    do:
      agent && agent.enabled && member && member.enabled && "manager" in member.roles &&
        "project_events.v1" in agent.approved_capabilities &&
        "project_events.v1" in agent.advertised_capabilities

  defp owner!(ctx, delivery, subscription, proof, now) do
    Commands.require_hub!(ctx)

    if delivery.state != "delivering" || token(delivery) != proof ||
         delivery.execution_epoch != ctx.authority.epoch || !delivery.lease_expires_at ||
         DateTime.compare(delivery.lease_expires_at, now) != :gt ||
         !target_current?(delivery, subscription),
       do: Commands.fail!(:ownership_lost)
  end

  defp token(d), do: %{lease_id: d.lease_id, fence: d.fence, execution_epoch: d.execution_epoch}

  defp normalize_outcome({:ok, result}, delivery, attempt) do
    method =
      if attempt.action == "receive", do: "project/event.receive", else: "project/event.status"

    valid =
      SamgitaProtocol.Schema.validate_result(method, result) == :ok &&
        result["event_id"] == delivery.event_id &&
        (attempt.action != "receive" || result["delivery_attempt_id"] == attempt.id)

    # A malformed reply may follow remote persistence, so its outcome is ambiguous.
    if valid,
      do: {:ok, result},
      else: {:error, %Failure{class: :ambiguous, code: :invalid_response}}
  end

  defp normalize_outcome({:error, %Failure{} = error}, _, _), do: {:error, error}

  defp normalize_outcome(_, _, _),
    do: {:error, %Failure{class: :ambiguous, code: :invalid_response}}

  defp acknowledge!(delivery, attempt, result, now, source) do
    durable = result["acceptance"] == "durable"
    final = durable && result["processing_status"] in @final_processing
    digest = Commands.digest(Map.drop(result, ["delivery_attempt_id"]))
    safe_result = safe_acknowledgement_result(result)

    record_acknowledgement!(delivery, attempt, result, safe_result, digest, now, source)
    finish_attempt!(delivery, now, "acknowledged", nil, nil)
    state = acknowledged_state(delivery, durable, final)
    safe_result = if map_size(safe_result) == 0, do: delivery.result, else: safe_result

    delivery
    |> change(
      state: state,
      transport_received_at: delivery.transport_received_at || now,
      accepted_at: acknowledgement_time(delivery.accepted_at, durable, now),
      completed_at: acknowledgement_time(delivery.completed_at, final, now),
      processing_status: result["processing_status"],
      result: safe_result,
      remote_outcome_uncertain: !durable,
      next_attempt_at:
        if(state == "reconciling", do: DateTime.add(now, backoff(delivery.cycle_attempt_count))),
      lease_id: nil,
      lease_expires_at: nil,
      version: delivery.version + 1,
      last_error_class: if(state == "uncertain", do: "ambiguous"),
      last_error_code: if(state == "uncertain", do: "durability_unconfirmed")
    )
    |> Commands.update!()
  end

  defp safe_acknowledgement_result(result) do
    payload = result["result"] || %{}
    if Events.validate_payload(payload) == :ok, do: payload, else: %{}
  end

  defp record_acknowledgement!(delivery, attempt, result, safe_result, digest, now, source) do
    if !Repo.get_by(EventAcknowledgement, delivery_id: delivery.id, result_digest: digest) do
      %EventAcknowledgement{}
      |> change(
        delivery_id: delivery.id,
        agent_id: delivery.agent_id,
        attempt_id: attempt && attempt.id,
        source: source,
        acceptance: result["acceptance"],
        processing_status: result["processing_status"],
        decision_id: result["decision_id"],
        result: safe_result,
        result_digest: digest,
        recorded_at: now
      )
      |> Commands.insert!()
    end
  end

  defp acknowledged_state(delivery, durable, final) do
    cond do
      final -> "completed"
      durable -> "accepted"
      delivery.cycle_attempt_count >= delivery.max_attempts -> "uncertain"
      true -> "reconciling"
    end
  end

  defp acknowledgement_time(existing, true, now), do: existing || now
  defp acknowledgement_time(existing, false, _now), do: existing

  defp failed!(delivery, subscription, attempt, error, now) do
    code = safe_code(error.code)
    class = to_string(error.class)
    finish_attempt!(delivery, now, "failed", class, code)
    unknown = delivery.remote_outcome_uncertain || error.class == :ambiguous

    state =
      failure_state(
        error.class,
        attempt.action,
        code,
        subscription.idempotency_guaranteed,
        unknown
      )

    state = exhaust_failure(state, delivery, unknown)

    delay = max(backoff(delivery.cycle_attempt_count), bounded_retry_after(error.retry_after))

    delivery
    |> change(
      state: state,
      remote_outcome_uncertain: unknown || state == "uncertain",
      last_error_class: class,
      last_error_code: code,
      next_attempt_at: if(state in @ready, do: DateTime.add(now, delay)),
      lease_id: nil,
      lease_expires_at: nil,
      version: delivery.version + 1
    )
    |> Commands.update!()
  end

  defp failure_state(class, action, code, idempotent, unknown) do
    case {class, action, code, idempotent} do
      {:authentication, _, _, _} -> "authentication_failed"
      {_, "status", "not_found", _} -> if(idempotent, do: "retry_wait", else: "uncertain")
      {:permanent, _, _, _} -> if(unknown, do: "uncertain", else: "dead_letter")
      {_, "status", _, _} -> "reconciling"
      _ -> if(unknown, do: "reconciling", else: "retry_wait")
    end
  end

  defp exhaust_failure(state, delivery, unknown) do
    if delivery.cycle_attempt_count >= delivery.max_attempts && state in @ready,
      do: if(unknown, do: "uncertain", else: "dead_letter"),
      else: state
  end

  defp expire_locked(delivery, now, force \\ false) do
    if delivery.state == "delivering" &&
         (force || DateTime.compare(delivery.lease_expires_at, now) != :gt) do
      finish_attempt!(delivery, now, "unknown", "ambiguous", "handler_lost")

      delivery
      |> change(
        state: "reconciling",
        remote_outcome_uncertain: true,
        fence: delivery.fence + 1,
        lease_id: nil,
        lease_expires_at: nil,
        next_attempt_at: now,
        version: delivery.version + 1,
        last_error_class: "ambiguous",
        last_error_code: "handler_lost"
      )
      |> Commands.update!()
    else
      delivery
    end
  end

  defp block_target!(delivery, _now) do
    state =
      if delivery.remote_outcome_uncertain || delivery.accepted_at,
        do: "uncertain",
        else: "dead_letter"

    delivery
    |> change(
      state: state,
      remote_outcome_uncertain: delivery.remote_outcome_uncertain || state == "uncertain",
      next_attempt_at: nil,
      last_error_class: "permanent",
      last_error_code: "target_changed",
      version: delivery.version + 1
    )
    |> Commands.update!()
    |> project()
  end

  defp exhaust!(delivery, _now) do
    delivery
    |> change(
      state: if(delivery.remote_outcome_uncertain, do: "uncertain", else: "dead_letter"),
      next_attempt_at: nil,
      last_error_class: "permanent",
      last_error_code: "retry_exhausted",
      version: delivery.version + 1
    )
    |> Commands.update!()
    |> project()
  end

  defp finish_attempt!(%{last_attempt_id: nil}, _, _, _, _), do: :ok

  defp finish_attempt!(delivery, now, state, class, code) do
    attempt = Repo.get!(EventDeliveryAttempt, delivery.last_attempt_id)

    if attempt.state == "started",
      do:
        attempt
        |> change(state: state, finished_at: now, error_class: class, error_code: code)
        |> Commands.update!()

    :ok
  end

  def backoff(number), do: min(3600, 5 * Integer.pow(2, min(max(number - 1, 0), 10)))
  defp bounded_retry_after(n) when is_integer(n), do: n |> max(0) |> min(3600)
  defp bounded_retry_after(_), do: 0
  defp safe_code(code) when is_atom(code), do: safe_code(to_string(code))

  defp safe_code(code) when is_binary(code) do
    if Regex.match?(~r/\A[a-z0-9_]{1,80}\z/, code), do: code, else: "upstream_error"
  end

  defp safe_code(_), do: "upstream_error"
  defp min_time(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
end
