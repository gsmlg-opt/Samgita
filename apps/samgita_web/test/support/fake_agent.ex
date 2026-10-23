defmodule SamgitaWeb.FakeAgent do
  @moduledoc """
  Test-only protocol host with a fsynced journal. It records facts and simulated
  execution starts, never invokes a model, shell, GitHub write or provider service.
  """
  use GenServer
  alias SamgitaProtocol.{Error, Event}
  alias SamgitaProtocolWebSocket.Server

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def url(pid), do: GenServer.call(pid, :url)
  def snapshot(pid), do: GenServer.call(pid, :snapshot)
  def lose_ack(pid, owner), do: GenServer.call(pid, {:lose_ack, owner})
  def start_once(pid, operation), do: GenServer.call(pid, {:start_once, operation})
  def stop_once(pid, operation), do: GenServer.call(pid, {:stop_once, operation})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :journal)
    token = Keyword.fetch!(opts, :token)

    data =
      if File.exists?(path),
        do: path |> File.read!() |> Jason.decode!(),
        else: %{"events" => %{}, "starts" => [], "calls" => []}

    data = Map.put_new(data, "stops", %{})

    store = self()

    {:ok, listener} =
      Server.start_link(
        port: Keyword.get(opts, :port, 0),
        handler: __MODULE__.Handler,
        handler_state: %{store: store},
        authenticate: fn supplied ->
          if byte_size(supplied) == byte_size(token) &&
               Plug.Crypto.secure_compare(supplied, token),
             do: {:ok, %{id: "qualification-client"}},
             else: :error
        end
      )

    {:ok, %{path: path, listener: listener, data: data, lose_ack: nil}}
  end

  @impl true
  def handle_call(:url, _from, state) do
    {:ok, {_, port}} = ThousandIsland.listener_info(state.listener)
    {:reply, "ws://127.0.0.1:#{port}/app-server", state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, state.data, state}
  def handle_call({:lose_ack, owner}, _from, state), do: {:reply, :ok, %{state | lose_ack: owner}}

  def handle_call({:start_once, operation}, _from, state) do
    if operation in state.data["starts"] do
      {:reply, :already_started, state}
    else
      data = Map.update!(state.data, "starts", &(&1 ++ [operation]))
      persist!(state.path, data)
      {:reply, :started, %{state | data: data}}
    end
  end

  def handle_call({:stop_once, operation}, _from, state) do
    cond do
      operation not in state.data["starts"] ->
        {:reply, {:error, :not_started}, state}

      evidence = state.data["stops"][operation] ->
        {:reply, {:ok, evidence}, state}

      true ->
        evidence = %{
          "operation_id" => operation,
          "state" => "stopped",
          "evidence_ref" => "fake-agent-journal:#{state.path}##{operation}"
        }

        data = put_in(state.data, ["stops", operation], evidence)
        persist!(state.path, data)
        {:reply, {:ok, evidence}, %{state | data: data}}
    end
  end

  def handle_call({:receive_event, event, operation}, _from, state) do
    old = state.data["events"][event["event_id"]]

    if old && (!Event.same?(old["event"], event) || old["operation"] != operation) do
      {:reply, {:error, Error.new("conflict")}, state}
    else
      entry = old || %{"event" => event, "operation" => operation, "status" => "pending"}

      data =
        state.data
        |> put_in(["events", event["event_id"]], entry)
        |> Map.update!("calls", &(&1 ++ ["receive"]))

      persist!(state.path, data)
      reply = {:ok, ack(entry, event["delivery_attempt_id"]), state.lose_ack}
      {:reply, reply, %{state | data: data, lose_ack: nil}}
    end
  end

  def handle_call({:status, id}, _from, state) do
    entry = state.data["events"][id]
    data = Map.update!(state.data, "calls", &(&1 ++ ["status"]))
    persist!(state.path, data)
    result = if entry, do: {:ok, ack(entry, nil)}, else: {:error, Error.new("not_found")}
    {:reply, result, %{state | data: data}}
  end

  def handle_call({:report, report}, _from, state) do
    id = report["event_id"]

    case state.data["events"][id] do
      nil ->
        {:reply, {:error, Error.new("not_found")}, state}

      entry ->
        if entry["report"] && entry["report"] != report do
          {:reply, {:error, Error.new("conflict")}, state}
        else
          entry = Map.merge(entry, %{"status" => report["status"], "report" => report})
          data = put_in(state.data, ["events", id], entry)
          persist!(state.path, data)

          {:reply,
           {:ok,
            %{
              "event_id" => id,
              "decision_id" => report["decision_id"],
              "report_status" => "recorded",
              "management_acceptance" => "not_requested"
            }}, %{state | data: data}}
        end
    end
  end

  @impl true
  def handle_info({:EXIT, listener, reason}, %{listener: listener} = state),
    do: {:stop, reason, state}

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.listener), do: Supervisor.stop(state.listener)
  end

  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)

  defp ack(entry, attempt) do
    %{
      "event_id" => entry["event"]["event_id"],
      "acceptance" => "durable",
      "processing_status" => entry["status"]
    }
    |> then(fn result ->
      if attempt,
        do: Map.put(result, "delivery_attempt_id", attempt),
        else: Map.merge(result, Map.take(entry["report"] || %{}, ~w(decision_id decision result)))
    end)
  end

  defp persist!(path, data) do
    {:ok, file} = File.open(path <> ".tmp", [:write, :binary])
    :ok = IO.binwrite(file, Jason.encode!(data))
    :ok = :file.sync(file)
    :ok = File.close(file)
    :ok = File.rename(path <> ".tmp", path)
  end

  defmodule Handler do
    @moduledoc false
    def capabilities, do: ["project_events.v1"]
    def methods, do: SamgitaProtocol.Capabilities.methods(capabilities())

    def handle_request("project/event.receive", %{"event" => event}, context, state) do
      case GenServer.call(state.store, {:receive_event, event, context["command_id"]}) do
        {:ok, result, nil} ->
          {:ok, result, state}

        {:ok, result, owner} ->
          send(owner, {:journal_committed_before_ack, self(), event["event_id"]})

          receive do
            :release_ack -> {:ok, result, state}
          after
            5_000 -> {:error, SamgitaProtocol.Error.new("timeout"), state}
          end

        {:error, error} ->
          {:error, error, state}
      end
    end

    def handle_request("project/event.status", %{"event_id" => id}, _context, state) do
      case GenServer.call(state.store, {:status, id}) do
        {:ok, result} -> {:ok, result, state}
        {:error, error} -> {:error, error, state}
      end
    end

    def handle_request("project/event.report", params, _context, state) do
      case GenServer.call(state.store, {:report, params}) do
        {:ok, result} -> {:ok, result, state}
        {:error, error} -> {:error, error, state}
      end
    end

    def handle_request(_, _, _, state),
      do: {:error, SamgitaProtocol.Error.new("unsupported_method"), state}
  end
end
