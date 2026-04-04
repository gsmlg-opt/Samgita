defmodule Samgita.Agent.PromptBuilder do
  @moduledoc """
  Pure-function module that assembles LLM prompts for agent tasks.

  Extracted from `Samgita.Agent.Worker` to separate prompt construction
  from state machine logic. Every function is side-effect free — no DB
  queries, no PubSub, no process messages.

  ## Context map

  The `context` argument accepted by `build/2` and the private builders
  is a plain map with these keys:

    * `:learnings`        – list of strings (previous task learnings)
    * `:agent_type`       – string agent type id (e.g. `"eng-backend"`)
    * `:task_count`       – integer, number of tasks completed so far
    * `:project_info`     – string block with project name/location/phase
    * `:prd_context`      – string block with PRD title and content
    * `:memory_learnings` – list of strings from the memory system
  """

  alias Samgita.Agent.ContextAssembler
  alias Samgita.Agent.Types

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  @doc """
  Build a prompt string for the given task and context.

  Dispatches to a type-specific builder based on `task_type(task)`.
  """
  @spec build(map(), map()) :: String.t()
  def build(task, context) do
    base_prompt =
      case task_type(task) do
        "bootstrap" -> build_bootstrap_prompt(task, context)
        "generate-prd" -> build_prd_prompt(task, context)
        "analysis" -> build_analysis_prompt(task, context)
        "architecture" -> build_architecture_prompt(task, context)
        "implement" -> build_implement_prompt(task, context)
        "review" -> build_review_prompt(task, context)
        "test" -> build_test_prompt(task, context)
        _ -> build_generic_prompt(task, context)
      end

    base_prompt <> format_messages_section(context)
  end

  @doc """
  Extract the task type from a string-keyed or atom-keyed map.
  """
  @spec task_type(map()) :: String.t()
  def task_type(%{type: type}), do: type
  def task_type(%{"type" => type}), do: type
  def task_type(_), do: "unknown"

  @doc """
  Extract the description from a task's payload, falling back to `""`.
  """
  @spec task_description(map()) :: String.t()
  def task_description(task) do
    payload = task_payload(task)
    payload["description"] || ""
  end

  @doc """
  Extract the payload map from a string-keyed or atom-keyed task.
  """
  @spec task_payload(map()) :: map()
  def task_payload(%{payload: payload}), do: payload
  def task_payload(%{"payload" => payload}), do: payload
  def task_payload(_), do: %{}

  @doc """
  Combine `:learnings` and `:memory_learnings` from the context into a
  single formatted string suitable for inclusion in a prompt.
  """
  @spec format_learnings(map()) :: String.t()
  def format_learnings(context) do
    learnings = Map.get(context, :learnings, []) || []
    memory = Map.get(context, :memory_learnings, []) || []
    all = learnings ++ memory
    do_format_learnings(all)
  end

  # -------------------------------------------------------------------
  # Private builders
  # -------------------------------------------------------------------

  defp resolve_type(context) do
    agent_type = Map.get(context, :agent_type, "unknown")
    Types.get(agent_type) || {nil, agent_type, ""}
  end

  defp project_and_prd_context(context) do
    project_info = Map.get(context, :project_info, "") || ""
    prd_context = Map.get(context, :prd_context, "") || ""
    project_info <> prd_context
  end

  # -- bootstrap -------------------------------------------------------

  defp build_bootstrap_prompt(task, context) do
    payload = task_payload(task)
    {_, type_name, type_desc} = resolve_type(context)

    project_name = payload["project_name"] || "Unnamed Project"
    git_url = payload["git_url"] || ""
    working_path = payload["working_path"] || ""
    prd_title = payload["prd_title"] || "Untitled"
    prd_content = payload["prd_content"] || ""

    location =
      if working_path != "" do
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

  # -- prd -------------------------------------------------------------

  defp build_prd_prompt(task, context) do
    payload = task_payload(task)
    {_, type_name, type_desc} = resolve_type(context)

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

  # -- analysis --------------------------------------------------------

  defp build_analysis_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || "Analyze the project"

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
    ## Task: Discovery Analysis

    #{description}

    ## Previous Learnings
    #{format_learnings(context)}

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

  # -- architecture ----------------------------------------------------

  defp build_architecture_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || "Design the architecture"
    learnings = format_learnings(context)

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
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

  # -- implement -------------------------------------------------------

  defp build_implement_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || "Implement the feature"

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
    ## Task: Implementation

    #{description}

    ## Previous Learnings
    #{format_learnings(context)}

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

  # -- review ----------------------------------------------------------

  defp build_review_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || "Review the implementation"

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
    ## Task: Code Review

    #{description}

    ## Previous Learnings
    #{format_learnings(context)}

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

  # -- test ------------------------------------------------------------

  defp build_test_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || "Write and run tests"

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
    ## Task: Testing

    #{description}

    ## Previous Learnings
    #{format_learnings(context)}

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

  # -- generic ---------------------------------------------------------

  defp build_generic_prompt(task, context) do
    {_, type_name, type_desc} = resolve_type(context)
    payload = task_payload(task)
    combined_context = project_and_prd_context(context)
    description = payload["description"] || inspect(payload)

    """
    You are a #{type_name} (#{type_desc}).
    #{combined_context}
    ## Task
    Type: #{task_type(task)}
    Description: #{description}

    ## Previous Learnings
    #{format_learnings(context)}

    Execute this task thoroughly. Analyze the codebase if needed, implement changes,
    and verify your work compiles and tests pass. Output your results in markdown format.
    """
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp do_format_learnings([]), do: "None yet."
  defp do_format_learnings(items), do: Enum.map_join(items, "\n", &"- #{&1}")

  defp format_messages_section(context) do
    messages = Map.get(context, :received_messages, [])

    case messages do
      [] ->
        ""

      _ ->
        formatted = ContextAssembler.format_received_messages(messages)

        """

        ## Messages from Teammates
        #{formatted}
        """
    end
  end
end
