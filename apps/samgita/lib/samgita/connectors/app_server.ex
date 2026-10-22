defmodule Samgita.Connectors.AppServer do
  @moduledoc """
  A scoped native `project_events.v1` connector over the existing `/app-server` WebSocket.

  Each invocation authenticates and negotiates a bounded connection. It sends one operation and
  closes; it never reconnects/replays a mutation, starts a thread/turn, or interprets a decision.
  A received ACK is not durable acceptance. The delivery context persists and interprets the
  response and uses explicit status calls for ambiguous outcomes.
  """
  @behaviour Samgita.Connector
  alias Samgita.Connector.Failure
  alias Samgita.Connectors.Destination
  alias SamgitaProtocol.{Event, Schema}
  alias SamgitaProtocolWebSocket.Client
  @capabilities ["project_events.v1"]
  @timeout 5_000

  @impl true
  def receive_event(target, event, operation_id) do
    with :ok <- Event.validate(event),
         true <- Schema.valid?(operation_id, :id) do
      metadata =
        for {key, name} <- [
              correlation_id: "correlation_id",
              causation_id: "causation_id",
              project_ref: "project_ref",
              task_ref: "task_ref"
            ],
            Map.has_key?(event, name),
            do: {key, event[name]}

      call(target, "project/event.receive", %{"event" => event}, operation_id, metadata)
    else
      _ -> {:error, Failure.new(:permanent, :invalid_event)}
    end
  end

  @impl true
  def status(target, event_id, operation_id) do
    if Schema.valid?(event_id, :id) && Schema.valid?(operation_id, :id),
      do: call(target, "project/event.status", %{"event_id" => event_id}, operation_id, []),
      else: {:error, Failure.new(:permanent, :invalid_event)}
  end

  defp call(target, method, params, operation_id, metadata) do
    with {:ok, token} <- credential(target),
         {:ok, destination} <- Destination.resolve(target),
         {:ok, client} <- connect(destination, token) do
      try do
        with {:ok, _initialized} <- initialize(client, operation_id) do
          opts = Keyword.merge([correlation_id: operation_id, timeout_ms: @timeout], metadata)

          opts =
            if method == "project/event.receive",
              do: Keyword.put(opts, :command_id, operation_id),
              else: opts

          case Client.request(client, method, params, opts) do
            {:ok, result} ->
              {:ok, result}

            {:error, error} ->
              {:error, Failure.protocol(error, method == "project/event.receive")}
          end
        end
      catch
        :exit, _ ->
          {:error,
           Failure.new(
             if(method == "project/event.receive", do: :ambiguous, else: :retryable),
             :connector_disconnected
           )}
      after
        close(client)
      end
    end
  end

  defp connect(destination, token) do
    case Client.connect(destination.url,
           token: token,
           capabilities: @capabilities,
           connect_address: destination.address,
           connect_timeout_ms: 3_000,
           request_timeout_ms: @timeout,
           max_frame_bytes: 262_144,
           max_pending: 1,
           max_buffer: 8,
           max_completed: 2,
           max_streams: 1
         ) do
      {:ok, client} -> {:ok, client}
      {:error, error} -> {:error, Failure.protocol(error, false)}
    end
  end

  defp initialize(client, operation_id) do
    params = %{
      "versions" => ["1.0"],
      "capabilities" => @capabilities,
      "required_capabilities" => @capabilities
    }

    case Client.request(client, "connection/initialize", params,
           correlation_id: operation_id,
           timeout_ms: @timeout
         ) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, Failure.protocol(error, false)}
    end
  end

  defp credential(%{credential_ref: reference}) when is_binary(reference) do
    token = Application.get_env(:samgita, :event_credentials, %{})[reference]

    if is_binary(token) && byte_size(token) in 1..8192 && !String.contains?(token, ["\r", "\n"]),
      do: {:ok, token},
      else: {:error, Failure.new(:authentication, :credential_unavailable)}
  end

  defp credential(_), do: {:error, Failure.new(:authentication, :credential_unavailable)}

  defp close(client) do
    if Process.alive?(client), do: Client.close(client)
  catch
    :exit, _ -> :ok
  end
end
