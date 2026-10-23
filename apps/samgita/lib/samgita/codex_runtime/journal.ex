defmodule Samgita.CodexRuntime.Journal do
  @moduledoc false
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{CodexRuntime, Commands, Repo}
  alias Samgita.CodexRuntime.{Native, Payload}
  alias Samgita.Domain.{NativeRuntimeEvent, NativeRuntimeLink, NativeRuntimeOperation}
  alias SamgitaProtocolCodex.Wire

  def append!(ctx, attrs) do
    runtime = ctx.runtime
    sequence = attrs["source_sequence"]
    instance!(runtime, attrs)
    wire = attrs["native"]
    fingerprint = CodexRuntime.take!(Payload.fingerprint(wire, runtime.fingerprint_key_id))

    case Repo.get_by(NativeRuntimeEvent,
           runtime_id: runtime.id,
           instance_id: runtime.instance_id,
           driver_generation: runtime.driver_generation,
           source_sequence: sequence
         ) do
      nil -> append_new!(ctx, attrs, fingerprint)
      %{fingerprint: ^fingerprint} = event -> event
      _ -> Commands.fail!(:conflict, %{reason: "native_source_sequence_reused"})
    end
  end

  defp append_new!(ctx, attrs, fingerprint) do
    runtime = ctx.runtime
    sequence = attrs["source_sequence"]
    Commands.expect!(runtime, attrs)

    if sequence <= runtime.source_sequence,
      do: Commands.fail!(:conflict, %{reason: "native_source_sequence_out_of_order"})

    {kind, method} = event_kind!(attrs["native"], runtime)
    capacity!(runtime, kind)
    id = Ecto.UUID.generate()
    wire = attrs["native"]
    request? = kind == "server_request"

    event = %NativeRuntimeEvent{
      id: id,
      runtime_id: runtime.id,
      instance_id: runtime.instance_id,
      driver_generation: runtime.driver_generation,
      source_sequence: sequence,
      kind: kind,
      method: method,
      fingerprint: fingerprint,
      native_payload: CodexRuntime.seal!(wire, runtime.id, id, "event"),
      state: if(request?, do: "pending", else: "recorded"),
      expires_at: if(request?, do: interaction_deadline!(ctx, attrs)),
      request_id_digest: if(request?, do: digest!(runtime, wire["id"])),
      thread_id_digest: if(request?, do: digest!(runtime, thread_id(wire)))
    }

    event =
      event
      |> change()
      |> unique_constraint([:runtime_id, :instance_id, :driver_generation, :source_sequence],
        name: :native_event_source_identity
      )
      |> unique_constraint([:runtime_id, :instance_id, :driver_generation, :request_id_digest],
        name: :native_server_request_identity
      )
      |> Commands.insert!()

    runtime
    |> change(
      source_sequence: sequence,
      notification_gap: runtime.notification_gap || sequence != runtime.source_sequence + 1,
      version: runtime.version + 1
    )
    |> Commands.update!()

    observe_links!(runtime.id, wire)
    observe_resolution!(runtime, wire)
    event
  end

  def settled!(runtime, %{direction: "client_response"} = operation, _wire) do
    Repo.update_all(
      from(e in NativeRuntimeEvent,
        where: e.id == ^operation.interaction_id and e.runtime_id == ^runtime.id
      ),
      set: [state: operation.state],
      inc: [version: 1]
    )
  end

  def settled!(runtime, operation, %{"result" => result}) do
    request = CodexRuntime.open!(operation.request_payload, runtime.id, operation.id, "request")

    if is_map(result) do
      thread = result["thread"]
      if is_map(thread), do: link_thread!(runtime.id, thread)
      turn = result["turn"]
      if is_map(turn), do: link_turn!(runtime.id, turn, get_in(request, ["params", "threadId"]))
    end
  end

  def settled!(_runtime, _operation, _wire), do: :ok

  def links(runtime_id) do
    Repo.all(
      from l in NativeRuntimeLink, where: l.runtime_id == ^runtime_id, order_by: l.id, limit: 100
    )
    |> Enum.map(
      &Samgita.Projection.fields(
        &1,
        ~w(id kind external_id parent_external_id state inserted_at updated_at)a
      )
    )
  end

  def live_turns?(runtimes) do
    Repo.exists?(
      from l in NativeRuntimeLink,
        where:
          l.runtime_id in subquery(runtimes) and
            ((l.kind == "turn" and
                l.state not in ["completed", "failed", "interrupted", "cessation_attested"]) or
               (l.kind == "thread" and l.state == "active"))
    )
  end

  def unresolved_interactions?(runtimes) do
    Repo.exists?(
      from e in NativeRuntimeEvent,
        where:
          e.runtime_id in subquery(runtimes) and e.kind == "server_request" and
            e.state not in ["resolution_observed", "cessation_attested", "terminal_observed"]
    )
  end

  def attest_cessation!(runtime_id) do
    Repo.update_all(
      from(e in NativeRuntimeEvent,
        where:
          e.runtime_id == ^runtime_id and
            e.kind == "server_request" and e.state != "resolution_observed"
      ),
      set: [state: "cessation_attested"],
      inc: [version: 1]
    )

    Repo.update_all(
      from(l in NativeRuntimeLink,
        where:
          l.runtime_id == ^runtime_id and
            ((l.kind == "turn" and l.state not in ["completed", "failed", "interrupted"]) or
               (l.kind == "thread" and l.state == "active"))
      ),
      set: [state: "cessation_attested"]
    )
  end

  defp interaction_deadline!(ctx, attrs) do
    timeout = Map.get(attrs, "interaction_timeout_ms", 60_000)

    if !is_integer(timeout) || timeout not in 1..60_000,
      do: Commands.fail!(:invalid, %{field: "interaction_timeout_ms"})

    [
      DateTime.add(DateTime.utc_now(), timeout, :millisecond),
      ctx.attempt.execution_deadline,
      ctx.attempt.lease_expires_at
    ]
    |> Enum.min_by(&DateTime.to_unix(&1, :microsecond))
  end

  defp instance!(runtime, attrs) do
    if attrs["instance_id"] != runtime.instance_id ||
         attrs["driver_generation"] != runtime.driver_generation,
       do: Commands.fail!(:ownership_lost)

    if !is_integer(attrs["source_sequence"]) ||
         attrs["source_sequence"] not in 1..9_223_372_036_854_775_807,
       do: Commands.fail!(:invalid)
  end

  defp event_kind!(wire, runtime) do
    if Wire.classify(wire) in [:response, :error] do
      digest = digest!(runtime, wire["id"])

      operation =
        Repo.get_by(NativeRuntimeOperation,
          runtime_id: runtime.id,
          instance_id: runtime.instance_id,
          driver_generation: runtime.driver_generation,
          direction: "client_request",
          wire_id_digest: digest
        ) || Commands.fail!(:invalid_native_payload)

      request = CodexRuntime.open!(operation.request_payload, runtime.id, operation.id, "request")
      Native.response!(wire, request, :server_response, operation.method)
      {"server_response", operation.method}
    else
      {Native.event!(wire, runtime), wire["method"]}
    end
  end

  defp capacity!(runtime, "server_request") do
    now = DateTime.utc_now()

    count =
      Repo.aggregate(
        from(e in NativeRuntimeEvent,
          where: e.runtime_id == ^runtime.id and e.state == "pending" and e.expires_at > ^now
        ),
        :count
      )

    if count >= 128, do: Commands.fail!(:capacity_exceeded)
  end

  defp capacity!(_runtime, _kind), do: :ok

  defp observe_links!(runtime_id, %{"params" => %{"thread" => thread}}) when is_map(thread),
    do: link_thread!(runtime_id, thread)

  defp observe_links!(runtime_id, %{"params" => %{"turn" => turn, "threadId" => thread_id}})
       when is_map(turn),
       do: link_turn!(runtime_id, turn, thread_id)

  defp observe_links!(runtime_id, %{"method" => "thread/status/changed", "params" => params}),
    do: link!(runtime_id, "thread", params["threadId"], nil, lifecycle(params["status"]))

  defp observe_links!(_runtime_id, _wire), do: :ok

  defp link_thread!(runtime_id, %{"id" => id} = thread) when is_binary(id) do
    link!(runtime_id, "thread", id, nil, lifecycle(thread["status"]))
    Enum.each(Map.get(thread, "turns", []), &link_turn!(runtime_id, &1, id))
  end

  defp link_thread!(_runtime_id, _thread), do: :ok

  defp link_turn!(runtime_id, %{"id" => id} = turn, parent) when is_binary(id),
    do: link!(runtime_id, "turn", id, parent, turn["status"] || "observed")

  defp link_turn!(_runtime_id, _turn, _parent), do: :ok

  defp link!(runtime_id, kind, id, parent, state) do
    # Only native IDs and lifecycle states enter the public link projection.
    state = if is_binary(state), do: state, else: "observed"

    if !valid_id?(id) || (parent != nil && !valid_id?(parent)),
      do: Commands.fail!(:invalid_native_payload)

    %NativeRuntimeLink{
      runtime_id: runtime_id,
      kind: kind,
      external_id: id,
      parent_external_id: parent,
      state: state
    }
    |> Repo.insert!(
      on_conflict: {:replace, [:state, :parent_external_id, :updated_at]},
      conflict_target: [:runtime_id, :kind, :external_id]
    )
  end

  defp observe_resolution!(runtime, %{"method" => "serverRequest/resolved", "params" => params}) do
    interactions = resolution_interactions(runtime, params)

    Repo.update_all(
      interactions,
      set: [state: "resolution_observed"],
      inc: [version: 1]
    )

    interaction_ids = from e in interactions, select: e.id

    Repo.update_all(
      from(o in NativeRuntimeOperation,
        where:
          o.runtime_id == ^runtime.id and
            o.instance_id == ^runtime.instance_id and
            o.driver_generation == ^runtime.driver_generation and
            o.interaction_id in subquery(interaction_ids) and
            o.state in ["in_flight", "sent_unconfirmed", "uncertain"]
      ),
      set: [state: "completed"],
      inc: [version: 1]
    )
  end

  defp observe_resolution!(
         runtime,
         %{
           "method" => "item/completed",
           "params" => %{"item" => %{"type" => "dynamicToolCall", "status" => status}} = params
         }
       )
       when status in ["completed", "failed"] do
    retire_dynamic_interactions!(runtime, params["threadId"], params["turnId"], fn request ->
      get_in(request, ["params", "callId"]) == params["item"]["id"]
    end)
  end

  defp observe_resolution!(
         runtime,
         %{"method" => "turn/completed", "params" => %{"turn" => %{"status" => status}} = params}
       )
       when status in ["completed", "interrupted", "failed"] do
    retire_dynamic_interactions!(runtime, params["threadId"], params["turn"]["id"], fn _ ->
      true
    end)
  end

  defp observe_resolution!(_runtime, _wire), do: :ok

  defp retire_dynamic_interactions!(runtime, thread_id, turn_id, matches_item) do
    # Runtime ownership is already locked by the command context. Stream bounded
    # batches because turn/call IDs stay inside encrypted payloads, including for
    # historical records. Terminal evidence cannot settle a dispatched response.
    retirement_candidates(runtime, thread_id)
    |> Repo.stream(max_rows: 128)
    |> Enum.each(fn event ->
      request = CodexRuntime.open!(event.native_payload, runtime.id, event.id, "event")

      if get_in(request, ["params", "threadId"]) == thread_id and
           get_in(request, ["params", "turnId"]) == turn_id and matches_item.(request),
         do: retire_interaction!(event)
    end)
  end

  defp retirement_candidates(runtime, thread_id) do
    dispatched =
      from o in NativeRuntimeOperation,
        where:
          o.interaction_id == parent_as(:interaction).id and
            o.state not in ["prepared", "cancelled"],
        select: 1

    thread_digest = digest!(runtime, thread_id)

    from(e in NativeRuntimeEvent,
      as: :interaction,
      where:
        e.runtime_id == ^runtime.id and e.instance_id == ^runtime.instance_id and
          e.driver_generation == ^runtime.driver_generation and
          e.kind == "server_request" and e.method == "item/tool/call" and
          e.state in ["pending", "reply_prepared"] and e.thread_id_digest == ^thread_digest and
          not exists(subquery(dispatched)),
      order_by: e.id
    )
  end

  defp retire_interaction!(event) do
    Repo.update_all(
      from(o in NativeRuntimeOperation,
        where: o.interaction_id == ^event.id and o.state == "prepared"
      ),
      set: [state: "cancelled"],
      inc: [version: 1]
    )

    event
    |> change(state: "terminal_observed", version: event.version + 1)
    |> Commands.update!()
  end

  defp resolution_interactions(runtime, params) do
    request_digest = digest!(runtime, params["requestId"])
    thread_digest = digest!(runtime, params["threadId"])

    from e in NativeRuntimeEvent,
      where:
        e.runtime_id == ^runtime.id and e.instance_id == ^runtime.instance_id and
          e.driver_generation == ^runtime.driver_generation and
          e.request_id_digest == ^request_digest and e.thread_id_digest == ^thread_digest
  end

  defp digest!(runtime, value),
    do: CodexRuntime.take!(Payload.fingerprint(value, runtime.fingerprint_key_id))

  defp thread_id(wire),
    do: get_in(wire, ["params", "threadId"]) || get_in(wire, ["params", "conversationId"])

  defp valid_id?(id), do: is_binary(id) && byte_size(id) in 1..512 && !String.contains?(id, <<0>>)
  defp lifecycle(%{"type" => type}) when type in ~w(active idle notLoaded systemError), do: type
  defp lifecycle(value) when is_binary(value), do: value
  defp lifecycle(_), do: "observed"
end
