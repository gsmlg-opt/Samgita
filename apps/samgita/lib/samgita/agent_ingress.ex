defmodule Samgita.AgentIngress do
  @moduledoc """
  Bounded, node-local routes to Agent-owned inbound WebSockets.

  Pending requests are disposable; trusted device digests and connection generations live in
  PostgreSQL through Agents. A socket is usable only after native initialization. This process
  never owns work or replays an uncertain request; the durable delivery context does that.
  """
  use GenServer

  alias Samgita.{Agents, Error, Principal}
  alias Samgita.Connector.Failure

  @pending_ms 300_000
  @max_pending 100
  @request_ms 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def topic, do: "agent_ingress"
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @doc "Bootstrap a socket without retaining its plaintext device token."
  def connect(socket, attrs) do
    with :ok <- validate_bootstrap(attrs) do
      token = attrs["device_token"]

      case Agents.authenticate_device(token) do
        {:ok, principal} ->
          open(socket, principal)

        :unknown ->
          request = %{
            id: Ecto.UUID.generate(),
            name: attrs["name"],
            implementation: attrs["implementation"],
            digest: :crypto.hash(:sha256, token)
          }

          GenServer.call(__MODULE__, {:pending, socket, request})

        {:error, _} = error ->
          error
      end
    end
  end

  def approve(%Principal{kind: :operator} = operator, id, attrs) do
    GenServer.call(__MODULE__, {:approve, operator, id, attrs}, :infinity)
  end

  def approve(_, _, _), do: {:error, Error.new(:forbidden)}

  def reject(%Principal{kind: :operator}, id),
    do: GenServer.call(__MODULE__, {:reject, id})

  def reject(_, _), do: {:error, Error.new(:forbidden)}

  def disconnect(%Principal{kind: :operator}, id),
    do: GenServer.call(__MODULE__, {:disconnect, id})

  def disconnect(_, _), do: {:error, Error.new(:forbidden)}

  def ready(socket, principal), do: GenServer.call(__MODULE__, {:ready, socket, principal})
  def reply(socket, id, result), do: GenServer.cast(__MODULE__, {:response, socket, id, result})

  @doc "Send once over the current initialized socket. No automatic outbound fallback."
  def request(agent_id, method, params, opts) do
    case GenServer.call(__MODULE__, {:route, agent_id}) do
      {:ok, %{principal: principal} = route} ->
        case Agents.bind_connection(principal, principal.connection_id) do
          {:ok, _} ->
            GenServer.call(__MODULE__, {:request, route, method, params, opts}, :infinity)

          {:error, _} ->
            {:error, Failure.new(:authentication, :connection_invalid)}
        end

      {:error, _} = error ->
        error
    end
  catch
    :exit, _ -> {:error, Failure.new(:ambiguous, :inbound_disconnected)}
  end

  defp open(socket, principal),
    do: GenServer.call(__MODULE__, {:open, socket, principal}, :infinity)

  defp new_connection(principal) do
    with {:ok, connection} <- Agents.connect(principal, %{"command_id" => Ecto.UUID.generate()}),
         {:ok, principal} <- Agents.bind_connection(principal, connection["id"]) do
      {:ok, connection, principal}
    end
  end

  defp validate_bootstrap(attrs) when is_map(attrs) do
    if Enum.sort(Map.keys(attrs)) == ~w(device_token implementation name type) &&
         attrs["type"] == "agent/connect" &&
         bounded_string?(attrs["name"], 200) &&
         bounded_string?(attrs["implementation"], 200) &&
         is_binary(attrs["device_token"]) && byte_size(attrs["device_token"]) in 32..256,
       do: :ok,
       else: {:error, Error.new(:invalid)}
  end

  defp validate_bootstrap(_), do: {:error, Error.new(:invalid)}
  defp bounded_string?(s, max), do: is_binary(s) && byte_size(s) in 1..max && String.trim(s) != ""

  @impl true
  def init(_opts), do: {:ok, %{pending: %{}, connections: %{}, requests: %{}}}

  @impl true
  def handle_call(:snapshot, _from, state) do
    pending =
      state.pending
      |> Map.values()
      |> Enum.map(&Map.take(&1, [:id, :name, :implementation, :expires_at]))
      |> Enum.sort_by(& &1.id)

    connected =
      Map.new(state.connections, fn {id, route} ->
        {id,
         %{
           state: if(route.ready, do: :connected, else: :initializing),
           connection_id: route.principal.connection_id
         }}
      end)

    {:reply, %{pending: pending, connected: connected}, state}
  end

  def handle_call({:pending, socket, request}, from, state) do
    # Authentication may have raced a queued confirmation. Recheck under the same lifecycle owner
    # so that a newly trusted reconnect resumes instead of getting stuck as a second applicant.
    case Agents.lookup_device(request.digest) do
      :unknown -> put_pending(socket, request, state)
      {:ok, principal} -> handle_call({:open, socket, principal}, from, state)
      {:error, _} = error -> {:reply, error, state}
    end
  end

  # Serialize the complete decision with reject, expiry and replacement. Concurrent confirmations
  # cannot create two generations for a socket, and a rejected request cannot later become trusted.
  def handle_call({:approve, operator, id, attrs}, _from, state) do
    case state.pending[id] do
      nil ->
        {:reply, {:error, Error.new(:not_found)}, state}

      pending ->
        if Process.alive?(pending.socket) &&
             DateTime.compare(pending.expires_at, DateTime.utc_now()) == :gt do
          approve_pending(operator, pending, attrs, state)
        else
          {:reply, {:error, Error.new(:not_found)},
           state |> drop_pending(id, true) |> broadcast()}
        end
    end
  end

  def handle_call({:reject, id}, _from, state),
    do: {:reply, :ok, state |> drop_pending(id, true) |> broadcast()}

  def handle_call({:disconnect, id}, _from, state),
    do: {:reply, :ok, state |> drop_connection(id, true) |> broadcast()}

  def handle_call({:open, socket, principal}, _from, state) do
    # Generation creation and route replacement have the same order, even on simultaneous reconnects.
    case new_connection(principal) do
      {:ok, _connection, principal} = result ->
        {:reply, result, broadcast(attach(state, socket, principal))}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:ready, socket, principal}, _from, state) do
    case state.connections[principal.agent_id] do
      %{socket: ^socket, principal: ^principal} ->
        {:reply, :ok, broadcast(put_in(state.connections[principal.agent_id].ready, true))}

      _ ->
        {:reply, {:error, Error.new(:unauthorized)}, state}
    end
  end

  def handle_call({:route, agent_id}, _from, state) do
    case state.connections[agent_id] do
      %{ready: true} = route -> {:reply, {:ok, route}, state}
      _ -> {:reply, {:error, Failure.new(:retryable, :inbound_disconnected)}, state}
    end
  end

  def handle_call({:request, route, method, params, opts}, from, state) do
    current = state.connections[route.principal.agent_id]

    cond do
      current != route ->
        {:reply, {:error, Failure.new(:retryable, :inbound_disconnected)}, state}

      Enum.any?(state.requests, fn {_, r} -> r.socket == route.socket end) ->
        {:reply, {:error, Failure.new(:retryable, :inbound_busy)}, state}

      true ->
        id = Ecto.UUID.generate()
        opts = Keyword.put(opts, :id, id)
        timer = Process.send_after(self(), {:request_expired, id}, @request_ms)
        request = %{from: from, socket: route.socket, method: method, timer: timer}
        send(route.socket, {:protocol_request, method, params, opts})
        {:noreply, put_in(state.requests[id], request)}
    end
  end

  @impl true
  def handle_cast({:response, socket, id, result}, state) do
    case state.requests[id] do
      %{socket: ^socket} = request ->
        result =
          case result do
            {:ok, _} ->
              result

            {:error, error} ->
              {:error, Failure.protocol(error, request.method == "project/event.receive")}
          end

        state = settle(state, id, result)

        state =
          if match?({:error, %Failure{class: :ambiguous}}, result),
            do: close_route(state, socket),
            else: state

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:request_expired, id}, state) do
    case state.requests[id] do
      nil ->
        {:noreply, state}

      request ->
        state =
          state |> settle(id, disconnected(request, :timeout)) |> close_route(request.socket)

        {:noreply, state}
    end
  end

  def handle_info({:pending_expired, id}, state),
    do: {:noreply, state |> drop_pending(id, true) |> broadcast()}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state.pending, state, fn {id, p}, state ->
        if p.monitor == monitor, do: drop_pending(state, id, false), else: state
      end)

    state =
      Enum.reduce(state.connections, state, fn {id, r}, state ->
        if r.monitor == monitor, do: drop_connection(state, id, false), else: state
      end)

    {:noreply, broadcast(state)}
  end

  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)

  defp approve_pending(operator, pending, attrs, state) do
    attrs =
      attrs
      |> Map.take(~w(command_id agent_id expected_version))
      |> Map.merge(%{
        "request_id" => pending.id,
        "device_digest" => Base.encode16(pending.digest, case: :lower),
        "name" => pending.name,
        "implementation" => pending.implementation
      })

    case Agents.pair_device(operator, attrs) do
      {:ok, agent} ->
        with {:ok, principal} <- Agents.device_principal(pending.digest),
             {:ok, connection, principal} <- new_connection(principal) do
          state = attach(state, pending.socket, principal)
          send(pending.socket, {:agent_ingress_approved, connection, principal})
          {:reply, {:ok, agent}, broadcast(state)}
        else
          {:error, _} = error ->
            # Trust is committed. Closing lets the client recover using its saved token rather
            # than presenting a second approval for an already registered device.
            {:reply, error, state |> drop_pending(pending.id, true) |> broadcast()}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp put_pending(socket, request, state) do
    # One pending request per device: reconnect replaces its disposable request, never its trust.
    state =
      Enum.reduce(state.pending, state, fn {id, old}, state ->
        if old.digest == request.digest || old.socket == socket,
          do: drop_pending(state, id, true),
          else: state
      end)

    if map_size(state.pending) >= @max_pending do
      {:reply, {:error, Error.new(:conflict, %{reason: "pending_limit"})}, state}
    else
      request =
        Map.merge(request, %{
          socket: socket,
          monitor: Process.monitor(socket),
          timer: Process.send_after(self(), {:pending_expired, request.id}, @pending_ms),
          expires_at: DateTime.add(DateTime.utc_now(), div(@pending_ms, 1000))
        })

      {:reply, {:pending, request.id}, broadcast(put_in(state.pending[request.id], request))}
    end
  end

  defp drop_pending(state, id, close) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {pending, rest} ->
        Process.cancel_timer(pending.timer)
        Process.demonitor(pending.monitor, [:flush])
        if close, do: send(pending.socket, :agent_ingress_close)
        %{state | pending: rest}
    end
  end

  defp attach(state, socket, principal) do
    state =
      Enum.reduce(state.pending, state, fn {id, request}, state ->
        if request.socket == socket, do: drop_pending(state, id, false), else: state
      end)

    state = drop_connection(state, principal.agent_id, true)

    route = %{
      socket: socket,
      principal: principal,
      monitor: Process.monitor(socket),
      ready: false
    }

    put_in(state.connections[principal.agent_id], route)
  end

  defp drop_connection(state, id, close) do
    case Map.pop(state.connections, id) do
      {nil, _} ->
        state

      {route, rest} ->
        Process.demonitor(route.monitor, [:flush])
        if close, do: send(route.socket, :agent_ingress_close)
        state = %{state | connections: rest}

        Enum.reduce(state.requests, state, fn {id, request}, state ->
          if request.socket == route.socket,
            do: settle(state, id, disconnected(request, :inbound_disconnected)),
            else: state
        end)
    end
  end

  # A timed-out mutation consumes the native client's uncertainty budget. Close rather than
  # silently replay or reuse that protocol state; the remembered device reconnects for status.
  defp close_route(state, socket) do
    Enum.reduce(state.connections, state, fn {id, route}, state ->
      if route.socket == socket, do: drop_connection(state, id, true) |> broadcast(), else: state
    end)
  end

  defp disconnected(request, code) do
    class = if request.method == "project/event.receive", do: :ambiguous, else: :retryable
    {:error, Failure.new(class, code)}
  end

  defp settle(state, id, result) do
    {request, rest} = Map.pop(state.requests, id)
    Process.cancel_timer(request.timer)
    GenServer.reply(request.from, result)
    %{state | requests: rest}
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Samgita.PubSub, topic(), {:agent_ingress_changed})
    state
  end
end
