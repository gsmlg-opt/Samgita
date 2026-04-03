# Samgita v2 — Design Document

## Motivation

Samgita v1 proves the core thesis: OTP supervision trees, gen_statem FSMs, and Oban job queues form a superior foundation for autonomous multi-agent orchestration compared to bash scripts. The v1 system successfully decomposes a PRD into tasks, dispatches them across specialized agents, and drives through SDLC phases with quality gates.

Six structural gaps prevent Samgita from reaching its full potential:

1. The provider behaviour is fire-and-forget — no session lifecycle, no streaming, no multi-turn conversation support
2. Tasks are independent counters — no dependency graph, no critical path, no blocked/unblocked distinction
3. There is no plan mode — the system assumes a PRD already exists
4. The Agent Worker is a 1300-line gen_statem monolith mixing FSM transitions, prompt construction, CLI invocation, git worktree management, memory retrieval, and quality checks
5. Agents cannot communicate with each other — only report completion counts to the Orchestrator
6. Samgita shells out directly to Claude CLI, bypassing Synapsis entirely, with no path to Synapsis-as-executor

This document specifies how to resolve all six.

---

## 1. Provider Behaviour Evolution

### Scenario

An eng-backend agent needs to iterate on an API implementation across multiple RARV cycles. Today, each cycle is a cold `System.cmd` invocation with no conversation memory — the agent re-explains the project context from scratch every time. A session-aware provider would maintain conversation state across turns, reducing prompt tokens by 60-80% on subsequent iterations.

### Current State

`SamgitaProvider.Provider` defines a single callback: `query(prompt, opts) → {:ok, result} | {:error, reason}`. This maps to `claude --print` with `--no-session-persistence`. No streaming, no multi-turn, no tool-use awareness.

### Architecture

The provider behaviour expands to three lifecycle phases: session management, message exchange, and teardown.

**Session Management.** A provider session wraps a long-running CLI process (Erlang Port for Claude Code, stdin/stdout pipe for Codex) or an HTTP conversation (Anthropic Messages API with conversation history). The session holds: system prompt, conversation history, model selection, working directory, and provider-specific state (Port reference, HTTP client, API key).

**Message Exchange.** Within a session, `send_message` appends a user turn and returns the assistant response. For CLI providers, this means writing to the Port's stdin and reading structured output from stdout. For API providers, this means sending the accumulated message history. The response includes: text content, tool use requests (if any), token usage, and stop reason.

**Streaming.** A new `stream_message` callback returns a stream reference. The caller receives chunks via messages (PubSub broadcast or direct process message). This enables real-time UI updates during long LLM calls. Providers that do not support streaming (Codex in `--full-auto` mode) implement `stream_message` as a wrapper around `send_message` that sends one final chunk.

**Teardown.** `close_session` terminates the Port, closes the HTTP connection, and releases resources. Sessions that crash are not automatically restarted — the Agent Worker decides whether to open a new session.

### Behaviour Callbacks

Six callbacks replace the single `query/2`:

- `start_session(system_prompt, opts)` — returns `{:ok, session}` or `{:error, reason}`
- `send_message(session, message)` — synchronous, returns `{:ok, response, updated_session}` or `{:error, reason}`
- `stream_message(session, message, subscriber_pid)` — async, returns `{:ok, stream_ref, updated_session}` or `{:error, reason}`
- `close_session(session)` — returns `:ok`
- `capabilities()` — returns a map of provider capabilities: supports_streaming, supports_tools, supports_multi_turn, max_context_tokens, available_models
- `health_check()` — returns `:ok` or `{:error, reason}` for circuit breaker integration

The existing `query/2` is retained as a convenience that opens a session, sends one message, and closes it. Backward compatible — all existing callers continue to work.

### Session State

The session is an opaque struct owned by the provider implementation. For `ClaudeCode`, it wraps a Port. For `ClaudeAPI`, it wraps an HTTP client and message list. For `Codex`, it wraps a command builder. The Agent Worker holds the session reference in its gen_statem data and passes it through RARV cycles.

### Provider Implementations

**ClaudeCode** — transitions from `System.cmd` (fire-and-forget) to `Port.open` (long-running). The Port runs `claude --interactive` (or equivalent stateful mode). Messages are sent as JSON-delimited lines on stdin, responses read from stdout. Streaming is natural — stdout chunks arrive as Port messages.

**ClaudeAPI** — direct HTTP client to `api.anthropic.com/v1/messages`. Session state is the accumulated messages list. Streaming uses SSE. This is the production-grade path for fine-grained control.

**Codex** — remains `System.cmd`-based since Codex CLI lacks interactive mode. `start_session` is a no-op that stores config. `send_message` runs `codex --full-auto` with the accumulated context in the prompt. No real streaming.

**Synapsis** — new provider that talks to a Synapsis instance's HTTP API or Phoenix Channel. Detailed in section 6.

### Session Lifecycle in the Worker

The Agent Worker opens a session when entering `:reason` for the first time on a task, keeps it open through `:act`, `:reflect`, and `:verify`, and closes it when the task completes or fails terminally. If the session errors mid-cycle, the Worker opens a fresh session and retries from the current RARV state (not from the beginning). This bounds the blast radius of provider failures.

### Migration Path

Phase 1: Add new callbacks to `SamgitaProvider.Provider` with default implementations that delegate to `query/2`. Existing providers continue to work unchanged.

Phase 2: Implement `ClaudeCode` Port-based session. The Worker gains a `:session` field in its data struct. If session is `nil`, it opens one on first use.

Phase 3: Implement `ClaudeAPI` HTTP-based session. This becomes the recommended provider for production deployments.

Phase 4: Implement `Synapsis` provider once Synapsis's API surface stabilizes.

---

## 2. Task Dependency DAG

### Scenario

During the Development phase, `eng-backend` produces an API endpoint that `eng-frontend` must integrate with. Today, both agents receive their tasks simultaneously and work independently. `eng-frontend` either builds against a non-existent API (waste) or produces a mock integration (tech debt). A dependency graph ensures `eng-frontend`'s integration task is blocked until `eng-backend`'s API task completes.

### Current State

The Orchestrator tracks two integers per phase: `phase_tasks_total` and `phase_tasks_completed`. Phase advancement triggers when `completed >= total`. No dependency ordering, no blocked/unblocked distinction, no critical path awareness.

### Data Model

**Task** gains three new fields:

- `depends_on` — a list of task IDs that must complete before this task becomes unblocked. Empty list means immediately available.
- `blocks` — inverse of depends_on, computed at query time. List of task IDs that are waiting for this task.
- `status` — expanded from `{pending, running, completed, failed}` to include `blocked`. A task with unresolved dependencies starts in `blocked` and transitions to `pending` when all dependencies resolve.

**Dependency edges** are stored in a join table: `task_dependencies(task_id, depends_on_task_id)`. This allows efficient queries: "give me all unblocked pending tasks" is a left join where no unresolved dependency exists.

### Graph Construction

The BootstrapWorker already parses the PRD and generates tasks. The enhancement: after generating the flat task list, a second pass infers dependencies using three strategies (applied in order):

**Explicit dependencies.** The PRD may contain dependency markers: "Feature B requires Feature A" or checklist nesting. The parser extracts these as explicit edges.

**Swarm-level ordering.** Within the Engineering swarm, database schema tasks block API tasks, which block frontend integration tasks. Within Operations, infrastructure provisioning blocks deployment configuration. These are static rules encoded in a dependency template per phase.

**LLM-assisted inference.** For complex PRDs where dependencies are implicit, a lightweight LLM call (haiku-tier) reviews the task list and outputs dependency edges as structured JSON. This runs once during bootstrap, not per-task. The prompt includes the task list and asks: "Which tasks must complete before which other tasks can start? Return only direct dependencies, not transitive."

### Dispatch Logic

The Orchestrator's `enqueue_phase_tasks` changes from "enqueue all tasks for this phase" to "enqueue all unblocked tasks for this phase." When a task completes, the Orchestrator queries for newly unblocked tasks (tasks whose entire `depends_on` list is now resolved) and enqueues them.

This naturally produces wave-based execution: wave 1 is all root tasks (no dependencies), wave 2 is everything unblocked by wave 1, and so on. Maximum parallelism is achieved automatically without manual scheduling.

### Critical Path

The longest chain of dependent tasks determines the minimum phase duration. The Orchestrator can compute this using a topological sort with accumulated duration estimates. This information is exposed to the UI for progress visualization — the user sees not just "45/120 tasks done" but "critical path: 12 tasks remaining, estimated 4 hours."

### Cycle Detection

The dependency graph must be a DAG. A cycle (A depends on B, B depends on A) would deadlock the phase. Cycle detection runs at graph construction time using Kahn's algorithm (topological sort — if the sort doesn't include all nodes, there's a cycle). Cycles are reported as bootstrap errors and block phase entry.

### Phase Advancement

Phase completion is no longer "all tasks done" but "all tasks in the DAG are in a terminal state (completed or permanently failed)." A task that fails after max retries enters `failed` status, which unblocks dependents with a `dependency_failed` flag — the dependent task can choose to proceed with degraded input or skip.

---

## 3. Plan Mode (Idea → PRD)

### Scenario

A user has an idea: "Build a SaaS platform for managing restaurant reservations." They have no PRD. Today, they must write one manually before Samgita can begin. Plan mode automates this: the user provides a one-paragraph description, and Samgita produces a structured, reviewed PRD ready for bootstrap.

### Architecture

Plan mode is a new phase in the Orchestrator FSM: `:planning`, inserted before `:bootstrap`. It is optional — projects that start with a PRD skip directly to `:bootstrap`.

The planning phase runs five sequential sub-phases, each driven by specialized agents via Oban workers:

**Research** — 2-4 `plan-researcher` agents run in parallel, each covering a different research axis: market/competitive analysis, technical feasibility, user experience patterns, and regulatory/compliance considerations. Each researcher uses web_search and web_fetch tools to gather information and produces a structured research digest (stored as a memory in `samgita_memory`).

**Architecture** — 1 `plan-architect` agent receives all research digests as context. Outputs: recommended tech stack, high-level system architecture (components, data flows, external integrations), scalability considerations, and major technical risks. Stored as a planning artifact.

**Draft** — 1 `plan-writer` agent receives research + architecture as context. Produces a structured PRD following the project's PRD conventions: numbered requirements, acceptance criteria, milestones/phases, task decomposition hints. The PRD is stored in `samgita_memory.prd` as a draft.

**Review** — 1 `plan-reviewer` agent operates with an adversarial prompt. It receives the draft PRD without the original idea description (blind review) and critiques it for: missing requirements, unrealistic scope, ambiguous acceptance criteria, missing error/edge cases, security gaps, and internal contradictions. Outputs a structured review with severity-tagged findings.

**Revise** — `plan-writer` receives the review findings and produces a revised PRD. The review-revise loop runs up to 3 iterations or until the reviewer produces zero high-severity findings. The final PRD is promoted from draft to active.

### New Agent Types

Four planning agents join the type registry under a new `@planning` swarm:

- `plan-researcher` — Research Analyst. Market research, competitive analysis, tech evaluation. Model: opus (quality-critical).
- `plan-architect` — System Architect. Technical architecture, component design, tech stack selection. Model: opus.
- `plan-writer` — PRD Author. Requirements writing, acceptance criteria, scope definition. Model: opus.
- `plan-reviewer` — PRD Critic. Adversarial review, gap analysis, scope validation. Model: opus.

All planning agents use opus because planning quality gates everything downstream. A bad PRD produces bad tasks which produce bad code.

### Orchestrator Integration

The `@phases` list becomes:

`:planning → :bootstrap → :discovery → :architecture → :infrastructure → :development → :qa → :deployment → :business → :growth → :perpetual`

`agents_for_phase(:planning)` returns `["plan-researcher", "plan-architect", "plan-writer", "plan-reviewer"]`, though they are not all spawned simultaneously — the Orchestrator dispatches them sequentially per sub-phase.

A new field on the Project schema: `start_mode` — either `:from_prd` (skip planning, go straight to bootstrap) or `:from_idea` (start with planning phase). The UI's "New Project" form offers both options.

### Planning State Machine

Within the `:planning` phase, the Orchestrator tracks a sub-state: `{:planning, sub_phase}` where sub_phase is one of `:research`, `:architecture`, `:draft`, `:review`, `:revise`. Sub-phase transitions are driven by Oban worker completion, same pattern as phase transitions in the main FSM.

### Human-in-the-Loop

After the planning phase produces a final PRD, the Orchestrator can either auto-advance to `:bootstrap` (fully autonomous mode) or pause for human review (supervised mode). A project-level configuration `planning_auto_advance` controls this. In supervised mode, the UI presents the generated PRD with a diff view showing review-revise changes, and the user can edit before approving.

---

## 4. Worker Decomposition

### Scenario

A developer needs to modify how RARV prompts are constructed — perhaps adding project-specific few-shot examples. Today, this requires navigating a 1300-line gen_statem to find where prompts are assembled, carefully avoiding changes to state transition logic, timeout handling, git worktree lifecycle, and PubSub broadcasting. Extracting these concerns into focused modules makes each independently testable and modifiable.

### Current State

`Samgita.Agent.Worker` (1326 lines) owns:

- Gen_statem lifecycle (init, state enter/exit, timeout handling)
- RARV state transitions (idle → reason → act → reflect → verify)
- Provider invocation (building prompts, calling Claude, parsing results)
- Git worktree management (setup, checkout, commit, push)
- Memory retrieval (fetching context, writing continuity files)
- Quality checks (output guardrails)
- PubSub broadcasting (state changes, activity logs)
- Circuit breaker integration
- Error classification and retry logic

### Decomposition

The Worker retains ownership of gen_statem lifecycle and RARV state transitions. Everything else extracts into delegate modules that the Worker calls.

**Samgita.Agent.PromptBuilder** — Assembles the LLM prompt for the Act phase. Inputs: task description, agent type definition, project context, learnings, continuity log, previous act results (if retrying). Output: a structured prompt string. This module is pure — no side effects, no process state, fully testable in isolation.

**Samgita.Agent.ResultParser** — Parses the provider response. Extracts: text content, file changes (if parseable from Claude's output), error indicators, completion signals. Classifies the result as success, partial success (work done but verification needed), or failure (with error category). Pure function.

**Samgita.Agent.WorktreeManager** — Manages the git worktree lifecycle for an agent. Operations: create worktree from project base (one per agent, branch named after agent ID), commit changes (atomic, with structured commit message), push to remote, cleanup on agent termination. Stateful — holds the worktree path and branch name. Implemented as a simple struct with functions, not a separate process.

**Samgita.Agent.ContextAssembler** — Fetches and assembles the context window for an RARV cycle. Pulls from: `samgita_memory` (episodic memories, learnings), project metadata (tech stack, architecture decisions), task description and dependencies, previous cycle results. Writes the CONTINUITY.md file. Returns a structured context map consumed by PromptBuilder.

**Samgita.Agent.ActivityBroadcaster** — Wraps PubSub broadcasting and telemetry emission. Every state transition, activity log entry, and error report goes through this module. The Worker calls `ActivityBroadcaster.state_change(data, :reason)` instead of inline PubSub/telemetry code. This centralizes the event schema and makes it easy to add new event consumers (webhooks, external monitoring) without touching the Worker.

**Samgita.Agent.RetryStrategy** — Encapsulates retry logic. Given an error category (rate_limit, overloaded, timeout, unknown) and current retry count, returns: the backoff duration, whether to retry at all, and whether to escalate (open circuit breaker). The Worker's error handling clauses become simple delegations to this module.

### Worker After Decomposition

The Worker's gen_statem states become thin dispatchers:

- `:reason` enter → calls ContextAssembler, stores result in data, transitions to `:act`
- `:act` enter → calls PromptBuilder with context, calls Provider.send_message (or stream_message), calls ResultParser on response, transitions to `:reflect`
- `:reflect` enter → writes learnings to memory via ContextAssembler, transitions to `:verify`
- `:verify` enter → runs OutputGuardrails, checks compilation/tests, decides: complete → `:idle`, retry → `:reason`, fail → error path

Each state function should be under 30 lines. The gen_statem owns only: state transitions, timeout management, session lifecycle (open/close provider session), and the retry decision loop.

### Testing Impact

Before decomposition: testing the Worker requires starting a gen_statem, mocking the provider, and asserting on PubSub messages — integration tests only.

After decomposition: PromptBuilder, ResultParser, ContextAssembler, and RetryStrategy are pure-function modules testable with unit tests. WorktreeManager tests against a real git repo in a temp directory. ActivityBroadcaster tests assert on PubSub subscriptions. The Worker itself has a small set of integration tests covering state transition sequences.

---

## 5. Inter-Agent Communication

### Scenario

During the Development phase, `eng-backend` finishes implementing a REST API endpoint. `eng-api` needs to update the API documentation to reflect the new endpoint. `eng-frontend` needs to integrate with it. Today, none of these agents know about each other's output — they work in isolation, producing inconsistent artifacts.

### Current State

Agents interact with the Orchestrator only: `Orchestrator.notify_task_completed(pid, task_id)`. There is no agent-to-agent message passing. The only shared state is the git repository and the memory system, both of which are passive (agents must poll or re-read to discover changes).

### Architecture

Inter-agent communication uses a two-layer model: indirect communication via the dependency DAG (section 2) and direct communication via a message bus.

### Indirect Communication (Dependency-Driven)

When a task completes, the DAG resolver identifies newly unblocked tasks and dispatches them. The completing agent's output (committed to git, stored in memory) becomes the input context for the dependent agent. This is the primary coordination mechanism — most agent interactions are "I finished X, now you can start Y."

The ContextAssembler (section 4) gains awareness of upstream task outputs. When assembling context for a task that has dependencies, it includes a summary of each dependency's output: what files were changed, what the agent reported as its result, and any learnings tagged to the dependency task.

### Direct Communication (Message Bus)

For cases where agents need to communicate outside the dependency structure — questions, clarifications, shared discoveries — a lightweight PubSub-based message bus enables agent-to-agent messages.

**Message structure:** sender agent ID, recipient agent ID (or broadcast to swarm), message type (notify, request, response), content (text), correlation ID (for request-response pairs), timestamp.

**Routing:** Messages are published to a PubSub topic namespaced by project: `samgita:project:{project_id}:agent_messages`. Each agent's Worker subscribes to messages addressed to it. Broadcast messages use a swarm-level topic.

**Delivery semantics:** Best-effort, at-most-once. Messages are not persisted — if the recipient agent is not running, the message is lost. This is intentional: the dependency DAG handles the durable coordination path. The message bus is for opportunistic, advisory communication only.

**Agent awareness:** The agent's LLM prompt includes a section describing available teammates (names, types, current tasks) and the `send_message` capability. The LLM decides when to send messages, same as any other tool invocation. Messages appear in the recipient's context on its next RARV cycle as injected system messages.

### Orchestrator as Router

The Orchestrator gains a message routing responsibility. When an agent sends a message, it goes through the Orchestrator, which:

1. Validates the recipient exists and is alive
2. Logs the message for observability
3. Forwards to the recipient's Worker process
4. For request-type messages, tracks the correlation ID and enforces a response timeout

The Orchestrator does not read or interpret message content — it is a dumb router. Content interpretation is the recipient agent's responsibility.

### Preventing Runaway Communication

Agents left to communicate freely can enter infinite loops ("Agent A asks Agent B, who asks Agent A back"). Safeguards:

- **Message budget:** Each agent has a per-task message budget (default: 10 outbound messages). Exceeding it is logged as a warning and further messages are dropped.
- **Depth limiting:** Request-response chains are limited to depth 3. A response to a response to a response cannot generate another request.
- **Timeout:** Unanswered requests time out after 60 seconds. The sender proceeds without the response.

---

## 6. Synapsis Integration

### Scenario

Samgita dispatches 6 engineering agents for the Development phase. Instead of each agent shelling out to `claude --print` independently (6 cold CLI processes), they connect to a running Synapsis instance that provides: persistent sessions, tool execution (filesystem, bash, MCP), workspace management, and swarm coordination. Samgita becomes the strategic orchestrator; Synapsis becomes the tactical executor.

### Boundary

The boundary established in the Synapsis tools PRD:

- **Synapsis swarm tools** — within-session, same project, same machine, parallel worktrees. Local parallelism.
- **Samgita** — across Synapsis instances, multi-repo, multi-machine. Distributed orchestration.

Samgita does not replicate Synapsis's tool system. It delegates execution to Synapsis and manages the lifecycle (start session, assign task, collect result, close session).

### SamgitaProvider.Synapsis

A new provider implementation that talks to Synapsis's API:

**start_session** — creates a Synapsis session via HTTP POST to `/api/sessions`. Configures: agent mode (`:build`), model selection, tool allowlist, working directory (worktree path), system prompt (including agent type description and task context). Returns a session ID.

**send_message** — sends a user message to the Synapsis session via the REST API or Phoenix Channel. The message triggers Synapsis's internal agent loop (LLM call → tool execution → result). Returns the assistant's response when the agent loop completes.

**stream_message** — connects to the Synapsis session's Phoenix Channel. Subscribes to token streaming events. The Channel pushes chunks as they arrive from the LLM. The subscriber PID receives `{:stream_chunk, ref, chunk}` messages.

**close_session** — sends DELETE to `/api/sessions/:id`. Synapsis cleans up the agent process, closes bash ports, releases resources.

### Connection Topology

Three deployment models:

**Colocated** — Samgita and Synapsis run on the same machine. Synapsis is accessed via localhost. This is the default development setup.

**Single remote** — Samgita connects to one remote Synapsis instance (e.g., a powerful GPU machine). All agents share the instance.

**Multi-instance** — Samgita connects to N Synapsis instances across a cluster. The Orchestrator implements round-robin or load-aware agent-to-instance assignment. Each agent is pinned to one Synapsis instance for the duration of its task (session affinity).

Connection configuration is stored per-project: a list of Synapsis endpoints with health status. The Orchestrator periodically health-checks each endpoint and routes new agents away from unhealthy instances.

### Fallback

If all Synapsis instances are unavailable, Samgita falls back to the `ClaudeCode` provider (direct CLI invocation). This ensures the system degrades gracefully rather than halting entirely. The fallback is automatic — the Worker's session opening logic tries `Synapsis` first, catches connection errors, and retries with `ClaudeCode`.

### Synapsis API Requirements

For this integration to work, Synapsis must expose:

- `POST /api/sessions` — create session with agent mode, model, tools, working directory
- `DELETE /api/sessions/:id` — terminate session
- `POST /api/sessions/:id/messages` — send message, get response (synchronous)
- `GET /api/sessions/:id/status` — session health, token usage, active tool calls
- Phoenix Channel `session:{id}` — streaming events (tokens, tool calls, tool results, completion)

These are additive to Synapsis's existing architecture — `synapsis_server` already owns the Channel and REST layers. The new endpoints are thin wrappers around `Synapsis.Sessions` and `SynapsisAgent` public APIs.

---

## 7. Data Model Changes

### Task Schema (Modified)

New fields on `Samgita.Domain.Task`:

- `depends_on_ids` — array of task UUIDs, references `tasks.id`. Tasks that must complete before this task is unblocked.
- `status` — extended enum: `blocked`, `pending`, `assigned`, `running`, `completed`, `failed`, `skipped`
- `dependency_outputs` — JSONB map of `{task_id → output_summary}` populated when dependencies complete. Consumed by ContextAssembler for downstream tasks.
- `estimated_duration_minutes` — integer, set during bootstrap, used for critical path calculation
- `wave` — integer, computed from topological sort. Wave 0 = root tasks, wave N = tasks whose latest dependency is in wave N-1.

### Task Dependency Join Table (New)

`task_dependencies`:
- `task_id` — references `tasks.id`
- `depends_on_id` — references `tasks.id`
- `dependency_type` — enum: `hard` (must complete), `soft` (should complete, not blocking)
- Unique constraint on `{task_id, depends_on_id}`

### Agent Message Log (New)

`agent_messages`:
- `id` — UUID
- `project_id` — references `projects.id`
- `sender_agent_id` — string (agent identifier)
- `recipient_agent_id` — string (agent identifier, or `*` for broadcast)
- `message_type` — enum: `notify`, `request`, `response`
- `content` — text
- `correlation_id` — UUID, links request-response pairs
- `inserted_at` — timestamp

Indexed on `{project_id, recipient_agent_id, inserted_at}` for efficient retrieval of unread messages.

### Provider Session (New ETS Table)

`samgita_provider_sessions`:
- `{project_id, agent_id}` — key
- `session_ref` — opaque reference (Port, HTTP client, Synapsis session ID)
- `provider` — atom (`:claude_code`, `:claude_api`, `:codex`, `:synapsis`)
- `started_at` — timestamp
- `message_count` — integer
- `total_tokens` — integer

ETS (not Postgres) because sessions are ephemeral — they die with the agent process. The table exists for observability (dashboard can show active sessions) and cleanup (find orphaned sessions on agent crash).

### Project Schema (Modified)

New fields on `Samgita.Domain.Project`:

- `start_mode` — enum: `:from_prd`, `:from_idea`. Determines whether the Orchestrator enters `:planning` or `:bootstrap`.
- `planning_auto_advance` — boolean, default false. If true, skip human review of generated PRD.
- `synapsis_endpoints` — JSONB list of `{url, api_key_ref, status, last_health_check}`. Empty means use direct CLI providers.
- `provider_preference` — enum: `:synapsis`, `:claude_code`, `:claude_api`, `:codex`. Default provider for agent sessions.

---

## 8. Supervision Tree Changes

### Current Tree

```
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub
├── Horde.Registry (AgentRegistry)
├── Horde.DynamicSupervisor (ProjectSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem)
│       ├── Memory (GenServer)
│       └── Agent Workers (gen_statem, via AgentSupervisor)
├── Oban
└── SamgitaWeb.Endpoint
```

### New Tree

```
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub
├── Horde.Registry (AgentRegistry)
├── Horde.DynamicSupervisor (ProjectSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem)
│       ├── Memory (GenServer)
│       ├── MessageRouter (GenServer)          ← NEW
│       └── Agent Workers (gen_statem, via AgentSupervisor)
├── Samgita.Provider.SessionRegistry (ETS)     ← NEW
├── Samgita.Provider.HealthChecker (GenServer)  ← NEW
├── Oban
└── SamgitaWeb.Endpoint
```

**MessageRouter** — per-project GenServer that receives agent messages, validates routing, enforces message budgets, and forwards to recipient Workers. Lives under the Project Supervisor because its lifecycle is tied to the project.

**SessionRegistry** — application-wide ETS table tracking active provider sessions for observability and orphan cleanup.

**HealthChecker** — periodic health check of configured Synapsis endpoints. Publishes health status changes via PubSub. The Orchestrator subscribes to route agents away from unhealthy endpoints.

---

## 9. Orchestrator Phase Dispatch (Revised)

### Current Flow

```
phase enter → spawn agents → enqueue all tasks → count completions → advance
```

### Revised Flow

```
phase enter
  → spawn agents for phase
  → build/load task dependency DAG for phase
  → validate DAG (cycle detection)
  → compute waves and critical path
  → dispatch wave 0 (unblocked root tasks)
  → on task completion:
      → mark task completed in DAG
      → propagate outputs to dependents (dependency_outputs field)
      → identify newly unblocked tasks
      → dispatch newly unblocked tasks
      → recompute critical path
      → if all tasks terminal (completed or failed): trigger quality gates or advance
  → stagnation detection now checks:
      → are there pending tasks with no running agent?
      → are there running tasks that exceeded estimated_duration?
      → are all remaining tasks blocked by failed dependencies?
```

### Quality Gate Integration

Quality gates remain at phase boundaries (dev → qa, qa → deploy). The gate workers gain access to the dependency DAG, enabling smarter checks: "did all critical-path tasks pass?", "are there failed non-critical tasks we can skip?", "is test coverage sufficient for the completed feature set?"

---

## 10. UI Changes

### Dashboard Enhancements

**Dependency Graph View.** A DAG visualization for the current phase's tasks. Nodes are tasks colored by status (blocked=gray, pending=blue, running=yellow, completed=green, failed=red). Edges are dependency arrows. The critical path is highlighted. Clicking a node shows the task details and its agent's activity log.

**Agent Communication Log.** A filterable timeline of inter-agent messages for a project. Useful for debugging coordination issues ("why did eng-frontend proceed before eng-backend finished?").

**Provider Session Panel.** Shows active provider sessions per project: which agent, which provider, token count, duration, stream status. Enables manual session termination for stuck agents.

**Planning Phase UI.** When a project is in `:planning` phase: displays the research digests as they arrive, shows the draft PRD in an editor, presents review findings alongside the PRD, and offers approve/edit/reject controls for human-in-the-loop review.

**Critical Path Indicator.** On the project overview, a progress bar that tracks critical path completion rather than raw task count. This gives a more accurate time estimate than "45/120 tasks."

---

## 11. Implementation Phases

### Phase 1: Worker Decomposition

Extract PromptBuilder, ResultParser, ContextAssembler, WorktreeManager, ActivityBroadcaster, RetryStrategy from the Worker. The Worker delegates to these modules. No functional changes — same behaviour, cleaner structure. All existing tests must pass.

Prerequisite for: everything else (all subsequent phases touch the Worker).

### Phase 2: Provider Evolution

Add session lifecycle callbacks to the Provider behaviour. Implement ClaudeCode Port-based sessions. The Worker uses sessions when available, falls back to one-shot query when not. Add SessionRegistry ETS table.

Prerequisite for: Synapsis integration (phase 6).

### Phase 3: Task Dependency DAG

Add dependency fields to Task schema. Implement DAG builder in BootstrapWorker. Modify Orchestrator dispatch to wave-based execution. Add cycle detection. Compute critical path.

Prerequisite for: inter-agent communication (phase 4) benefits from dependency awareness.

### Phase 4: Inter-Agent Communication

Add MessageRouter per project. Add message bus via PubSub. Add message budget and depth limiting. Modify ContextAssembler to include teammate awareness and inject received messages.

### Phase 5: Plan Mode

Add planning agent types. Add `:planning` phase to Orchestrator. Implement planning sub-phase workflow (research → architecture → draft → review → revise). Add planning UI.

### Phase 6: Synapsis Integration

Implement `SamgitaProvider.Synapsis`. Add HealthChecker. Add fallback logic. Add Synapsis endpoint configuration to Project schema.

---

## 12. Resolved Decisions

1. **Provider sessions are stateful, not stateless-with-replay.** The provider holds conversation history in its session state rather than replaying the full message history on each call. This uses more memory but saves tokens and reduces latency. The trade-off is acceptable because agent sessions are bounded (one task = one session) and the token savings are 60-80%.

2. **Dependency DAG is per-phase, not global.** Each phase has its own DAG. Cross-phase dependencies are implicit in phase ordering — infrastructure must complete before development starts. This keeps the DAG small and fast to compute. If a future requirement needs cross-phase dependencies, the DAG can be extended without architectural changes.

3. **Inter-agent messages are ephemeral, not persisted.** Messages are not stored in Postgres — only logged to the agent_messages table for observability. The canonical coordination mechanism is the dependency DAG (durable, structured). Messages are advisory and opportunistic.

4. **Planning uses opus for all agents.** The cost premium is justified because planning quality determines everything downstream. A bad PRD from a cheaper model costs more in wasted development cycles than the opus inference cost.

5. **Synapsis integration is a provider, not a protocol.** Samgita talks to Synapsis via its HTTP API and Phoenix Channel, not via MCP or a custom protocol. This means Samgita is a Synapsis API client, not a peer. The asymmetry is intentional — Samgita orchestrates, Synapsis executes.

6. **Worker decomposition preserves gen_statem.** The Worker remains a gen_statem — the decomposition extracts helper modules, not the FSM itself. Alternatives considered: replacing gen_statem with a graph runtime (similar to Synapsis's synapsis_agent approach). Rejected because Samgita's RARV cycle is a fixed 4-state loop, not a dynamic graph. Gen_statem is the right abstraction for a fixed state machine.

7. **Human-in-the-loop defaults to ON for planning.** `planning_auto_advance` defaults to false. Generating and immediately executing a PRD without human review is too risky for most use cases. Fully autonomous mode is opt-in per project.

8. **No Gemini/Cline/Aider providers in v2.** Loki-mode supports 5 providers but only Claude has full capability (parallel agents, Task tool, MCP). Adding degraded-mode providers that cannot participate in session lifecycle or streaming adds complexity without proportional value. Codex is retained because it has MCP support and is a credible alternative. Gemini/Cline/Aider can be added as community contributions following the Provider behaviour contract.

---

## 13. Open Questions

None at this time. All architectural questions have been resolved as decisions above. Implementation-level questions (exact API payloads, specific prompt templates, migration ordering) will be resolved during each phase's detailed task planning.