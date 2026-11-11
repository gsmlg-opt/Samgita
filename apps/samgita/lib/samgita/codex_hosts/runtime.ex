defmodule Samgita.CodexHosts.Runtime do
  @moduledoc """
  Supervises one connection process per enabled Codex host.

  `config :samgita, :codex_hosts, enabled: false` keeps the tree running but
  opens no connection, for tests and maintenance boots. Status is runtime state
  published on the `"codex_hosts"` PubSub topic.
  """
  use Supervisor
  alias Samgita.CodexHosts
  alias Samgita.CodexHosts.Connection

  @registry Samgita.CodexHosts.Registry
  @connections Samgita.CodexHosts.ConnectionSupervisor
  @topic "codex_hosts"

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @connections, strategy: :one_for_one},
      {Task.Supervisor, name: Samgita.CodexHosts.ProbeSupervisor},
      Supervisor.child_spec({Task, &sync_all/0}, id: :boot_sync, restart: :temporary)
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def topic, do: @topic

  def enabled?, do: Keyword.get(Application.get_env(:samgita, :codex_hosts, []), :enabled, true)

  @doc "Start connections for every enabled host."
  def sync_all, do: Enum.each(CodexHosts.enabled_ids(), &sync/1)

  @doc "Converge one host's process with its committed configuration."
  def sync(id) do
    host = CodexHosts.load(id)

    # The running configuration version is read from the Registry, never from
    # the connection process, which may be busy connecting for many seconds.
    case {host, lookup(id)} do
      {%{enabled: true} = host, nil} ->
        if enabled?(), do: start(host), else: :ok

      {%{enabled: true, version: version}, {pid, running}} ->
        if running != version, do: restart(id, pid), else: :ok

      {_, nil} ->
        :ok

      {_, {pid, _}} ->
        stop(pid)
    end
  end

  def status(id) do
    case whereis(id) do
      nil -> %{"state" => "stopped"}
      pid -> Connection.status(pid)
    end
  catch
    :exit, _ -> %{"state" => "stopped"}
  end

  def reconnect(id) do
    case whereis(id) do
      nil -> {:error, Samgita.Error.new(:invalid_transition)}
      pid -> Connection.reconnect(pid)
    end
  end

  @doc "The live initialized Session of a connected host, or nil."
  def session(id) do
    case whereis(id) do
      nil -> nil
      pid -> Connection.session(pid)
    end
  catch
    :exit, _ -> nil
  end

  def whereis(id) do
    case lookup(id) do
      {pid, _version} -> pid
      nil -> nil
    end
  end

  # Registry removes entries asynchronously after a process exits.
  defp lookup(id) do
    case Registry.lookup(@registry, id) do
      [{pid, version}] -> if Process.alive?(pid), do: {pid, version}
      [] -> nil
    end
  end

  @doc false
  def via(id, version), do: {:via, Registry, {@registry, id, version}}

  @doc "PubSub topic carrying one Codex thread's live events on one host."
  def thread_topic(host_id, thread_id), do: "codex_thread:" <> host_id <> ":" <> thread_id

  def broadcast_thread(host_id, thread_id, message),
    do: Phoenix.PubSub.broadcast(Samgita.PubSub, thread_topic(host_id, thread_id), message)

  @doc "Call the live connection process of a host, or return `{:error, :not_connected}`."
  def call(id, fun) do
    case whereis(id) do
      nil -> {:error, :not_connected}
      pid -> fun.(pid)
    end
  catch
    :exit, _ -> {:error, :not_connected}
  end

  @doc false
  def broadcast(id, status),
    do: Phoenix.PubSub.broadcast(Samgita.PubSub, @topic, {:codex_host_status, id, status})

  defp start(host) do
    case DynamicSupervisor.start_child(@connections, {Connection, host}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, _} = error -> error
    end
  end

  defp restart(id, pid) do
    stop(pid)
    sync(id)
  end

  defp stop(pid) do
    DynamicSupervisor.terminate_child(@connections, pid)
    :ok
  end
end
