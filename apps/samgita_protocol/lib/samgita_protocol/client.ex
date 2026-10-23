defmodule SamgitaProtocol.Client do
  @moduledoc """
  Pure bidirectional connection state. The caller sends returned messages and executes effects.

  Disconnects/timeouts never resend work. Mutations with unknown outcomes remain in `uncertain`
  until the caller reconciles them with its authenticated host. Cursors advance only after an
  explicit processed acknowledgement, not on transport receipt.
  """
  alias SamgitaProtocol.{Capabilities, Codec, Error, Schema}
  @context ~w(id correlation_id causation_id project_ref task_ref command_id)
  defstruct phase: :new,
            capabilities: [],
            negotiated: [],
            connection_id: nil,
            generation: 0,
            sequence: 0,
            pending: %{},
            incoming: %{},
            uncertain: %{},
            completed: %{},
            completed_order: [],
            buffer: [],
            streams: %{},
            max_pending: 64,
            max_buffer: 128,
            max_completed: 128,
            max_streams: 64,
            max_frame_bytes: 1_048_576,
            request_timeout_ms: 30_000

  def new(opts \\ []) do
    config =
      Keyword.take(opts, [
        :capabilities,
        :max_pending,
        :max_buffer,
        :max_completed,
        :max_streams,
        :max_frame_bytes,
        :request_timeout_ms
      ])

    client = struct!(__MODULE__, config)
    checkpoints = Keyword.get(opts, :checkpoints, %{})

    with :ok <- Capabilities.validate(client.capabilities),
         true <-
           Enum.all?(
             [
               client.max_pending,
               client.max_buffer,
               client.max_completed,
               client.max_streams,
               client.max_frame_bytes,
               client.request_timeout_ms
             ],
             &(is_integer(&1) and &1 > 0)
           ),
         true <-
           is_map(checkpoints) and not is_struct(checkpoints) and
             map_size(checkpoints) <= client.max_streams and
             Enum.all?(checkpoints, fn {stream, cursor} ->
               Schema.valid?(stream, :id) and Schema.valid?(cursor, :nonneg)
             end) do
      streams =
        Map.new(checkpoints, fn {stream, cursor} ->
          {stream, %{seen: cursor, delivered: cursor, acked: cursor, hashes: %{}}}
        end)

      {:ok, %{client | streams: streams}}
    else
      _ -> {:error, Error.new("invalid_params")}
    end
  end

  def request(client, method, params, opts \\ []) do
    id = Keyword.get(opts, :id, "#{client.generation}:#{client.sequence + 1}")

    message = %{
      "schema_version" => "1.0",
      "type" => "request",
      "id" => id,
      "correlation_id" => Keyword.get(opts, :correlation_id, id),
      "method" => method,
      "params" => params
    }

    message =
      Enum.reduce([:command_id, :causation_id, :project_ref, :task_ref], message, fn key, acc ->
        if Keyword.has_key?(opts, key),
          do: Map.put(acc, Atom.to_string(key), opts[key]),
          else: acc
      end)

    with {:ok, _} <- Codec.encode(message, max_frame_bytes: client.max_frame_bytes),
         :ok <- outgoing_allowed(client, message),
         :ok <- request_capacity(client, message),
         :ok <- request_identity(client, message),
         timeout when is_integer(timeout) and timeout > 0 <-
           Keyword.get(opts, :timeout_ms, client.request_timeout_ms) do
      pending = %{request: message, deadline: Keyword.get(opts, :now_ms, now()) + timeout}
      phase = if method == "connection/initialize", do: :initializing, else: client.phase

      {:ok, message,
       %{
         client
         | pending: Map.put(client.pending, id, pending),
           phase: phase,
           sequence: client.sequence + 1
       }}
    else
      {:error, error} -> {:error, error, client}
      _ -> {:error, Error.new("invalid_params"), client}
    end
  end

  def receive(client, data) do
    case decode(data, client.max_frame_bytes) do
      {:ok, message} -> receive_message(client, message)
      {:error, error} -> {:error, error, client}
    end
  end

  @doc "Explicitly ingest events from an already correlated stream/resume result. Failure leaves client state unchanged."
  def receive_replay(client, result) do
    with :ok <- Schema.validate_result("stream/resume", result),
         true <- Enum.all?(result["events"], &(&1["stream_id"] == result["stream_id"])),
         true <-
           result["events"] == [] or List.last(result["events"])["cursor"] == result["cursor"] do
      ingest_replay(client, result["events"])
    else
      false -> {:error, Error.new("invalid_response"), client}
      {:error, error} -> {:error, error, client}
    end
  end

  defp ingest_replay(client, events) do
    Enum.reduce_while(events, {:ok, [], client}, fn event, {:ok, effects, next} ->
      case receive(next, event) do
        {:ok, more, next} -> {:cont, {:ok, effects ++ more, next}}
        {:error, error, _} -> {:halt, {:error, error, client}}
      end
    end)
  end

  defp receive_message(client, %{"type" => "response", "id" => id} = message) do
    cond do
      client.phase == :disconnected -> {:error, Error.new("stale_connection"), client}
      Map.has_key?(client.pending, id) -> settle_response(client, message, client.pending[id])
      Map.has_key?(client.completed, id) and client.completed[id] == message -> {:ok, [], client}
      Map.has_key?(client.completed, id) -> {:error, Error.new("conflicting_response"), client}
      true -> {:error, Error.new("unknown_response"), client}
    end
  end

  defp receive_message(client, %{"type" => "request"} = message) do
    with :ok <- incoming_allowed(client, message),
         true <- map_size(client.incoming) < client.max_pending do
      case client.incoming[message["id"]] do
        ^message ->
          {:ok, [], client}

        nil ->
          {:ok, [{:request, message}],
           %{client | incoming: Map.put(client.incoming, message["id"], message)}}

        _ ->
          {:error, Error.new("conflict"), client}
      end
    else
      false -> {:error, Error.new("too_many_requests"), client}
      {:error, error} -> {:error, error, client}
    end
  end

  defp receive_message(client, %{"type" => "notification"} = message) do
    with :ok <- incoming_allowed(client, message),
         {:ok, status, streams} <- stream_position(client, message) do
      cond do
        status == :duplicate ->
          {:ok, [], client}

        length(client.buffer) >= client.max_buffer ->
          {:error, Error.new("buffer_full"), client}

        true ->
          {:ok, [{:notification, message}],
           %{client | buffer: client.buffer ++ [message], streams: streams}}
      end
    else
      {:error, error} -> {:error, error, client}
    end
  end

  def reply(client, original, result) when is_map(original) and not is_struct(original) do
    with true <- client.phase == :ready,
         true <- client.incoming[original["id"]] == original,
         {:ok, response} <- response_to(original, result),
         :ok <- Schema.validate_reply(original, response) do
      {:ok, response, %{client | incoming: Map.delete(client.incoming, original["id"])}}
    else
      false -> {:error, Error.new("correlation_mismatch"), client}
      {:error, error} -> {:error, error, client}
    end
  end

  def reply(client, _, _), do: {:error, Error.new("invalid_message"), client}

  def response_to(request, {:ok, result}), do: build_response(request, "result", result)

  def response_to(request, {:error, %Error{} = error}),
    do: build_response(request, "error", Error.to_map(error))

  def response_to(_, _), do: {:error, Error.new("invalid_response")}

  defp build_response(request, key, payload) when is_map(request) and not is_struct(request) do
    request
    |> Map.take(@context)
    |> Map.merge(%{"schema_version" => "1.0", "type" => "response", key => payload})
    |> Schema.validate()
  end

  defp build_response(_, _, _), do: {:error, Error.new("invalid_message")}

  def disconnect(client) do
    {effects, client} = lose_pending(client, Map.keys(client.pending), "disconnected")
    {:ok, effects, %{client | phase: :disconnected, incoming: %{}}}
  end

  def reconnect(%{phase: :disconnected} = client) do
    {:ok,
     %{
       client
       | phase: :new,
         negotiated: [],
         connection_id: nil,
         generation: client.generation + 1,
         pending: %{},
         incoming: %{},
         completed: %{},
         completed_order: []
     }}
  end

  def reconnect(client), do: {:error, Error.new("conflict"), client}

  def expire(client, now_ms) when is_integer(now_ms) do
    expired = for {id, %{deadline: deadline}} <- client.pending, deadline <= now_ms, do: id
    {effects, client} = lose_pending(client, expired, "timeout")
    {:ok, effects, client}
  end

  @doc "Call only after an authenticated host query or audited reconciliation resolves an unknown effect."
  def resolve_uncertain(client, command_id, %{"status" => status, "evidence_ref" => evidence})
      when status in ["completed", "not_accepted", "reconciled"] do
    case {client.uncertain[command_id], Schema.valid?(evidence, :id)} do
      {nil, _} ->
        {:error, Error.new("not_found"), client}

      {entry, true} ->
        {:ok, entry.request, %{client | uncertain: Map.delete(client.uncertain, command_id)}}

      _ ->
        {:error, Error.new("invalid_params"), client}
    end
  end

  def resolve_uncertain(client, _, _), do: {:error, Error.new("invalid_params"), client}

  def drain(client, limit) when is_integer(limit) and limit >= 0 do
    {messages, remaining} = Enum.split(client.buffer, min(limit, client.max_buffer))

    streams =
      Enum.reduce(messages, client.streams, fn
        %{"stream_id" => stream, "cursor" => cursor}, acc ->
          update_in(acc, [stream, :delivered], &max(&1, cursor))

        _, acc ->
          acc
      end)

    {messages, %{client | buffer: remaining, streams: streams}}
  end

  def ack_cursor(client, stream, cursor) when is_integer(cursor) and cursor >= 0 do
    case client.streams[stream] do
      %{delivered: delivered, acked: acked} when cursor <= delivered and cursor >= acked ->
        {:ok, put_in(client.streams[stream].acked, cursor)}

      _ ->
        {:error, Error.new("stale_cursor"), client}
    end
  end

  def ack_cursor(client, _, _), do: {:error, Error.new("stale_cursor"), client}

  @doc "The checkpoint to persist externally and request from the host after reconnect."
  def replay_cursor(client, stream), do: get_in(client.streams, [stream, :acked]) || 0

  @doc "Persist these processed checkpoints and restore with new(checkpoints: map) after a process restart."
  def checkpoints(client),
    do: Map.new(client.streams, fn {stream, state} -> {stream, state.acked} end)

  @doc false
  def establish(client, capabilities, connection_id),
    do: %{client | phase: :ready, negotiated: capabilities, connection_id: connection_id}

  defp settle_response(client, message, %{request: request}) do
    with true <- Map.take(message, @context) == Map.take(request, @context),
         :ok <- Schema.validate_reply(request, message),
         {:ok, client} <- initialize_result(client, request, message) do
      effect =
        if Map.has_key?(message, "result"),
          do: {:response, message["id"], message["result"]},
          else: {:error, message["id"], elem(Error.from_map(message["error"]), 1)}

      client = %{client | pending: Map.delete(client.pending, message["id"])} |> remember(message)
      {:ok, [effect], client}
    else
      false -> {:error, Error.new("correlation_mismatch"), client}
      {:error, error} -> {:error, error, client}
    end
  end

  defp initialize_result(client, %{"method" => "connection/initialize", "params" => params}, %{
         "result" => result
       }) do
    selected = result["capabilities"]

    if result["version"] in params["versions"] and
         Enum.all?(selected, &(&1 in client.capabilities and &1 in params["capabilities"])) and
         Enum.all?(Map.get(params, "required_capabilities", []), &(&1 in selected)) do
      {:ok, establish(client, selected, result["connection_id"])}
    else
      {:error, Error.new("unsupported_capability")}
    end
  end

  defp initialize_result(client, %{"method" => "connection/initialize"}, %{"error" => _}),
    do: {:ok, %{client | phase: :new}}

  defp initialize_result(client, _, _), do: {:ok, client}

  defp outgoing_allowed(%{phase: :new}, %{"method" => "connection/initialize"}), do: :ok

  defp outgoing_allowed(_, %{"method" => "connection/initialize"}),
    do: {:error, Error.new("already_initialized")}

  defp outgoing_allowed(client, message), do: incoming_allowed(client, message)

  defp incoming_allowed(%{phase: :ready, negotiated: groups}, message) do
    if Capabilities.supports?(groups, message["method"]),
      do: :ok,
      else: {:error, Error.new("unsupported_capability")}
  end

  defp incoming_allowed(_, _), do: {:error, Error.new("not_initialized")}

  defp request_capacity(client, %{"method" => "connection/initialize"}) do
    if map_size(client.pending) == 0, do: :ok, else: {:error, Error.new("too_many_requests")}
  end

  defp request_capacity(client, _) do
    if map_size(client.pending) + map_size(client.uncertain) < client.max_pending,
      do: :ok,
      else: {:error, Error.new("too_many_requests")}
  end

  defp request_identity(client, message) do
    cond do
      Map.has_key?(client.pending, message["id"]) or Map.has_key?(client.completed, message["id"]) ->
        {:error, Error.new("conflict")}

      message["command_id"] != nil and Map.has_key?(client.uncertain, message["command_id"]) ->
        {:error, Error.new("ambiguous_disconnect")}

      message["command_id"] != nil and
          Enum.any?(client.pending, fn {_, entry} ->
            entry.request["command_id"] == message["command_id"]
          end) ->
        {:error, Error.new("conflict")}

      true ->
        :ok
    end
  end

  defp remember(client, message) do
    order = [message["id"] | client.completed_order] |> Enum.take(client.max_completed)

    %{
      client
      | completed_order: order,
        completed: client.completed |> Map.put(message["id"], message) |> Map.take(order)
    }
  end

  defp lose_pending(client, ids, read_code) do
    Enum.reduce(Enum.sort(ids), {[], client}, fn id, {effects, acc} ->
      entry = acc.pending[id]
      mutation = Schema.mutating?(entry.request["method"])
      error = Error.new(if mutation, do: "ambiguous_disconnect", else: read_code)

      uncertain =
        if mutation,
          do: Map.put(acc.uncertain, entry.request["command_id"], entry),
          else: acc.uncertain

      phase =
        if entry.request["method"] == "connection/initialize", do: :disconnected, else: acc.phase

      {effects ++ [{:error, id, error}],
       %{acc | pending: Map.delete(acc.pending, id), uncertain: uncertain, phase: phase}
       |> remember(%{"id" => id})}
    end)
  end

  defp stream_position(client, %{"stream_id" => id, "cursor" => cursor} = message) do
    stream = Map.get(client.streams, id, %{seen: 0, delivered: 0, acked: 0, hashes: %{}})
    digest = :crypto.hash(:sha256, JSON.encode!(message))

    cond do
      not Map.has_key?(client.streams, id) and map_size(client.streams) >= client.max_streams ->
        {:error, Error.new("buffer_full")}

      cursor <= stream.acked ->
        {:ok, :duplicate, client.streams}

      cursor > stream.seen + 1 ->
        {:error, Error.new("replay_gap")}

      cursor <= stream.seen ->
        known_cursor(client.streams, stream.hashes, cursor, digest)

      true ->
        hashes =
          stream.hashes
          |> Map.put(cursor, digest)
          |> Enum.filter(fn {n, _} -> n > cursor - client.max_completed end)
          |> Map.new()

        {:ok, :new, Map.put(client.streams, id, %{stream | seen: cursor, hashes: hashes})}
    end
  end

  defp stream_position(client, _), do: {:ok, :new, client.streams}

  defp known_cursor(streams, hashes, cursor, digest) do
    cond do
      hashes[cursor] == digest -> {:ok, :duplicate, streams}
      Map.has_key?(hashes, cursor) -> {:error, Error.new("conflict")}
      true -> {:error, Error.new("stale_cursor")}
    end
  end

  defp decode(binary, max) when is_binary(binary), do: Codec.decode(binary, max_frame_bytes: max)

  defp decode(message, max) do
    with {:ok, _} <- Codec.encode(message, max_frame_bytes: max), do: {:ok, message}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
