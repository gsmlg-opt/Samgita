defmodule Samgita.Agent.Worker do
  @moduledoc """
  Agent worker implementing the RARV (Reason-Act-Reflect-Verify) cycle
  as a gen_statem state machine.

  States: :idle -> :reason -> :act -> :reflect -> :verify
  On verify failure: loops back to :reason with updated learnings.
  """

  @behaviour :gen_statem

  require Logger

  alias Samgita.Agent.Claude
  alias Samgita.Agent.Types
  alias Samgita.Project.Memory

  defstruct [
    :id,
    :agent_type,
    :project_id,
    :current_task,
    :act_result,
    task_count: 0,
    token_count: 0,
    retry_count: 0,
    started_at: nil,
    learnings: []
  ]

  @max_retries 3

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

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
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
      started_at: DateTime.utc_now()
    }

    {:ok, :idle, data}
  end

  ## State: idle

  def idle(:enter, _old_state, _data) do
    :keep_state_and_data
  end

  def idle(:cast, {:assign_task, task}, data) do
    {:next_state, :reason, %{data | current_task: task, retry_count: 0}}
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
    Logger.info("[#{data.id}] REASON: Planning approach for task #{inspect(data.current_task)}")

    context = build_context(data)
    memory_context = fetch_memory_context(data.project_id)
    learnings = context.learnings ++ memory_learnings(memory_context)
    data = %{data | act_result: nil, learnings: learnings}

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
    Logger.info("[#{data.id}] ACT: Executing task via Claude CLI")

    prompt = build_prompt(data)
    model = Types.model_for_type(data.agent_type)

    case Claude.chat(prompt, model: model) do
      {:ok, result} ->
        Logger.info("[#{data.id}] ACT: Claude returned result (#{String.length(result)} chars)")
        {:next_state, :reflect, %{data | act_result: result}}

      {:error, :rate_limit} ->
        backoff = Claude.backoff_ms(data.retry_count)
        Logger.warning("[#{data.id}] ACT: Rate limited, backing off #{backoff}ms")

        {:keep_state, %{data | retry_count: data.retry_count + 1},
         [{:state_timeout, backoff, :execute}]}

      {:error, :overloaded} ->
        backoff = Claude.backoff_ms(data.retry_count)
        Logger.warning("[#{data.id}] ACT: Overloaded, backing off #{backoff}ms")

        {:keep_state, %{data | retry_count: data.retry_count + 1},
         [{:state_timeout, backoff, :execute}]}

      {:error, reason} ->
        Logger.error("[#{data.id}] ACT: Failed - #{inspect(reason)}")
        {:next_state, :reflect, %{data | act_result: {:error, reason}}}
    end
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
    Logger.info("[#{data.id}] REFLECT: Recording learnings")

    learning =
      case data.act_result do
        {:error, reason} ->
          "Task failed: #{inspect(reason)}"

        result when is_binary(result) ->
          "Task completed successfully with #{String.length(result)} chars output"

        _ ->
          "Task completed"
      end

    data = %{data | learnings: [learning | data.learnings]}

    persist_learning(data.project_id, learning)

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
    Logger.info("[#{data.id}] VERIFY: Validating task output")

    case data.act_result do
      {:error, _reason} when data.retry_count < @max_retries ->
        Logger.warning("[#{data.id}] VERIFY: Failed, retrying from reason phase")
        {:next_state, :reason, %{data | retry_count: data.retry_count + 1}}

      {:error, reason} ->
        Logger.error("[#{data.id}] VERIFY: Max retries reached, marking failed")

        data = %{
          data
          | current_task: nil,
            learnings: ["Max retries: #{inspect(reason)}" | data.learnings]
        }

        {:next_state, :idle, data}

      _ ->
        Logger.info("[#{data.id}] VERIFY: Task verified successfully")

        # Handle post-task actions
        handle_task_completion(data)

        data = %{
          data
          | current_task: nil,
            act_result: nil,
            task_count: data.task_count + 1,
            retry_count: 0
        }

        {:next_state, :idle, data}
    end
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

  defp build_context(data) do
    %{
      learnings: data.learnings,
      agent_type: data.agent_type,
      task_count: data.task_count
    }
  end

  defp build_prompt(data) do
    task = data.current_task
    task_type = task_type(task)

    case task_type do
      "generate-prd" -> build_prd_prompt(data)
      _ -> build_generic_prompt(data)
    end
  end

  defp build_prd_prompt(data) do
    task = data.current_task
    payload = task_payload(task)
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}

    project_name = payload["project_name"] || "Unnamed Project"
    git_url = payload["git_url"] || ""
    working_path = payload["working_path"] || ""
    existing_prd = payload["existing_prd"]

    context_info =
      if working_path && working_path != "" do
        "Working directory: #{working_path}"
      else
        "Repository: #{git_url}"
      end

    existing_context =
      if existing_prd && existing_prd != "" do
        """

        ## Existing PRD (refine/expand this)
        #{existing_prd}
        """
      else
        ""
      end

    """
    You are a #{type_name} (#{type_desc}).

    ## Task: Generate Product Requirements Document

    Create a comprehensive Product Requirements Document (PRD) for the project "#{project_name}".

    #{context_info}

    #{existing_context}

    ## PRD Structure

    Please analyze the project and create a PRD with the following sections:

    1. **Project Overview**
       - Brief description
       - Problem statement
       - Target users/audience

    2. **Goals & Objectives**
       - Primary goals
       - Success metrics
       - Out of scope

    3. **User Stories / Use Cases**
       - Key user flows
       - Core functionality requirements

    4. **Technical Requirements**
       - Technology stack recommendations
       - Architecture considerations
       - Integration points

    5. **Non-Functional Requirements**
       - Performance targets
       - Security requirements
       - Scalability considerations

    6. **Milestones & Phases**
       - Development phases
       - Key deliverables
       - Timeline estimates

    ## Instructions

    - If there's a git repository, analyze the existing code/docs to understand the project
    - If there's an existing PRD, enhance and expand it with more details
    - Be specific and actionable
    - Focus on what needs to be built, not how to build it
    - Output only the PRD content in markdown format
    - Do not include any meta-commentary or explanations outside the PRD

    Generate the PRD now:
    """
  end

  defp build_generic_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}

    learnings_text =
      case data.learnings do
        [] -> "None yet."
        items -> Enum.join(items, "\n- ")
      end

    """
    You are a #{type_name} (#{type_desc}).

    ## Task
    Type: #{task_type(task)}
    Payload: #{inspect(task_payload(task))}

    ## Previous Learnings
    #{learnings_text}

    Execute this task and provide the result.
    """
  end

  defp task_type(%{type: type}), do: type
  defp task_type(%{"type" => type}), do: type
  defp task_type(_), do: "unknown"

  defp task_payload(%{payload: payload}), do: payload
  defp task_payload(%{"payload" => payload}), do: payload
  defp task_payload(_), do: %{}

  defp fetch_memory_context(project_id) do
    Memory.get_context(project_id)
  catch
    :exit, _ -> %{episodic: [], semantic: [], procedural: []}
  end

  defp memory_learnings(%{procedural: procedural, semantic: semantic}) do
    procedures = Enum.map(procedural, fn m -> "Procedure: #{m.content}" end)
    semantics = Enum.map(semantic, fn m -> "Knowledge: #{m.content}" end)
    Enum.take(procedures ++ semantics, 5)
  end

  defp memory_learnings(_), do: []

  defp handle_task_completion(data) do
    task = data.current_task
    task_type = task_type(task)

    case task_type do
      "generate-prd" ->
        save_generated_prd(data)

      _ ->
        :ok
    end
  end

  defp save_generated_prd(data) do
    case data.act_result do
      result when is_binary(result) ->
        Logger.info("[#{data.id}] Saving generated PRD to project #{data.project_id}")

        case Samgita.Projects.get_project(data.project_id) do
          {:ok, project} ->
            case Samgita.Projects.update_prd(project, result) do
              {:ok, _} ->
                Logger.info("[#{data.id}] PRD saved successfully")
                Phoenix.PubSub.broadcast(
                  Samgita.PubSub,
                  "project:#{data.project_id}",
                  {:prd_generated, data.project_id}
                )

              {:error, reason} ->
                Logger.error("[#{data.id}] Failed to save PRD: #{inspect(reason)}")
            end

          {:error, reason} ->
            Logger.error("[#{data.id}] Failed to get project: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("[#{data.id}] No PRD content to save")
    end
  end

  defp persist_learning(project_id, learning) do
    Memory.add_memory(project_id, :episodic, learning)
  catch
    :exit, _ -> :ok
  end
end
