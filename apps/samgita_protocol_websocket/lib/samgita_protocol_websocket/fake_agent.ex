defmodule SamgitaProtocolWebSocket.FakeAgent do
  @moduledoc "An explicitly started, in-memory reference host; it never executes tools or stores durably."
  use GenServer
  alias SamgitaProtocol.{Error, Event, Replay, Schema}
  alias SamgitaProtocolWebSocket.Server

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, Keyword.put_new(opts, :owner, self()))

  def url(pid), do: GenServer.call(pid, :url)
  def event_count(pid), do: GenServer.call(pid, :event_count)
  def approval_count(pid), do: GenServer.call(pid, :approval_count)
  def emit_delta(pid, thread, turn, text), do: GenServer.call(pid, {:delta, thread, turn, text})

  def request_approval(pid, thread, turn, id),
    do: GenServer.call(pid, {:approval, thread, turn, id})

  @impl true
  def init(opts) do
    store = self()
    token = Keyword.fetch!(opts, :token)
    owner = Keyword.fetch!(opts, :owner)

    server_opts = [
      port: Keyword.fetch!(opts, :port),
      handler: __MODULE__.Handler,
      handler_state: fn principal ->
        %{store: store, socket: self(), principal: principal, owner: owner}
      end,
      authenticate: fn supplied ->
        if byte_size(supplied) == byte_size(token) and
             Plug.Crypto.secure_compare(supplied, token),
           do: {:ok, %{id: "fake-agent-client"}},
           else: :error
      end
    ]

    case Server.start_link(server_opts) do
      {:ok, listener} ->
        {:ok,
         %{
           listener: listener,
           owner: owner,
           events: %{},
           threads: %{},
           turns: %{},
           streams: %{},
           requests: %{},
           approvals: %{},
           limit: Keyword.get(opts, :replay_limit, 4),
           max_records: Keyword.get(opts, :max_records, 128)
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(state.listener)
    {:reply, "ws://127.0.0.1:#{port}/app-server", state}
  end

  def handle_call(:event_count, _from, state), do: {:reply, map_size(state.events), state}
  def handle_call(:approval_count, _from, state), do: {:reply, map_size(state.approvals), state}

  def handle_call({:dispatch, method, params, context, socket}, _from, state) do
    {result, state} =
      if capacity?(state, method, params),
        do: dispatch(method, params, context, socket, state),
        else: {{:error, Error.new("buffer_full")}, state}

    {:reply, result, state}
  end

  def handle_call({:delta, thread, turn, text}, _from, state) do
    case state.turns[turn] do
      %{thread: ^thread, status: "running", socket: socket} ->
        if Schema.valid?(text, :string) do
          params = %{
            "thread_id" => thread,
            "turn_id" => turn,
            "item_id" => "item:" <> turn,
            "delta" => text
          }

          state = emit(state, socket, "thread:" <> thread, "item/delta", params)
          {:reply, :ok, state}
        else
          {:reply, {:error, Error.new("invalid_params")}, state}
        end

      _ ->
        {:reply, {:error, Error.new("conflict")}, state}
    end
  end

  def handle_call({:approval, thread, turn, id}, _from, state) do
    case state.turns[turn] do
      %{thread: ^thread, status: "running", socket: socket} ->
        if Map.has_key?(state.approvals, id) or map_size(state.approvals) >= state.max_records do
          {:reply, {:error, Error.new("conflict")}, state}
        else
          params = %{
            "approval_id" => id,
            "thread_id" => thread,
            "turn_id" => turn,
            "action" => %{"kind" => "simulation"}
          }

          Server.request(socket, "approval/request", params,
            id: id,
            correlation_id: "approval:" <> id,
            command_id: "approval:" <> id
          )

          {:reply, :ok, put_in(state.approvals[id], :pending)}
        end

      _ ->
        {:reply, {:error, Error.new("conflict")}, state}
    end
  end

  def handle_call({:approval_result, id, decision}, _from, state) do
    if state.approvals[id] == :pending do
      send(state.owner, {:fake_agent_approval, id, decision})
      {:reply, :ok, put_in(state.approvals[id], decision)}
    else
      {:reply, {:error, Error.new("conflict")}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.listener), do: Supervisor.stop(state.listener)
  end

  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)

  defp dispatch("project/event.receive", %{"event" => event}, _context, _socket, state) do
    id = event["event_id"]
    previous = state.events[id]

    if previous == nil or Event.same?(previous.event, event) do
      entry = previous || %{event: event, status: "pending"}

      result = %{
        "event_id" => id,
        "delivery_attempt_id" => event["delivery_attempt_id"],
        "acceptance" => "received",
        "processing_status" => entry.status
      }

      {{:ok, result}, put_in(state.events[id], entry)}
    else
      {{:error, Error.new("conflict")}, state}
    end
  end

  defp dispatch("project/event.status", %{"event_id" => id}, _context, _socket, state) do
    case state.events[id] do
      nil ->
        {{:error, Error.new("not_found")}, state}

      entry ->
        result = %{
          "event_id" => id,
          "acceptance" => "received",
          "processing_status" => entry.status
        }

        result =
          if entry[:report],
            do: Map.merge(result, Map.take(entry.report, ["decision_id", "decision", "result"])),
            else: result

        {{:ok, result}, state}
    end
  end

  defp dispatch("project/event.report", %{"event_id" => id} = report, _context, socket, state) do
    case state.events[id] do
      nil ->
        {{:error, Error.new("not_found")}, state}

      entry ->
        record_report(entry, report, socket, state)
    end
  end

  defp dispatch("thread/start", params, _context, socket, state) do
    id = unique("thread")
    state = put_in(state.threads[id], params)
    state = emit(state, socket, "thread:" <> id, "thread/started", %{"thread_id" => id})
    {{:ok, %{"thread_id" => id, "thread" => params}}, state}
  end

  defp dispatch(method, %{"thread_id" => id}, _context, socket, state)
       when method in ["thread/read", "thread/resume"] do
    case state.threads[id] do
      nil ->
        {{:error, Error.new("not_found")}, state}

      thread ->
        turns =
          if method == "thread/resume",
            do: resume_turns(state.turns, id, socket),
            else: state.turns

        {{:ok, %{"thread_id" => id, "thread" => thread}}, %{state | turns: turns}}
    end
  end

  defp dispatch("turn/start", %{"thread_id" => thread} = params, context, socket, state) do
    cond do
      not Map.has_key?(state.threads, thread) ->
        {{:error, Error.new("not_found")}, state}

      Enum.any?(state.turns, fn {_id, turn} ->
        turn.thread == thread and turn.status == "running"
      end) ->
        {{:error, Error.new("conflict")}, state}

      true ->
        id = unique("turn")
        turn = %{thread: thread, status: "running", input: params["input"], socket: socket}
        state = put_in(state.turns[id], turn)
        state = put_in(state.requests[{context["connection_id"], context["request_id"]}], id)

        state =
          emit(state, socket, "thread:" <> thread, "turn/started", %{
            "thread_id" => thread,
            "turn_id" => id
          })

        {{:ok, %{"thread_id" => thread, "turn_id" => id, "status" => "running"}}, state}
    end
  end

  defp dispatch(
         "turn/steer",
         %{"thread_id" => thread, "turn_id" => id} = params,
         _context,
         _socket,
         state
       ) do
    case state.turns[id] do
      %{thread: ^thread, status: "running"} ->
        {{:ok, %{"thread_id" => thread, "turn_id" => id, "status" => "running"}},
         put_in(state.turns[id].input, params["input"])}

      _ ->
        {{:error, Error.new("conflict")}, state}
    end
  end

  defp dispatch(
         "turn/interrupt",
         %{"thread_id" => thread, "turn_id" => id},
         _context,
         socket,
         state
       ) do
    case state.turns[id] do
      %{thread: ^thread, status: "running"} ->
        state = put_in(state.turns[id].status, "interrupted")

        state =
          emit(state, socket, "thread:" <> thread, "turn/completed", %{
            "thread_id" => thread,
            "turn_id" => id,
            "status" => "interrupted"
          })

        {{:ok, %{"thread_id" => thread, "turn_id" => id, "status" => "interrupted"}}, state}

      %{thread: ^thread} ->
        {{:ok, %{"thread_id" => thread, "turn_id" => id, "status" => "already_finished"}}, state}

      _ ->
        {{:error, Error.new("not_found")}, state}
    end
  end

  defp dispatch("request/cancel", %{"request_id" => request_id}, context, socket, state) do
    turn_id = state.requests[{context["connection_id"], request_id}]

    case state.turns[turn_id] do
      %{status: "running", thread: thread} ->
        {{:ok, _}, state} =
          dispatch(
            "turn/interrupt",
            %{"thread_id" => thread, "turn_id" => turn_id},
            context,
            socket,
            state
          )

        {{:ok, %{"request_id" => request_id, "status" => "requested"}}, state}

      _ ->
        {{:ok, %{"request_id" => request_id, "status" => "already_finished"}}, state}
    end
  end

  defp dispatch(
         "stream/resume",
         %{"stream_id" => stream, "cursor" => cursor},
         _context,
         _socket,
         state
       ) do
    with replay when not is_nil(replay) <- state.streams[stream],
         {:ok, events} <- Replay.since(replay, cursor) do
      last_cursor = if events == [], do: cursor, else: List.last(events)["cursor"]
      {{:ok, %{"stream_id" => stream, "cursor" => last_cursor, "events" => events}}, state}
    else
      nil -> {{:error, Error.new("not_found")}, state}
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp dispatch(
         "approval/request",
         %{"approval_id" => id, "thread_id" => thread, "turn_id" => turn},
         _context,
         socket,
         state
       ) do
    case state.turns[turn] do
      %{thread: ^thread, status: "running"} ->
        if Map.has_key?(state.approvals, id) do
          {{:error, Error.new("conflict")}, state}
        else
          send(state.owner, {:fake_agent_approval_requested, id, socket})
          {{:wait_for_approval, id}, put_in(state.approvals[id], :pending)}
        end

      _ ->
        {{:error, Error.new("conflict")}, state}
    end
  end

  defp resume_turns(turns, thread, socket) do
    Map.new(turns, fn {key, turn} ->
      {key, if(turn.thread == thread, do: %{turn | socket: socket}, else: turn)}
    end)
  end

  defp record_report(entry, report, socket, state) do
    if entry[:report] && entry.report != report do
      {{:error, Error.new("conflict")}, state}
    else
      id = report["event_id"]
      entry = Map.merge(entry, %{report: report, status: report["status"]})
      state = put_in(state.events[id], entry)

      state =
        emit(state, socket, "project-events", "project/event.updated", %{
          "event_id" => id,
          "acceptance" => "received",
          "processing_status" => entry.status
        })

      {{:ok,
        %{
          "event_id" => id,
          "decision_id" => report["decision_id"],
          "report_status" => "recorded",
          "management_acceptance" => "not_requested"
        }}, state}
    end
  end

  defp emit(state, socket, stream, method, params) do
    {:ok, empty} = Replay.new(stream, limit: state.limit)
    replay = Map.get(state.streams, stream, empty)

    notification = %{
      "schema_version" => "1.0",
      "type" => "notification",
      "method" => method,
      "params" => params,
      "correlation_id" => unique("notification")
    }

    {:ok, message, replay} = Replay.append(replay, notification)
    Server.notify(socket, message)
    put_in(state.streams[stream], replay)
  end

  defp unique(prefix), do: prefix <> ":" <> Integer.to_string(System.unique_integer([:positive]))

  defp capacity?(state, "project/event.receive", %{"event" => event}),
    do:
      Map.has_key?(state.events, event["event_id"]) or map_size(state.events) < state.max_records

  defp capacity?(state, "thread/start", _params), do: map_size(state.threads) < state.max_records
  defp capacity?(state, "turn/start", _params), do: map_size(state.turns) < state.max_records

  defp capacity?(state, "approval/request", params),
    do:
      Map.has_key?(state.approvals, params["approval_id"]) or
        map_size(state.approvals) < state.max_records

  defp capacity?(_state, _method, _params), do: true

  defmodule Handler do
    @moduledoc false
    alias SamgitaProtocol.{Capabilities, Error}

    def capabilities, do: Capabilities.all()
    def methods, do: Capabilities.methods(capabilities())

    def handle_request(method, params, context, state) do
      result = GenServer.call(state.store, {:dispatch, method, params, context, self()})

      case result do
        {:ok, result} ->
          {:ok, result, state}

        {:error, error} ->
          {:error, error, state}

        {:wait_for_approval, id} ->
          receive do
            {:fake_approval, ^id, decision} when decision in ["approve", "deny"] ->
              GenServer.call(state.store, {:approval_result, id, decision})
              {:ok, %{"approval_id" => id, "decision" => decision, "scope" => "once"}, state}
          after
            5_000 -> {:error, Error.new("timeout"), state}
          end
      end
    end

    def handle_response("approval/request", {:ok, result}, _context, state) do
      GenServer.call(state.store, {:approval_result, result["approval_id"], result["decision"]})
      {:ok, state}
    end

    def handle_response("approval/request", {:error, error}, context, state) do
      send(state.owner, {:fake_agent_approval_error, context, error})
      {:ok, state}
    end
  end
end
