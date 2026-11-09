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

    case {host, whereis(id)} do
      {%{enabled: true} = host, nil} ->
        if enabled?(), do: start(host), else: :ok

      {%{enabled: true, version: version}, pid} ->
        if Connection.config_version(pid) != version, do: restart(id, pid), else: :ok

      {_, nil} ->
        :ok

      {_, pid} ->
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
    # Registry removes entries asynchronously after a process exits.
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @doc false
  def via(id), do: {:via, Registry, {@registry, id}}

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
