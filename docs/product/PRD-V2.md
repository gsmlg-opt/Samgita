# PRD: Samgita v2 — Structured Agent Orchestration

**Status:** Draft
**Version:** 2.0.0
**Date:** 2026-04-03
**Design Reference:** [docs/design-v2.md](../design-v2.md)

---

## Executive Summary

Samgita v1 proves the core thesis: OTP supervision trees, gen_statem FSMs, and Oban job queues form a superior foundation for autonomous multi-agent orchestration. The v1 system decomposes a PRD into tasks, dispatches them across specialized agents, and drives through SDLC phases with quality gates.

Six structural gaps prevent Samgita from reaching its full potential:

| # | Gap | Impact |
|---|-----|--------|
| 1 | Provider is fire-and-forget | No session lifecycle, no streaming, no multi-turn. Each RARV cycle re-explains full context (~60-80% wasted tokens). |
| 2 | Tasks are independent counters | No dependency graph, no critical path, no blocked/unblocked distinction. Parallel agents produce inconsistent artifacts. |
| 3 | No plan mode | System assumes a PRD already exists. Users must write one manually. |
| 4 | Agent Worker is a 1325-line monolith | Mixes FSM transitions, prompt construction, CLI invocation, git worktree management, memory retrieval, and quality checks. |
| 5 | Agents cannot communicate | Only report completion counts to Orchestrator. No agent-to-agent coordination. |
| 6 | No Synapsis integration | Shells out directly to Claude CLI, bypassing Synapsis entirely. |

This PRD specifies how to resolve all six, organized as 6 implementation phases with explicit requirements, acceptance criteria, and test plans.

**Implementation order:** Phase 1 → 2 → 3 → 4 → 5 → 6 (dependency chain documented per phase).

---

## Phase 1: Worker Decomposition

### Motivation

A developer needs to modify how RARV prompts are constructed — perhaps adding project-specific few-shot examples. Today, this requires navigating a 1325-line gen_statem (`apps/samgita/lib/samgita/agent/worker.ex`) to find where prompts are assembled, carefully avoiding changes to state transition logic, timeout handling, git worktree lifecycle, and PubSub broadcasting.

### Requirements

**P1-R1.** Extract `Samgita.Agent.PromptBuilder` module.
- Assembles the LLM prompt for the Act phase.
- Inputs: task description, agent type definition, project context, learnings, continuity log, previous act results (if retrying).
- Output: a structured prompt string.
- Pure function module — no side effects, no process state.

**P1-R2.** Extract `Samgita.Agent.ResultParser` module.
- Parses the provider response.
- Extracts: text content, file changes (if parseable), error indicators, completion signals.
- Classifies result as: `:success`, `:partial_success`, `:failure` (with error category).
- Pure function module.

**P1-R3.** Extract `Samgita.Agent.WorktreeManager` module.
- Manages the git worktree lifecycle for an agent.
- Operations: create worktree from project base (one per agent, branch named after agent ID), commit changes (atomic, with structured commit message), push to remote, cleanup on termination.
- Implemented as a struct with functions, not a separate process.
- Holds worktree path and branch name.

**P1-R4.** Extract `Samgita.Agent.ContextAssembler` module.
- Fetches and assembles the context window for an RARV cycle.
- Pulls from: `samgita_memory` (episodic memories, learnings), project metadata (tech stack, architecture decisions), task description and dependencies, previous cycle results.
- Writes the CONTINUITY.md file.
- Returns a structured context map consumed by PromptBuilder.

**P1-R5.** Extract `Samgita.Agent.ActivityBroadcaster` module.
- Wraps PubSub broadcasting and telemetry emission.
- Every state transition, activity log entry, and error report goes through this module.
- The Worker calls `ActivityBroadcaster.state_change(data, :reason)` instead of inline PubSub/telemetry code.
- Centralizes the event schema.

**P1-R6.** Extract `Samgita.Agent.RetryStrategy` module.
- Encapsulates retry logic.
- Given an error category (`:rate_limit`, `:overloaded`, `:timeout`, `:unknown`) and current retry count, returns: the backoff duration, whether to retry at all, and whether to escalate (open circuit breaker).
- The Worker's error handling clauses become simple delegations.

**P1-R7.** After decomposition, each Worker gen_statem state function must be under 30 lines.
- `:reason` enter → calls ContextAssembler, stores result, transitions to `:act`
- `:act` enter → calls PromptBuilder, calls Provider, calls ResultParser, transitions to `:reflect`
- `:reflect` enter → writes learnings via ContextAssembler, transitions to `:verify`
- `:verify` enter → runs OutputGuardrails, decides: complete → `:idle`, retry → `:reason`, fail → error path

**P1-R8.** No functional changes. All existing tests must pass without modification. Same external behaviour, cleaner internal structure.

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita/lib/samgita/agent/prompt_builder.ex` | Prompt assembly (pure) |
| `apps/samgita/lib/samgita/agent/result_parser.ex` | Response parsing (pure) |
| `apps/samgita/lib/samgita/agent/worktree_manager.ex` | Git worktree lifecycle |
| `apps/samgita/lib/samgita/agent/context_assembler.ex` | Context/memory assembly |
| `apps/samgita/lib/samgita/agent/activity_broadcaster.ex` | PubSub/telemetry wrapper |
| `apps/samgita/lib/samgita/agent/retry_strategy.ex` | Retry/backoff logic |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/agent/worker.ex` | Replace inline logic with delegate calls. Target: ~200 lines (from 1325). |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita/test/samgita/agent/prompt_builder_test.exs` | Unit tests for prompt assembly with various agent types, tasks, contexts |
| `apps/samgita/test/samgita/agent/result_parser_test.exs` | Unit tests for response classification (success, partial, failure) |
| `apps/samgita/test/samgita/agent/worktree_manager_test.exs` | Tests against a real git repo in `@tag :tmp_dir` |
| `apps/samgita/test/samgita/agent/context_assembler_test.exs` | Unit tests for context assembly, CONTINUITY.md generation |
| `apps/samgita/test/samgita/agent/activity_broadcaster_test.exs` | Assert on PubSub subscriptions and telemetry events |
| `apps/samgita/test/samgita/agent/retry_strategy_test.exs` | Unit tests for backoff calculation, escalation thresholds |

### Acceptance Criteria

- [ ] `Samgita.Agent.Worker` is under 250 lines
- [ ] Each extracted module has its own test file with >90% coverage
- [ ] PromptBuilder, ResultParser, ContextAssembler, and RetryStrategy are pure-function modules (no process state, no side effects)
- [ ] WorktreeManager operates on a struct, not a process
- [ ] ActivityBroadcaster centralizes all PubSub and telemetry calls
- [ ] `mix test apps/samgita/test` passes with zero failures and zero new warnings
- [ ] `mix credo --strict` passes
- [ ] No new processes added to supervision tree

### Database Migrations

None. This is a code-only refactoring.

---

## Phase 2: Provider Evolution

### Motivation

An eng-backend agent needs to iterate on an API implementation across multiple RARV cycles. Today, each cycle is a cold `System.cmd` invocation with no conversation memory — the agent re-explains the project context from scratch every time. A session-aware provider would maintain conversation state across turns, reducing prompt tokens by 60-80% on subsequent iterations.

### Requirements

**P2-R1.** Expand `SamgitaProvider.Provider` behaviour from 1 callback to 7 callbacks.

New callbacks:
```elixir
@callback start_session(system_prompt :: String.t(), opts :: keyword()) ::
            {:ok, session :: term()} | {:error, term()}

@callback send_message(session :: term(), message :: String.t()) ::
            {:ok, response :: String.t(), updated_session :: term()} | {:error, term()}

@callback stream_message(session :: term(), message :: String.t(), subscriber :: pid()) ::
            {:ok, stream_ref :: reference(), updated_session :: term()} | {:error, term()}

@callback close_session(session :: term()) :: :ok

@callback capabilities() :: %{
            supports_streaming: boolean(),
            supports_tools: boolean(),
            supports_multi_turn: boolean(),
            max_context_tokens: pos_integer(),
            available_models: [String.t()]
          }

@callback health_check() :: :ok | {:error, term()}
```

Existing `query/2` retained as convenience wrapper (opens session, sends one message, closes). All existing callers continue to work unchanged.

**P2-R2.** Implement `SamgitaProvider.ClaudeCode` session support via Erlang Port.
- `start_session/2` opens a Port running `claude` in interactive/conversational mode.
- `send_message/2` writes JSON-delimited lines to Port stdin, reads structured output from stdout.
- `stream_message/3` uses Port messages — stdout chunks arrive as `{port, {:data, chunk}}`.
- `close_session/1` closes the Port.
- `query/2` continues to work via `System.cmd` for backward compatibility.

**P2-R3.** Implement `SamgitaProvider.ClaudeAPI` provider.
- Direct HTTP client to `api.anthropic.com/v1/messages`.
- Session state is the accumulated messages list.
- Streaming uses Server-Sent Events (SSE) via Finch.
- Configurable model, max tokens, system prompt.

**P2-R4.** Add `Samgita.Provider.SessionRegistry` ETS table.
- Key: `{project_id, agent_id}`
- Value: `%{session_ref, provider, started_at, message_count, total_tokens}`
- Application-wide, not per-project. Lives in Samgita.Application supervision tree.
- Purpose: observability (dashboard shows active sessions) and cleanup (find orphaned sessions on agent crash).

**P2-R5.** Default implementations for new callbacks.
- Providers that only implement `query/2` get default `start_session` that stores config, `send_message` that delegates to `query/2`, and `close_session` that is a no-op.
- This preserves backward compatibility — existing custom providers continue to work.

**P2-R6.** The Agent Worker (after Phase 1 decomposition) gains a `:session` field in its data struct.
- Opens session when entering `:reason` for the first time on a task.
- Keeps session open through `:act`, `:reflect`, `:verify`.
- Closes session when task completes or fails terminally.
- If session errors mid-cycle, opens fresh session and retries from current RARV state.

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita_provider/lib/samgita_provider/claude_api.ex` | HTTP-based provider (Messages API + SSE) |
| `apps/samgita_provider/lib/samgita_provider/session.ex` | Session struct definition |
| `apps/samgita/lib/samgita/provider/session_registry.ex` | ETS-backed session tracking |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita_provider/lib/samgita_provider/provider.ex` | Add 6 new callbacks with `@optional_callbacks` and default implementations |
| `apps/samgita_provider/lib/samgita_provider/claude_code.ex` | Add Port-based session support alongside existing System.cmd |
| `apps/samgita_provider/lib/samgita_provider.ex` | Add `start_session/2`, `send_message/2`, `stream_message/3`, `close_session/1` public API functions |
| `apps/samgita/lib/samgita/agent/worker.ex` | Add `:session` field to data struct, session lifecycle in RARV states |
| `apps/samgita/lib/samgita/application.ex` | Add SessionRegistry to supervision tree |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita_provider/test/samgita_provider/claude_api_test.exs` | ClaudeAPI provider tests (mocked HTTP) |
| `apps/samgita_provider/test/samgita_provider/session_test.exs` | Session struct and lifecycle tests |
| `apps/samgita/test/samgita/provider/session_registry_test.exs` | ETS registry CRUD, orphan cleanup |

### Acceptance Criteria

- [ ] `SamgitaProvider.query/2` continues to work for all existing callers (backward compatible)
- [ ] `SamgitaProvider.start_session/2` → `send_message/2` → `close_session/1` lifecycle works for ClaudeCode
- [ ] ClaudeCode Port-based session maintains conversation state across multiple `send_message` calls
- [ ] ClaudeAPI sends accumulated message history on each call, streaming via SSE
- [ ] SessionRegistry tracks active sessions and cleans up on agent termination
- [ ] Agent Worker reuses session across RARV cycle (verified via SessionRegistry message_count > 1)
- [ ] `mix test apps/samgita_provider/test` passes
- [ ] `mix test apps/samgita/test` passes

### Database Migrations

None. SessionRegistry is ETS-only (ephemeral).

### Prerequisites

- Phase 1 (Worker Decomposition) — Worker must be decomposed before adding session lifecycle.

---

## Phase 3: Task Dependency DAG

### Motivation

During the Development phase, `eng-backend` produces an API endpoint that `eng-frontend` must integrate with. Today, both agents receive their tasks simultaneously and work independently. `eng-frontend` either builds against a non-existent API (waste) or produces a mock integration (tech debt). A dependency graph ensures `eng-frontend`'s integration task is blocked until `eng-backend`'s API task completes.

### Requirements

**P3-R1.** Extend `Samgita.Domain.Task` schema with dependency fields.

New fields:
- `depends_on_ids` — `{:array, :binary_id}`, references `tasks.id`. Tasks that must complete before this task is unblocked.
- `status` — expand enum from `[:pending, :running, :completed, :failed, :dead_letter]` to `[:blocked, :pending, :assigned, :running, :completed, :failed, :skipped]`
- `dependency_outputs` — `:map`, populated when dependencies complete. Map of `{task_id => output_summary}`. Consumed by ContextAssembler for downstream tasks.
- `estimated_duration_minutes` — `:integer`, set during bootstrap, used for critical path calculation.
- `wave` — `:integer`, computed from topological sort. Wave 0 = root tasks, wave N = tasks whose latest dependency is in wave N-1.

**P3-R2.** Create `task_dependencies` join table.

```
task_dependencies
├── task_id          — references tasks.id, NOT NULL
├── depends_on_id    — references tasks.id, NOT NULL
├── dependency_type  — enum [:hard, :soft], default :hard
├── inserted_at      — timestamp
└── UNIQUE(task_id, depends_on_id)
```

- `:hard` — must complete before dependent becomes unblocked.
- `:soft` — should complete but not blocking.

**P3-R3.** Create `Samgita.Tasks.DependencyGraph` module.
- `build(tasks)` — constructs a DAG from tasks and their `depends_on_ids`.
- `validate(graph)` — cycle detection using Kahn's algorithm. Returns `{:ok, sorted}` or `{:error, {:cycle, nodes}}`.
- `compute_waves(graph)` — topological sort, assigns wave numbers. Returns `%{wave_number => [task_ids]}`.
- `critical_path(graph)` — longest chain of dependent tasks using accumulated `estimated_duration_minutes`. Returns `{path, total_minutes}`.
- `unblocked_tasks(graph, completed_ids)` — given a set of completed task IDs, returns newly unblocked tasks.
- Pure function module. No process state.

**P3-R4.** Enhance `BootstrapWorker` to generate dependency edges.

Three strategies applied in order:
1. **Explicit dependencies** — PRD contains dependency markers ("Feature B requires Feature A", checklist nesting). Parser extracts as explicit edges.
2. **Swarm-level ordering** — Static rules: database schema tasks → API tasks → frontend integration tasks. Infrastructure provisioning → deployment configuration. Encoded in a dependency template per phase.
3. **LLM-assisted inference** — For complex PRDs, a lightweight LLM call (haiku-tier) reviews the task list and outputs dependency edges as structured JSON. Runs once during bootstrap.

After generating tasks, a second pass infers dependencies and persists to `task_dependencies` table. Then calls `DependencyGraph.validate/1` — cycles are bootstrap errors that block phase entry.

**P3-R5.** Modify Orchestrator dispatch to wave-based execution.

Change from:
```
phase enter → enqueue all tasks
```
To:
```
phase enter → build DAG → validate → compute waves → dispatch wave 0
  → on task completion:
      → mark completed in DAG
      → propagate outputs to dependents (dependency_outputs field)
      → identify newly unblocked tasks
      → dispatch newly unblocked tasks
      → recompute critical path
      → if all tasks terminal: advance
```

**P3-R6.** Phase completion changes from "all tasks done" to "all tasks in terminal state (completed or failed)."
- A task that fails after max retries enters `:failed` status, which unblocks dependents with a `dependency_failed` flag.
- Dependent tasks can choose to proceed with degraded input or skip.

**P3-R7.** Stagnation detection enhancements.
- Are there pending tasks with no running agent?
- Are there running tasks that exceeded `estimated_duration_minutes`?
- Are all remaining tasks blocked by failed dependencies?

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita/lib/samgita/tasks/dependency_graph.ex` | DAG builder, validator, wave computation, critical path |
| `apps/samgita/lib/samgita/domain/task_dependency.ex` | Ecto schema for join table |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/domain/task.ex` | Add `depends_on_ids`, `dependency_outputs`, `estimated_duration_minutes`, `wave` fields. Expand status enum. |
| `apps/samgita/lib/samgita/workers/bootstrap_worker.ex` | Add dependency inference pass after task generation |
| `apps/samgita/lib/samgita/project/orchestrator.ex` | Wave-based dispatch, DAG-aware task completion, critical path tracking |
| `apps/samgita/lib/samgita/tasks.ex` | Add dependency query functions (`unblocked_tasks/2`, `tasks_with_dependencies/1`) |
| `apps/samgita/lib/samgita/agent/context_assembler.ex` | Include upstream dependency outputs in context |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita/test/samgita/tasks/dependency_graph_test.exs` | DAG construction, cycle detection, wave computation, critical path, unblocked resolution |
| `apps/samgita/test/samgita/domain/task_dependency_test.exs` | Schema validation, unique constraint |

### Database Migrations

**Migration 1: Add dependency fields to tasks**
```elixir
alter table(:tasks) do
  add :depends_on_ids, {:array, :binary_id}, default: []
  add :dependency_outputs, :map, default: %{}
  add :estimated_duration_minutes, :integer
  add :wave, :integer
end

# Expand status enum
execute "ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'blocked'"
execute "ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'assigned'"
execute "ALTER TYPE task_status ADD VALUE IF NOT EXISTS 'skipped'"
```

**Migration 2: Create task_dependencies table**
```elixir
create table(:task_dependencies, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
  add :depends_on_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
  add :dependency_type, :string, default: "hard", null: false
  timestamps(updated_at: false)
end

create unique_index(:task_dependencies, [:task_id, :depends_on_id])
create index(:task_dependencies, [:depends_on_id])
```

### Acceptance Criteria

- [ ] Tasks with unresolved hard dependencies start in `:blocked` status
- [ ] When all hard dependencies complete, task transitions to `:pending`
- [ ] Cycle detection catches A→B→A cycles and returns error
- [ ] Wave computation assigns wave 0 to root tasks (no dependencies)
- [ ] Critical path returns the longest dependency chain
- [ ] Orchestrator dispatches wave 0 on phase entry, then newly unblocked tasks on each completion
- [ ] `dependency_outputs` is populated when upstream task completes
- [ ] ContextAssembler includes dependency outputs in downstream task context
- [ ] Failed tasks unblock dependents with `dependency_failed` flag
- [ ] `mix test apps/samgita/test` passes
- [ ] `mix ecto.migrate` runs without errors

### Prerequisites

- Phase 1 (Worker Decomposition) — ContextAssembler must exist to add dependency awareness.

---

## Phase 4: Inter-Agent Communication

### Motivation

During the Development phase, `eng-backend` finishes implementing a REST API endpoint. `eng-api` needs to update the API documentation. `eng-frontend` needs to integrate with it. Today, none of these agents know about each other's output — they work in isolation, producing inconsistent artifacts.

### Requirements

**P4-R1.** Create `Samgita.Agent.MessageRouter` GenServer.
- One per project, under `Samgita.Project.Supervisor`.
- Receives agent messages, validates routing, enforces budgets, forwards to recipient Workers.
- Registered via Horde.Registry with key `{:message_router, project_id}`.

**P4-R2.** Define message structure.
```elixir
%{
  sender_agent_id: String.t(),
  recipient_agent_id: String.t(),  # or "*" for broadcast
  message_type: :notify | :request | :response,
  content: String.t(),
  correlation_id: binary_id(),     # links request-response pairs
  timestamp: DateTime.t()
}
```

**P4-R3.** Implement message routing via PubSub.
- Messages published to topic `samgita:project:{project_id}:agent_messages`.
- Each Worker subscribes to messages addressed to it.
- Broadcast messages use swarm-level topic.

**P4-R4.** Implement runaway prevention.
- **Message budget:** 10 outbound messages per agent per task. Exceeding is logged as warning, further messages dropped.
- **Depth limiting:** Request-response chains limited to depth 3. A response-to-response-to-response cannot generate another request.
- **Timeout:** Unanswered requests time out after 60 seconds. Sender proceeds without response.

**P4-R5.** Create `agent_messages` log table for observability.
- Messages are logged but not used for delivery (PubSub handles delivery).
- Indexed on `{project_id, recipient_agent_id, inserted_at}`.

**P4-R6.** Modify ContextAssembler to include teammate awareness.
- Agent's LLM prompt includes a section describing available teammates (names, types, current tasks).
- Includes `send_message` capability description.
- Received messages appear in the context on next RARV cycle as injected system messages.

**P4-R7.** Indirect communication via dependency DAG.
- When a task completes, the ContextAssembler for dependent tasks includes a summary of each dependency's output: files changed, result reported, learnings tagged to the dependency.

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita/lib/samgita/agent/message_router.ex` | Per-project GenServer for message routing |
| `apps/samgita/lib/samgita/domain/agent_message.ex` | Ecto schema for message log |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/project/supervisor.ex` | Add MessageRouter as child |
| `apps/samgita/lib/samgita/agent/worker.ex` | Subscribe to messages, handle incoming messages, expose `send_message` to LLM |
| `apps/samgita/lib/samgita/agent/context_assembler.ex` | Include teammate awareness, inject received messages |
| `apps/samgita/lib/samgita/agent/prompt_builder.ex` | Add teammate section to prompts |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita/test/samgita/agent/message_router_test.exs` | Routing, budget enforcement, depth limiting, timeout |
| `apps/samgita/test/samgita/domain/agent_message_test.exs` | Schema validation |

### Database Migrations

**Migration: Create agent_messages table**
```elixir
create table(:agent_messages, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
  add :sender_agent_id, :string, null: false
  add :recipient_agent_id, :string, null: false  # "*" for broadcast
  add :message_type, :string, null: false         # notify, request, response
  add :content, :text, null: false
  add :correlation_id, :binary_id
  add :inserted_at, :utc_datetime, null: false
end

create index(:agent_messages, [:project_id, :recipient_agent_id, :inserted_at])
create index(:agent_messages, [:correlation_id])
```

### Acceptance Criteria

- [ ] MessageRouter starts with Project.Supervisor, one per project
- [ ] Agent A can send a `:notify` message to Agent B; Agent B receives it on next RARV cycle
- [ ] Message budget (10/task) is enforced — 11th message is dropped with warning log
- [ ] Request-response depth limited to 3
- [ ] Unanswered requests time out after 60 seconds
- [ ] Broadcast messages ("*" recipient) reach all agents in the project
- [ ] `agent_messages` table records all messages for observability
- [ ] ContextAssembler includes teammate list and received messages in agent prompt
- [ ] `mix test apps/samgita/test` passes

### Prerequisites

- Phase 1 (Worker Decomposition) — ContextAssembler and PromptBuilder must exist.
- Phase 3 (Task DAG) — Indirect communication depends on dependency awareness.

---

## Phase 5: Plan Mode (Idea → PRD)

### Motivation

A user has an idea: "Build a SaaS platform for managing restaurant reservations." They have no PRD. Today, they must write one manually before Samgita can begin. Plan mode automates this: the user provides a one-paragraph description, and Samgita produces a structured, reviewed PRD ready for bootstrap.

### Requirements

**P5-R1.** Add `:planning` phase to the Orchestrator.

The `@phases` list becomes:
```
:planning → :bootstrap → :discovery → :architecture → :infrastructure →
:development → :qa → :deployment → :business → :growth → :perpetual
```

The `:planning` phase is optional — projects that start with a PRD skip directly to `:bootstrap`.

**P5-R2.** Add `start_mode` field to `Samgita.Domain.Project`.
- Enum: `:from_prd` (skip planning, go to bootstrap) or `:from_idea` (start with planning).
- Default: `:from_prd` (backward compatible).

**P5-R3.** Add `planning_auto_advance` field to `Samgita.Domain.Project`.
- Boolean, default `false`.
- If true, skip human review of generated PRD and auto-advance to `:bootstrap`.
- If false, pause for human review after planning produces final PRD.

**P5-R4.** Register 4 new planning agent types under `@planning` swarm.

| Agent Type | Role | Model |
|------------|------|-------|
| `plan-researcher` | Research Analyst. Market research, competitive analysis, tech evaluation. | opus |
| `plan-architect` | System Architect. Technical architecture, component design, tech stack selection. | opus |
| `plan-writer` | PRD Author. Requirements writing, acceptance criteria, scope definition. | opus |
| `plan-reviewer` | PRD Critic. Adversarial review, gap analysis, scope validation. | opus |

All use opus because planning quality gates everything downstream.

**P5-R5.** Implement 5 sequential sub-phases within `:planning`.

```
:research → :architecture → :draft → :review → :revise
```

Each sub-phase is driven by an Oban worker:

1. **Research** — 2-4 `plan-researcher` agents run in parallel. Each covers a research axis: market/competitive, technical feasibility, UX patterns, regulatory/compliance. Outputs stored as memories in `samgita_memory`.

2. **Architecture** — 1 `plan-architect` receives all research digests. Outputs: tech stack, system architecture, scalability considerations, technical risks. Stored as planning artifact.

3. **Draft** — 1 `plan-writer` receives research + architecture. Produces structured PRD: numbered requirements, acceptance criteria, milestones, task decomposition hints. Stored as draft PRD in `samgita_memory.prd`.

4. **Review** — 1 `plan-reviewer` with adversarial prompt. Receives draft PRD without original idea (blind review). Critiques: missing requirements, unrealistic scope, ambiguous acceptance criteria, security gaps, contradictions. Outputs severity-tagged findings.

5. **Revise** — `plan-writer` receives review findings, produces revised PRD. Review-revise loop runs up to 3 iterations or until reviewer produces zero high-severity findings. Final PRD promoted from draft to active.

**P5-R6.** Planning sub-state tracking in Orchestrator.
- The Orchestrator tracks `{:planning, sub_phase}` where sub_phase is `:research | :architecture | :draft | :review | :revise`.
- Sub-phase transitions driven by Oban worker completion, same pattern as main phase transitions.
- Orchestrator tracks `review_iteration_count` (max 3).

**P5-R7.** Human-in-the-loop review.
- After planning produces final PRD, Orchestrator pauses if `planning_auto_advance == false`.
- UI presents generated PRD with diff view showing review-revise changes.
- User can edit before approving.
- Approval triggers advance to `:bootstrap`.

**P5-R8.** Create `Samgita.Workers.PlanningWorker` Oban worker.
- Queue: `:orchestration`
- Handles all 5 planning sub-phases.
- Args: `%{"project_id" => id, "sub_phase" => sub_phase, "iteration" => n}`

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita/lib/samgita/workers/planning_worker.ex` | Oban worker for planning sub-phases |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/agent/types.ex` | Add `@planning` swarm with 4 agent types |
| `apps/samgita/lib/samgita/domain/project.ex` | Add `start_mode`, `planning_auto_advance` fields |
| `apps/samgita/lib/samgita/project/orchestrator.ex` | Add `:planning` phase with sub-states, optional phase skipping |
| `apps/samgita_web/lib/samgita_web/live/project_form_live.ex` | Add "Start from idea" option in project creation |
| `apps/samgita_web/lib/samgita_web/live/project_live.ex` | Add planning phase UI (research digests, PRD editor, review findings, approve/reject) |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita/test/samgita/workers/planning_worker_test.exs` | Sub-phase execution, iteration limiting, PRD generation |

### Database Migrations

**Migration: Add planning fields to projects**
```elixir
alter table(:projects) do
  add :start_mode, :string, default: "from_prd", null: false
  add :planning_auto_advance, :boolean, default: false, null: false
end

# Add :planning to phase enum
execute "ALTER TYPE project_phase ADD VALUE IF NOT EXISTS 'planning' BEFORE 'bootstrap'"
```

### Acceptance Criteria

- [ ] Project created with `start_mode: :from_idea` enters `:planning` phase
- [ ] Project created with `start_mode: :from_prd` skips to `:bootstrap` (backward compatible)
- [ ] Research sub-phase spawns 2-4 researchers in parallel
- [ ] Architecture sub-phase receives research digests as context
- [ ] Draft sub-phase produces a structured PRD
- [ ] Review sub-phase runs blind (no access to original idea)
- [ ] Revise loop runs max 3 iterations
- [ ] `planning_auto_advance: false` pauses for human review
- [ ] `planning_auto_advance: true` auto-advances to bootstrap
- [ ] UI shows planning progress (research → architecture → draft → review → revise)
- [ ] All 4 planning agent types registered in `Agent.Types`
- [ ] `mix test` passes

### Prerequisites

- Phase 1 (Worker Decomposition) — Worker must support planning agents.
- Phase 2 (Provider Evolution) — Planning agents benefit from session lifecycle (opus is expensive, token savings matter).

---

## Phase 6: Synapsis Integration

### Motivation

Samgita dispatches 6 engineering agents for the Development phase. Instead of each agent shelling out to `claude --print` independently (6 cold CLI processes), they connect to a running Synapsis instance that provides: persistent sessions, tool execution, workspace management, and swarm coordination. Samgita becomes the strategic orchestrator; Synapsis becomes the tactical executor.

### Requirements

**P6-R1.** Implement `SamgitaProvider.Synapsis` provider.

- `start_session/2` — creates a Synapsis session via HTTP POST to `/api/sessions`. Configures: agent mode (`:build`), model selection, tool allowlist, working directory, system prompt. Returns session ID.
- `send_message/2` — sends user message via REST API or Phoenix Channel. Returns assistant response when agent loop completes.
- `stream_message/3` — connects to Synapsis session's Phoenix Channel. Subscribes to token streaming events. Pushes chunks as `{:stream_chunk, ref, chunk}` to subscriber.
- `close_session/1` — sends DELETE to `/api/sessions/:id`.
- `capabilities/0` — returns full capabilities (streaming, tools, multi-turn).
- `health_check/0` — pings Synapsis health endpoint.

**P6-R2.** Add `synapsis_endpoints` field to `Samgita.Domain.Project`.
- JSONB list of `%{url: String.t(), api_key_ref: String.t(), status: String.t(), last_health_check: DateTime.t()}`.
- Empty list means use direct CLI providers.

**P6-R3.** Add `provider_preference` field to `Samgita.Domain.Project`.
- Enum: `:synapsis | :claude_code | :claude_api | :codex`.
- Default: `:claude_code`.

**P6-R4.** Create `Samgita.Provider.HealthChecker` GenServer.
- Application-wide, in Samgita.Application supervision tree.
- Periodically health-checks all configured Synapsis endpoints across all projects.
- Publishes health status changes via PubSub topic `samgita:provider:health`.
- Check interval: 30 seconds.

**P6-R5.** Implement automatic fallback.
- If all Synapsis instances are unavailable, fall back to `ClaudeCode` provider (direct CLI invocation).
- Fallback is automatic — Worker's session opening logic tries Synapsis first, catches connection errors, retries with ClaudeCode.
- Log fallback events for observability.

**P6-R6.** Support three deployment models.
1. **Colocated** — Samgita and Synapsis on same machine, accessed via localhost. Default development setup.
2. **Single remote** — Samgita connects to one remote Synapsis instance.
3. **Multi-instance** — Samgita connects to N Synapsis instances. Round-robin or load-aware assignment. Session affinity (agent pinned to one instance for task duration).

### Files to Create

| File | Purpose |
|------|---------|
| `apps/samgita_provider/lib/samgita_provider/synapsis.ex` | Synapsis HTTP/Channel provider |
| `apps/samgita/lib/samgita/provider/health_checker.ex` | Periodic Synapsis health checks |

### Files to Modify

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/domain/project.ex` | Add `synapsis_endpoints`, `provider_preference` fields |
| `apps/samgita/lib/samgita/application.ex` | Add HealthChecker to supervision tree |
| `apps/samgita/lib/samgita/agent/worker.ex` | Provider selection logic, fallback on Synapsis failure |
| `apps/samgita_web/lib/samgita_web/live/project_form_live.ex` | Synapsis endpoint configuration UI |

### Test Files to Create

| File | Scope |
|------|-------|
| `apps/samgita_provider/test/samgita_provider/synapsis_test.exs` | Session lifecycle, message exchange (mocked HTTP) |
| `apps/samgita/test/samgita/provider/health_checker_test.exs` | Health check cycling, status propagation |

### Database Migrations

**Migration: Add Synapsis fields to projects**
```elixir
alter table(:projects) do
  add :synapsis_endpoints, :jsonb, default: "[]"
  add :provider_preference, :string, default: "claude_code", null: false
end
```

### Acceptance Criteria

- [ ] `SamgitaProvider.Synapsis.start_session/2` creates a Synapsis session via HTTP
- [ ] `send_message/2` sends message and receives response
- [ ] `stream_message/3` delivers streaming chunks via Phoenix Channel
- [ ] HealthChecker detects unhealthy endpoints within 30 seconds
- [ ] Automatic fallback to ClaudeCode when Synapsis is unavailable
- [ ] Multi-instance deployment routes agents to healthy endpoints
- [ ] Session affinity maintained for agent's task duration
- [ ] Project UI allows configuring Synapsis endpoints
- [ ] `mix test` passes

### Prerequisites

- Phase 2 (Provider Evolution) — Session lifecycle callbacks must exist.

---

## Supervision Tree Changes (All Phases)

### Current Tree
```
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub
├── Horde.Registry (AgentRegistry)
├── Horde.DynamicSupervisor (AgentSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem)
│       ├── Memory (GenServer)
│       └── Agent Workers (gen_statem, via AgentSupervisor)
├── Oban
└── SamgitaWeb.Endpoint
```

### Target Tree (after all phases)
```
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub
├── Horde.Registry (AgentRegistry)
├── Horde.DynamicSupervisor (AgentSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem)
│       ├── Memory (GenServer)
│       ├── MessageRouter (GenServer)          ← Phase 4
│       └── Agent Workers (gen_statem, via AgentSupervisor)
├── Samgita.Provider.SessionRegistry (ETS)     ← Phase 2
├── Samgita.Provider.HealthChecker (GenServer)  ← Phase 6
├── Oban
└── SamgitaWeb.Endpoint
```

---

## UI Changes (All Phases)

### Dashboard Enhancements

**Dependency Graph View** (Phase 3)
- DAG visualization for current phase tasks.
- Nodes colored by status: blocked=gray, pending=blue, running=yellow, completed=green, failed=red.
- Edges = dependency arrows. Critical path highlighted.
- Click node → task details + agent activity log.

**Agent Communication Log** (Phase 4)
- Filterable timeline of inter-agent messages per project.
- Filter by agent, message type, time range.

**Provider Session Panel** (Phase 2)
- Active sessions per project: agent, provider, token count, duration, stream status.
- Manual session termination for stuck agents.

**Planning Phase UI** (Phase 5)
- Research digests as they arrive.
- Draft PRD in editor view.
- Review findings alongside PRD.
- Approve/edit/reject controls.

**Critical Path Indicator** (Phase 3)
- Progress bar tracking critical path completion (not raw task count).
- Shows: "Critical path: 12 tasks remaining, estimated 4 hours."

---

## Migration Summary

All migrations for `Samgita.Repo`:

| Phase | Migration | Description |
|-------|-----------|-------------|
| 3 | `add_dependency_fields_to_tasks` | `depends_on_ids`, `dependency_outputs`, `estimated_duration_minutes`, `wave` on tasks. Expand status enum. |
| 3 | `create_task_dependencies` | Join table for task dependencies |
| 4 | `create_agent_messages` | Inter-agent message log |
| 5 | `add_planning_fields_to_projects` | `start_mode`, `planning_auto_advance`. Expand phase enum. |
| 6 | `add_synapsis_fields_to_projects` | `synapsis_endpoints`, `provider_preference` |

Total: 5 new migrations.

---

## Global Test Strategy

### Unit Tests (per extracted module)
- PromptBuilder, ResultParser, ContextAssembler, RetryStrategy — pure function tests
- DependencyGraph — DAG operations, cycle detection, critical path
- MessageRouter — routing, budget, depth limiting

### Integration Tests
- Worker RARV cycle with session lifecycle
- Orchestrator wave-based dispatch with dependency resolution
- Planning sub-phase flow (research → revise)
- Synapsis provider with mocked HTTP

### End-to-End Tests (`@tag :e2e`)
- Project from idea → planning → bootstrap → development with task DAG
- Agent communication during development phase
- Provider fallback when Synapsis unavailable

### Test Commands
```bash
mix test                              # All unit + integration
mix test apps/samgita/test            # Core app only
mix test apps/samgita_provider/test   # Provider app only
mix test --include e2e                # Full lifecycle
mix format --check-formatted          # Format check
mix credo --strict                    # Lint
```

---

## Success Criteria (v2 Complete)

1. Agent Worker is under 250 lines, with 6 focused delegate modules
2. Provider sessions reduce token usage by 60-80% on multi-turn RARV cycles
3. Task dependency DAG enables wave-based execution with critical path visibility
4. Agents communicate via message bus with enforced budgets (no runaway loops)
5. "Start from idea" produces a reviewed PRD through 5 automated sub-phases
6. Synapsis provider with automatic fallback to direct CLI
7. All existing v1 tests continue to pass (backward compatibility)
8. Zero new `mix credo --strict` warnings

---

**Last Updated:** 2026-04-03
**Design Reference:** [docs/design-v2.md](../design-v2.md)
**Implementation Plan:** [docs/plan.md](../plan.md)
