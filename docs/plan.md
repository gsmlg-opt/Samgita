# Samgita v2 Implementation Plan

## Context

Samgita v1 is complete. Phases 1-4 delivered: blocker fixes, end-to-end wiring, loki-mode capability parity, and production polish (MCP memory server, enhanced commits, PRD chat, quality gates). The system successfully decomposes PRDs into tasks, dispatches them across 37 agent types in 7 swarms, and drives through SDLC phases with quality gates on OTP supervision trees.

Six structural gaps prevent Samgita from reaching its full potential: the Agent.Worker is a 1300-line monolith, the provider behaviour is fire-and-forget with no session lifecycle, tasks have no dependency graph, agents cannot communicate with each other, there is no plan mode for idea-to-PRD generation, and Claude CLI is invoked directly with no path to Synapsis-as-executor. This plan addresses all six across 6 phases.

See `docs/design-v2.md` for full architectural design, data model changes, supervision tree changes, and resolved decisions.

Last Updated: 2026-04-03

---

## Phase 1: Worker Decomposition [PENDING]

**Goal:** Extract six focused modules from the 1300-line Agent.Worker gen_statem. No functional changes -- same behaviour, cleaner structure. All existing tests must pass. Prerequisite for everything else.

### Key Deliverables

- PromptBuilder: pure module assembling LLM prompts from task, agent type, context, and continuity log
- ResultParser: pure module classifying provider responses as success, partial, or failure with error category
- ContextAssembler: fetches and assembles context from samgita_memory, project metadata, task description, previous cycle results; writes CONTINUITY.md
- WorktreeManager: manages git worktree lifecycle (create, commit, push, cleanup) as a struct with functions
- ActivityBroadcaster: centralizes PubSub broadcasting and telemetry emission for state transitions and activity logs
- RetryStrategy: encapsulates backoff duration, retry decisions, and circuit breaker escalation given error category and retry count
- Worker gen_statem states reduced to thin dispatchers (each under 30 lines)

### New / Modified Modules

| Module | Status |
|--------|--------|
| `Samgita.Agent.PromptBuilder` | New |
| `Samgita.Agent.ResultParser` | New |
| `Samgita.Agent.ContextAssembler` | New |
| `Samgita.Agent.WorktreeManager` | New |
| `Samgita.Agent.ActivityBroadcaster` | New |
| `Samgita.Agent.RetryStrategy` | New |
| `Samgita.Agent.Worker` | Modified (delegates to above) |

### Prerequisite Phases

None -- this is the foundation for all subsequent phases.

### Success Criteria

- `mix test` passes with zero regressions
- Worker module line count drops below 400 lines
- PromptBuilder, ResultParser, ContextAssembler, and RetryStrategy have pure-function unit tests
- WorktreeManager has integration tests against a real git repo in a temp directory
- ActivityBroadcaster has tests asserting on PubSub subscriptions
- `mix credo --strict` passes

---

## Phase 2: Provider Evolution [PENDING]

**Goal:** Expand the Provider behaviour from a single `query/2` callback to a full session lifecycle with streaming support. Implement ClaudeCode Port-based sessions. Add SessionRegistry ETS table for observability.

### Key Deliverables

- Six new Provider behaviour callbacks: `start_session/2`, `send_message/2`, `stream_message/3`, `close_session/1`, `capabilities/0`, `health_check/0`
- Existing `query/2` retained as convenience (open session, send one message, close)
- ClaudeCode provider transitioned from `System.cmd` to `Port.open` for long-running sessions
- Worker gains `:session` field in data struct; opens session on first `:reason` entry, closes on task completion
- SessionRegistry ETS table tracking active sessions for dashboard observability and orphan cleanup
- Fallback: Worker uses sessions when available, degrades to one-shot `query/2` when not

### New / Modified Modules

| Module | Status |
|--------|--------|
| `SamgitaProvider.Provider` | Modified (new callbacks with defaults) |
| `SamgitaProvider.ClaudeCode` | Modified (Port-based sessions) |
| `SamgitaProvider.Mock` | Modified (implement session callbacks) |
| `Samgita.Provider.SessionRegistry` | New (ETS table) |
| `Samgita.Agent.Worker` | Modified (session lifecycle in data) |
| `Samgita.Application` | Modified (start SessionRegistry) |

### Prerequisite Phases

- Phase 1 (Worker Decomposition) -- the Worker must be decomposed before adding session lifecycle to it

### Success Criteria

- All existing provider tests pass unchanged (backward compatibility)
- New tests cover session lifecycle: open, multi-turn send, stream, close
- SessionRegistry correctly tracks active sessions and cleans up on agent crash
- `mix test` passes across all umbrella apps
- ClaudeCode Port-based session can sustain a multi-turn conversation

---

## Phase 3: Task Dependency DAG [PENDING]

**Goal:** Add dependency tracking to tasks enabling wave-based execution, critical path computation, and cycle detection. Replace flat task counting with DAG-aware dispatch in the Orchestrator.

### Key Deliverables

- New Task fields: `depends_on_ids` (array of UUIDs), expanded `status` enum (add `blocked`, `skipped`), `wave` (integer), `estimated_duration_minutes` (integer)
- New `task_dependencies` join table with `dependency_type` (hard/soft)
- DAG builder in BootstrapWorker: explicit dependencies from PRD, swarm-level ordering rules, optional LLM-assisted inference
- Cycle detection via Kahn's algorithm at graph construction time
- Critical path computation via topological sort with accumulated duration estimates
- Orchestrator dispatch changed from "enqueue all" to "enqueue wave 0, then dispatch newly unblocked tasks on completion"
- Phase advancement changed from counter-based to "all tasks in terminal state"
- Stagnation detection enhanced: blocked-by-failed detection, exceeded-duration detection

### New / Modified Modules

| Module | Status |
|--------|--------|
| `Samgita.Domain.Task` | Modified (new fields) |
| `Samgita.Domain.TaskDependency` | New (join table schema) |
| `Samgita.Task.DAG` | New (graph builder, cycle detection, critical path) |
| `Samgita.Workers.BootstrapWorker` | Modified (dependency inference pass) |
| `Samgita.Project.Orchestrator` | Modified (wave-based dispatch) |
| Migration for task_dependencies table | New |
| Migration for Task field additions | New |

### Prerequisite Phases

- Phase 1 (Worker Decomposition) -- Orchestrator changes touch dispatch logic shared with Worker

### Success Criteria

- Cycle detection rejects circular dependencies at bootstrap time with clear error
- Wave computation correctly assigns wave numbers from topological sort
- Orchestrator dispatches wave 0 tasks first, then unblocks dependents on completion
- Critical path is computable and exposed via PubSub for UI consumption
- Tasks blocked by failed dependencies receive `dependency_failed` flag
- `mix test` passes; new DAG module has comprehensive unit tests

---

## Phase 4: Inter-Agent Communication [PENDING]

**Goal:** Enable agents to exchange messages within a project via a PubSub-based message bus with budget and depth limiting. Add MessageRouter per project.

### Key Deliverables

- MessageRouter GenServer per project under Project.Supervisor
- Message bus via PubSub topic `samgita:project:{project_id}:agent_messages`
- Message structure: sender, recipient (or broadcast), type (notify/request/response), content, correlation_id
- Message budget enforcement: 10 outbound messages per agent per task
- Depth limiting: request-response chains capped at depth 3
- Request timeout: 60 seconds for unanswered requests
- ContextAssembler modified to include teammate awareness (names, types, current tasks) and inject received messages into agent prompts
- `agent_messages` table for observability logging (not durable coordination)

### New / Modified Modules

| Module | Status |
|--------|--------|
| `Samgita.Agent.MessageRouter` | New (per-project GenServer) |
| `Samgita.Domain.AgentMessage` | New (schema for observability log) |
| `Samgita.Agent.ContextAssembler` | Modified (teammate awareness, message injection) |
| `Samgita.Project.Supervisor` | Modified (start MessageRouter) |
| `Samgita.Project.Orchestrator` | Modified (route messages via MessageRouter) |
| Migration for agent_messages table | New |

### Prerequisite Phases

- Phase 1 (Worker Decomposition) -- ContextAssembler must exist as a separate module
- Phase 3 (Task Dependency DAG) -- dependency awareness enriches indirect communication via upstream task outputs

### Success Criteria

- Agents can send and receive messages within a project
- Message budget prevents runaway communication (messages dropped after limit, warning logged)
- Depth limiting prevents infinite request-response loops
- Unanswered requests time out after 60 seconds without blocking the sender
- MessageRouter dies with its project (lifecycle tied to Project.Supervisor)
- `mix test` passes; MessageRouter has unit and integration tests

---

## Phase 5: Plan Mode [PENDING]

**Goal:** Add a `:planning` phase to the Orchestrator that transforms a one-paragraph idea into a structured, reviewed PRD through specialized planning agents. Human-in-the-loop review defaults ON.

### Key Deliverables

- Four new agent types under `@planning` swarm: `plan-researcher`, `plan-architect`, `plan-writer`, `plan-reviewer`
- `:planning` phase added to Orchestrator before `:bootstrap`
- Planning sub-phase workflow: research (parallel researchers) -> architecture -> draft -> review -> revise (up to 3 iterations)
- New Project fields: `start_mode` (`:from_prd` or `:from_idea`), `planning_auto_advance` (boolean, default false)
- "New Project" UI offers both start modes
- Planning phase UI: research digest display, draft PRD editor, review findings, approve/edit/reject controls
- Supervised mode: Orchestrator pauses after planning for human PRD review before advancing to `:bootstrap`

### New / Modified Modules

| Module | Status |
|--------|--------|
| `Samgita.Agent.Types` | Modified (add @planning swarm, 4 agent types) |
| `Samgita.Project.Orchestrator` | Modified (add :planning phase and sub-states) |
| `Samgita.Workers.PlanningWorker` | New (drives sub-phase workflow) |
| `Samgita.Domain.Project` | Modified (start_mode, planning_auto_advance fields) |
| `SamgitaWeb.Live.ProjectFormLive` | Modified (start mode selection) |
| `SamgitaWeb.Live.PlanningLive` | New (planning phase UI) |
| Migration for Project field additions | New |

### Prerequisite Phases

- Phase 1 (Worker Decomposition) -- planning agents run through the same Worker; PromptBuilder must handle planning prompts
- Phase 3 (Task Dependency DAG) -- planning sub-phases benefit from sequential dependency dispatch

### Success Criteria

- A project created with `start_mode: :from_idea` enters `:planning` phase
- A project created with `start_mode: :from_prd` skips directly to `:bootstrap`
- Planning produces a structured PRD from a one-paragraph idea
- Review-revise loop runs up to 3 iterations or until zero high-severity findings
- Human review gate pauses the Orchestrator when `planning_auto_advance` is false
- All 4 planning agent types registered in Agent.Types with correct swarm
- `mix test` passes; planning workflow has integration tests

---

## Phase 6: Synapsis Integration [PENDING]

**Goal:** Implement `SamgitaProvider.Synapsis` so agents can execute through a Synapsis instance instead of direct CLI invocation. Add health checking, automatic fallback, and multi-instance support.

### Key Deliverables

- SamgitaProvider.Synapsis: full Provider implementation (start_session via HTTP, send_message via REST/Channel, stream_message via Phoenix Channel, close_session via DELETE)
- HealthChecker GenServer: periodic health check of Synapsis endpoints, publishes status via PubSub
- Automatic fallback: Worker tries Synapsis first, falls back to ClaudeCode on connection failure
- Project schema additions: `synapsis_endpoints` (JSONB list), `provider_preference` (enum)
- Three deployment models supported: colocated (localhost), single remote, multi-instance (round-robin/load-aware)
- Provider Session Panel in dashboard showing active sessions per project

### New / Modified Modules

| Module | Status |
|--------|--------|
| `SamgitaProvider.Synapsis` | New (Provider implementation) |
| `Samgita.Provider.HealthChecker` | New (GenServer for endpoint health) |
| `Samgita.Agent.Worker` | Modified (fallback logic: Synapsis -> ClaudeCode) |
| `Samgita.Domain.Project` | Modified (synapsis_endpoints, provider_preference) |
| `Samgita.Application` | Modified (start HealthChecker) |
| `SamgitaWeb.Live.SessionPanelComponent` | New (provider session dashboard) |
| Migration for Project field additions | New |

### Prerequisite Phases

- Phase 2 (Provider Evolution) -- Synapsis implements the session lifecycle callbacks defined in Phase 2

### Success Criteria

- SamgitaProvider.Synapsis can open a session, exchange messages, stream responses, and close cleanly against a running Synapsis instance
- HealthChecker detects unhealthy endpoints and publishes status changes
- Worker automatically falls back to ClaudeCode when Synapsis is unavailable
- Multi-instance routing distributes agents across healthy endpoints
- `mix test` passes; Synapsis provider has tests using mock HTTP/Channel
- System degrades gracefully (no halt) when all Synapsis instances are down
