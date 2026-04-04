defmodule Samgita.Agent.MessageRouter do
  @moduledoc """
  GenServer that routes messages between agents within a project.

  Registered via Horde as `{:message_router, project_id}`.
  Enforces per-sender/task message budgets and depth limits to prevent
  runaway cascades. Messages are broadcast over PubSub and logged to
  the `agent_messages` table on a best-effort basis.
  """

  use GenServer

  require Logger

  @max_messages_per_task 10
  @max_depth 3

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    GenServer.start_link(__MODULE__, opts, name: via(project_id))
  end

  @doc """
  Send a message through the router. The message map must include at
  least `:sender_agent_id` and `:content`. Optional keys: `:recipient_agent_id`,
  `:message_type`, `:task_id`, `:correlation_id`, `:depth`.
  """
  def send_message(project_id, message) do
    case lookup(project_id) do
      {:ok, pid} -> GenServer.call(pid, {:send_message, message})
      error -> error
    end
  end

  @doc """
  Reset the message budget for a given agent, allowing it to send again.
  """
  def reset_budget(project_id, agent_id) do
    case lookup(project_id) do
      {:ok, pid} -> GenServer.cast(pid, {:reset_budget, agent_id})
      _ -> :ok
    end
  end

  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    %{
      id: {__MODULE__, project_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    {:ok, %{project_id: project_id, budgets: %{}}}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    case process_message(message, state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:reset_budget, agent_id}, state) do
    budgets =
      state.budgets
      |> Enum.reject(fn {{sender, _task}, _count} -> sender == agent_id end)
      |> Map.new()

    {:noreply, %{state | budgets: budgets}}
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp process_message(message, state) do
    sender = message.sender_agent_id
    task_id = message[:task_id] || "default"
    budget_key = {sender, task_id}

    current_count = Map.get(state.budgets, budget_key, 0)

    cond do
      current_count >= @max_messages_per_task ->
        Logger.warning("[MessageRouter] Budget exceeded for #{sender} on task #{task_id}")
        {:error, :budget_exceeded}

      (message[:depth] || 0) >= @max_depth ->
        Logger.warning("[MessageRouter] Depth limit exceeded for message from #{sender}")
        {:error, :depth_exceeded}

      true ->
        log_message(state.project_id, message)
        publish_message(state.project_id, message)

        new_budgets = Map.put(state.budgets, budget_key, current_count + 1)
        {:ok, %{state | budgets: new_budgets}}
    end
  end

  defp publish_message(project_id, message) do
    topic = "samgita:agents:#{project_id}"
    Phoenix.PubSub.broadcast(Samgita.PubSub, topic, {:agent_message, message})
  end

  defp log_message(project_id, message) do
    %Samgita.Domain.AgentMessage{}
    |> Samgita.Domain.AgentMessage.changeset(%{
      project_id: project_id,
      sender_agent_id: message.sender_agent_id,
      recipient_agent_id: message[:recipient_agent_id] || "*",
      message_type: to_string(message[:message_type] || "notify"),
      content: message.content,
      correlation_id: message[:correlation_id],
      depth: message[:depth] || 0
    })
    |> Samgita.Repo.insert()
  rescue
    e -> Logger.debug("[MessageRouter] Failed to log message: #{inspect(e)}")
  end

  defp via(project_id) do
    {:via, Horde.Registry, {Samgita.AgentRegistry, {:message_router, project_id}}}
  end

  defp lookup(project_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:message_router, project_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
