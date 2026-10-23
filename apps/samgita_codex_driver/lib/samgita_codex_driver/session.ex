defmodule SamgitaCodexDriver.Session do
  @moduledoc """
  Explicitly started, supervised native Codex connection.

  Children are temporary: supervisor restart must not recreate an execution.
  Reconnect and initialization are explicit and never resend requests. Native
  results/errors and complete incoming messages stay available to the authorized
  owner. Events use a bounded pull queue and one availability notification, rather
  than streaming unbounded payloads into the owner's mailbox.

  A local event sequence is not an upstream replay cursor. Disconnection or
  overflow exposes a gap. `thread/resume` may replay upstream pending interactions;
  it cannot reconstruct missing notification history. All server interactions
  require an explicit response to their exact generation and opaque handle.
  """
  use GenServer, restart: :temporary

  alias SamgitaProtocolCodex.{Failure, Schema, Wire}

  @defaults [
    max_pending: 128,
    max_interactions: 128,
    max_interaction_outcomes: 256,
    max_events: 256,
    max_event_bytes: 8_388_608,
    max_message_bytes: 8_388_608,
    max_uncertain: 256,
    max_request_ids: 100_000,
    request_timeout_ms: 30_000,
    interaction_timeout_ms: 60_000
  ]

  # Conservative, audited reads. Unclassified/extension operations are mutations.
  # A caller cannot suppress uncertainty by labelling a mutation as a read.
  @read_only ~w(initialize thread/list thread/loaded/list thread/read thread/turns/list model/list config/read configRequirements/read account/read skills/list)

  def start_link(opts) do
    opts = Keyword.put_new(opts, :owner, self())
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def initialize(pid, client_info, capabilities \\ %{}, opts \\ []) do
    GenServer.call(pid, {:initialize, client_info, capabilities, opts}, :infinity)
  end

  @doc "Return the complete native response, or a redacted-inspect failure retaining `wire`."
  def request(pid, method, params \\ %{}, opts \\ []) do
    GenServer.call(pid, {:request, method, params, opts}, :infinity)
  end

  @doc "Send a complete native request, retaining trace context and future envelope fields."
  def request_native(pid, wire, opts \\ []) do
    GenServer.call(pid, {:request_native, wire, opts}, :infinity)
  end

  @doc "Respond explicitly to a drained server-request handle with {:ok, result} or {:error, error}."
  def respond(pid, handle, result), do: GenServer.call(pid, {:respond, handle, result})

  def drain(pid, limit \\ 100), do: GenServer.call(pid, {:drain, limit})
  def status(pid), do: GenServer.call(pid, :status)
  def uncertain_operations(pid), do: GenServer.call(pid, :uncertain_operations)
  def interaction_outcomes(pid), do: GenServer.call(pid, :interaction_outcomes)

  @doc "Acknowledge local outcome metadata after consuming/journaling it; not an upstream ACK."
  def acknowledge_interaction_outcome(pid, handle) do
    GenServer.call(pid, {:acknowledge_interaction_outcome, handle})
  end

  def reconnect(pid), do: GenServer.call(pid, :reconnect, :infinity)
  def close(pid), do: GenServer.call(pid, :close, :infinity)

  @doc "Stop waiting locally. This does not cancel an upstream operation or prove cessation."
  def abandon(pid, id), do: GenServer.call(pid, {:abandon, id})

  @doc "Release a recorded uncertainty after caller-owned reconciliation; never resends work."
  def record_reconciliation(pid, id, disposition, evidence_digest) do
    GenServer.call(pid, {:reconciled, id, disposition, evidence_digest})
  end

  @impl true
  def init(opts) do
    opts = Keyword.merge(@defaults, opts)

    with :ok <- validate_options(opts),
         {transport, transport_opts} <- Keyword.fetch!(opts, :transport),
         {:ok, connection} <- transport.open(transport_opts(opts, transport_opts)) do
      {:ok,
       %{
         opts: opts,
         transport: transport,
         transport_opts: transport_opts,
         connection: connection,
         owner: Keyword.fetch!(opts, :owner),
         owner_monitor: Process.monitor(Keyword.fetch!(opts, :owner)),
         incarnation: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
         generation: 1,
         phase: :new,
         experimental: false,
         pending: %{},
         interactions: %{},
         interaction_outcomes: %{},
         used_ids: MapSet.new(),
         next_id: 0,
         next_sequence: 0,
         events: :queue.new(),
         event_count: 0,
         event_bytes: 0,
         uncertain: %{},
         gap: nil
       }}
    else
      {:error, failure} -> {:stop, failure}
      _ -> {:stop, Failure.new(:invalid_options)}
    end
  end

  @impl true
  def handle_call({:initialize, info, capabilities, opts}, from, %{phase: :new} = state)
      when is_map(info) and is_map(capabilities) and is_list(opts) do
    params = %{"clientInfo" => info, "capabilities" => capabilities}
    experimental = capabilities["experimentalApi"] == true
    state = %{state | phase: :initializing, experimental: experimental}
    submit("initialize", params, opts, from, state)
  end

  def handle_call({:initialize, _, _, _}, _from, state) do
    {:reply, {:error, Failure.new(:invalid_initialization_state)}, state}
  end

  def handle_call({:request, "initialize", _, _}, _from, state) do
    {:reply, {:error, Failure.new(:use_initialize)}, state}
  end

  def handle_call({:request, method, params, opts}, from, %{phase: :ready} = state) do
    submit(method, params, opts, from, state)
  end

  def handle_call({:request, _, _, _}, _from, state) do
    {:reply, {:error, Failure.new(:not_initialized)}, state}
  end

  def handle_call({:request_native, wire, opts}, from, state) when is_list(opts) do
    if Wire.classify(wire) == :request do
      opts =
        opts
        |> Keyword.put(:id, wire["id"])
        |> Keyword.put(:params_present, Map.has_key?(wire, "params"))
        |> Keyword.put(:envelope, Map.drop(wire, ~w(id method params)))

      if wire["method"] == "initialize" do
        initialize_native(wire, opts, from, state)
      else
        handle_call({:request, wire["method"], wire["params"], opts}, from, state)
      end
    else
      {:reply, {:error, Failure.new(:invalid_envelope)}, state}
    end
  end

  def handle_call({:request_native, _, _}, _from, state) do
    {:reply, {:error, Failure.new(:invalid_options)}, state}
  end

  def handle_call({:respond, handle, result}, _from, state) do
    respond_to_interaction(handle, result, state)
  end

  def handle_call({:drain, limit}, _from, state) when is_integer(limit) and limit in 1..10_000 do
    {events, state} = take_events(state, limit, [])
    {:reply, {:ok, events}, state}
  end

  def handle_call({:drain, _}, _from, state) do
    {:reply, {:error, Failure.new(:invalid_limit)}, state}
  end

  def handle_call(:status, _from, state) do
    {:reply,
     %{
       phase: state.phase,
       generation: state.generation,
       pending: map_size(state.pending),
       interactions: map_size(state.interactions),
       interaction_outcomes: map_size(state.interaction_outcomes),
       buffered_events: state.event_count,
       buffered_bytes: state.event_bytes,
       uncertain: map_size(state.uncertain),
       gap: state.gap,
       transport:
         if(state.connection,
           do: state.transport.metadata(state.connection),
           else: %{connected: false}
         )
     }, state}
  end

  def handle_call(:uncertain_operations, _from, state) do
    {:reply, Map.values(state.uncertain), state}
  end

  def handle_call(:interaction_outcomes, _from, state) do
    {:reply, Map.values(state.interaction_outcomes), state}
  end

  def handle_call({:acknowledge_interaction_outcome, handle}, _from, state) do
    if Map.has_key?(state.interaction_outcomes, handle) do
      {:reply, :ok,
       %{state | interaction_outcomes: Map.delete(state.interaction_outcomes, handle)}}
    else
      {:reply, {:error, Failure.new(:unknown_interaction_outcome)}, state}
    end
  end

  def handle_call(:reconnect, _from, state) do
    state = disconnect(state, :explicit_reconnect)

    case state.transport.open(transport_opts(state.opts, state.transport_opts)) do
      {:ok, connection} ->
        {:reply, :ok,
         %{
           state
           | connection: connection,
             generation: state.generation + 1,
             phase: :new,
             experimental: false,
             used_ids: MapSet.new()
         }}

      {:error, failure} ->
        {:reply, {:error, failure}, state}
    end
  end

  def handle_call({:abandon, id}, _from, state) do
    case state.pending[id] do
      nil ->
        {:reply, {:error, Failure.new(:unknown_operation)}, state}

      %{method: "initialize"} ->
        state = fail_pending(state, id, :locally_abandoned)
        {:reply, :ok, disconnect(state, :initialization_abandoned)}

      _ ->
        {:reply, :ok, fail_pending(state, id, :locally_abandoned)}
    end
  end

  def handle_call({:reconciled, id, disposition, digest}, _from, state)
      when disposition in [:applied, :not_applied, :abandoned] and is_binary(digest) and
             byte_size(digest) == 64 do
    if Map.has_key?(state.uncertain, id) and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) do
      # This is caller-provided evidence, not an upstream deduplication guarantee.
      {:reply, :ok, %{state | uncertain: Map.delete(state.uncertain, id)}}
    else
      {:reply, {:error, Failure.new(:invalid_reconciliation)}, state}
    end
  end

  def handle_call({:reconciled, _, _, _}, _from, state) do
    {:reply, {:error, Failure.new(:invalid_reconciliation)}, state}
  end

  def handle_call(:close, _from, state) do
    {:stop, :normal, :ok, disconnect(state, :closed)}
  end

  @impl true
  def handle_info({:request_deadline, id, token}, state) do
    case state.pending[id] do
      %{token: ^token, method: "initialize"} ->
        state = fail_pending(state, id, :deadline_exceeded)
        {:noreply, disconnect(state, :initialization_deadline_exceeded)}

      %{token: ^token} ->
        {:noreply, fail_pending(state, id, :deadline_exceeded)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:interaction_deadline, id, token}, state) do
    case state.interactions[id] do
      %{token: ^token} = interaction ->
        wire = %{
          "id" => id,
          "error" => %{"code" => -32_000, "message" => "Client interaction deadline expired"}
        }

        state = remove_interaction(state, id)

        case send_wire(state, wire) do
          {:ok, state} ->
            {:noreply,
             enqueue(state, %{kind: :interaction_expired, handle: interaction.handle}, 128)}

          {:error, _failure, state} ->
            {:noreply, disconnect(state, :interaction_send_failed)}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{owner_monitor: monitor} = state) do
    {:stop, :normal, disconnect(state, :owner_down)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.pending, fn {_id, pending} -> pending.monitor == monitor end) do
      {id, %{method: "initialize"}} ->
        state = fail_pending(state, id, :caller_down)
        {:noreply, disconnect(state, :initialization_caller_down)}

      {id, _} ->
        {:noreply, fail_pending(state, id, :caller_down)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, %{connection: nil} = state), do: {:noreply, state}

  def handle_info(message, state) do
    case state.transport.handle_info(message, state.connection) do
      {:ok, events, connection} ->
        state = %{state | connection: connection}
        {:noreply, Enum.reduce(events, state, &receive_event/2)}

      {:error, failure, connection} ->
        {:noreply, disconnect(%{state | connection: connection}, failure.code)}

      :unknown ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state), do: disconnect(state, :session_stopped)

  @impl true
  def format_status(status) do
    Map.merge(status, %{state: :redacted, message: :redacted, log: []})
  end

  defp submit(method, params, opts, from, state) when is_list(opts) do
    with :ok <- request_capacity(state, method),
         :ok <- validate_effect(method, opts),
         :ok <- validate_request(method, params, opts, state),
         {:ok, id, state} <- request_id(state, opts),
         {:ok, timeout} <- timeout(opts, state.opts),
         {:ok, encoded} <- encode_request(id, method, params, opts, state) do
      token = make_ref()

      pending = %{
        from: from,
        method: method,
        validation: Keyword.get(opts, :validation, :schema),
        mutation: method not in @read_only,
        generation: state.generation,
        token: token,
        timer: Process.send_after(self(), {:request_deadline, id, token}, timeout),
        monitor: Process.monitor(elem(from, 0))
      }

      state = %{state | pending: Map.put(state.pending, id, pending)}

      case send_encoded(state, encoded) do
        {:ok, state} -> {:noreply, state}
        {:error, _failure, state} -> {:noreply, disconnect(state, :send_failed)}
      end
    else
      {:error, failure} ->
        state = if method == "initialize", do: %{state | phase: :new}, else: state
        {:reply, {:error, failure}, state}
    end
  end

  defp submit(_, _, _, _, state), do: {:reply, {:error, Failure.new(:invalid_options)}, state}

  defp initialize_native(wire, opts, from, %{phase: :new} = state) do
    experimental =
      case wire do
        %{"params" => %{"capabilities" => %{"experimentalApi" => true}}} -> true
        _ -> false
      end

    state = %{state | phase: :initializing, experimental: experimental}
    submit("initialize", wire["params"], opts, from, state)
  end

  defp initialize_native(_, _, _, state) do
    {:reply, {:error, Failure.new(:invalid_initialization_state)}, state}
  end

  defp request_capacity(state, method) do
    cond do
      map_size(state.pending) >= state.opts[:max_pending] ->
        {:error, Failure.new(:too_many_requests)}

      map_size(state.uncertain) + map_size(state.pending) >= state.opts[:max_uncertain] and
          method not in @read_only ->
        {:error, Failure.new(:reconciliation_required)}

      MapSet.size(state.used_ids) >= state.opts[:max_request_ids] ->
        {:error, Failure.new(:connection_id_limit)}

      true ->
        :ok
    end
  end

  defp validate_effect(method, opts) do
    if Keyword.get(opts, :effect) == :read and method not in @read_only,
      do: {:error, Failure.new(:unsafe_read_classification)},
      else: :ok
  end

  defp validate_request(method, params, opts, state) do
    if Keyword.get(opts, :validation, :schema) == :wire do
      :ok
    else
      Schema.validate_request(method, params,
        experimental: state.experimental,
        params_present: Keyword.get(opts, :params_present, true)
      )
    end
  end

  defp request_id(state, opts) do
    next = state.next_id + 1
    id = Keyword.get(opts, :id, "#{state.incarnation}:#{state.generation}:#{next}")

    if (is_binary(id) or is_integer(id)) and not MapSet.member?(state.used_ids, id) and
         not Map.has_key?(state.uncertain, id) do
      {:ok, id, %{state | next_id: next, used_ids: MapSet.put(state.used_ids, id)}}
    else
      {:error, Failure.new(:invalid_or_reused_request_id)}
    end
  end

  defp timeout(opts, defaults) do
    value = Keyword.get(opts, :timeout_ms, defaults[:request_timeout_ms])

    if is_integer(value) and value in 1..86_400_000,
      do: {:ok, value},
      else: {:error, Failure.new(:invalid_deadline)}
  end

  defp send_wire(%{connection: nil} = state, _wire) do
    {:error, Failure.new(:disconnected), state}
  end

  defp send_wire(state, wire) do
    with {:ok, encoded} <- Wire.encode(wire, max_bytes: state.opts[:max_message_bytes]) do
      send_encoded(state, encoded)
    else
      {:error, failure} -> {:error, failure, state}
    end
  end

  defp encode_request(id, method, params, opts, state) do
    wire = %{"id" => id, "method" => method}

    wire =
      if Keyword.get(opts, :params_present, true), do: Map.put(wire, "params", params), else: wire

    envelope = Keyword.get(opts, :envelope, %{})

    if is_map(envelope) and not is_struct(envelope) and
         Enum.all?(~w(id method params), &(not Map.has_key?(envelope, &1))) do
      Wire.encode(Map.merge(wire, envelope), max_bytes: state.opts[:max_message_bytes])
    else
      {:error, Failure.new(:invalid_envelope)}
    end
  end

  defp send_encoded(state, encoded) do
    case state.transport.send(state.connection, encoded) do
      {:ok, connection} -> {:ok, %{state | connection: connection}}
      {:error, failure, connection} -> {:error, failure, %{state | connection: connection}}
    end
  end

  defp receive_event(_event, %{connection: nil} = state), do: state
  defp receive_event({:closed, _metadata}, state), do: disconnect(state, :disconnected)

  defp receive_event({:message, body}, state) do
    case Wire.decode(body, max_bytes: state.opts[:max_message_bytes]) do
      {:ok, wire} -> receive_wire(Wire.classify(wire), wire, byte_size(body), state)
      {:error, failure} -> disconnect(state, failure.code)
    end
  end

  defp receive_wire(kind, wire, bytes, state) when kind in [:response, :error] do
    case state.pending[wire["id"]] do
      nil -> enqueue(state, %{kind: :late_response, wire: wire}, bytes)
      pending -> complete_request(wire, pending, state)
    end
  end

  defp receive_wire(:notification, wire, bytes, state) do
    method = wire["method"]

    if method in Schema.methods(:server_notification, experimental: state.experimental) do
      case Schema.validate_notification(:server_notification, method, wire["params"],
             experimental: state.experimental,
             params_present: Map.has_key?(wire, "params")
           ) do
        :ok ->
          state = resolve_interaction(wire, state)
          enqueue(state, %{kind: :notification, wire: wire}, bytes)

        {:error, failure} ->
          disconnect(state, failure.code)
      end
    else
      enqueue(state, %{kind: :unknown_notification, wire: wire}, bytes)
    end
  end

  defp receive_wire(:request, wire, bytes, state) do
    method = wire["method"]

    cond do
      Map.has_key?(state.interactions, wire["id"]) ->
        disconnect(state, :duplicate_server_request_id)

      map_size(state.interactions) >= state.opts[:max_interactions] ->
        disconnect(state, :interaction_overflow)

      map_size(state.interactions) + map_size(state.interaction_outcomes) >=
          state.opts[:max_interaction_outcomes] ->
        disconnect(state, :interaction_outcome_overflow)

      method in Schema.methods(:server_request, experimental: state.experimental) ->
        accept_interaction(wire, bytes, state)

      true ->
        reject_unknown_interaction(wire, bytes, state)
    end
  end

  defp receive_wire(_, _, _, state), do: disconnect(state, :invalid_message)

  defp complete_request(%{"error" => _} = wire, pending, state) do
    state = settle(state, wire["id"], {:error, Failure.upstream(wire)})
    if pending.method == "initialize", do: %{state | phase: :new}, else: state
  end

  defp complete_request(wire, pending, state) do
    validation =
      if pending.validation == :wire,
        do: :ok,
        else:
          Schema.validate_result(:server_response, pending.method, wire["result"],
            experimental: state.experimental
          )

    case validation do
      :ok ->
        finish_success(wire, pending, state)

      {:error, failure} ->
        # A malformed reply does not establish that a mutation failed to execute.
        state = fail_pending(state, wire["id"], failure.code)
        disconnect(state, :invalid_response)
    end
  end

  defp finish_success(wire, %{method: "initialize"}, state) do
    case send_wire(state, %{"method" => "initialized"}) do
      {:ok, state} -> settle(%{state | phase: :ready}, wire["id"], {:ok, wire})
      {:error, _failure, state} -> disconnect(state, :initialization_send_failed)
    end
  end

  defp finish_success(wire, _pending, state), do: settle(state, wire["id"], {:ok, wire})

  defp accept_interaction(wire, bytes, state) do
    case Schema.validate_request(wire["method"], wire["params"],
           direction: :server_request,
           experimental: state.experimental,
           params_present: Map.has_key?(wire, "params")
         ) do
      :ok ->
        handle = %{id: wire["id"], generation: state.generation, reference: make_ref()}
        token = make_ref()

        interaction = %{
          handle: handle,
          method: wire["method"],
          thread_id:
            get_in(wire, ["params", "threadId"]) || get_in(wire, ["params", "conversationId"]),
          token: token,
          timer:
            Process.send_after(
              self(),
              {:interaction_deadline, wire["id"], token},
              state.opts[:interaction_timeout_ms]
            )
        }

        state = %{state | interactions: Map.put(state.interactions, wire["id"], interaction)}
        enqueue(state, %{kind: :server_request, wire: wire, handle: handle}, bytes)

      {:error, failure} ->
        disconnect(state, failure.code)
    end
  end

  defp reject_unknown_interaction(wire, bytes, state) do
    reply = %{
      "id" => wire["id"],
      "error" => %{"code" => -32_601, "message" => "Unsupported server request"}
    }

    case send_wire(state, reply) do
      {:ok, state} -> enqueue(state, %{kind: :unsupported_server_request, wire: wire}, bytes)
      {:error, _failure, state} -> disconnect(state, :interaction_send_failed)
    end
  end

  defp respond_to_interaction(%{id: id} = handle, result, state) do
    case state.interactions[id] do
      %{handle: ^handle} = interaction when state.phase == :ready ->
        with {:ok, wire} <- interaction_response(id, interaction.method, result, state),
             {:ok, encoded} <- Wire.encode(wire, max_bytes: state.opts[:max_message_bytes]) do
          # Transport send has no Codex response ACK. Keep this fact inspectable
          # until the owner journals it; a resolved notification is not approval
          # acceptance either (another connection or cancellation may resolve it).
          outcome = %{
            handle: handle,
            method: interaction.method,
            thread_id: interaction.thread_id,
            status: :uncertain,
            response_digest: :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)
          }

          state = remove_interaction(state, id)

          state = %{
            state
            | interaction_outcomes: Map.put(state.interaction_outcomes, handle, outcome)
          }

          case send_encoded(state, encoded) do
            {:ok, state} ->
              outcome = %{outcome | status: :sent_unconfirmed}

              {:reply, :ok,
               %{
                 state
                 | interaction_outcomes: Map.put(state.interaction_outcomes, handle, outcome)
               }}

            {:error, failure, state} ->
              failure = %{failure | uncertain: true}
              {:reply, {:error, failure}, disconnect(state, :interaction_send_failed)}
          end
        else
          {:error, failure} ->
            {:reply, {:error, failure}, state}
        end

      _ ->
        {:reply, {:error, Failure.new(:stale_interaction)}, state}
    end
  end

  defp respond_to_interaction(_, _, state) do
    {:reply, {:error, Failure.new(:stale_interaction)}, state}
  end

  defp interaction_response(id, method, {:ok, result}, state) do
    with :ok <-
           Schema.validate_result(:client_response, method, result,
             experimental: state.experimental
           ) do
      {:ok, %{"id" => id, "result" => result}}
    end
  end

  defp interaction_response(id, _method, {:error, error}, _state) do
    wire = %{"id" => id, "error" => error}
    with {:ok, _encoded} <- Wire.encode(wire), do: {:ok, wire}
  end

  defp interaction_response(_, _, _, _), do: {:error, Failure.new(:invalid_response)}

  defp resolve_interaction(%{"method" => "serverRequest/resolved", "params" => params}, state) do
    expected_thread = params["threadId"]

    state =
      case state.interactions[params["requestId"]] do
        %{thread_id: ^expected_thread} ->
          remove_interaction(state, params["requestId"])

        _ ->
          state
      end

    outcomes =
      Map.new(state.interaction_outcomes, fn {handle, outcome} ->
        if handle.generation == state.generation and handle.id == params["requestId"] and
             outcome.thread_id == expected_thread,
           do: {handle, %{outcome | status: :resolution_observed}},
           else: {handle, outcome}
      end)

    %{state | interaction_outcomes: outcomes}
  end

  defp resolve_interaction(_, state), do: state

  defp remove_interaction(state, id) do
    case Map.pop(state.interactions, id) do
      {nil, _} ->
        state

      {interaction, rest} ->
        Process.cancel_timer(interaction.timer)
        %{state | interactions: rest}
    end
  end

  defp settle(state, id, result) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {pending, rest} ->
        Process.cancel_timer(pending.timer)
        Process.demonitor(pending.monitor, [:flush])
        GenServer.reply(pending.from, result)
        %{state | pending: rest}
    end
  end

  defp fail_pending(state, id, reason) do
    pending = Map.fetch!(state.pending, id)
    failure = Failure.new(reason, %{"request_id" => id}, uncertain: pending.mutation)

    state =
      if pending.mutation do
        operation = %{
          id: id,
          method: pending.method,
          generation: pending.generation,
          reason: reason
        }

        %{state | uncertain: Map.put(state.uncertain, id, operation)}
      else
        state
      end

    state = settle(state, id, {:error, failure})
    if pending.method == "initialize", do: %{state | phase: :new}, else: state
  end

  defp disconnect(%{connection: nil} = state, _reason), do: state

  defp disconnect(state, reason) do
    state.transport.close(state.connection)
    state = Enum.reduce(Map.keys(state.pending), state, &fail_pending(&2, &1, reason))
    state = Enum.reduce(Map.keys(state.interactions), state, &remove_interaction(&2, &1))

    outcomes =
      Map.new(state.interaction_outcomes, fn {handle, outcome} ->
        if outcome.status == :sent_unconfirmed,
          do: {handle, %{outcome | status: :uncertain}},
          else: {handle, outcome}
      end)

    gap = %{reason: reason, generation: state.generation, after_sequence: state.next_sequence}
    send(state.owner, {:codex_driver, self(), {:gap, gap}})
    %{state | connection: nil, phase: :disconnected, gap: gap, interaction_outcomes: outcomes}
  end

  defp enqueue(state, event, bytes) do
    if state.event_count >= state.opts[:max_events] or
         state.event_bytes + bytes > state.opts[:max_event_bytes] do
      disconnect(state, :event_buffer_overflow)
    else
      sequence = state.next_sequence + 1
      event = Map.merge(event, %{generation: state.generation, sequence: sequence})
      if state.event_count == 0, do: send(state.owner, {:codex_driver, self(), :events_available})

      %{
        state
        | events: :queue.in({event, bytes}, state.events),
          next_sequence: sequence,
          event_count: state.event_count + 1,
          event_bytes: state.event_bytes + bytes
      }
    end
  end

  defp take_events(state, 0, collected), do: {Enum.reverse(collected), state}

  defp take_events(state, remaining, collected) do
    case :queue.out(state.events) do
      {:empty, _} ->
        {Enum.reverse(collected), state}

      {{:value, {event, bytes}}, rest} ->
        state = %{
          state
          | events: rest,
            event_count: state.event_count - 1,
            event_bytes: state.event_bytes - bytes
        }

        take_events(state, remaining - 1, [event | collected])
    end
  end

  defp validate_options(opts) do
    valid =
      Enum.all?(@defaults, fn {key, _default} ->
        value = Keyword.get(opts, key)
        is_integer(value) and value > 0 and value <= 1_073_741_824
      end)

    if valid and is_pid(opts[:owner]) and
         match?({module, args} when is_atom(module) and is_list(args), opts[:transport]),
       do: :ok,
       else: {:error, Failure.new(:invalid_options)}
  end

  defp transport_opts(opts, transport_opts) do
    Keyword.put(transport_opts, :max_message_bytes, opts[:max_message_bytes])
  end
end
