defmodule Samgita.Agent.Worker do
  @moduledoc """
  Agent worker implementing the RARV (Reason-Act-Reflect-Verify) cycle
  as a gen_statem state machine.

  States: :idle -> :reason -> :act -> :reflect -> :verify
  On verify failure: loops back to :reason with updated learnings.
  """

  @behaviour :gen_statem

  require Logger

  alias Samgita.Agent.CircuitBreaker
  alias Samgita.Agent.Claude
  alias Samgita.Agent.Types
  alias Samgita.Domain.Artifact
  alias Samgita.Git.Worktree
  alias Samgita.Project.Memory
  alias Samgita.Project.Orchestrator
  alias Samgita.Quality.OutputGuardrails

  defstruct [
    :id,
    :agent_type,
    :project_id,
    :current_task,
    :act_result,
    :reply_to,
    task_count: 0,
    token_count: 0,
    retry_count: 0,
    started_at: nil,
    learnings: []
  ]

  @max_retries 3
  @reason_timeout_ms 60_000
  @reflect_timeout_ms 60_000

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

  def assign_task(pid, task, reply_to \\ nil) do
    :gen_statem.cast(pid, {:assign_task, task, reply_to})
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

  def idle(:cast, {:assign_task, task, reply_to}, data) do
    case CircuitBreaker.allow?(data.agent_type) do
      :ok ->
        {:next_state, :reason, %{data | current_task: task, retry_count: 0, reply_to: reply_to}}

      {:error, :circuit_open} ->
        Logger.warning("[#{data.id}] Circuit open for #{data.agent_type}, rejecting task")

        broadcast_activity(
          data,
          :idle,
          "Circuit breaker open for #{data.agent_type}, task rejected"
        )

        notify_caller(reply_to, data.current_task, {:error, :circuit_open})
        :keep_state_and_data
    end
  end

  def idle({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:idle, data}}]}
  end

  ## State: reason

  def reason(:enter, _old_state, data) do
    broadcast_state_change(data, :reason)
    emit_telemetry(:state_transition, data, %{state: :reason})

    {:keep_state_and_data,
     [
       {:state_timeout, 0, :execute},
       {{:timeout, :reason_deadline}, @reason_timeout_ms, :deadline}
     ]}
  end

  def reason(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] REASON: Planning approach for task #{inspect(data.current_task)}")

    broadcast_activity(
      data,
      :reason,
      "Planning approach for task #{task_type(data.current_task)}"
    )

    try do
      context = build_context(data)
      memory_context = fetch_memory_context(data.project_id)
      learnings = context.learnings ++ memory_learnings(memory_context)
      data = %{data | act_result: nil, learnings: learnings}

      write_continuity_file(data, memory_context)

      {:next_state, :act, data}
    rescue
      e ->
        Logger.error("[#{data.id}] REASON: Error building context: #{inspect(e)}")
        emit_telemetry(:error, data, %{state: :reason, error: inspect(e)})
        {:next_state, :act, %{data | act_result: nil, learnings: data.learnings}}
    end
  end

  def reason({:timeout, :reason_deadline}, :deadline, data) do
    Logger.warning("[#{data.id}] REASON: Timed out after #{@reason_timeout_ms}ms")
    emit_telemetry(:error, data, %{state: :reason, error: :timeout})
    broadcast_activity(data, :reason, "Timed out, proceeding to act")
    {:next_state, :act, %{data | act_result: nil}}
  end

  def reason({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reason, data}}]}
  end

  ## State: act

  def act(:enter, _old_state, data) do
    broadcast_state_change(data, :act)
    emit_telemetry(:state_transition, data, %{state: :act})
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def act(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] ACT: Executing task via Claude CLI")

    broadcast_activity(data, :act, "Executing task via Claude CLI")

    prompt = build_prompt(data)
    model = Types.model_for_type(data.agent_type)

    working_dir = get_working_path(data)

    chat_opts =
      [model: model]
      |> then(fn opts ->
        if working_dir, do: Keyword.put(opts, :working_directory, working_dir), else: opts
      end)

    case Claude.chat(prompt, chat_opts) do
      {:ok, result} ->
        Logger.info("[#{data.id}] ACT: Claude returned result (#{String.length(result)} chars)")

        broadcast_activity(data, :act, "Claude returned result (#{String.length(result)} chars)",
          output: truncate_output(result, 2000)
        )

        {:next_state, :reflect, %{data | act_result: result}}

      {:error, :rate_limit} ->
        backoff = Claude.backoff_ms(data.retry_count)
        Logger.warning("[#{data.id}] ACT: Rate limited, backing off #{backoff}ms")
        broadcast_activity(data, :act, "Rate limited, backing off #{backoff}ms")

        {:keep_state, %{data | retry_count: data.retry_count + 1},
         [{:state_timeout, backoff, :execute}]}

      {:error, :overloaded} ->
        backoff = Claude.backoff_ms(data.retry_count)
        Logger.warning("[#{data.id}] ACT: Overloaded, backing off #{backoff}ms")
        broadcast_activity(data, :act, "Overloaded, backing off #{backoff}ms")

        {:keep_state, %{data | retry_count: data.retry_count + 1},
         [{:state_timeout, backoff, :execute}]}

      {:error, reason} ->
        Logger.error("[#{data.id}] ACT: Failed - #{inspect(reason)}")
        broadcast_activity(data, :act, "Execution failed: #{inspect(reason)}")
        {:next_state, :reflect, %{data | act_result: {:error, reason}}}
    end
  end

  def act({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:act, data}}]}
  end

  ## State: reflect

  def reflect(:enter, _old_state, data) do
    broadcast_state_change(data, :reflect)
    emit_telemetry(:state_transition, data, %{state: :reflect})

    {:keep_state_and_data,
     [
       {:state_timeout, 0, :execute},
       {{:timeout, :reflect_deadline}, @reflect_timeout_ms, :deadline}
     ]}
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

    broadcast_activity(data, :reflect, "Recording learnings: #{learning}")

    data = %{data | learnings: [learning | data.learnings]}

    try do
      persist_learning(data.project_id, learning)
    rescue
      e ->
        Logger.warning("[#{data.id}] REFLECT: Failed to persist learning: #{inspect(e)}")
        emit_telemetry(:error, data, %{state: :reflect, error: inspect(e)})
    end

    {:next_state, :verify, data}
  end

  def reflect({:timeout, :reflect_deadline}, :deadline, data) do
    Logger.warning("[#{data.id}] REFLECT: Timed out after #{@reflect_timeout_ms}ms")
    emit_telemetry(:error, data, %{state: :reflect, error: :timeout})
    broadcast_activity(data, :reflect, "Timed out, proceeding to verify")
    {:next_state, :verify, data}
  end

  def reflect({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reflect, data}}]}
  end

  ## State: verify

  def verify(:enter, _old_state, data) do
    broadcast_state_change(data, :verify)
    emit_telemetry(:state_transition, data, %{state: :verify})
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def verify(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] VERIFY: Validating task output")

    case data.act_result do
      {:error, _reason} when data.retry_count < @max_retries ->
        Logger.warning("[#{data.id}] VERIFY: Failed, retrying from reason phase")

        broadcast_activity(
          data,
          :verify,
          "Verification failed, retrying (attempt #{data.retry_count + 1}/#{@max_retries})"
        )

        {:next_state, :reason, %{data | retry_count: data.retry_count + 1}}

      {:error, reason} ->
        Logger.error("[#{data.id}] VERIFY: Max retries reached, marking failed")
        CircuitBreaker.record_failure(data.agent_type)

        broadcast_activity(
          data,
          :verify,
          "Max retries reached, marking failed: #{inspect(reason)}"
        )

        notify_caller(data.reply_to, data.current_task, {:error, reason})

        data = %{
          data
          | current_task: nil,
            reply_to: nil,
            learnings: ["Max retries: #{inspect(reason)}" | data.learnings]
        }

        {:next_state, :idle, data}

      result when is_binary(result) ->
        # Gate 5: Output Guardrails
        gate_result = OutputGuardrails.validate(result)

        if gate_result.verdict == :fail do
          Logger.warning(
            "[#{data.id}] VERIFY: Output guardrails failed: #{inspect(Enum.map(gate_result.findings, & &1.message))}"
          )

          broadcast_activity(
            data,
            :verify,
            "Output guardrails flagged issues (#{length(gate_result.findings)} findings)"
          )

          # Log but don't block — findings are informational for now
          # Critical secrets should still be flagged
        end

        Logger.info("[#{data.id}] VERIFY: Task verified successfully")
        CircuitBreaker.record_success(data.agent_type)
        broadcast_activity(data, :verify, "Task verified successfully")

        handle_task_completion(data)
        complete_and_notify(data)
        maybe_git_checkpoint(data)
        notify_caller(data.reply_to, data.current_task, :ok)

        data = %{
          data
          | current_task: nil,
            act_result: nil,
            reply_to: nil,
            task_count: data.task_count + 1,
            retry_count: 0
        }

        {:next_state, :idle, data}

      _ ->
        Logger.info("[#{data.id}] VERIFY: Task completed (non-string result)")
        CircuitBreaker.record_success(data.agent_type)
        broadcast_activity(data, :verify, "Task verified successfully")

        handle_task_completion(data)
        complete_and_notify(data)
        maybe_git_checkpoint(data)
        notify_caller(data.reply_to, data.current_task, :ok)

        data = %{
          data
          | current_task: nil,
            act_result: nil,
            reply_to: nil,
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

  defp notify_caller(nil, _task, _result), do: :ok

  defp notify_caller(pid, task, result) when is_pid(pid) do
    task_id =
      case task do
        %{id: id} -> id
        _ -> nil
      end

    send(pid, {:task_completed, task_id, result})
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp notify_caller(_other, _task, _result), do: :ok

  defp broadcast_activity(data, stage, message, opts \\ []) do
    entry = Samgita.Events.build_log_entry(:agent, data.id, stage, message, opts)
    Samgita.Events.activity_log(data.project_id, entry)
  end

  defp truncate_output(text, max_len) when byte_size(text) > max_len do
    String.slice(text, 0, max_len) <> "\n... (truncated)"
  end

  defp truncate_output(text, _max_len), do: text

  defp broadcast_state_change(data, state) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{data.project_id}",
      {:agent_state_changed, data.id, state}
    )

    update_agent_run_status(data, state)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp update_agent_run_status(data, state) do
    case find_active_agent_run(data.project_id, data.agent_type) do
      nil -> :ok
      run -> Samgita.Projects.update_agent_run(run, %{status: state})
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # Write a CONTINUITY.md file to the project's working directory before each RARV cycle.
  # This gives Claude persistent file-based context, matching loki-mode's .loki/CONTINUITY.md.
  defp write_continuity_file(data, memory_context) do
    working_path = get_working_path(data)

    if working_path do
      dir = Path.join(working_path, ".samgita")
      File.mkdir_p!(dir)

      task_desc =
        case data.current_task do
          %{payload: %{"description" => desc}} -> desc
          %{"description" => desc} -> desc
          _ -> task_type(data.current_task)
        end

      episodic_lines =
        memory_context
        |> Map.get(:episodic, [])
        |> Enum.take(5)
        |> Enum.map_join("\n", fn m -> "- #{m.content}" end)

      semantic_lines =
        memory_context
        |> Map.get(:semantic, [])
        |> Enum.take(5)
        |> Enum.map_join("\n", fn m -> "- #{m.content}" end)

      learnings_lines =
        data.learnings
        |> Enum.take(5)
        |> Enum.map_join("\n", fn l -> "- #{l}" end)

      content = """
      # Samgita Continuity
      Agent: #{data.agent_type} | Task Count: #{data.task_count} | Retries: #{data.retry_count}
      Current Task: #{task_desc}

      ## Episodic Memory
      #{if episodic_lines == "", do: "(none)", else: episodic_lines}

      ## Semantic Knowledge
      #{if semantic_lines == "", do: "(none)", else: semantic_lines}

      ## Session Learnings
      #{if learnings_lines == "", do: "(none)", else: learnings_lines}
      """

      path = Path.join(dir, "CONTINUITY.md")
      File.write!(path, content)
    end
  rescue
    e -> Logger.warning("[#{data.id}] Failed to write CONTINUITY.md: #{inspect(e)}")
  catch
    :exit, _ -> :ok
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
      "bootstrap" -> build_bootstrap_prompt(data)
      "generate-prd" -> build_prd_prompt(data)
      "analysis" -> build_analysis_prompt(data)
      "architecture" -> build_architecture_prompt(data)
      "implement" -> build_implement_prompt(data)
      "review" -> build_review_prompt(data)
      "test" -> build_test_prompt(data)
      _ -> build_generic_prompt(data)
    end
  end

  defp build_bootstrap_prompt(data) do
    task = data.current_task
    payload = task_payload(task)
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}

    project_name = payload["project_name"] || "Unnamed Project"
    git_url = payload["git_url"] || ""
    working_path = payload["working_path"] || ""
    prd_title = payload["prd_title"] || "Untitled"
    prd_content = payload["prd_content"] || ""

    location =
      if working_path && working_path != "" do
        "Working directory: #{working_path}"
      else
        "Repository: #{git_url}"
      end

    """
    You are a #{type_name} (#{type_desc}).

    ## Task: Bootstrap Project "#{project_name}"

    #{location}

    You have been given a Product Requirements Document (PRD) to guide the project.
    Analyze it and begin the bootstrap phase.

    ## PRD: #{prd_title}

    #{prd_content}

    ## Instructions

    1. Read and analyze the PRD thoroughly
    2. If there is a git repository or working directory, explore the existing codebase
    3. Identify the key components, features, and milestones described in the PRD
    4. Create an initial project plan breaking down the PRD into actionable tasks
    5. Set up any necessary project structure, configuration, or scaffolding
    6. Document your findings and the plan for the next phases

    Focus on understanding the full scope of the project and preparing for development.
    Output your analysis, plan, and any actions taken in markdown format.
    """
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

  defp build_analysis_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || "Analyze the project"

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task: Discovery Analysis

    #{description}

    ## Previous Learnings
    #{format_learnings(data.learnings)}

    ## Instructions

    Perform a thorough analysis during the discovery phase. Your output should include:

    1. **Findings Summary** — Key observations about the codebase, architecture, and patterns
    2. **Requirements Analysis** — Extracted functional and non-functional requirements
    3. **User Stories** — User stories with acceptance criteria derived from the PRD
    4. **Technical Gaps** — Missing components, outdated dependencies, or architectural concerns
    5. **Recommendations** — Prioritized list of recommendations for the architecture phase
    6. **Risk Assessment** — Potential risks and mitigation strategies

    Be specific and actionable. Reference specific files, modules, or code patterns where relevant.
    Output your analysis in structured markdown format.
    """
  end

  defp build_architecture_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || "Design the architecture"
    learnings = format_learnings(data.learnings)

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task: Architecture Design

    #{description}

    ## Previous Learnings
    #{learnings}

    ## Instructions

    Create a detailed architecture design document. Your output should include:

    1. **Component Overview** — High-level system components and their responsibilities
    2. **API Contracts** — Endpoint definitions, request/response schemas, error codes
    3. **Data Model** — Database schemas, relationships, indexes, constraints
    4. **Integration Points** — External services, third-party APIs, message queues
    5. **Technology Decisions** — Justified technology choices with alternatives considered
    6. **Security Architecture** — Authentication, authorization, data protection patterns
    7. **Scalability Considerations** — Horizontal/vertical scaling strategy, bottleneck analysis

    Be concrete — include actual schema definitions, API endpoint paths, and configuration.
    Output your design in structured markdown format with code blocks for schemas and APIs.
    """
  end

  defp build_implement_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || "Implement the feature"

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task: Implementation

    #{description}

    ## Previous Learnings
    #{format_learnings(data.learnings)}

    ## Instructions

    1. Analyze the existing codebase and architecture to understand the current patterns
    2. Implement the described feature following existing code conventions
    3. Write clean, well-structured code with appropriate error handling
    4. Add or update tests to cover the new functionality
    5. Ensure the code compiles and all tests pass
    6. Make atomic git commits for each logical change

    ## Quality Requirements

    - Follow existing naming conventions and code style
    - Handle edge cases and error conditions
    - Add necessary validations at system boundaries
    - Ensure backward compatibility unless explicitly replacing functionality

    Output your implementation summary including files changed and test results.
    """
  end

  defp build_review_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || "Review the implementation"

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task: Code Review

    #{description}

    ## Previous Learnings
    #{format_learnings(data.learnings)}

    ## Instructions

    Perform a thorough review. Your output should include:

    1. **Summary** — Overall assessment (PASS/FAIL/NEEDS_CHANGES)
    2. **Critical Issues** — Blocking problems that must be fixed
    3. **Warnings** — Non-blocking concerns that should be addressed
    4. **Suggestions** — Optional improvements for code quality
    5. **Security Findings** — Any security vulnerabilities or risks
    6. **Test Coverage** — Assessment of test adequacy

    For each finding, include the file path, line range, severity (critical/high/medium/low),
    and a specific recommendation. Output in structured markdown format.
    """
  end

  defp build_test_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || "Write and run tests"

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task: Testing

    #{description}

    ## Previous Learnings
    #{format_learnings(data.learnings)}

    ## Instructions

    1. Analyze the existing codebase and identify areas lacking test coverage
    2. Write comprehensive tests covering:
       - Unit tests for individual functions and modules
       - Integration tests for module interactions
       - Edge cases and error conditions
       - Boundary value testing
    3. Run the test suite and verify all tests pass
    4. Report test results with coverage metrics

    ## Output Format

    Provide a structured report:
    - **Tests Written** — List of new test files and what they cover
    - **Test Results** — Pass/fail counts, any failures with details
    - **Coverage** — Areas covered and remaining gaps
    - **Recommendations** — Additional tests that should be written

    Output in structured markdown format.
    """
  end

  defp build_generic_prompt(data) do
    task = data.current_task
    {_, type_name, type_desc} = Types.get(data.agent_type) || {nil, data.agent_type, ""}
    payload = task_payload(task)
    project_context = build_project_context(data.project_id, payload)
    description = payload["description"] || inspect(payload)

    """
    You are a #{type_name} (#{type_desc}).
    #{project_context}
    ## Task
    Type: #{task_type(task)}
    Description: #{description}

    ## Previous Learnings
    #{format_learnings(data.learnings)}

    Execute this task thoroughly. Analyze the codebase if needed, implement changes,
    and verify your work compiles and tests pass. Output your results in markdown format.
    """
  end

  defp build_project_context(project_id, payload) do
    project_info = fetch_project_info(project_id)
    prd_context = fetch_prd_context(payload["prd_id"])

    project_info <> prd_context
  end

  defp fetch_project_info(project_id) do
    case Samgita.Projects.get_project(project_id) do
      {:ok, project} ->
        build_project_info_string(project)

      _ ->
        ""
    end
  rescue
    _ -> ""
  end

  defp build_project_info_string(project) do
    working_path = project.working_path || ""
    git_url = project.git_url || ""

    location =
      if working_path != "",
        do: "Working directory: #{working_path}",
        else: "Repository: #{git_url}"

    """

    ## Project: #{project.name}
    #{location}
    Phase: #{project.phase}
    """
  end

  defp fetch_prd_context(nil), do: ""

  defp fetch_prd_context(prd_id) do
    case Samgita.Prds.get_prd(prd_id) do
      {:ok, prd} ->
        build_prd_context_string(prd)

      _ ->
        ""
    end
  rescue
    _ -> ""
  end

  defp build_prd_context_string(prd) do
    content = String.slice(prd.content || "", 0, 2000)

    """

    ## PRD: #{prd.title}
    #{content}
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

  defp format_learnings([]), do: "None yet."
  defp format_learnings(items), do: Enum.join(items, "\n- ")

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

      "analysis" ->
        save_artifact(data, :doc, "discovery")

      "architecture" ->
        save_artifact(data, :doc, "architecture")

      "review" ->
        save_artifact(data, :doc, "review")

      _ ->
        :ok
    end

    increment_agent_run_tasks(data)
  end

  # Mark the DB task as completed and notify the Orchestrator.
  # This is called from the verify state AFTER the RARV cycle completes,
  # ensuring task completion is driven by actual Claude output, not the dispatcher.
  defp complete_and_notify(data) do
    task = data.current_task

    task_id =
      case task do
        %{id: id} -> id
        _ -> nil
      end

    if task_id do
      case Samgita.Projects.complete_task(task_id) do
        {:ok, completed_task} ->
          Samgita.Events.task_completed(completed_task)

        {:error, reason} ->
          Logger.warning(
            "[#{data.id}] Failed to mark task #{task_id} complete: #{inspect(reason)}"
          )
      end

      notify_orchestrator(data.project_id, task_id)
    end
  rescue
    e -> Logger.warning("[#{data.id}] complete_and_notify failed: #{inspect(e)}")
  catch
    :exit, _ -> :ok
  end

  defp notify_orchestrator(project_id, task_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        Orchestrator.notify_task_completed(pid, task_id)

      [] ->
        Logger.warning(
          "[#{project_id}] No orchestrator found for task #{task_id} completion notification"
        )
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp increment_agent_run_tasks(data) do
    case find_active_agent_run(data.project_id, data.agent_type) do
      nil ->
        :ok

      run ->
        Samgita.Projects.update_agent_run(run, %{
          total_tasks: (run.total_tasks || 0) + 1
        })
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp find_active_agent_run(project_id, agent_type) do
    import Ecto.Query

    Samgita.Domain.AgentRun
    |> where([a], a.project_id == ^project_id and a.agent_type == ^agent_type)
    |> where([a], is_nil(a.ended_at))
    |> Samgita.Repo.one()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp save_generated_prd(data) do
    case data.act_result do
      result when is_binary(result) ->
        Logger.info("[#{data.id}] Saving generated PRD to project #{data.project_id}")
        do_save_prd(data, result)

      _ ->
        Logger.warning("[#{data.id}] No PRD content to save")
    end
  end

  defp do_save_prd(data, result) do
    case Samgita.Projects.get_project(data.project_id) do
      {:ok, project} ->
        update_and_broadcast_prd(data, project, result)

      {:error, reason} ->
        Logger.error("[#{data.id}] Failed to get project: #{inspect(reason)}")
    end
  end

  defp update_and_broadcast_prd(data, project, result) do
    save_result =
      case Samgita.Prds.list_prds(project.id) do
        [prd | _] ->
          Samgita.Prds.update_prd(prd, %{content: result, status: :approved})

        [] ->
          Samgita.Prds.create_prd(%{
            project_id: project.id,
            title: "Generated PRD",
            content: result,
            status: :approved
          })
      end

    case save_result do
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
  end

  defp save_artifact(data, type, category) do
    case data.act_result do
      result when is_binary(result) and result != "" ->
        task = data.current_task
        payload = task_payload(task)
        description = payload["description"] || category

        task_id =
          case task do
            %{id: id} -> id
            _ -> nil
          end

        attrs = %{
          type: type,
          path: "#{category}/#{data.agent_type}/#{task_type(task)}",
          content: result,
          content_hash: :crypto.hash(:sha256, result) |> Base.encode16(case: :lower),
          metadata: %{
            "agent_type" => data.agent_type,
            "phase" => payload["phase"],
            "description" => description,
            "category" => category
          },
          project_id: data.project_id,
          task_id: task_id
        }

        case Samgita.Repo.insert(Artifact.changeset(%Artifact{}, attrs)) do
          {:ok, artifact} ->
            Logger.info("[#{data.id}] Saved #{category} artifact: #{artifact.id}")

          {:error, reason} ->
            Logger.warning("[#{data.id}] Failed to save #{category} artifact: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("[#{data.id}] No content to save as #{category} artifact")
    end
  rescue
    e ->
      Logger.warning("[#{data.id}] Error saving #{category} artifact: #{inspect(e)}")
  end

  defp maybe_git_checkpoint(data) do
    task = data.current_task
    working_path = get_working_path(data)

    if working_path && File.dir?(working_path) do
      create_git_checkpoint_if_changes(data, task, working_path)
    end
  rescue
    e ->
      Logger.warning("[#{data.id}] Git checkpoint error: #{inspect(e)}")
  end

  defp create_git_checkpoint_if_changes(data, task, working_path) do
    if Worktree.has_changes?(working_path) do
      phase =
        case Samgita.Projects.get_project(data.project_id) do
          {:ok, p} -> p.phase
          _ -> "unknown"
        end

      message = build_commit_message(data.agent_type, task, phase)
      commit_checkpoint(data, working_path, message)
    end
  rescue
    _ ->
      task_desc = build_task_description(task)
      message = "[samgita] #{data.agent_type}: #{task_desc}"
      commit_checkpoint(data, working_path, message)
  end

  @doc false
  def build_task_description(task) do
    case task do
      %{type: type, payload: %{"description" => desc}} -> "#{type}: #{desc}"
      %{type: type} -> type
      _ -> "task"
    end
  end

  @doc false
  def build_commit_message(agent_type, task, phase) do
    task_desc = build_task_description(task)

    task_id =
      case task do
        %{id: id} -> id
        _ -> "unknown"
      end

    message = """
    [samgita] #{agent_type}: #{task_desc}

    Agent-Type: #{agent_type}
    Phase: #{phase}
    Task-ID: #{task_id}
    Samgita-Version: #{Application.spec(:samgita, :vsn)}
    """

    String.trim(message)
  end

  defp commit_checkpoint(data, working_path, message) do
    case Worktree.commit(working_path, message) do
      {:ok, hash} ->
        Logger.info("[#{data.id}] Git checkpoint: #{hash}")
        broadcast_activity(data, :verify, "Git checkpoint: #{hash}")

      {:error, reason} ->
        Logger.warning("[#{data.id}] Git checkpoint failed: #{inspect(reason)}")
    end
  end

  defp get_working_path(data) do
    case Samgita.Projects.get_project(data.project_id) do
      {:ok, project} -> project.working_path
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp persist_learning(project_id, learning) do
    Memory.add_memory(project_id, :episodic, learning)
  catch
    :exit, _ -> :ok
  end

  defp emit_telemetry(:state_transition, data, metadata) do
    :telemetry.execute(
      [:samgita, :agent, :state_transition],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{
        agent_id: data.id,
        agent_type: data.agent_type,
        project_id: data.project_id
      })
    )
  rescue
    _ -> :ok
  end

  defp emit_telemetry(:error, data, metadata) do
    :telemetry.execute(
      [:samgita, :agent, :error],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{
        agent_id: data.id,
        agent_type: data.agent_type,
        project_id: data.project_id
      })
    )
  rescue
    _ -> :ok
  end
end
