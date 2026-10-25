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
  Terminal dynamic-tool item/turn evidence retires unanswered matching handles;
  it does not acknowledge a response or change a sent-unconfirmed outcome.
  """
  use GenServer, restart: :temporary

  alias SamgitaProtocolCodex.{Error, Schema, Wire}

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

  @doc """
  Send a complete native request, retaining trace context and future envelope fields.

  Optional `:expected_instance_id`, `:expected_generation` and
  `:dispatch_deadline_ms` (absolute Unix milliseconds) fence dispatch inside the
  Session immediately before sending. Expired or stale calls send nothing.
  """
  def request_native(pid, wire, opts \\ []) do
    GenServer.call(pid, {:request_native, wire, opts}, :infinity)
  end

  @doc """
  Send a complete native client notification without allocating an ID or awaiting an ACK.

  Success reports only `%{outcome: :sent_unconfirmed}` for the local transport write.
  The pinned client-notification schema is checked unless `validation: :wire` is
  explicit. Accepts the same dispatch fences as `request_native/3`; notifications
  never change initialization readiness and are never replayed after reconnect.
  """
  def notify_native(pid, wire, opts \\ []) do
    GenServer.call(pid, {:notify_native, wire, opts}, :infinity)
  end

  @doc """
  Respond explicitly to a drained server-request handle with {:ok, result} or {:error, error}.
  Accepts the same optional dispatch fences as `request_native/3`.
  """
  def respond(pid, handle, result, opts \\ []),
    do: GenServer.call(pid, {:respond, handle, result, opts})

  def drain(pid, limit \\ 100), do: GenServer.call(pid, {:drain, limit})
  def status(pid), do: GenServer.call(pid, :status)
  def uncertain_operations(pid), do: GenServer.call(pid, :uncertain_operations)
  def interaction_outcomes(pid), do: GenServer.call(pid, :interaction_outcomes)

  @doc "Acknowledge local outcome metadata after consuming/journaling it; not an upstream ACK."
  def acknowledge_interaction_outcome(pid, handle) do
    GenServer.call(pid, {:acknowledge_interaction_outcome, handle})
  end

  @doc """
  Explicitly replace the connection without resending work.

  A returned transport open error leaves the Session disconnected. A replacement
  open callback exception returns a sanitized error and stops this Session so
  owner-death guardians can reap resources allocated before the exception.
  Pending mutations are reported uncertain before replacement is attempted.
  """
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
         {:ok, connection} <- open_transport(transport, transport_opts(opts, transport_opts)) do
      {:ok,
       %{
         opts: opts,
         transport: transport,
         transport_opts: transport_opts,
         connection: connection,
         owner: Keyword.fetch!(opts, :owner),
         owner_monitor: Process.monitor(Keyword.fetch!(opts, :owner)),
         incarnation: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
         instance_id: instance_id(),
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
         gap: nil,
         shutdown_error: nil
       }}
    else
      {:error, failure} -> {:stop, failure}
      {:callback_error, failure} -> {:stop, failure}
      _ -> {:stop, Error.new(:invalid_options)}
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
    {:reply, {:error, Error.new(:invalid_initialization_state)}, state}
  end

  def handle_call({:request, "initialize", _, _}, _from, state) do
    {:reply, {:error, Error.new(:use_initialize)}, state}
  end

  def handle_call({:request, method, params, opts}, from, %{phase: :ready} = state) do
    submit(method, params, opts, from, state)
  end

  def handle_call({:request, _, _, _}, _from, state) do
    {:reply, {:error, Error.new(:not_initialized)}, state}
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
      {:reply, {:error, Error.new(:invalid_envelope)}, state}
    end
  end

  def handle_call({:request_native, _, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_options)}, state}
  end

  def handle_call({:notify_native, wire, opts}, _from, state) do
    cond do
      not (is_list(opts) and Keyword.keyword?(opts)) ->
        {:reply, {:error, Error.new(:invalid_options)}, state}

      Wire.classify(wire) != :notification ->
        {:reply, {:error, Error.new(:invalid_envelope)}, state}

      is_nil(state.connection) ->
        {:reply, {:error, Error.new(:disconnected)}, state}

      true ->
        send_notification(wire, opts, state)
    end
  end

  def handle_call({:respond, handle, result, opts}, _from, state) do
    respond_to_interaction(handle, result, opts, state)
  end

  def handle_call({:drain, limit}, _from, state) when is_integer(limit) and limit in 1..10_000 do
    {events, state} = take_events(state, limit, [])
    {:reply, {:ok, events}, state}
  end

  def handle_call({:drain, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_limit)}, state}
  end

  def handle_call(:status, _from, state) do
    case connection_metadata(state) do
      {:ok, metadata} ->
        {:reply, status(state, metadata), state}

      {:error, failure} ->
        {:reply, {:error, failure}, disconnect(state, failure.code)}
    end
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
      {:reply, {:error, Error.new(:unknown_interaction_outcome)}, state}
    end
  end

  def handle_call(:reconnect, _from, state) do
    state = disconnect(state, :explicit_reconnect)

    if state.shutdown_error do
      {:reply, {:error, state.shutdown_error}, state}
    else
      open_replacement(state)
    end
  end

  def handle_call({:abandon, id}, _from, state) do
    case state.pending[id] do
      nil ->
        {:reply, {:error, Error.new(:unknown_operation)}, state}

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
      {:reply, {:error, Error.new(:invalid_reconciliation)}, state}
    end
  end

  def handle_call({:reconciled, _, _, _}, _from, state) do
    {:reply, {:error, Error.new(:invalid_reconciliation)}, state}
  end

  def handle_call(:close, _from, state) do
    state = disconnect(state, :closed)

    if state.shutdown_error,
      do: {:reply, {:error, state.shutdown_error}, state},
      else: {:stop, :normal, :ok, state}
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

          {:error, failure, state} ->
            {:noreply, disconnect(state, send_failure_reason(failure, :interaction_send_failed))}
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
    case transport_callback(state.transport, :handle_info, [message, state.connection]) do
      {:ok, {:ok, events, connection}} ->
        state = %{state | connection: connection}
        {:noreply, Enum.reduce(events, state, &receive_event/2)}

      {:ok, {:error, failure, connection}} ->
        {:noreply, disconnect(%{state | connection: connection}, failure.code)}

      {:ok, :unknown} ->
        {:noreply, state}

      {:error, failure} ->
        {:noreply, disconnect(state, failure.code)}
    end
  end

  @impl true
  def terminate(_reason, state), do: disconnect(state, :session_stopped)

  @impl true
  def format_status(status) do
    Map.merge(status, %{state: :redacted, message: :redacted, log: []})
  end

  defp open_replacement(state) do
    case open_transport(state.transport, transport_opts(state.opts, state.transport_opts)) do
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

      {:callback_error, failure} ->
        # No connection was returned: only owner death can trigger cleanup of
        # an unknown partial allocation. Never allow another replacement here.
        {:stop, :normal, {:error, failure}, state}
    end
  end

  defp submit(method, params, opts, from, state) when is_list(opts) do
    with :ok <- request_capacity(state, method),
         :ok <- validate_effect(method, opts),
         :ok <- validate_request(method, params, opts, state),
         {:ok, id, state} <- request_id(state, opts),
         {:ok, timeout} <- timeout(opts, state.opts),
         {:ok, encoded} <- encode_request(id, method, params, opts, state),
         :ok <- dispatch_guard(state, opts) do
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
        {:ok, state} ->
          {:noreply, state}

        {:error, failure, state} ->
          {:noreply, disconnect(state, send_failure_reason(failure, :send_failed))}
      end
    else
      {:error, failure} ->
        state = if method == "initialize", do: %{state | phase: :new}, else: state
        {:reply, {:error, failure}, state}
    end
  end

  defp submit(_, _, _, _, state), do: {:reply, {:error, Error.new(:invalid_options)}, state}

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
    {:reply, {:error, Error.new(:invalid_initialization_state)}, state}
  end

  defp request_capacity(state, method) do
    cond do
      map_size(state.pending) >= state.opts[:max_pending] ->
        {:error, Error.new(:too_many_requests)}

      map_size(state.uncertain) + map_size(state.pending) >= state.opts[:max_uncertain] and
          method not in @read_only ->
        {:error, Error.new(:reconciliation_required)}

      MapSet.size(state.used_ids) >= state.opts[:max_request_ids] ->
        {:error, Error.new(:connection_id_limit)}

      true ->
        :ok
    end
  end

  defp validate_effect(method, opts) do
    if Keyword.get(opts, :effect) == :read and method not in @read_only,
      do: {:error, Error.new(:unsafe_read_classification)},
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

  defp send_notification(wire, opts, state) do
    with {:ok, encoded} <- Wire.encode(wire, max_bytes: state.opts[:max_message_bytes]),
         :ok <- validate_notification(wire, opts, state),
         :ok <- dispatch_guard(state, opts) do
      case send_encoded(state, encoded) do
        {:ok, state} ->
          {:reply, {:ok, %{outcome: :sent_unconfirmed}}, state}

        {:error, failure, state} ->
          failure = %{failure | uncertain: true, wire: wire}

          {:reply, {:error, failure},
           disconnect(state, send_failure_reason(failure, :send_failed))}
      end
    else
      {:error, failure} -> {:reply, {:error, failure}, state}
    end
  end

  defp validate_notification(wire, opts, state) do
    if Keyword.get(opts, :validation, :schema) == :wire do
      :ok
    else
      Schema.validate_notification(:client_notification, wire["method"], wire["params"],
        experimental: state.experimental,
        params_present: Map.has_key?(wire, "params")
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
      {:error, Error.new(:invalid_or_reused_request_id)}
    end
  end

  defp timeout(opts, defaults) do
    value = Keyword.get(opts, :timeout_ms, defaults[:request_timeout_ms])

    if is_integer(value) and value in 1..86_400_000,
      do: {:ok, value},
      else: {:error, Error.new(:invalid_deadline)}
  end

  defp dispatch_guard(state, opts) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, Error.new(:invalid_options)}

      Keyword.has_key?(opts, :expected_instance_id) &&
          opts[:expected_instance_id] != state.instance_id ->
        {:error, Error.new(:stale_session)}

      Keyword.has_key?(opts, :expected_generation) &&
          opts[:expected_generation] != state.generation ->
        {:error, Error.new(:stale_session)}

      true ->
        dispatch_deadline(Keyword.fetch(opts, :dispatch_deadline_ms))
    end
  end

  defp dispatch_guard(_, _), do: {:error, Error.new(:invalid_options)}

  defp dispatch_deadline(:error), do: :ok

  defp dispatch_deadline({:ok, deadline}) when is_integer(deadline) do
    if System.system_time(:millisecond) >= deadline,
      do: {:error, Error.new(:dispatch_expired)},
      else: :ok
  end

  defp dispatch_deadline(_), do: {:error, Error.new(:invalid_deadline)}

  defp instance_id do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)
    encoded = Base.encode16(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>, case: :lower)

    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary>> =
      encoded

    Enum.join([a, b, c, d, e], "-")
  end

  defp send_wire(%{connection: nil} = state, _wire) do
    {:error, Error.new(:disconnected), state}
  end

  defp send_wire(state, wire) do
    case Wire.encode(wire, max_bytes: state.opts[:max_message_bytes]) do
      {:ok, encoded} -> send_encoded(state, encoded)
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
      {:error, Error.new(:invalid_envelope)}
    end
  end

  defp send_encoded(state, encoded) do
    case transport_callback(state.transport, :send, [state.connection, encoded]) do
      {:ok, {:ok, connection}} -> {:ok, %{state | connection: connection}}
      {:ok, {:error, failure, connection}} -> {:error, failure, %{state | connection: connection}}
      {:error, failure} -> {:error, failure, state}
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
    state = settle(state, wire["id"], {:error, Error.upstream(wire)})
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
      {:ok, state} ->
        settle(%{state | phase: :ready}, wire["id"], {:ok, wire})

      {:error, failure, state} ->
        disconnect(state, send_failure_reason(failure, :initialization_send_failed))
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
          turn_id: get_in(wire, ["params", "turnId"]),
          item_id: get_in(wire, ["params", "callId"]),
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

  defp respond_to_interaction(%{id: id} = handle, result, opts, state) do
    case state.interactions[id] do
      %{handle: ^handle} = interaction when state.phase == :ready ->
        with {:ok, wire} <- interaction_response(id, interaction.method, result, state),
             {:ok, encoded} <- Wire.encode(wire, max_bytes: state.opts[:max_message_bytes]),
             :ok <- dispatch_guard(state, opts) do
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

          send_interaction_response(state, encoded, handle, outcome)
        else
          {:error, failure} ->
            {:reply, {:error, failure}, state}
        end

      _ ->
        {:reply, {:error, Error.new(:stale_interaction)}, state}
    end
  end

  defp respond_to_interaction(_, _, _, state) do
    {:reply, {:error, Error.new(:stale_interaction)}, state}
  end

  defp send_interaction_response(state, encoded, handle, outcome) do
    case send_encoded(state, encoded) do
      {:ok, state} ->
        outcome = %{outcome | status: :sent_unconfirmed}

        {:reply, :ok,
         %{state | interaction_outcomes: Map.put(state.interaction_outcomes, handle, outcome)}}

      {:error, failure, state} ->
        failure = %{failure | uncertain: true}

        {:reply, {:error, failure},
         disconnect(state, send_failure_reason(failure, :interaction_send_failed))}
    end
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

  defp interaction_response(_, _, _, _), do: {:error, Error.new(:invalid_response)}

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

  defp resolve_interaction(
         %{
           "method" => "item/completed",
           "params" => %{"item" => %{"type" => "dynamicToolCall", "status" => status}} = params
         },
         state
       )
       when status in ["completed", "failed"] do
    retire_dynamic_interactions(state, params["threadId"], params["turnId"], fn interaction ->
      interaction.item_id == params["item"]["id"]
    end)
  end

  defp resolve_interaction(
         %{"method" => "turn/completed", "params" => %{"turn" => %{"status" => status}} = params},
         state
       )
       when status in ["completed", "interrupted", "failed"] do
    retire_dynamic_interactions(state, params["threadId"], params["turn"]["id"], fn _ -> true end)
  end

  defp resolve_interaction(_, state), do: state

  defp retire_dynamic_interactions(state, thread_id, turn_id, matches_item) do
    Enum.reduce(state.interactions, state, fn {id, interaction}, state ->
      if interaction.method == "item/tool/call" and
           interaction.handle.generation == state.generation and
           interaction.thread_id == thread_id and interaction.turn_id == turn_id and
           matches_item.(interaction),
         do: remove_interaction(state, id),
         else: state
    end)
  end

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
    failure = Error.new(reason, %{"request_id" => id}, uncertain: pending.mutation)

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
    state = Enum.reduce(Map.keys(state.pending), state, &fail_pending(&2, &1, reason))
    state = Enum.reduce(Map.keys(state.interactions), state, &remove_interaction(&2, &1))
    shutdown_error = close_transport(state)

    outcomes =
      Map.new(state.interaction_outcomes, fn {handle, outcome} ->
        if outcome.status == :sent_unconfirmed,
          do: {handle, %{outcome | status: :uncertain}},
          else: {handle, outcome}
      end)

    gap = %{reason: reason, generation: state.generation, after_sequence: state.next_sequence}
    send(state.owner, {:codex_driver, self(), {:gap, gap}})

    %{
      state
      | connection: nil,
        phase: if(shutdown_error, do: :shutdown_failed, else: :disconnected),
        shutdown_error: shutdown_error,
        gap: gap,
        interaction_outcomes: outcomes
    }
  end

  defp close_transport(state) do
    case transport_callback(state.transport, :close, [state.connection]) do
      {:ok, :ok} -> nil
      {:error, failure} -> failure
      {:ok, _unconfirmed} -> Error.new(:owned_process_shutdown_unconfirmed)
    end
  end

  defp open_transport(transport, opts) do
    case transport_callback(transport, :open, [opts]) do
      {:ok, result} -> result
      {:error, failure} -> {:callback_error, failure}
    end
  end

  defp connection_metadata(%{connection: nil}), do: {:ok, %{connected: false}}

  defp connection_metadata(state),
    do: transport_callback(state.transport, :metadata, [state.connection])

  defp status(state, metadata) do
    %{
      phase: state.phase,
      instance_id: state.instance_id,
      generation: state.generation,
      pending: map_size(state.pending),
      interactions: map_size(state.interactions),
      interaction_outcomes: map_size(state.interaction_outcomes),
      buffered_events: state.event_count,
      buffered_bytes: state.event_bytes,
      uncertain: map_size(state.uncertain),
      gap: state.gap,
      shutdown_error: if(state.shutdown_error, do: state.shutdown_error.code),
      transport: metadata
    }
  end

  # Catch only the external callback invocation. Arbitrary reasons and argument-
  # bearing stacks must not escape into OTP Logger reports. Never retain either
  # in failure details. Returned protocol Errors keep their exact authorized wire.
  defp transport_callback(transport, callback, args) do
    {:ok, apply(transport, callback, args)}
  catch
    :error, %Error{} = failure when callback == :close ->
      # Stdio's checked owner guardian raises typed cleanup failures. Preserve
      # that existing contract without treating an exception as successful close.
      {:error, failure}

    _kind, _reason ->
      {:error, Error.new(:transport_callback_failed, %{"callback" => Atom.to_string(callback)})}
  end

  defp send_failure_reason(%Error{code: :transport_callback_failed}, _default),
    do: :transport_callback_failed

  defp send_failure_reason(_failure, default), do: default

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
       else: {:error, Error.new(:invalid_options)}
  end

  defp transport_opts(opts, transport_opts) do
    Keyword.put(transport_opts, :max_message_bytes, opts[:max_message_bytes])
  end
end
