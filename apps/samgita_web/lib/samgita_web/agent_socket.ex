defmodule SamgitaWeb.AgentSocket do
  @moduledoc "Operator-confirmed device bootstrap followed by the native bidirectional protocol."
  @behaviour WebSock

  alias Samgita.{AgentIngress, Agents, Error}
  alias SamgitaProtocolWebSocket.Socket

  @frame_bytes 262_144

  @impl true
  def init(_opts) do
    monitor = Process.monitor(AgentIngress)
    timer = Process.send_after(self(), :bootstrap_expired, 10_000)
    {:ok, %{protocol: nil, principal: nil, phase: :new, monitor: monitor, timer: timer}}
  end

  @impl true
  def handle_in({text, opcode: :text}, %{phase: :new} = state)
      when byte_size(text) <= 4096 do
    with {:ok, attrs} <- JSON.decode(text) do
      case AgentIngress.connect(self(), attrs) do
        {:pending, id} ->
          Process.cancel_timer(state.timer)
          push(%{"type" => "agent/pending", "request_id" => id}, %{state | phase: :pending})

        {:ok, connection, principal} ->
          connected(connection, principal, state)

        {:error, %Error{code: :conflict, details: %{reason: "pending_limit"}}} ->
          stop(state, :retry)

        {:error, error} ->
          close_for_error(state, error)
      end
    else
      _ -> stop(state, :policy)
    end
  end

  def handle_in(frame, %{phase: :native} = state) do
    with {:ok, _} <- current(state) do
      Socket.handle_in(frame, state.protocol) |> native_result(state)
    else
      {:error, error} -> close_for_error(state, error)
    end
  end

  def handle_in(_frame, state), do: stop(state, :policy)

  @impl true
  def handle_info({:agent_ingress_approved, connection, principal}, %{phase: :pending} = state),
    do: connected(connection, principal, state)

  def handle_info({:agent_ingress_close, reason}, state), do: stop(state, reason)
  def handle_info(:bootstrap_expired, %{phase: :new} = state), do: stop(state, :retry)
  def handle_info(:bootstrap_expired, state), do: {:ok, state}

  def handle_info(:check_connection, %{phase: :native} = state) do
    case current(state) do
      {:ok, _} ->
        Process.send_after(self(), :check_connection, 15_000)
        {:ok, state}

      {:error, error} ->
        close_for_error(state, error)
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state),
    do: stop(state, :restart)

  def handle_info(message, %{phase: :native} = state) do
    with {:ok, _} <- current(state) do
      Socket.handle_info(message, state.protocol) |> native_result(state)
    else
      {:error, error} -> close_for_error(state, error)
    end
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(reason, %{protocol: protocol}) when not is_nil(protocol),
    do: Socket.terminate(reason, protocol)

  def terminate(_reason, _state), do: :ok

  defp connected(connection, principal, state) do
    Process.cancel_timer(state.timer)

    opts = [
      principal: principal,
      connection_id: connection["id"],
      handler: __MODULE__.Handler,
      max_frame_bytes: @frame_bytes,
      max_pending: 1,
      max_buffer: 8,
      max_completed: 32,
      max_streams: 1,
      request_timeout_ms: 5_000
    ]

    case Socket.init(opts) do
      {:ok, protocol} ->
        Process.send_after(self(), :check_connection, 15_000)

        push(%{"type" => "agent/connected", "connection" => connection}, %{
          state
          | protocol: protocol,
            principal: principal,
            phase: :native
        })

      _ ->
        stop(state, :internal)
    end
  end

  defp current(state), do: Agents.check_ingress_connection(state.principal)

  defp native_result({:ok, protocol}, state), do: initialized(:ok, protocol, state)

  defp native_result({:push, frames, protocol}, state),
    do: initialized({:push, frames}, protocol, state)

  defp native_result({:stop, reason, code, protocol}, state),
    do: {:stop, reason, code, %{state | protocol: protocol}}

  defp initialized(action, protocol, state) do
    just_initialized =
      state.protocol.server.client.phase != :ready && protocol.server.client.phase == :ready

    state = %{state | protocol: protocol}

    with :ok <- ready(just_initialized, state) do
      case action do
        :ok -> {:ok, state}
        {:push, frames} -> {:push, frames, state}
      end
    end
  end

  defp ready(false, _state), do: :ok

  defp ready(true, state) do
    with true <- "project_events.v1" in state.protocol.server.client.negotiated,
         :ok <- AgentIngress.ready(self(), state.principal) do
      :ok
    else
      false ->
        stop(state, :policy)

      {:error, _} ->
        case current(state) do
          {:ok, _} -> stop(state, :retry)
          {:error, error} -> close_for_error(state, error)
        end
    end
  end

  defp close_for_error(state, %Error{code: :connection_expired}), do: stop(state, :retry)
  defp close_for_error(state, %Error{code: :connection_replaced}), do: stop(state, :replaced)

  defp close_for_error(state, %Error{code: code})
       when code in [:invalid, :unauthorized, :forbidden],
       do: stop(state, :policy)

  defp close_for_error(state, _error), do: stop(state, :internal)

  defp push(message, state), do: {:push, {:text, JSON.encode!(message)}, state}
  defp stop(state, :policy), do: {:stop, :normal, 1008, state}
  defp stop(state, :internal), do: {:stop, :normal, 1011, state}
  defp stop(state, :restart), do: {:stop, :normal, 1012, state}
  defp stop(state, :retry), do: {:stop, :normal, 1013, state}
  defp stop(state, :replaced), do: {:stop, :normal, 4001, state}

  defmodule Handler do
    @moduledoc false
    @behaviour SamgitaProtocol.Handler

    @impl true
    def capabilities, do: ["project_events.v1"]
    @impl true
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())

    # Management commands remain on the fenced REST API. This endpoint only delivers events.
    @impl true
    def handle_request(_method, _params, _context, state),
      do: {:error, SamgitaProtocol.Error.new("unsupported_method"), state}

    @impl true
    def handle_response(_method, result, context, state) do
      AgentIngress.reply(self(), context["request_id"], result)
      {:ok, state}
    end
  end
end
