defmodule Samgita.CodexRuntime do
  @moduledoc """
  Durable, ordinary-Agent native runtime journals. This context makes no decisions.

  Agents explicitly create an intent, claim its one-use dispatch ticket, send it
  with their independently owned driver, then report its outcome. PostgreSQL
  authorization and fencing run before receipt replay and again before settling.
  No job, reconnect, event delivery or application restart dispatches a native call.
  Complete native payloads are encrypted separately from receipts and domain events.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.CodexRuntime.{Authorization, Journal, Native, Payload}
  alias Samgita.{Commands, Events, Params, Projection, Repo}
  alias Samgita.Domain.{NativeRuntimeBinding, NativeRuntimeEvent, NativeRuntimeOperation}
  @roles ~w(observer worker manager reviewer)

  def bind(principal, project_id, attrs) do
    attrs = Params.strings(attrs)

    safe =
      Map.take(
        attrs,
        ~w(command_id proof expected_version attempt_id runtime_ref instance_id driver_generation experimental)
      )

    Commands.run(
      principal,
      project_id,
      safe,
      [
        operation: "native_runtime.bind",
        target: attrs["attempt_id"],
        roles: ["worker"],
        execution: true,
        authorize: &Authorization.create_context(&1, attrs["attempt_id"], attrs["proof"])
      ],
      fn ctx ->
        Commands.expect!(ctx.attempt, safe)
        validate_instance!(attrs)
        fingerprint = take!(Payload.fingerprint(nil))
        [key_id, _] = String.split(fingerprint, ":", parts: 2)

        runtime = %NativeRuntimeBinding{
          project_id: project_id,
          task_id: ctx.task.id,
          attempt_id: ctx.attempt.id,
          agent_id: ctx.attempt.agent_id,
          session_id: ctx.attempt.session_id,
          connection_id: ctx.attempt.connection_id,
          connection_generation: ctx.attempt.connection_generation,
          fence: ctx.attempt.fence,
          execution_epoch: ctx.attempt.execution_epoch,
          runtime_ref: attrs["runtime_ref"],
          instance_id: attrs["instance_id"],
          driver_generation: attrs["driver_generation"],
          experimental: attrs["experimental"] == true,
          fingerprint_key_id: key_id
        }

        runtime =
          runtime
          |> change()
          |> unique_constraint(:attempt_id)
          |> unique_constraint(:runtime_ref)
          |> Commands.insert!()

        audit!(ctx, runtime, "native_runtime.bound", "native_runtime", runtime.id)
        runtime_projection(runtime)
      end
    )
  end

  def list(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, @roles, fn _ctx ->
      {limit, offset} = Params.page(params)

      rows =
        Repo.all(
          from r in NativeRuntimeBinding,
            where: r.project_id == ^project_id,
            order_by: r.id,
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(rows, &runtime_projection/1), "limit" => limit, "offset" => offset}
    end)
  end

  def get(principal, project_id, id) do
    read(principal, project_id, id, fn _ctx, runtime ->
      runtime_projection(runtime)
      |> Map.put("links", Journal.links(runtime.id))
    end)
  end

  def prepare(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    with {:ok, safe} <- protected_attrs(id, attrs) do
      command(principal, project_id, id, safe, "prepare", fn ctx ->
        runtime = ctx.runtime
        Commands.expect!(runtime, attrs)
        direction = Native.outgoing!(attrs["native"], runtime)

        active_mutation!(ctx.project, attrs["native"]["method"], direction)

        operation = insert_operation!(ctx, attrs["native"], direction, nil, timeout!(attrs))

        operation_projection(operation)
      end)
    end
  end

  @doc "Prepare an explicit native interaction decision; it does not send or grant approval."
  def reply(principal, project_id, id, interaction_id, attrs) do
    attrs = Params.strings(attrs)

    with {:ok, safe} <- protected_attrs(id, attrs) do
      safe = Map.put(safe, "interaction_id", interaction_id)

      command(
        principal,
        project_id,
        id,
        safe,
        "reply",
        fn ctx ->
          active_project!(ctx.project)
          interaction = interaction!(ctx.runtime, interaction_id)
          Commands.expect!(interaction, attrs)
          request = open!(interaction.native_payload, id, interaction.id, "event")
          Native.response!(attrs["native"], request, :client_response, interaction.method)
          pending_interaction!(interaction)

          operation =
            insert_operation!(
              ctx,
              attrs["native"],
              "client_response",
              interaction,
              timeout!(attrs)
            )

          interaction
          |> change(state: "reply_prepared", version: interaction.version + 1)
          |> Commands.update!()

          operation_projection(operation)
        end,
        operator_reply: true
      )
    end
  end

  @doc "One-use, non-cacheable dispatch ticket. An ambiguous retry never returns another ticket."
  def dispatch(principal, project_id, id, operation_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.read(principal, project_id, ["worker"], fn ctx ->
      ctx = Authorization.context(ctx, id, attrs["proof"])
      operation = operation!(id, operation_id)
      Commands.expect!(operation, attrs)
      current_instance!(ctx.runtime, operation)

      if operation.state != "prepared",
        do: Commands.fail!(:conflict, %{reason: "dispatch_not_repeatable"})

      dispatch_eligible!(ctx.runtime, operation)

      if ctx.project.state != "active" && operation.effect == "mutation" &&
           operation.method != "turn/interrupt",
         do: Commands.fail!(:execution_closed)

      native = open!(operation.request_payload, id, operation.id, "request")
      token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      operation =
        operation
        |> change(
          state: "in_flight",
          dispatch_token_digest: :crypto.hash(:sha256, token),
          dispatch_expires_at: deadline(ctx.attempt, operation.timeout_ms),
          version: operation.version + 1
        )
        |> Commands.update!()

      ctx = Map.put(ctx, :command_id, operation.id)
      audit!(ctx, ctx.runtime, "native_operation.dispatched", "native_operation", operation.id)

      operation_projection(operation)
      |> Map.put("native", native)
      |> Map.put("dispatch_token", token)
    end)
  end

  def settle(principal, project_id, id, operation_id, attrs) do
    attrs = Params.strings(attrs)

    with {:ok, safe} <- protected_attrs(id, attrs) do
      safe = Map.put(safe, "operation_id", operation_id)

      authorize = fn ctx ->
        ctx = Authorization.context(ctx, id, nil, require_proof: false)
        operation = operation!(id, operation_id)
        current_instance!(ctx.runtime, operation)
        token!(operation, attrs["dispatch_token"])
        Map.put(ctx, :operation, operation)
      end

      command(
        principal,
        project_id,
        id,
        safe,
        "settle",
        fn ctx ->
          operation = ctx.operation
          Commands.expect!(operation, attrs)
          settleable!(operation)

          state = settlement!(ctx.runtime, operation, attrs)

          response = seal_response(attrs["native"], id, operation.id)

          operation =
            operation
            |> change(state: state, response_payload: response, version: operation.version + 1)
            |> Commands.update!()

          Journal.settled!(ctx.runtime, operation, attrs["native"])

          audit!(
            ctx,
            ctx.runtime,
            "native_operation.settled",
            "native_operation",
            operation.id,
            %{"state" => state}
          )

          operation_projection(operation)
        end,
        authorize: authorize
      )
    end
  end

  @doc "Record an original driver sequence. This cursor is local evidence, not upstream replay."
  def record_event(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    with {:ok, safe} <- protected_attrs(id, attrs) do
      safe =
        Map.merge(
          safe,
          Map.take(
            attrs,
            ~w(instance_id driver_generation source_sequence interaction_timeout_ms)
          )
        )

      command(principal, project_id, id, safe, "event", fn ctx ->
        event = Journal.append!(ctx, attrs)
        event_projection(event)
      end)
    end
  end

  def operations(principal, project_id, id, params \\ %{}) do
    read(principal, project_id, id, fn _ctx, _runtime ->
      {limit, offset} = Params.page(params)

      rows =
        Repo.all(
          from o in NativeRuntimeOperation,
            where: o.runtime_id == ^id,
            order_by: [desc: o.inserted_at, asc: o.id],
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(rows, &operation_projection/1), "limit" => limit, "offset" => offset}
    end)
  end

  def events(principal, project_id, id, params \\ %{}) do
    read(principal, project_id, id, fn _ctx, _runtime ->
      {limit, offset} = Params.page(params)

      rows =
        Repo.all(
          from e in NativeRuntimeEvent,
            where: e.runtime_id == ^id,
            order_by: [desc: e.inserted_at, asc: e.id],
            limit: ^limit,
            offset: ^offset
        )

      %{"data" => Enum.map(rows, &event_projection/1), "limit" => limit, "offset" => offset}
    end)
  end

  @doc "Explicit protected payload retrieval. Callers must set Cache-Control: no-store."
  def native_operation(principal, project_id, id, operation_id) do
    read(principal, project_id, id, fn ctx, runtime ->
      Authorization.payload_owner!(ctx, runtime)
      operation = operation!(id, operation_id)
      result = operation_projection(operation)

      result =
        Map.put(result, "request", open!(operation.request_payload, id, operation.id, "request"))

      if operation.response_payload,
        do:
          Map.put(
            result,
            "response",
            open!(operation.response_payload, id, operation.id, "response")
          ),
        else: result
    end)
  end

  def native_event(principal, project_id, id, event_id) do
    read(principal, project_id, id, fn ctx, runtime ->
      Authorization.payload_owner!(ctx, runtime)
      event = event!(id, event_id)

      Map.put(
        event_projection(event),
        "native",
        open!(event.native_payload, id, event.id, "event")
      )
    end)
  end

  def reconnect(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)
    safe = Map.take(attrs, ~w(command_id proof expected_version instance_id driver_generation))

    command(
      principal,
      project_id,
      id,
      safe,
      "reconnect",
      fn ctx ->
        runtime = ctx.runtime
        Commands.expect!(runtime, attrs)
        validate_generation!(attrs)

        if attrs["instance_id"] == runtime.instance_id &&
             attrs["driver_generation"] <= runtime.driver_generation,
           do: Commands.fail!(:conflict)

        Repo.update_all(
          from(o in NativeRuntimeOperation,
            where: o.runtime_id == ^id and o.state in ["in_flight", "sent_unconfirmed"]
          ),
          set: [state: "uncertain"],
          inc: [version: 1]
        )

        Repo.update_all(
          from(o in NativeRuntimeOperation, where: o.runtime_id == ^id and o.state == "prepared"),
          set: [state: "cancelled"],
          inc: [version: 1]
        )

        Repo.update_all(
          from(e in NativeRuntimeEvent,
            where:
              e.runtime_id == ^id and e.kind == "server_request" and
                e.state not in ["resolution_observed", "terminal_observed"]
          ),
          set: [state: "stale"],
          inc: [version: 1]
        )

        runtime =
          runtime
          |> change(
            connection_id: ctx.attempt.connection_id,
            connection_generation: ctx.attempt.connection_generation,
            fence: ctx.attempt.fence,
            execution_epoch: ctx.attempt.execution_epoch,
            instance_id: attrs["instance_id"],
            driver_generation: attrs["driver_generation"],
            source_sequence: 0,
            notification_gap: true,
            version: runtime.version + 1
          )
          |> Commands.update!()

        audit!(ctx, runtime, "native_runtime.reconnected", "native_runtime", id, %{
          "notification_gap" => true
        })

        runtime_projection(runtime)
      end,
      rebind: true
    )
  end

  @doc "Evidence-only resolution. Never resends, clears a Task hold, or asserts upstream deduplication."
  def reconcile(principal, project_id, id, operation_id, attrs) do
    attrs = Params.strings(attrs)

    safe =
      Map.take(attrs, ~w(command_id expected_version evidence_ref))
      |> Map.put("operation_id", operation_id)

    history_command(principal, project_id, id, safe, "reconcile", fn ctx ->
      operation = operation!(id, operation_id)
      Commands.expect!(operation, attrs)

      unless operation.state in ~w(uncertain sent_unconfirmed) ||
               (operation.state == "in_flight" && Commands.expired?(operation.dispatch_expires_at)),
             do: Commands.fail!(:invalid_transition)

      evidence = evidence!(attrs)

      operation =
        operation
        |> change(state: "reconciled", evidence_ref: evidence, version: operation.version + 1)
        |> Commands.update!()

      audit!(ctx, ctx.runtime, "native_operation.reconciled", "native_operation", operation.id)
      operation_projection(operation)
    end)
  end

  @doc "Cancel an unsent intent. A dispatched operation requires explicit interruption/reconciliation."
  def cancel(principal, project_id, id, operation_id, attrs) do
    attrs = Params.strings(attrs)

    safe =
      Map.take(attrs, ~w(command_id expected_version)) |> Map.put("operation_id", operation_id)

    history_command(
      principal,
      project_id,
      id,
      safe,
      "cancel",
      fn ctx ->
        Authorization.payload_owner!(ctx, ctx.runtime)
        operation = operation!(id, operation_id)
        Commands.expect!(operation, attrs)
        if operation.state != "prepared", do: Commands.fail!(:uncertain_outcome)

        operation =
          operation
          |> change(state: "cancelled", version: operation.version + 1)
          |> Commands.update!()

        audit!(ctx, ctx.runtime, "native_operation.cancelled", "native_operation", operation.id)
        operation_projection(operation)
      end,
      operator_only: false
    )
  end

  @doc "Record operator evidence of cessation/gap assessment; does not settle operations or release Task holds."
  def attest_cessation(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)
    safe = Map.take(attrs, ~w(command_id expected_version evidence_ref))

    history_command(principal, project_id, id, safe, "attest_cessation", fn ctx ->
      Commands.expect!(ctx.runtime, attrs)
      evidence!(attrs)
      Journal.attest_cessation!(ctx.runtime.id)

      runtime =
        ctx.runtime
        |> change(notification_gap: false, version: ctx.runtime.version + 1)
        |> Commands.update!()

      audit!(ctx, runtime, "native_runtime.cessation_attested", "native_runtime", id, %{
        "evidence_ref" => attrs["evidence_ref"]
      })

      runtime_projection(runtime)
    end)
  end

  @doc "Conservative evidence guard; callers hold the existing Project/Task authority locks."
  def unresolved_effects?(attempt_id) do
    runtimes = from r in NativeRuntimeBinding, where: r.attempt_id == ^attempt_id, select: r.id

    Repo.exists?(
      from r in NativeRuntimeBinding, where: r.attempt_id == ^attempt_id and r.notification_gap
    ) ||
      Repo.exists?(
        from o in NativeRuntimeOperation,
          where:
            o.runtime_id in subquery(runtimes) and
              (o.state == "in_flight" or
                 (o.effect == "mutation" and o.state in ["uncertain", "sent_unconfirmed"]))
      ) ||
      Journal.unresolved_interactions?(runtimes) ||
      Journal.live_turns?(runtimes)
  end

  @doc false
  def operation_projection(operation) do
    Projection.fields(
      operation,
      ~w(id runtime_id interaction_id instance_id driver_generation direction method state effect timeout_ms dispatch_expires_at version inserted_at updated_at)a
    )
    |> Map.put("outcome_uncertain", uncertain?(operation))
  end

  @doc false
  def event_projection(event) do
    Projection.fields(
      event,
      ~w(id runtime_id instance_id driver_generation source_sequence kind method state expires_at version inserted_at)a
    )
    |> Map.put("expired", event.kind == "server_request" && Commands.expired?(event.expires_at))
  end

  @doc false
  def seal!(native, runtime_id, record_id, slot),
    do: take!(Payload.seal(native, Payload.aad(runtime_id, record_id, slot)))

  @doc false
  def open!(payload, runtime_id, record_id, slot),
    do: take!(Payload.open(payload, Payload.aad(runtime_id, record_id, slot)))

  @doc false
  def take!({:ok, value}), do: value
  def take!({:error, error}), do: Repo.rollback(error)

  defp command(principal, project_id, id, attrs, operation, callback, options \\ []) do
    authorize =
      Keyword.get(options, :authorize, &Authorization.context(&1, id, attrs["proof"], options))

    Commands.run(
      principal,
      project_id,
      attrs,
      [
        operation: "native_runtime." <> operation,
        target: id,
        roles: ["worker"],
        execution: true,
        agent_ids: Authorization.agent_ids(id),
        authorize: authorize
      ],
      callback
    )
  end

  defp read(principal, project_id, id, callback) do
    Commands.read(principal, project_id, @roles, fn ctx ->
      callback.(ctx, Authorization.scoped!(project_id, id))
    end)
  end

  defp history_command(principal, project_id, id, attrs, operation, callback, opts \\ []) do
    Commands.run(
      principal,
      project_id,
      attrs,
      [
        operation: "native_runtime." <> operation,
        target: id,
        roles: ["worker"],
        agent_ids: Authorization.agent_ids(id)
      ],
      fn ctx ->
        if Keyword.get(opts, :operator_only, true), do: Commands.operator!(principal)
        runtime = Authorization.scoped!(project_id, id)

        runtime =
          Repo.one!(
            from r in NativeRuntimeBinding, where: r.id == ^runtime.id, lock: "FOR UPDATE"
          )

        callback.(Map.put(ctx, :runtime, runtime))
      end
    )
  end

  defp protected_attrs(id, attrs) do
    runtime = if Params.uuid?(id), do: Repo.get(NativeRuntimeBinding, id)
    key_id = runtime && runtime.fingerprint_key_id

    with {:ok, digest} <- Payload.fingerprint(attrs["native"], key_id) do
      safe = Map.take(attrs, ~w(command_id proof expected_version delivery_outcome timeout_ms))
      {:ok, Map.put(safe, "native_fingerprint", digest)}
    end
  end

  defp insert_operation!(ctx, native, direction, interaction, timeout_ms) do
    runtime = ctx.runtime
    id = Ecto.UUID.generate()
    method = if interaction, do: interaction.method, else: native["method"]
    now = DateTime.utc_now()

    pending =
      Repo.aggregate(
        from(o in NativeRuntimeOperation,
          where: o.runtime_id == ^runtime.id and o.state in ["prepared", "in_flight"]
        ),
        :count
      )

    if pending >= 128, do: Commands.fail!(:capacity_exceeded)

    # Notifications have no wire ID. Keep their local journal identity separate
    # from the unchanged native envelope, allowing distinct explicit sends.
    identity = if direction == "client_notification", do: [direction, id], else: native["id"]

    operation = %NativeRuntimeOperation{
      id: id,
      runtime_id: runtime.id,
      instance_id: runtime.instance_id,
      driver_generation: runtime.driver_generation,
      direction: direction,
      method: method,
      effect: if(interaction, do: "mutation", else: Native.effect(method, direction)),
      interaction_id: interaction && interaction.id,
      timeout_ms: timeout_ms,
      wire_id_digest: take!(Payload.fingerprint(identity, runtime.fingerprint_key_id)),
      request_payload: seal!(native, runtime.id, id, "request"),
      inserted_at: now,
      updated_at: now
    }

    operation =
      operation
      |> change()
      |> unique_constraint(:wire_id_digest, name: :native_runtime_request_generation_identity)
      |> Commands.insert!()

    audit!(ctx, runtime, "native_operation.prepared", "native_operation", id, %{
      "method" => method,
      "direction" => direction
    })

    operation
  end

  defp operation!(runtime_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from o in NativeRuntimeOperation,
        where: o.id == ^id and o.runtime_id == ^runtime_id,
        lock: "FOR UPDATE"
    ) || Commands.fail!(:not_found)
  end

  defp event!(runtime_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)
    Repo.get_by(NativeRuntimeEvent, id: id, runtime_id: runtime_id) || Commands.fail!(:not_found)
  end

  defp interaction!(runtime, id) do
    event = event!(runtime.id, id)
    current_instance!(runtime, event)

    if event.kind != "server_request" || Commands.expired?(event.expires_at),
      do: Commands.fail!(:stale_interaction)

    event
  end

  defp current_instance!(runtime, record) do
    if record.instance_id != runtime.instance_id ||
         record.driver_generation != runtime.driver_generation,
       do: Commands.fail!(:ownership_lost)
  end

  defp dispatch_eligible!(runtime, %{direction: "client_response"} = operation) do
    event = interaction!(runtime, operation.interaction_id)
    if event.state != "reply_prepared", do: Commands.fail!(:stale_interaction)
  end

  # An explicit interruption remains available to stop an uncertain running turn.
  # It is a new control request, never replay of the possibly executed mutation.
  defp dispatch_eligible!(_runtime, %{method: "turn/interrupt"}), do: :ok

  defp dispatch_eligible!(runtime, %{effect: "mutation"}) do
    now = DateTime.utc_now()

    ambiguous =
      Repo.exists?(
        from o in NativeRuntimeOperation,
          where:
            o.runtime_id == ^runtime.id and o.effect == "mutation" and
              (o.state in ["uncertain", "sent_unconfirmed"] or
                 (o.state == "in_flight" and o.dispatch_expires_at <= ^now))
      )

    if ambiguous, do: Commands.fail!(:uncertain_outcome)
  end

  defp dispatch_eligible!(_runtime, _operation), do: :ok

  defp token!(operation, token) when is_binary(token) and byte_size(token) <= 128 do
    digest = :crypto.hash(:sha256, token)

    if !is_binary(operation.dispatch_token_digest) ||
         !:crypto.hash_equals(digest, operation.dispatch_token_digest),
       do: Commands.fail!(:unauthorized)
  end

  defp token!(_operation, _token), do: Commands.fail!(:unauthorized)

  defp settlement!(_runtime, %{direction: direction}, attrs)
       when direction in ~w(client_response client_notification) do
    if attrs["native"] != nil || attrs["delivery_outcome"] not in ~w(sent_unconfirmed uncertain),
      do: Commands.fail!(:invalid_native_payload)

    attrs["delivery_outcome"]
  end

  defp settlement!(runtime, operation, %{"native" => native}) when is_map(native) do
    request = open!(operation.request_payload, runtime.id, operation.id, "request")
    Native.response!(native, request, :server_response, operation.method)
    if Map.has_key?(native, "error"), do: "native_error", else: "completed"
  end

  defp settlement!(_runtime, _operation, %{"delivery_outcome" => "uncertain"}), do: "uncertain"
  defp settlement!(_runtime, _operation, _attrs), do: Commands.fail!(:invalid_native_payload)

  defp uncertain?(%{state: state}) when state in ~w(uncertain sent_unconfirmed), do: true

  defp uncertain?(%{state: "in_flight", dispatch_expires_at: deadline}),
    do: Commands.expired?(deadline)

  defp uncertain?(_), do: false

  defp runtime_projection(runtime),
    do:
      Projection.fields(
        runtime,
        ~w(id project_id task_id attempt_id agent_id session_id connection_id connection_generation fence execution_epoch runtime_ref instance_id driver_generation driver driver_version experimental state source_sequence notification_gap version inserted_at updated_at)a
      )

  defp validate_instance!(attrs) do
    validate_generation!(attrs)

    if !Params.uuid?(attrs["runtime_ref"]) || attrs["experimental"] not in [nil, true, false],
      do: Commands.fail!(:invalid)
  end

  defp validate_generation!(attrs) do
    if !Params.uuid?(attrs["instance_id"]) || !is_integer(attrs["driver_generation"]) ||
         attrs["driver_generation"] not in 1..2_147_483_647,
       do: Commands.fail!(:invalid, %{reason: "invalid_runtime_instance"})
  end

  defp timeout!(attrs) do
    timeout = Map.get(attrs, "timeout_ms", 30_000)

    if !is_integer(timeout) || timeout not in 1..300_000,
      do: Commands.fail!(:invalid, %{field: "timeout_ms"})

    timeout
  end

  defp active_project!(%{state: "active"}), do: :ok
  defp active_project!(_), do: Commands.fail!(:execution_closed)
  defp pending_interaction!(%{state: "pending"}), do: :ok
  defp pending_interaction!(_), do: Commands.fail!(:conflict)

  defp active_mutation!(project, method, direction) do
    if method != "turn/interrupt" && Native.effect(method, direction) == "mutation",
      do: active_project!(project)
  end

  defp settleable!(operation) do
    if operation.state != "in_flight", do: Commands.fail!(:conflict)
    if Commands.expired?(operation.dispatch_expires_at), do: Commands.fail!(:uncertain_outcome)
  end

  defp seal_response(nil, _, _), do: nil
  defp seal_response(native, id, operation_id), do: seal!(native, id, operation_id, "response")

  defp deadline(attempt, timeout_ms) do
    [
      DateTime.add(DateTime.utc_now(), timeout_ms, :millisecond),
      attempt.execution_deadline,
      attempt.lease_expires_at
    ]
    |> Enum.min_by(&DateTime.to_unix(&1, :microsecond))
  end

  defp evidence!(attrs) do
    value = attrs["evidence_ref"]

    if !is_binary(value) || String.trim(value) == "" || byte_size(value) > 512 ||
         String.contains?(value, <<0>>),
       do: Commands.fail!(:invalid, %{field: "evidence_ref"})

    value
  end

  defp audit!(ctx, runtime, type, resource, id, data \\ %{}) do
    Events.append!(
      runtime.project_id,
      type,
      ctx,
      resource,
      id,
      Map.merge(%{"runtime_id" => runtime.id, "task_id" => runtime.task_id}, data)
    )
  end
end
