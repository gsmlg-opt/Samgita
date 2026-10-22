defmodule Samgita.Events do
  @moduledoc "Transactional source events, explicit responsible-Agent routing and durable cursors."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Params, Projection, Repo}

  alias Samgita.Domain.{
    Agent,
    DomainEvent,
    EventDelivery,
    EventSubscription,
    ExternalEvent,
    Project,
    ProjectAgent,
    Task
  }

  @read_roles ~w(observer worker manager reviewer)
  @payload_fields ~w(reason summary reference subject external_ref status labels repository_id task_id check)

  def append!(
        project_id,
        type,
        %{principal: principal, command_id: command_id} = ctx,
        resource_type,
        resource_id,
        data \\ %{},
        states \\ []
      ) do
    if !Repo.in_transaction?(), do: raise("events require an aggregate transaction")

    sequence =
      if project_id do
        {1, [sequence]} =
          Repo.update_all(
            from(p in Project, where: p.id == ^project_id, select: p.event_sequence),
            inc: [event_sequence: 1]
          )

        sequence
      end

    event =
      %DomainEvent{}
      |> Ecto.Changeset.change(
        project_id: project_id,
        sequence: sequence,
        type: type,
        actor: Commands.actor_key(principal),
        command_id: command_id,
        correlation_id: Map.get(ctx, :correlation_id, command_id),
        causation_id: Map.get(ctx, :causation_id),
        source: Map.get(ctx, :source, "domain"),
        source_id: Map.get(ctx, :source_id),
        resource_type: resource_type,
        resource_id: resource_id,
        data: data,
        before_state: snapshot(Keyword.get(states, :previous)),
        after_state: snapshot(Keyword.get(states, :current)),
        created_at: DateTime.utc_now()
      )
      |> Repo.insert!()

    if project_id && Map.get(ctx, :notify, true) do
      Repo.all(from s in EventSubscription, where: s.project_id == ^project_id and s.enabled)
      |> Enum.filter(&(&1.types == [] || type in &1.types))
      |> Enum.each(fn subscription ->
        delivery =
          %EventDelivery{}
          |> change(
            event_id: event.id,
            subscription_id: subscription.id,
            subscription_revision: subscription.revision,
            project_id: project_id,
            agent_id: subscription.agent_id,
            operation_id: Ecto.UUID.generate(),
            target_digest: subscription.target_digest,
            next_attempt_at: DateTime.utc_now(),
            state: if(subscription.target_digest, do: "pending", else: "legacy_unreviewed")
          )
          |> Repo.insert!()

        if delivery.state == "pending", do: enqueue!(delivery)
      end)
    end

    event
  end

  @doc "Explicitly bind one responsible Agent. Capabilities are checked after membership grants."
  def configure(principal, project_id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "events.configure", agent_ids: [attrs["agent_id"]]],
      fn ctx ->
        Commands.operator!(principal)
        Commands.expect!(ctx.project, attrs)
        agent = Repo.get(Agent, attrs["agent_id"]) || Commands.fail!(:not_found)
        member = Repo.get_by(ProjectAgent, project_id: project_id, agent_id: agent.id)

        if !agent.enabled || !member || !member.enabled || "manager" not in member.roles,
          do: Commands.fail!(:forbidden)

        if "project_events.v1" not in agent.approved_capabilities ||
             "project_events.v1" not in agent.advertised_capabilities,
           do: Commands.fail!(:invalid, %{reason: "project_events_required"})

        types = attrs["types"] || []

        if !is_list(types) || length(types) > 100 || !Enum.all?(types, &event_type?/1) ||
             attrs["idempotency_guaranteed"] not in [nil, true, false],
           do: Commands.fail!(:invalid)

        old =
          Repo.one(
            from s in EventSubscription,
              where: s.project_id == ^project_id and s.purpose == "responsible" and s.enabled
          )

        if old,
          do: old |> change(enabled: false, revision: old.revision + 1) |> Commands.update!()

        subscription =
          %EventSubscription{}
          |> change(
            project_id: project_id,
            agent_id: agent.id,
            purpose: "responsible",
            types: types,
            target_digest: target_digest(agent),
            idempotency_guaranteed: attrs["idempotency_guaranteed"] == true
          )
          |> Commands.insert!()

        project = ctx.project |> change(version: ctx.project.version + 1) |> Commands.update!()

        append!(
          project_id,
          "event.routing_configured",
          Map.put(ctx, :notify, false),
          "subscription",
          subscription.id,
          %{"agent_id" => agent.id, "previous_subscription_id" => old && old.id}
        )

        Map.put(subscription_projection(subscription), "project_version", project.version)
      end
    )
  end

  def trigger(principal, project_id, attrs),
    do: source_event(principal, project_id, attrs, :manual)

  def external(principal, project_id, attrs),
    do: source_event(principal, project_id, attrs, :external)

  @doc "Explicitly replay an original event to a selected current subscription. Never retarget a delivery."
  def redeliver(principal, project_id, event_id, attrs) do
    attrs = Params.strings(attrs)

    subscription =
      if Params.uuid?(attrs["subscription_id"]),
        do: Repo.get(EventSubscription, attrs["subscription_id"])

    agent_ids = if subscription, do: [subscription.agent_id], else: []

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "events.redeliver:#{event_id}", agent_ids: agent_ids],
      fn ctx ->
        Commands.operator!(principal)
        Commands.require_hub!(ctx)
        if !Params.uuid?(event_id), do: Commands.fail!(:not_found)

        event =
          Repo.get_by(DomainEvent, id: event_id, project_id: project_id) ||
            Commands.fail!(:not_found)

        target = subscription!(project_id, attrs["subscription_id"])
        agent = Repo.get!(Agent, target.agent_id)
        member = Repo.get_by(ProjectAgent, project_id: project_id, agent_id: agent.id)

        if !target.enabled || target.purpose != "responsible" ||
             attrs["expected_subscription_revision"] != target.revision ||
             !agent.enabled || !member || !member.enabled || "manager" not in member.roles ||
             "project_events.v1" not in agent.approved_capabilities ||
             target.target_digest != target_digest(agent),
           do: Commands.fail!(:ownership_lost)

        if !is_binary(attrs["reason"]) || byte_size(attrs["reason"]) not in 1..2000 ||
             !is_binary(attrs["evidence_ref"]) || byte_size(attrs["evidence_ref"]) not in 1..2000,
           do: Commands.fail!(:invalid)

        previous =
          if Params.uuid?(attrs["source_delivery_id"]),
            do:
              Repo.get_by(EventDelivery,
                id: attrs["source_delivery_id"],
                project_id: project_id,
                event_id: event.id
              )

        existing = Repo.all(from d in EventDelivery, where: d.event_id == ^event.id)

        if existing != [] && !previous,
          do: Commands.fail!(:invalid, %{field: "source_delivery_id"})

        if Enum.any?(existing, &(&1.attempt_count > 0)) && attrs["risk_acknowledged"] != true,
          do: Commands.fail!(:conflict, %{reason: "duplicate_effect_risk"})

        if Repo.exists?(
             from d in EventDelivery,
               where: d.event_id == ^event.id and d.subscription_id == ^target.id
           ),
           do: Commands.fail!(:conflict, %{reason: "use_existing_delivery_recovery"})

        delivery =
          %EventDelivery{}
          |> change(
            event_id: event.id,
            project_id: project_id,
            agent_id: target.agent_id,
            subscription_id: target.id,
            subscription_revision: target.revision,
            target_digest: target.target_digest,
            operation_id: Ecto.UUID.generate(),
            next_attempt_at: DateTime.utc_now()
          )
          |> Commands.insert!()

        %Samgita.Domain.EventRecoveryAction{}
        |> change(
          delivery_id: delivery.id,
          previous_delivery_id: previous && previous.id,
          command_id: ctx.command_id,
          action: "retarget_redelivery",
          reason: attrs["reason"],
          evidence_ref: attrs["evidence_ref"],
          risk_acknowledged: attrs["risk_acknowledged"] == true,
          previous_state: if(previous, do: previous.state, else: "no_delivery"),
          resulting_state: "pending"
        )
        |> Commands.insert!()

        enqueue!(delivery)
        Samgita.EventDelivery.project(delivery)
      end
    )
  end

  defp source_event(principal, project_id, attrs, source) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "events.#{source}", roles: ["manager"]],
      fn ctx ->
        if source == :external, do: Commands.operator!(principal)
        if ctx.project.state != "active", do: Commands.fail!(:invalid_transition)
        payload = attrs["payload"] || %{}
        if validate_payload(payload) != :ok, do: Commands.fail!(:invalid, %{field: "payload"})
        validate_task!(project_id, payload["task_id"])
        validate_causation!(project_id, attrs["causation_id"])

        if attrs["correlation_id"] && !Params.uuid?(attrs["correlation_id"]),
          do: Commands.fail!(:invalid)

        ctx =
          ctx
          |> Map.put(:correlation_id, attrs["correlation_id"] || ctx.command_id)
          |> Map.put(:causation_id, attrs["causation_id"])

        if source == :external do
          external_source = attrs["source"]
          external_id = attrs["external_id"]
          if !safe_id?(external_source) || !safe_id?(external_id), do: Commands.fail!(:invalid)

          digest =
            Commands.digest(%{
              "payload" => payload,
              "correlation_id" => attrs["correlation_id"],
              "causation_id" => attrs["causation_id"]
            })

          case Repo.get_by(ExternalEvent,
                 project_id: project_id,
                 source: external_source,
                 external_id: external_id
               ) do
            nil ->
              inbox_id = Ecto.UUID.generate()

              event =
                append!(
                  project_id,
                  "external.received",
                  Map.merge(ctx, %{source: external_source, source_id: external_id}),
                  "external_event",
                  inbox_id,
                  payload
                )

              %ExternalEvent{id: inbox_id}
              |> change(
                project_id: project_id,
                source: external_source,
                external_id: external_id,
                payload_digest: digest,
                event_id: event.id
              )
              |> Commands.insert!()

              event_projection(event)

            inbox ->
              if inbox.payload_digest != digest,
                do: Commands.fail!(:conflict, %{reason: "external_id_reused"})

              event_projection(Repo.get!(DomainEvent, inbox.event_id))
          end
        else
          append!(
            project_id,
            "manual.triggered",
            Map.put(ctx, :source, "manual"),
            "project",
            project_id,
            payload
          )
          |> event_projection()
        end
      end
    )
  end

  def read(principal, project_id, params \\ %{}) do
    params = Params.strings(params)

    Commands.read(principal, project_id, @read_roles, fn ctx ->
      {limit, _} = Params.page(params)
      after_sequence = cursor_value(params["after"] || 0)

      data =
        Repo.all(
          from e in DomainEvent,
            where: e.project_id == ^project_id and e.sequence > ^after_sequence,
            order_by: e.sequence,
            limit: ^limit
        )

      %{
        "data" => Enum.map(data, &event_projection/1),
        "cursor" => if(data == [], do: after_sequence, else: List.last(data).sequence),
        "high_watermark" => ctx.project.event_sequence,
        "limit" => limit
      }
    end)
  end

  def routing(principal, project_id) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      case Repo.one(
             from s in EventSubscription,
               where: s.project_id == ^project_id and s.purpose == "responsible" and s.enabled
           ) do
        nil -> %{"subscription" => nil}
        subscription -> subscription_projection(subscription)
      end
    end)
  end

  def ack_cursor(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "events.cursor:#{id}", roles: ["manager"]],
      fn ctx ->
        subscription = subscription!(project_id, id)

        if principal.kind != :agent || principal.agent_id != subscription.agent_id,
          do: Commands.fail!(:forbidden)

        if !subscription.enabled, do: Commands.fail!(:ownership_lost)
        cursor = cursor_value(attrs["cursor"])

        if cursor < subscription.cursor || cursor > ctx.project.event_sequence,
          do: Commands.fail!(:invalid, %{reason: "cursor_out_of_range"})

        gap =
          Repo.exists?(
            from d in EventDelivery,
              join: e in DomainEvent,
              on: e.id == d.event_id,
              where:
                d.subscription_id == ^id and e.sequence > ^subscription.cursor and
                  e.sequence <= ^cursor and is_nil(d.accepted_at)
          )

        if gap, do: Commands.fail!(:conflict, %{reason: "unacknowledged_gap"})
        subscription |> change(cursor: cursor) |> Commands.update!() |> subscription_projection()
      end
    )
  end

  def subscription!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.one(
      from s in EventSubscription,
        where: s.id == ^id and s.project_id == ^project_id,
        lock: "FOR UPDATE"
    ) || Commands.fail!(:not_found)
  end

  def target_digest(agent),
    do:
      Commands.digest(
        {agent.id, agent.protocol, agent.protocol_version, agent.endpoint_metadata,
         agent.credential_ref}
      )

  def enqueue!(delivery, enqueue \\ &Oban.insert/1) do
    case enqueue.(Samgita.Workers.EventDeliveryWorker.new(%{"delivery_id" => delivery.id})) do
      {:ok, job} -> job
      {:error, _} -> Commands.fail!(:enqueue_failed, %{delivery_id: delivery.id})
    end
  end

  def envelope(event, attempt_id) do
    %{
      "schema_version" => event.schema_version,
      "event_id" => event.id,
      "delivery_attempt_id" => attempt_id,
      "created_at" => DateTime.to_iso8601(event.created_at),
      "correlation_id" => event.correlation_id || event.command_id,
      "type" => event.type,
      "project_ref" => event.project_id,
      "payload" => %{
        "sequence" => event.sequence,
        "resource_type" => event.resource_type,
        "resource_id" => event.resource_id,
        "source" => event.source,
        "source_id" => event.source_id,
        "data" => event.data,
        "before" => event.before_state,
        "after" => event.after_state
      }
    }
    |> optional("causation_id", event.causation_id)
    |> optional(
      "task_ref",
      if(event.resource_type == "task", do: event.resource_id, else: event.data["task_id"])
    )
  end

  def event_projection(event),
    do:
      Projection.fields(
        event,
        ~w(id project_id sequence type schema_version actor command_id correlation_id causation_id source source_id resource_type resource_id data before_state after_state created_at)a
      )

  def subscription_projection(s),
    do:
      Projection.fields(
        s,
        ~w(id project_id agent_id types enabled revision purpose idempotency_guaranteed cursor)a
      )

  def validate_payload(payload) when is_map(payload) and not is_struct(payload) do
    valid =
      Enum.all?(payload, fn
        {"labels", labels} ->
          is_list(labels) && length(labels) <= 50 &&
            Enum.all?(
              labels,
              &(is_binary(&1) && String.valid?(&1) && byte_size(&1) <= 100 &&
                  !String.contains?(&1, <<0>>))
            )

        {key, value} ->
          key in @payload_fields && is_binary(value) && String.valid?(value) &&
            byte_size(value) <= 2000 && !String.contains?(value, <<0>>)
      end)

    if valid && byte_size(Jason.encode!(payload)) <= 16_384,
      do: :ok,
      else: {:error, :invalid_payload}
  end

  def validate_payload(_), do: {:error, :invalid_payload}

  defp validate_task!(_, nil), do: :ok

  defp validate_task!(project_id, id) do
    if !Params.uuid?(id) ||
         !Repo.exists?(from t in Task, where: t.id == ^id and t.project_id == ^project_id),
       do: Commands.fail!(:not_found)
  end

  defp validate_causation!(_, nil), do: :ok

  defp validate_causation!(project_id, id) do
    if !Params.uuid?(id) ||
         !Repo.exists?(from e in DomainEvent, where: e.id == ^id and e.project_id == ^project_id),
       do: Commands.fail!(:not_found)
  end

  defp optional(map, _, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)

  defp event_type?(v),
    do: is_binary(v) && byte_size(v) <= 100 && Regex.match?(~r/\A[a-z][a-z0-9_.]*\z/, v)

  defp safe_id?(v),
    do: is_binary(v) && byte_size(v) in 1..200 && Regex.match?(~r/\A[A-Za-z0-9_.:\/-]+\z/, v)

  defp cursor_value(v) when is_integer(v) and v >= 0, do: v

  defp cursor_value(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n >= 0 -> n
      _ -> Commands.fail!(:invalid)
    end
  end

  defp cursor_value(_), do: Commands.fail!(:invalid)

  def snapshot(nil), do: nil

  def snapshot(record) do
    Map.take(record, [
      :state,
      :version,
      :enabled,
      :generation,
      :owner,
      :admission_open,
      :epoch,
      :adopted,
      :execution_hold
    ])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end
end
