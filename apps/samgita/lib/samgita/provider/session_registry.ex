defmodule Samgita.Provider.SessionRegistry do
  @moduledoc """
  Tracks active provider sessions for observability and orphan cleanup.

  Uses an ETS table with `:public` access and `read_concurrency: true` so
  callers can read directly without going through the GenServer process.
  Writes still go through the GenServer to serialise mutations and ensure the
  table owner remains alive.
  """

  use GenServer

  @table_name :samgita_provider_sessions

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Start the registry. Accepts the standard `GenServer` option list."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a session for `{project_id, agent_id}`.

  `session` must be a map with at least the keys defined in the module doc.
  Overwrites any existing entry for the same key.
  """
  @spec register(String.t(), String.t(), map()) :: :ok
  def register(project_id, agent_id, session) do
    GenServer.call(__MODULE__, {:register, project_id, agent_id, session})
  end

  @doc "Remove the session entry for `{project_id, agent_id}`."
  @spec unregister(String.t(), String.t()) :: :ok
  def unregister(project_id, agent_id) do
    GenServer.call(__MODULE__, {:unregister, project_id, agent_id})
  end

  @doc "Return the session info for `{project_id, agent_id}`, or `nil` if absent."
  @spec lookup(String.t(), String.t()) :: map() | nil
  def lookup(project_id, agent_id) do
    case :ets.lookup(@table_name, {project_id, agent_id}) do
      [{{^project_id, ^agent_id}, session}] -> session
      [] -> nil
    end
  end

  @doc "Return all active sessions as a list of `{key, session_info}` tuples."
  @spec list_sessions() :: [{term(), map()}]
  def list_sessions do
    :ets.tab2list(@table_name)
  end

  @doc "Return all sessions belonging to `project_id`."
  @spec list_sessions(String.t()) :: [{term(), map()}]
  def list_sessions(project_id) do
    :ets.match_object(@table_name, {{project_id, :_}, :_})
  end

  @doc """
  Remove the session for `{project_id, agent_id}`.

  Alias for `unregister/2`; called when the owning agent process crashes so
  the name makes the intent clear at the call-site.
  """
  @spec cleanup_for_agent(String.t(), String.t()) :: :ok
  def cleanup_for_agent(project_id, agent_id) do
    unregister(project_id, agent_id)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    table =
      :ets.new(@table_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, project_id, agent_id, session}, _from, state) do
    :ets.insert(@table_name, {{project_id, agent_id}, session})
    {:reply, :ok, state}
  end

  def handle_call({:unregister, project_id, agent_id}, _from, state) do
    :ets.delete(@table_name, {project_id, agent_id})
    {:reply, :ok, state}
  end
end
