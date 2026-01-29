defmodule Samgita.Agent.Worker do
  @moduledoc """
  Agent worker implementing the RARV (Reason-Act-Reflect-Verify) cycle
  as a gen_statem state machine.

  States: :idle -> :reason -> :act -> :reflect -> :verify
  On verify failure: loops back to :reason with updated learnings.
  """

  @behaviour :gen_statem

  defstruct [
    :id,
    :agent_type,
    :project_id,
    :current_task,
    :task_count,
    :token_count,
    :started_at,
    :learnings
  ]

  ## Public API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)

    :gen_statem.start_link(
      {:via, Horde.Registry, {Samgita.AgentRegistry, id}},
      __MODULE__,
      opts,
      []
    )
  end

  def assign_task(pid, task) do
    :gen_statem.cast(pid, {:assign_task, task})
  end

  def get_state(pid) do
    :gen_statem.call(pid, :get_state)
  end

  ## gen_statem callbacks

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  @impl true
  def init(opts) do
    data = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      agent_type: Keyword.fetch!(opts, :agent_type),
      project_id: Keyword.fetch!(opts, :project_id),
      current_task: nil,
      task_count: 0,
      token_count: 0,
      started_at: DateTime.utc_now(),
      learnings: []
    }

    {:ok, :idle, data}
  end

  ## State: idle

  def idle(:enter, _old_state, _data) do
    :keep_state_and_data
  end

  def idle(:cast, {:assign_task, task}, data) do
    {:next_state, :reason, %{data | current_task: task}}
  end

  def idle({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:idle, data}}]}
  end

  ## State: reason

  def reason(:enter, _old_state, data) do
    broadcast_state_change(data, :reason)
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def reason(:state_timeout, :execute, data) do
    # TODO: Load continuity log, check memory, plan approach
    {:next_state, :act, data}
  end

  def reason({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reason, data}}]}
  end

  ## State: act

  def act(:enter, _old_state, data) do
    broadcast_state_change(data, :act)
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def act(:state_timeout, :execute, data) do
    # TODO: Call Claude CLI, parse response, create artifacts, commit checkpoint
    {:next_state, :reflect, data}
  end

  def act({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:act, data}}]}
  end

  ## State: reflect

  def reflect(:enter, _old_state, data) do
    broadcast_state_change(data, :reflect)
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def reflect(:state_timeout, :execute, data) do
    # TODO: Update continuity log, store semantic memory, record metrics
    {:next_state, :verify, data}
  end

  def reflect({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reflect, data}}]}
  end

  ## State: verify

  def verify(:enter, _old_state, data) do
    broadcast_state_change(data, :verify)
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def verify(:state_timeout, :execute, data) do
    # TODO: Run verification (tests, lint, etc.)
    # On success: complete task, return to idle
    # On failure: record learning, return to reason
    data = %{data | current_task: nil, task_count: data.task_count + 1}
    {:next_state, :idle, data}
  end

  def verify({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:verify, data}}]}
  end

  ## Internal

  defp broadcast_state_change(data, state) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{data.project_id}",
      {:agent_state_changed, data.id, state}
    )
  end
end
