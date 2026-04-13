# Phase 1: Worker Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract 6 focused modules from the 1325-line Agent Worker gen_statem, making each independently testable while preserving all existing behavior.

**Architecture:** The Worker currently mixes prompt construction (~350 lines), PubSub/telemetry (~60 lines), git worktree ops (~70 lines), memory/context retrieval (~100 lines), retry logic (~30 lines), and result parsing (~30 lines) into gen_statem state functions. Each concern extracts into a pure-function or struct-based module. The Worker becomes a thin dispatcher — each state function under 30 lines.

**Tech Stack:** Elixir/OTP, gen_statem, Phoenix.PubSub, :telemetry

**PRD Reference:** [docs/product/PRD-V2.md](../../product/PRD-V2.md) — Phase 1 (P1-R1 through P1-R8)

---

## File Structure

| File | Responsibility | Pure? |
|------|---------------|-------|
| `apps/samgita/lib/samgita/agent/prompt_builder.ex` | Assembles LLM prompts for all task types | Yes |
| `apps/samgita/lib/samgita/agent/result_parser.ex` | Classifies provider responses | Yes |
| `apps/samgita/lib/samgita/agent/context_assembler.ex` | Fetches memory, writes CONTINUITY.md | No (I/O) |
| `apps/samgita/lib/samgita/agent/worktree_manager.ex` | Git worktree lifecycle (struct + functions) | No (I/O) |
| `apps/samgita/lib/samgita/agent/activity_broadcaster.ex` | PubSub + telemetry wrapper | No (side effects) |
| `apps/samgita/lib/samgita/agent/retry_strategy.ex` | Backoff calculation, escalation decisions | Yes |
| `apps/samgita/lib/samgita/agent/worker.ex` | Thin gen_statem dispatcher (~200 lines) | N/A |

---

### Task 1: RetryStrategy — Pure backoff and escalation logic

**Files:**
- Create: `apps/samgita/lib/samgita/agent/retry_strategy.ex`
- Test: `apps/samgita/test/samgita/agent/retry_strategy_test.exs`

Extracted from: `worker.ex` lines 223-237 (backoff in act state), lines 323-354 (retry/fail in verify state), and `claude.ex` lines 13-15 (backoff_ms calculation).

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/retry_strategy_test.exs
defmodule Samgita.Agent.RetryStrategyTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.RetryStrategy

  describe "should_retry?/2" do
    test "retries rate_limit errors under max retries" do
      assert RetryStrategy.should_retry?(:rate_limit, 0) == true
      assert RetryStrategy.should_retry?(:rate_limit, 2) == true
    end

    test "retries overloaded errors under max retries" do
      assert RetryStrategy.should_retry?(:overloaded, 1) == true
    end

    test "retries timeout errors under max retries" do
      assert RetryStrategy.should_retry?(:timeout, 0) == true
    end

    test "retries unknown errors under max retries" do
      assert RetryStrategy.should_retry?(:unknown, 2) == true
    end

    test "stops retrying at max retries" do
      assert RetryStrategy.should_retry?(:rate_limit, 3) == false
      assert RetryStrategy.should_retry?(:unknown, 3) == false
    end
  end

  describe "backoff_ms/2" do
    test "exponential backoff for rate_limit" do
      assert RetryStrategy.backoff_ms(:rate_limit, 0) == 60_000
      assert RetryStrategy.backoff_ms(:rate_limit, 1) == 120_000
      assert RetryStrategy.backoff_ms(:rate_limit, 2) == 240_000
    end

    test "exponential backoff for overloaded" do
      assert RetryStrategy.backoff_ms(:overloaded, 0) == 60_000
    end

    test "shorter backoff for timeout" do
      assert RetryStrategy.backoff_ms(:timeout, 0) == 5_000
    end

    test "caps at max backoff" do
      # At attempt 20, 60_000 * 2^20 would overflow, but we cap at 3_600_000
      assert RetryStrategy.backoff_ms(:rate_limit, 20) == 3_600_000
    end
  end

  describe "should_escalate?/2" do
    test "does not escalate under max retries" do
      assert RetryStrategy.should_escalate?(:unknown, 2) == false
    end

    test "escalates at max retries" do
      assert RetryStrategy.should_escalate?(:unknown, 3) == true
    end
  end

  describe "classify_for_retry/1" do
    test "classifies known error atoms" do
      assert RetryStrategy.classify_for_retry(:rate_limit) == :rate_limit
      assert RetryStrategy.classify_for_retry(:overloaded) == :overloaded
      assert RetryStrategy.classify_for_retry(:timeout) == :timeout
    end

    test "classifies string errors as unknown" do
      assert RetryStrategy.classify_for_retry("some error message") == :unknown
    end

    test "classifies other atoms as unknown" do
      assert RetryStrategy.classify_for_retry(:something_else) == :unknown
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/retry_strategy_test.exs`
Expected: Compilation error — `Samgita.Agent.RetryStrategy` not found

- [ ] **Step 3: Write the implementation**

```elixir
# apps/samgita/lib/samgita/agent/retry_strategy.ex
defmodule Samgita.Agent.RetryStrategy do
  @moduledoc """
  Pure-function module encapsulating retry decisions and backoff calculation.

  Given an error category and retry count, determines whether to retry,
  how long to wait, and whether to escalate (open circuit breaker).
  """

  @max_retries 3
  @max_backoff_ms 3_600_000

  @type error_category :: :rate_limit | :overloaded | :timeout | :unknown

  @doc "Returns true if the error should be retried at the given retry count."
  @spec should_retry?(error_category(), non_neg_integer()) :: boolean()
  def should_retry?(_category, retry_count) when retry_count >= @max_retries, do: false
  def should_retry?(_category, _retry_count), do: true

  @doc "Returns the backoff duration in milliseconds."
  @spec backoff_ms(error_category(), non_neg_integer()) :: pos_integer()
  def backoff_ms(:timeout, _attempt), do: 5_000

  def backoff_ms(_category, attempt) do
    min(round(60_000 * :math.pow(2, attempt)), @max_backoff_ms)
  end

  @doc "Returns true if the failure should escalate to circuit breaker."
  @spec should_escalate?(error_category(), non_neg_integer()) :: boolean()
  def should_escalate?(_category, retry_count) when retry_count >= @max_retries, do: true
  def should_escalate?(_category, _retry_count), do: false

  @doc "Classifies a raw error term into a retry category."
  @spec classify_for_retry(term()) :: error_category()
  def classify_for_retry(:rate_limit), do: :rate_limit
  def classify_for_retry(:overloaded), do: :overloaded
  def classify_for_retry(:timeout), do: :timeout
  def classify_for_retry(_other), do: :unknown
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/retry_strategy_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/retry_strategy.ex apps/samgita/test/samgita/agent/retry_strategy_test.exs
git commit -m "feat(agent): extract RetryStrategy module from Worker"
```

---

### Task 2: ActivityBroadcaster — PubSub and telemetry wrapper

**Files:**
- Create: `apps/samgita/lib/samgita/agent/activity_broadcaster.ex`
- Test: `apps/samgita/test/samgita/agent/activity_broadcaster_test.exs`

Extracted from: `worker.ex` lines 463-486 (broadcast_activity, broadcast_state_change), lines 1298-1324 (emit_telemetry).

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/activity_broadcaster_test.exs
defmodule Samgita.Agent.ActivityBroadcasterTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.ActivityBroadcaster

  describe "state_change_payload/3" do
    test "builds state change message" do
      data = %{project_id: "proj-1", id: "agent-1", agent_type: "eng-backend"}
      payload = ActivityBroadcaster.state_change_payload(data, :reason)

      assert payload.project_id == "proj-1"
      assert payload.agent_id == "agent-1"
      assert payload.state == :reason
    end
  end

  describe "activity_payload/4" do
    test "builds activity log payload" do
      data = %{project_id: "proj-1", id: "agent-1", agent_type: "eng-backend"}
      payload = ActivityBroadcaster.activity_payload(data, :act, "Executing task")

      assert payload.project_id == "proj-1"
      assert payload.agent_id == "agent-1"
      assert payload.state == :act
      assert payload.message == "Executing task"
    end

    test "truncates long messages" do
      data = %{project_id: "proj-1", id: "agent-1", agent_type: "eng-backend"}
      long_msg = String.duplicate("x", 600)
      payload = ActivityBroadcaster.activity_payload(data, :act, long_msg)

      assert String.length(payload.message) <= 503
    end
  end

  describe "telemetry_metadata/3" do
    test "builds telemetry metadata for state transition" do
      data = %{project_id: "proj-1", id: "agent-1", agent_type: "eng-backend"}
      meta = ActivityBroadcaster.telemetry_metadata(data, :reason)

      assert meta.agent_id == "agent-1"
      assert meta.agent_type == "eng-backend"
      assert meta.project_id == "proj-1"
      assert meta.state == :reason
      assert is_integer(meta.system_time)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/activity_broadcaster_test.exs`
Expected: Compilation error — module not found

- [ ] **Step 3: Write the implementation**

```elixir
# apps/samgita/lib/samgita/agent/activity_broadcaster.ex
defmodule Samgita.Agent.ActivityBroadcaster do
  @moduledoc """
  Centralizes PubSub broadcasting and telemetry emission for Agent Workers.

  All state transitions, activity logs, and error reports go through this module.
  Keeps the event schema in one place and decouples Workers from PubSub internals.
  """

  @max_message_length 500

  @doc "Broadcast a state change to PubSub and update agent run status."
  def broadcast_state_change(data, state) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{data.project_id}",
      {:agent_state_changed, data.id, state}
    )

    update_agent_run_status(data, state)
  end

  @doc "Broadcast an activity log entry."
  def broadcast_activity(data, state, message, details \\ nil) do
    Samgita.Events.activity_log(
      data.project_id,
      data.id,
      data.agent_type,
      state,
      message,
      details
    )
  end

  @doc "Emit a state transition telemetry event."
  def emit_state_transition(data, state) do
    :telemetry.execute(
      [:samgita, :agent, :state_transition],
      %{system_time: System.system_time()},
      telemetry_metadata(data, state)
    )
  end

  @doc "Emit an error telemetry event."
  def emit_error(data, state, error) do
    :telemetry.execute(
      [:samgita, :agent, :error],
      %{system_time: System.system_time()},
      Map.put(telemetry_metadata(data, state), :error, inspect(error))
    )
  end

  @doc "Build a state change payload map."
  def state_change_payload(data, state) do
    %{
      project_id: data.project_id,
      agent_id: data.id,
      agent_type: data.agent_type,
      state: state
    }
  end

  @doc "Build an activity log payload map."
  def activity_payload(data, state, message, _details \\ nil) do
    %{
      project_id: data.project_id,
      agent_id: data.id,
      agent_type: data.agent_type,
      state: state,
      message: truncate(message, @max_message_length)
    }
  end

  @doc "Build telemetry metadata map."
  def telemetry_metadata(data, state) do
    %{
      system_time: System.system_time(),
      agent_id: data.id,
      agent_type: data.agent_type,
      project_id: data.project_id,
      state: state
    }
  end

  defp truncate(text, max_len) when is_binary(text) and byte_size(text) > max_len do
    String.slice(text, 0, max_len) <> "..."
  end

  defp truncate(text, _max_len) when is_binary(text), do: text
  defp truncate(nil, _max_len), do: ""

  defp update_agent_run_status(data, state) do
    case Samgita.AgentRuns.get_active_run(data.project_id, data.agent_type) do
      nil -> :ok
      run -> Samgita.AgentRuns.update_run(run, %{status: to_string(state)})
    end
  rescue
    _ -> :ok
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/activity_broadcaster_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/activity_broadcaster.ex apps/samgita/test/samgita/agent/activity_broadcaster_test.exs
git commit -m "feat(agent): extract ActivityBroadcaster module from Worker"
```

---

### Task 3: ResultParser — Response classification

**Files:**
- Create: `apps/samgita/lib/samgita/agent/result_parser.ex`
- Test: `apps/samgita/test/samgita/agent/result_parser_test.exs`

Extracted from: `worker.ex` verify state logic (lines 319-416) — the branching on `data.act_result` being `{:ok, result}`, `{:error, reason}`, or unexpected values.

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/result_parser_test.exs
defmodule Samgita.Agent.ResultParserTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.ResultParser

  describe "classify/1" do
    test "classifies successful binary result" do
      assert {:success, "hello world"} = ResultParser.classify({:ok, "hello world"})
    end

    test "classifies empty string as failure" do
      assert {:failure, :empty_response} = ResultParser.classify({:ok, ""})
    end

    test "classifies nil result as failure" do
      assert {:failure, :nil_response} = ResultParser.classify({:ok, nil})
    end

    test "classifies error tuple" do
      assert {:failure, :rate_limit} = ResultParser.classify({:error, :rate_limit})
    end

    test "classifies string error" do
      assert {:failure, "connection refused"} = ResultParser.classify({:error, "connection refused"})
    end

    test "classifies unexpected format" do
      assert {:failure, :unexpected_format} = ResultParser.classify(:something_else)
    end
  end

  describe "success?/1" do
    test "true for success tuples" do
      assert ResultParser.success?({:success, "result"}) == true
    end

    test "false for failure tuples" do
      assert ResultParser.success?({:failure, :rate_limit}) == false
    end
  end

  describe "error_category/1" do
    test "extracts category from failure" do
      assert ResultParser.error_category({:failure, :rate_limit}) == :rate_limit
    end

    test "returns nil for success" do
      assert ResultParser.error_category({:success, "ok"}) == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/result_parser_test.exs`
Expected: Compilation error

- [ ] **Step 3: Write the implementation**

```elixir
# apps/samgita/lib/samgita/agent/result_parser.ex
defmodule Samgita.Agent.ResultParser do
  @moduledoc """
  Pure-function module that classifies provider responses.

  Takes raw provider output and returns a tagged tuple:
  - `{:success, content}` — valid response ready for verification
  - `{:failure, reason}` — error with category for retry decisions
  """

  @type classified :: {:success, String.t()} | {:failure, term()}

  @doc "Classify a raw provider response."
  @spec classify(term()) :: classified()
  def classify({:ok, result}) when is_binary(result) and byte_size(result) > 0 do
    {:success, result}
  end

  def classify({:ok, ""}) do
    {:failure, :empty_response}
  end

  def classify({:ok, nil}) do
    {:failure, :nil_response}
  end

  def classify({:error, reason}) do
    {:failure, reason}
  end

  def classify(_other) do
    {:failure, :unexpected_format}
  end

  @doc "Returns true if the classified result is a success."
  @spec success?(classified()) :: boolean()
  def success?({:success, _}), do: true
  def success?({:failure, _}), do: false

  @doc "Extracts the error category from a classified result."
  @spec error_category(classified()) :: term() | nil
  def error_category({:failure, reason}), do: reason
  def error_category({:success, _}), do: nil
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/result_parser_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/result_parser.ex apps/samgita/test/samgita/agent/result_parser_test.exs
git commit -m "feat(agent): extract ResultParser module from Worker"
```

---

### Task 4: PromptBuilder — LLM prompt assembly

**Files:**
- Create: `apps/samgita/lib/samgita/agent/prompt_builder.ex`
- Test: `apps/samgita/test/samgita/agent/prompt_builder_test.exs`

Extracted from: `worker.ex` lines 556-977 (~420 lines) — `build_context`, `build_prompt`, all `build_*_prompt` functions, project/PRD context fetching.

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/prompt_builder_test.exs
defmodule Samgita.Agent.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.PromptBuilder

  @sample_task %{
    "type" => "implement",
    "payload" => %{"description" => "Build user auth"}
  }

  @sample_context %{
    learnings: ["Use bcrypt for passwords"],
    agent_type: "eng-backend",
    task_count: 3,
    project_info: "Project: MyApp\nGit: https://github.com/test/myapp",
    prd_context: "## Requirements\n- User can register\n- User can login",
    memory_learnings: ["Previous auth attempts used JWT"]
  }

  describe "build/2" do
    test "builds implement prompt with context" do
      prompt = PromptBuilder.build(@sample_task, @sample_context)

      assert prompt =~ "Build user auth"
      assert prompt =~ "eng-backend"
      assert is_binary(prompt)
      assert String.length(prompt) > 100
    end

    test "builds bootstrap prompt" do
      task = %{"type" => "bootstrap", "payload" => %{"description" => "Init project"}}
      prompt = PromptBuilder.build(task, @sample_context)

      assert prompt =~ "bootstrap"
      assert is_binary(prompt)
    end

    test "builds review prompt" do
      task = %{"type" => "review", "payload" => %{"description" => "Review auth code"}}
      prompt = PromptBuilder.build(task, @sample_context)

      assert prompt =~ "review"
      assert is_binary(prompt)
    end

    test "builds test prompt" do
      task = %{"type" => "test", "payload" => %{"description" => "Write auth tests"}}
      prompt = PromptBuilder.build(task, @sample_context)

      assert prompt =~ "test"
      assert is_binary(prompt)
    end

    test "falls back to generic prompt for unknown type" do
      task = %{"type" => "custom_thing", "payload" => %{"description" => "Do stuff"}}
      prompt = PromptBuilder.build(task, @sample_context)

      assert prompt =~ "Do stuff"
      assert is_binary(prompt)
    end

    test "includes learnings when present" do
      prompt = PromptBuilder.build(@sample_task, @sample_context)
      assert prompt =~ "bcrypt"
    end

    test "handles nil/empty context gracefully" do
      context = %{
        learnings: [],
        agent_type: "eng-backend",
        task_count: 0,
        project_info: nil,
        prd_context: nil,
        memory_learnings: []
      }

      prompt = PromptBuilder.build(@sample_task, context)
      assert is_binary(prompt)
    end
  end

  describe "task_type/1" do
    test "extracts type from string-keyed map" do
      assert PromptBuilder.task_type(%{"type" => "implement"}) == "implement"
    end

    test "extracts type from atom-keyed map" do
      assert PromptBuilder.task_type(%{type: "review"}) == "review"
    end
  end

  describe "task_description/1" do
    test "extracts description from nested payload" do
      task = %{"payload" => %{"description" => "Build it"}}
      assert PromptBuilder.task_description(task) == "Build it"
    end

    test "returns fallback for missing description" do
      task = %{"payload" => %{}}
      desc = PromptBuilder.task_description(task)
      assert is_binary(desc)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/prompt_builder_test.exs`
Expected: Compilation error

- [ ] **Step 3: Write the implementation**

Read `worker.ex` lines 556-977 and extract all prompt-building functions. The module must reproduce the exact same prompt strings as the current Worker. Key functions to extract:

- `build_context/1` → becomes part of the context map passed in
- `build_prompt/1` → becomes `build/2` dispatching on task type
- `build_bootstrap_prompt/1` (lines 580-624)
- `build_prd_prompt/1` (lines 626-709)
- `build_analysis_prompt/1` (lines 711-742)
- `build_architecture_prompt/1` (lines 744-777)
- `build_implement_prompt/1` (lines 779-814)
- `build_review_prompt/1` (lines 816-847)
- `build_test_prompt/1` (lines 849-887)
- `build_generic_prompt/1` (lines 889-909)
- `build_project_context/2` (lines 911-916)
- `fetch_project_info/1` (lines 918-928)
- `build_project_info_string/1` (lines 930-945)
- `fetch_prd_context/1` (lines 947-959)
- `build_prd_context_string/1` (lines 961-969)
- `task_type/1` (lines 971-973)
- `task_payload/1` (lines 975-977)

```elixir
# apps/samgita/lib/samgita/agent/prompt_builder.ex
defmodule Samgita.Agent.PromptBuilder do
  @moduledoc """
  Pure-function module that assembles LLM prompts for RARV Act phase.

  Takes a task and a context map, returns a structured prompt string.
  All prompt templates are centralized here for easy modification.
  """

  @doc "Build a prompt for the given task and context."
  @spec build(map(), map()) :: String.t()
  def build(task, context) do
    case task_type(task) do
      "bootstrap" -> build_bootstrap_prompt(task, context)
      "prd" -> build_prd_prompt(task, context)
      "analysis" -> build_analysis_prompt(task, context)
      "architecture" -> build_architecture_prompt(task, context)
      "implement" -> build_implement_prompt(task, context)
      "review" -> build_review_prompt(task, context)
      "test" -> build_test_prompt(task, context)
      _ -> build_generic_prompt(task, context)
    end
  end

  @doc "Extract task type from atom or string-keyed map."
  def task_type(%{"type" => type}) when is_binary(type), do: type
  def task_type(%{type: type}) when is_binary(type), do: type
  def task_type(%{type: type}) when is_atom(type), do: to_string(type)
  def task_type(_), do: "generic"

  @doc "Extract task description from payload."
  def task_description(task) do
    payload = task_payload(task)
    payload["description"] || payload[:description] || "Execute assigned task"
  end

  def task_payload(%{"payload" => payload}) when is_map(payload), do: payload
  def task_payload(%{payload: payload}) when is_map(payload), do: payload
  def task_payload(_), do: %{}

  # NOTE: Each build_*_prompt function below must be copied EXACTLY from
  # worker.ex lines 580-909, replacing `data` references with `task` and `context`.
  # The actual extraction should read worker.ex and reproduce each prompt template.
  # Below are stubs — the implementer MUST read worker.ex and copy the full templates.

  defp build_bootstrap_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    prd_context = context[:prd_context] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent in the bootstrap phase.

    ## Project Context
    #{project_info}

    ## PRD
    #{prd_context}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Execute this bootstrap task. Create the necessary project structure, analyze the PRD, and generate an initial task backlog. Be thorough and systematic.
    """
  end

  defp build_prd_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent generating a Product Requirements Document.

    ## Project Context
    #{project_info}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Generate a comprehensive PRD with numbered requirements, acceptance criteria, milestones, and task decomposition. Follow industry best practices for PRD writing.
    """
  end

  defp build_analysis_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    prd_context = context[:prd_context] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent in the discovery/analysis phase.

    ## Project Context
    #{project_info}

    ## PRD
    #{prd_context}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Analyze the requirements thoroughly. Identify technical challenges, dependencies, and risks. Produce a structured analysis document.
    """
  end

  defp build_architecture_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    prd_context = context[:prd_context] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent in the architecture phase.

    ## Project Context
    #{project_info}

    ## PRD
    #{prd_context}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Design the system architecture. Define components, data flows, API contracts, and technology choices. Consider scalability, security, and maintainability.
    """
  end

  defp build_implement_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    prd_context = context[:prd_context] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent in the development phase.

    ## Project Context
    #{project_info}

    ## PRD
    #{prd_context}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Implement this feature following TDD practices. Write tests first, then implementation. Commit atomically. Follow existing code patterns and conventions.
    """
  end

  defp build_review_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent performing code review.

    ## Project Context
    #{project_info}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Review the code for correctness, security, performance, and maintainability. Provide specific, actionable feedback with line references. Flag any critical issues.
    """
  end

  defp build_test_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    prd_context = context[:prd_context] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent writing tests.

    ## Project Context
    #{project_info}

    ## PRD Requirements
    #{prd_context}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Write comprehensive tests covering happy paths, edge cases, and error scenarios. Aim for high coverage. Use the project's existing test patterns and frameworks.
    """
  end

  defp build_generic_prompt(task, context) do
    description = task_description(task)
    project_info = context[:project_info] || ""
    learnings = format_learnings(context)

    """
    You are a #{context[:agent_type]} agent.

    ## Project Context
    #{project_info}

    ## Task
    #{description}

    ## Previous Learnings
    #{learnings}

    Complete this task thoroughly and systematically. Follow best practices for your domain.
    """
  end

  defp format_learnings(context) do
    all_learnings =
      (context[:learnings] || []) ++ (context[:memory_learnings] || [])

    case all_learnings do
      [] -> "None yet."
      items -> Enum.map_join(items, "\n", &"- #{&1}")
    end
  end
end
```

**IMPORTANT NOTE FOR IMPLEMENTER:** The prompt templates above are simplified stubs. The actual implementation MUST read `worker.ex` lines 580-909 and reproduce the exact prompt strings from those functions. The structure (dispatching on task type, combining project/prd/learnings context) is correct, but the specific prompt text within each builder MUST match the current Worker output character-for-character to satisfy P1-R8 (no functional changes).

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/prompt_builder_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/prompt_builder.ex apps/samgita/test/samgita/agent/prompt_builder_test.exs
git commit -m "feat(agent): extract PromptBuilder module from Worker"
```

---

### Task 5: ContextAssembler — Memory fetching and CONTINUITY.md

**Files:**
- Create: `apps/samgita/lib/samgita/agent/context_assembler.ex`
- Test: `apps/samgita/test/samgita/agent/context_assembler_test.exs`

Extracted from: `worker.ex` lines 499-554 (write_continuity_file), lines 979-994 (fetch_memory_context, memory_learnings, format_learnings), lines 911-969 (project/PRD context fetching).

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/context_assembler_test.exs
defmodule Samgita.Agent.ContextAssemblerTest do
  use Samgita.DataCase, async: true

  alias Samgita.Agent.ContextAssembler

  describe "assemble/1" do
    test "returns a context map with all required keys" do
      # Use a fake project_id that won't find real data
      data = %{
        project_id: Ecto.UUID.generate(),
        agent_type: "eng-backend",
        task_count: 2,
        retry_count: 0,
        learnings: ["Learned something"],
        current_task: %{"type" => "implement", "payload" => %{"description" => "test"}}
      }

      context = ContextAssembler.assemble(data)

      assert is_map(context)
      assert Map.has_key?(context, :learnings)
      assert Map.has_key?(context, :agent_type)
      assert Map.has_key?(context, :task_count)
      assert Map.has_key?(context, :project_info)
      assert Map.has_key?(context, :prd_context)
      assert Map.has_key?(context, :memory_learnings)
    end
  end

  describe "build_continuity_content/1" do
    test "generates markdown content" do
      context = %{
        agent_type: "eng-backend",
        task_count: 3,
        retry_count: 1,
        current_task: %{"type" => "implement", "payload" => %{"description" => "Build auth"}},
        learnings: ["Use bcrypt"],
        memory_context: %{
          episodic: ["Task 1 completed"],
          semantic: ["Auth patterns"],
          procedural: []
        }
      }

      content = ContextAssembler.build_continuity_content(context)

      assert content =~ "Samgita Continuity"
      assert content =~ "eng-backend"
      assert content =~ "Build auth"
      assert content =~ "bcrypt"
    end

    test "handles empty context gracefully" do
      context = %{
        agent_type: "eng-backend",
        task_count: 0,
        retry_count: 0,
        current_task: nil,
        learnings: [],
        memory_context: %{episodic: [], semantic: [], procedural: []}
      }

      content = ContextAssembler.build_continuity_content(context)
      assert is_binary(content)
      assert content =~ "Samgita Continuity"
    end
  end

  describe "filter_memory_learnings/1" do
    test "filters procedural and semantic from memory context" do
      memory = %{
        episodic: ["event1"],
        semantic: ["pattern1", "pattern2"],
        procedural: ["proc1"]
      }

      learnings = ContextAssembler.filter_memory_learnings(memory)
      assert "pattern1" in learnings
      assert "pattern2" in learnings
      assert "proc1" in learnings
      refute "event1" in learnings
    end

    test "returns empty list for nil memory" do
      assert ContextAssembler.filter_memory_learnings(nil) == []
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/context_assembler_test.exs`
Expected: Compilation error

- [ ] **Step 3: Write the implementation**

```elixir
# apps/samgita/lib/samgita/agent/context_assembler.ex
defmodule Samgita.Agent.ContextAssembler do
  @moduledoc """
  Fetches and assembles the context window for an RARV cycle.

  Pulls from samgita_memory, project metadata, task description, and
  previous cycle results. Writes the CONTINUITY.md file. Returns a
  structured context map consumed by PromptBuilder.
  """

  alias Samgita.Project.Memory

  @doc """
  Assemble full context for an RARV cycle.

  Returns a map with keys: :learnings, :agent_type, :task_count,
  :project_info, :prd_context, :memory_learnings, :memory_context
  """
  def assemble(data) do
    memory_context = fetch_memory_context(data.project_id)
    project_info = fetch_project_info(data.project_id)
    prd_context = fetch_prd_context(data.project_id)
    memory_learnings = filter_memory_learnings(memory_context)

    %{
      learnings: data.learnings || [],
      agent_type: data.agent_type,
      task_count: data.task_count || 0,
      project_info: project_info,
      prd_context: prd_context,
      memory_learnings: memory_learnings,
      memory_context: memory_context
    }
  end

  @doc "Write CONTINUITY.md file to the working directory."
  def write_continuity_file(working_path, context) do
    content = build_continuity_content(context)
    dir = Path.join(working_path, ".samgita")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "CONTINUITY.md"), content)
    :ok
  rescue
    error -> {:error, error}
  end

  @doc "Build the CONTINUITY.md content string."
  def build_continuity_content(context) do
    task_desc =
      case context[:current_task] do
        %{"payload" => %{"description" => desc}} -> desc
        %{payload: %{description: desc}} -> desc
        _ -> "No active task"
      end

    memory = context[:memory_context] || %{episodic: [], semantic: [], procedural: []}
    learnings = context[:learnings] || []

    episodic_section =
      memory[:episodic]
      |> List.wrap()
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1}")

    semantic_section =
      memory[:semantic]
      |> List.wrap()
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1}")

    learnings_section =
      learnings
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1}")

    """
    # Samgita Continuity
    Agent: #{context[:agent_type]} | Task Count: #{context[:task_count]} | Retries: #{context[:retry_count] || 0}
    Current Task: #{task_desc}

    ## Episodic Memory
    #{if episodic_section == "", do: "None yet.", else: episodic_section}

    ## Semantic Knowledge
    #{if semantic_section == "", do: "None yet.", else: semantic_section}

    ## Session Learnings
    #{if learnings_section == "", do: "None yet.", else: learnings_section}
    """
  end

  @doc "Persist a learning to episodic memory."
  def persist_learning(project_id, learning) do
    Memory.add_memory(project_id, :episodic, learning)
  rescue
    _ -> :ok
  end

  @doc "Filter procedural and semantic learnings from memory context."
  def filter_memory_learnings(nil), do: []

  def filter_memory_learnings(memory) do
    semantic = List.wrap(memory[:semantic] || [])
    procedural = List.wrap(memory[:procedural] || [])
    semantic ++ procedural
  end

  defp fetch_memory_context(project_id) do
    Memory.get_context(project_id)
  rescue
    _ -> %{episodic: [], semantic: [], procedural: []}
  end

  defp fetch_project_info(project_id) do
    case Samgita.Projects.get_project(project_id) do
      nil ->
        nil

      project ->
        """
        Project: #{project.name}
        Git: #{project.git_url}
        Phase: #{project.phase}
        Status: #{project.status}
        """
    end
  rescue
    _ -> nil
  end

  defp fetch_prd_context(project_id) do
    case Samgita.Projects.get_project(project_id) do
      %{active_prd_id: prd_id} when not is_nil(prd_id) ->
        case Samgita.Prds.get_prd(prd_id) do
          nil -> nil
          prd -> String.slice(prd.content || "", 0, 2000)
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/context_assembler_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/context_assembler.ex apps/samgita/test/samgita/agent/context_assembler_test.exs
git commit -m "feat(agent): extract ContextAssembler module from Worker"
```

---

### Task 6: WorktreeManager — Git worktree lifecycle

**Files:**
- Create: `apps/samgita/lib/samgita/agent/worktree_manager.ex`
- Test: `apps/samgita/test/samgita/agent/worktree_manager_test.exs`

Extracted from: `worker.ex` lines 1207-1290 (git checkpoint, commit message, working path).

- [ ] **Step 1: Write the failing test**

```elixir
# apps/samgita/test/samgita/agent/worktree_manager_test.exs
defmodule Samgita.Agent.WorktreeManagerTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.WorktreeManager

  describe "build_commit_message/3" do
    test "builds structured commit message" do
      msg = WorktreeManager.build_commit_message(
        "eng-backend",
        "implement",
        "Build user authentication"
      )

      assert msg =~ "[samgita]"
      assert msg =~ "eng-backend"
      assert msg =~ "Build user authentication"
      assert msg =~ "Agent-Type:"
    end

    test "truncates long descriptions" do
      long_desc = String.duplicate("x", 200)
      msg = WorktreeManager.build_commit_message("eng-backend", "implement", long_desc)

      # Subject line (first line) should be reasonable length
      [subject | _] = String.split(msg, "\n")
      assert String.length(subject) <= 100
    end
  end

  describe "build_task_description/1" do
    test "extracts description from task" do
      task = %{"type" => "implement", "payload" => %{"description" => "Build auth"}}
      assert WorktreeManager.build_task_description(task) == "Build auth"
    end

    test "falls back for missing description" do
      task = %{"type" => "implement", "payload" => %{}}
      desc = WorktreeManager.build_task_description(task)
      assert is_binary(desc)
    end
  end

  describe "should_checkpoint?/1" do
    test "returns true when working_path is set" do
      data = %{working_path: "/tmp/some/path", current_task: %{"type" => "implement"}}
      assert WorktreeManager.should_checkpoint?(data) == true
    end

    test "returns false when working_path is nil" do
      data = %{working_path: nil, current_task: %{"type" => "implement"}}
      assert WorktreeManager.should_checkpoint?(data) == false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test apps/samgita/test/samgita/agent/worktree_manager_test.exs`
Expected: Compilation error

- [ ] **Step 3: Write the implementation**

```elixir
# apps/samgita/lib/samgita/agent/worktree_manager.ex
defmodule Samgita.Agent.WorktreeManager do
  @moduledoc """
  Manages the git worktree lifecycle for an agent.

  Implemented as functions operating on data maps (not a separate process).
  Handles: commit message construction, checkpoint decisions, and
  delegates to `Samgita.Git.Worktree` for actual git operations.
  """

  alias Samgita.Git.Worktree

  require Logger

  @max_subject_length 72

  @doc "Check if a git checkpoint should be created."
  def should_checkpoint?(%{working_path: nil}), do: false
  def should_checkpoint?(%{working_path: _}), do: true

  @doc "Create a git checkpoint if there are uncommitted changes."
  def maybe_checkpoint(data) do
    if should_checkpoint?(data) do
      create_checkpoint(data)
    else
      :ok
    end
  end

  @doc "Create a git checkpoint with structured commit message."
  def create_checkpoint(data) do
    path = data.working_path

    case Worktree.has_changes?(path) do
      true ->
        task_desc = build_task_description(data.current_task)
        agent_type = to_string(data.agent_type)
        task_type = get_task_type(data.current_task)
        message = build_commit_message(agent_type, task_type, task_desc)

        case Worktree.commit(path, message) do
          {:ok, _} -> :ok
          {:error, reason} ->
            Logger.warning("Git checkpoint failed: #{inspect(reason)}")
            :ok
        end

      false ->
        :ok
    end
  rescue
    error ->
      Logger.warning("Git checkpoint error: #{inspect(error)}")
      :ok
  end

  @doc "Build a structured commit message with agent metadata."
  def build_commit_message(agent_type, task_type, description) do
    subject = "[samgita] #{agent_type}: #{truncate_subject(description)}"

    """
    #{subject}

    Agent-Type: #{agent_type}
    Task-Type: #{task_type}
    Samgita-Version: #{Application.spec(:samgita, :vsn) || "dev"}
    """
    |> String.trim()
  end

  @doc "Extract a task description string from a task map."
  def build_task_description(task) do
    payload = task_payload(task)
    payload["description"] || payload[:description] || "Execute assigned task"
  end

  defp get_task_type(%{"type" => type}), do: type
  defp get_task_type(%{type: type}), do: to_string(type)
  defp get_task_type(_), do: "unknown"

  defp task_payload(%{"payload" => p}) when is_map(p), do: p
  defp task_payload(%{payload: p}) when is_map(p), do: p
  defp task_payload(_), do: %{}

  defp truncate_subject(text) when byte_size(text) > @max_subject_length do
    String.slice(text, 0, @max_subject_length - 3) <> "..."
  end

  defp truncate_subject(text), do: text
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test apps/samgita/test/samgita/agent/worktree_manager_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add apps/samgita/lib/samgita/agent/worktree_manager.ex apps/samgita/test/samgita/agent/worktree_manager_test.exs
git commit -m "feat(agent): extract WorktreeManager module from Worker"
```

---

### Task 7: Rewire Worker to use delegate modules

**Files:**
- Modify: `apps/samgita/lib/samgita/agent/worker.ex`
- Test: Run existing tests — no new test files

This is the critical integration step. The Worker's state functions must call the extracted modules instead of inline logic. Each state function must be under 30 lines.

- [ ] **Step 1: Run existing tests to establish baseline**

Run: `mix test apps/samgita/test/samgita/agent/worker_test.exs`
Expected: All tests pass (baseline)

- [ ] **Step 2: Add aliases for new modules**

Read `worker.ex`, then replace the alias block (lines 13-20) to add new module aliases:

```elixir
  alias Samgita.Agent.ActivityBroadcaster
  alias Samgita.Agent.CircuitBreaker
  alias Samgita.Agent.Claude
  alias Samgita.Agent.ContextAssembler
  alias Samgita.Agent.PromptBuilder
  alias Samgita.Agent.ResultParser
  alias Samgita.Agent.RetryStrategy
  alias Samgita.Agent.Types
  alias Samgita.Agent.WorktreeManager
  alias Samgita.Quality.OutputGuardrails
```

- [ ] **Step 3: Rewrite :reason state to use ContextAssembler**

Replace `reason(:state_timeout, :execute, data)` (lines 138-165) with:

```elixir
  def reason(:state_timeout, :execute, data) do
    ActivityBroadcaster.broadcast_activity(data, :reason, "Building context for task")
    ActivityBroadcaster.emit_state_transition(data, :reason)

    context = ContextAssembler.assemble(data)

    working_path = get_working_path(data)

    if working_path do
      ContextAssembler.write_continuity_file(working_path, Map.put(context, :current_task, data.current_task) |> Map.put(:retry_count, data.retry_count))
    end

    updated_data = %{data |
      learnings: context.learnings ++ context.memory_learnings,
      working_path: working_path
    }

    {:next_state, :act, Map.put(updated_data, :context, context)}
  end
```

- [ ] **Step 4: Rewrite :act state to use PromptBuilder and ResultParser**

Replace `act(:state_timeout, :execute, data)` (lines 191-244) with:

```elixir
  def act(:state_timeout, :execute, data) do
    ActivityBroadcaster.broadcast_activity(data, :act, "Executing task via Claude")
    ActivityBroadcaster.emit_state_transition(data, :act)
    ActivityBroadcaster.broadcast_state_change(data, :act)

    prompt = PromptBuilder.build(data.current_task, data.context)
    model = Types.model_for_type(data.agent_type)
    working_path = data.working_path

    chat_opts = [model: model]
    chat_opts = if working_path, do: Keyword.put(chat_opts, :working_directory, working_path), else: chat_opts

    raw_result = Claude.chat(prompt, chat_opts)
    classified = ResultParser.classify(raw_result)

    case classified do
      {:success, result} ->
        {:next_state, :reflect, %{data | act_result: result}}

      {:failure, category} ->
        error_cat = RetryStrategy.classify_for_retry(category)

        if error_cat in [:rate_limit, :overloaded] and RetryStrategy.should_retry?(error_cat, data.retry_count) do
          backoff = RetryStrategy.backoff_ms(error_cat, data.retry_count)
          ActivityBroadcaster.broadcast_activity(data, :act, "Rate limited, backing off #{backoff}ms")
          Process.sleep(backoff)
          {:repeat_state, %{data | retry_count: data.retry_count + 1}}
        else
          {:next_state, :reflect, %{data | act_result: {:error, category}}}
        end
    end
  end
```

- [ ] **Step 5: Rewrite :reflect state to use ContextAssembler**

Replace `reflect(:state_timeout, :execute, data)` (lines 270-298) with:

```elixir
  def reflect(:state_timeout, :execute, data) do
    ActivityBroadcaster.broadcast_activity(data, :reflect, "Recording learnings")
    ActivityBroadcaster.emit_state_transition(data, :reflect)
    ActivityBroadcaster.broadcast_state_change(data, :reflect)

    learning = build_learning_summary(data)

    updated_learnings =
      [learning | data.learnings]
      |> Enum.take(@max_learnings)

    ContextAssembler.persist_learning(data.project_id, learning)

    {:next_state, :verify, %{data | learnings: updated_learnings}}
  end

  defp build_learning_summary(data) do
    task_desc = PromptBuilder.task_description(data.current_task)
    result_preview = case data.act_result do
      result when is_binary(result) -> String.slice(result, 0, 200)
      {:error, reason} -> "Error: #{inspect(reason)}"
      _ -> "No result"
    end

    "Task: #{task_desc} | Result: #{result_preview}"
  end
```

- [ ] **Step 6: Rewrite :verify state to use RetryStrategy, WorktreeManager, ActivityBroadcaster**

Replace `verify(:state_timeout, :execute, data)` (lines 319-416) with the delegated version. This is the most complex state — read worker.ex lines 319-416 carefully and reproduce the branching logic using the extracted modules:

```elixir
  def verify(:state_timeout, :execute, data) do
    ActivityBroadcaster.broadcast_activity(data, :verify, "Validating output")
    ActivityBroadcaster.emit_state_transition(data, :verify)
    ActivityBroadcaster.broadcast_state_change(data, :verify)

    case data.act_result do
      {:error, reason} ->
        handle_verify_error(data, reason)

      result when is_binary(result) ->
        handle_verify_success(data, result)

      other ->
        ActivityBroadcaster.broadcast_activity(data, :verify, "Unexpected result: #{inspect(other)}")
        return_to_idle(data, :unexpected_result)
    end
  end
```

The `handle_verify_error/2` and `handle_verify_success/2` private functions use RetryStrategy, OutputGuardrails, WorktreeManager, and the existing task completion flow. These must be extracted from the current verify state logic (lines 319-416) — implementer reads those lines and maps each branch to the new helper modules.

- [ ] **Step 7: Remove all inlined helper functions that moved to extracted modules**

Delete from worker.ex:
- `build_context/1` (line 556-562)
- `build_prompt/1` (line 564-578)
- All `build_*_prompt/1` functions (lines 580-909)
- `build_project_context/2` (lines 911-916)
- `fetch_project_info/1` (lines 918-928)
- `build_project_info_string/1` (lines 930-945)
- `fetch_prd_context/1` (lines 947-959)
- `build_prd_context_string/1` (lines 961-969)
- `task_type/1` (lines 971-973)
- `task_payload/1` (lines 975-977)
- `fetch_memory_context/1` (lines 979-983)
- `format_learnings/1` (lines 985-986)
- `memory_learnings/1` (lines 988-992)
- `write_continuity_file/2` (lines 501-554)
- `persist_learning/2` (lines 1292-1296)
- `maybe_git_checkpoint/1` (lines 1207-1217)
- `create_git_checkpoint_if_changes/3` (lines 1219-1235)
- `build_task_description/1` (lines 1238-1244)
- `build_commit_message/3` (lines 1247-1266)
- `commit_checkpoint/3` (lines 1268-1277)
- `broadcast_activity/3-4` (lines 463-466)
- `broadcast_state_change/2` (lines 474-486)
- `emit_telemetry/3` (lines 1298-1324)
- `truncate_output/2` (lines 468-472)

Keep in worker.ex:
- Struct definition and module attributes
- `start_link/1`, `child_spec/1`, `assign_task/2-3`, `get_state/1`
- `callback_mode/0`, `init/1`, `terminate/2`
- All 5 state functions (`:idle`, `:reason`, `:act`, `:reflect`, `:verify`) — now thin
- `handle_task_completion/1`, `complete_and_notify/1`, `notify_orchestrator/2`, `do_notify_orchestrator/3` — task completion flow (stays in Worker because it coordinates with Orchestrator process)
- `notify_caller/3` — process message sending
- `save_generated_prd/1`, `save_artifact/3` — artifact persistence (stays because it's task-type-specific logic interleaved with DB writes)
- `get_working_path/1` — could move to WorktreeManager but keep for now since it caches on data struct
- `find_active_agent_run/2`, `increment_agent_run_tasks/1` — DB ops tied to worker lifecycle

- [ ] **Step 8: Run ALL existing tests**

Run: `mix test apps/samgita/test/samgita/agent/worker_test.exs`
Expected: All tests pass — no behavioral changes

Run: `mix test apps/samgita/test`
Expected: All tests pass

- [ ] **Step 9: Verify Worker line count**

Run: `wc -l apps/samgita/lib/samgita/agent/worker.ex`
Expected: Under 400 lines (target ~200-300 after removing ~900 lines of helpers)

- [ ] **Step 10: Run full test suite + quality checks**

```bash
mix test
mix format --check-formatted
mix credo --strict
```

Expected: All pass with zero new warnings

- [ ] **Step 11: Commit**

```bash
git add apps/samgita/lib/samgita/agent/worker.ex
git commit -m "refactor(agent): rewire Worker to use extracted delegate modules

Worker state functions now delegate to PromptBuilder, ResultParser,
ContextAssembler, WorktreeManager, ActivityBroadcaster, and RetryStrategy.
Each state function is under 30 lines. No behavioral changes."
```

---

### Task 8: Final verification and cleanup

- [ ] **Step 1: Verify no dead code remains**

Run: `mix credo --strict` and check for unused aliases, unused functions, or unreachable code in worker.ex.

- [ ] **Step 2: Run the full test suite one more time**

```bash
mix test
```

Expected: All tests pass. Zero failures. Zero new warnings.

- [ ] **Step 3: Verify module line counts**

```bash
wc -l apps/samgita/lib/samgita/agent/worker.ex
wc -l apps/samgita/lib/samgita/agent/prompt_builder.ex
wc -l apps/samgita/lib/samgita/agent/result_parser.ex
wc -l apps/samgita/lib/samgita/agent/context_assembler.ex
wc -l apps/samgita/lib/samgita/agent/worktree_manager.ex
wc -l apps/samgita/lib/samgita/agent/activity_broadcaster.ex
wc -l apps/samgita/lib/samgita/agent/retry_strategy.ex
```

Expected:
- worker.ex: under 400 lines
- Each extracted module: under 200 lines
- Total: roughly same as before (~1325) distributed across 7 files

- [ ] **Step 4: Final commit if any cleanup was needed**

```bash
git add -A apps/samgita/
git commit -m "chore(agent): cleanup after Worker decomposition"
```
