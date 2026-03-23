# PRD: Samgita — Autonomous Multi-Agent Orchestration System

## Overview

Samgita is an Elixir/OTP reimplementation of [loki-mode](https://github.com/asklokesh/loki-mode) — an autonomous multi-agent system that transforms a Product Requirements Document (PRD) into a fully built, tested, and deployed product with minimal human intervention.

**In one sentence:** PRD in, deployed product out.

Samgita replaces loki-mode's shell scripts (`autonomy/run.sh` — 8,766 lines of bash), flat-file state (`.loki/` JSON), and ad-hoc process management with OTP supervision trees, PostgreSQL persistence, Oban job queues, Horde distributed processes, and Phoenix LiveView real-time dashboards.

---

## Problem Statement

Building software from a PRD requires coordinating dozens of specialized tasks — architecture, implementation, testing, review, deployment, documentation — across multiple agents working in parallel. Existing approaches have critical limitations:

| Approach | Limitation |
|---|---|
| Single-agent coding assistants | No parallelism, single-threaded, context window saturation |
| loki-mode (shell scripts) | Fragile state management, no fault tolerance, no real-time observability |
| Direct LLM API orchestration | Reimplements tool execution, loses CLI-native capabilities |

### What Samgita Solves

1. **Autonomous end-to-end delivery** — PRD to deployed product without babysitting
2. **Multi-agent parallelism** — 10+ agents working simultaneously on different tasks
3. **Self-healing on failures** — OTP supervisors restart crashed agents, Oban retries failed tasks
4. **Real-time observability** — Phoenix LiveView dashboard showing agent states, task queues, activity logs
5. **Persistent memory** — pgvector-backed semantic memory across sessions and projects
6. **Fault-tolerant orchestration** — gen_statem state machines for agent RARV cycles and project phase transitions

---

## Core Workflow

```
PRD → Bootstrap → Discovery → Architecture → Infrastructure →
      Development (RARV loop) → QA (9 quality gates) → Deployment →
      Business Operations → Growth Loop (perpetual)
```

### The RARV Cycle

The atomic unit of all agent work. Every agent iteration follows this immutable cycle:

```
REASON  — Read context, check task queue, identify highest-priority unblocked task
   │
   ▼
ACT     — Execute task: write code, run commands, generate artifacts
   │      Commit changes atomically (git checkpoint)
   ▼
REFLECT — Did it work? Update working memory, record learnings
   │      Update task status and agent state
   ▼
VERIFY  — Run tests, check compilation, validate against spec
   │
   ├──[PASS]──→ Mark task complete, extract learnings, return to REASON
   │
   └──[FAIL]──→ Capture error in learnings, rollback if needed
                After 3 failures: try simpler approach
                After 5 failures: dead-letter queue, move to next task
```

**Research foundation:** Self-verification loops achieve 2-3x quality improvement (Boris Cherny's production observations). The RARV cycle is implemented as a `gen_statem` state machine in `Samgita.Agent.Worker`.

---

## Architecture

### Umbrella Structure

```
apps/
├── samgita_provider/  # Provider abstraction wrapping Claude Code CLI
│                      # Invokes `claude` CLI via System.cmd/3
│                      # Standalone — no dependencies on other apps
│
├── samgita/           # Core business logic
│                      # Projects, Tasks, Agent Runs, RARV Worker
│                      # Horde distributed supervision, Oban job queues
│                      # Depends on: samgita_provider
│
├── samgita_memory/    # Persistent memory with pgvector
│                      # Episodic, semantic, procedural memory types
│                      # PRD execution tracking, thinking chains
│                      # Standalone — shares same Postgres DB (sm_ table prefix)
│
└── samgita_web/       # Phoenix LiveView UI + REST API
                       # Real-time dashboard, project management
                       # Depends on: samgita, samgita_memory
```

### Provider Model — CLI-as-Provider

**Samgita does NOT call LLM APIs directly.** It orchestrates CLI tools as supervised OTP processes.

```
Samgita Agent Worker (gen_statem)
  → spawns Claude CLI via System.cmd/3 with --print and --output-format json
  → sends task prompt as system prompt + conversation
  → receives structured JSON output
  → parses tool calls, results, completion status
  → RARV cycle decides next action
  → repeat or terminate
```

| Provider | CLI Tool | Feature Level |
|---|---|---|
| **Claude Code** | `claude` CLI | Full — parallel agents, Task tool, MCP, streaming |
| **OpenAI Codex** | `codex` CLI | Degraded — sequential, no Task tool |

**Why CLI, not API:** The CLI tools handle their own tool execution, context management, conversation state, rate limiting, and model selection. Samgita's job is **orchestration** — deciding which agent does what, when, in parallel.

### Supervision Trees

**Samgita.Application** (core):
```
Samgita.Repo                                    # PostgreSQL
Phoenix.PubSub (Samgita.PubSub)                # Real-time events
Samgita.Cache (ETS + PubSub invalidation)      # Hot caching
Horde.Registry (Samgita.AgentRegistry)         # Distributed process registry
Horde.DynamicSupervisor (Samgita.AgentSupervisor)  # Agent supervision
Oban (queues: agent_tasks:100, orchestration:10, snapshots:5)
```

**Per-Project Supervision** (started on demand):
```
Samgita.Project.Supervisor
├── Samgita.Project.Orchestrator (gen_statem)   # Phase state machine
└── Agent Workers (gen_statem, via Horde)       # RARV cycle per agent
```

**SamgitaMemory.Application** (standalone):
```
SamgitaMemory.Repo                             # Same Postgres, sm_ prefix tables
SamgitaMemory.Cache.Supervisor
├── MemoryTable (ETS LRU, max 10k entries)
└── PrdTable (ETS LRU, max 100 entries)
SamgitaMemory.Formation.Supervisor             # Telemetry handlers
Oban (name: SamgitaMemory.Oban, queues: embeddings:5, compaction:2, summarization:3)
```

---

## Agent Model

### 37 Agent Types across 7 Swarms

| Swarm | Count | Agent Types |
|---|---|---|
| **Engineering** | 8 | eng-frontend, eng-backend, eng-database, eng-mobile, eng-api, eng-qa, eng-perf, eng-infra |
| **Operations** | 8 | ops-devops, ops-sre, ops-security, ops-monitor, ops-incident, ops-release, ops-cost, ops-compliance |
| **Business** | 8 | biz-marketing, biz-sales, biz-finance, biz-legal, biz-support, biz-hr, biz-investor, biz-partnerships |
| **Data** | 3 | data-ml, data-eng, data-analytics |
| **Product** | 3 | prod-pm, prod-design, prod-techwriter |
| **Growth** | 4 | growth-hacker, growth-community, growth-success, growth-lifecycle |
| **Review** | 3 | review-code, review-business, review-security |

Simple projects use 5-10 agents. Complex projects spawn 30+.

### Model Selection by Agent Type

| Tier | Model | Agent Types |
|---|---|---|
| **Planning** | Opus | prod-pm, eng-infra (architecture, system design, PRD analysis) |
| **Development** | Sonnet | eng-*, ops-*, biz-*, data-*, growth-* (implementation, complex bugs) |
| **Fast** | Haiku | eng-qa, ops-monitor, review-* (tests, linting, docs, simple fixes) |

### Agent State Machine (gen_statem)

```
:idle → :reason → :act → :reflect → :verify
          ↑                            │
          └────── on failure ──────────┘
```

Each agent worker is registered in Horde with `{:agent, project_id, agent_id}` naming. Agent state transitions broadcast via PubSub for real-time UI updates.

---

## Project Lifecycle Phases

### Phase Flow

```
BOOTSTRAP → DISCOVERY → ARCHITECTURE → INFRASTRUCTURE →
DEVELOPMENT → QA → DEPLOYMENT → BUSINESS → GROWTH → PERPETUAL
```

| Phase | Description | Key Actions |
|---|---|---|
| **Bootstrap** | Initialize project structure | Create working directory, validate PRD, initialize state, spawn initial agents |
| **Discovery** | Analyze PRD requirements | Parse PRD, competitive research, extract requirements, generate task backlog |
| **Architecture** | System design (spec-first) | Generate OpenAPI spec, select tech stack, create project scaffolding |
| **Infrastructure** | Provision environment | CI/CD setup, cloud resources, monitoring, database provisioning |
| **Development** | Implementation with TDD | RARV loop per task, parallel blind review, git checkpoints |
| **QA** | Quality verification | 9 quality gates, security audit, load testing, accessibility |
| **Deployment** | Release to production | Blue-green deploy, smoke tests, auto-rollback on errors |
| **Business** | Non-technical setup | Marketing site, billing, legal docs, support system |
| **Growth** | Continuous optimization | A/B testing, performance tuning, user feedback loops |
| **Perpetual** | Never-ending improvement | Dependency updates, security patches, feature refinement |

### Phase Transitions

Transitions are managed by the `Samgita.Project.Orchestrator` gen_statem. Requirements for transition:

1. All phase quality gates passed
2. No critical/high/medium unresolved issues
3. Git checkpoint created
4. Phase completion event recorded

### Spec-First Architecture (Architecture Phase)

Following loki-mode's spec-first pattern:

1. Extract API requirements from PRD
2. Generate OpenAPI 3.1 specification
3. Validate spec (spectral, swagger-cli)
4. Generate artifacts from spec (TypeScript types, client SDK, server stubs)
5. Select tech stack (consensus from eng-backend + eng-frontend agents)
6. Create project scaffolding
7. Spec becomes source of truth for contract testing in QA phase

---

## Quality Gates — 9-Gate System

Every code change passes through quality gates before acceptance:

| Gate | Name | Description |
|---|---|---|
| 1 | **Input Guardrails** | Validate task scope, detect prompt injection, check constraints |
| 2 | **Static Analysis** | Linting, type checking, compilation, unused code detection |
| 3 | **Blind Review** | 3 independent parallel reviewers (code, business-logic, security) |
| 4 | **Anti-Sycophancy** | Devil's advocate review on unanimous approval (CONSENSAGENT research) |
| 5 | **Output Guardrails** | Secret detection, spec compliance, quality validation |
| 6 | **Severity Blocking** | Critical/High/Medium = BLOCK; Low/Cosmetic = TODO comment |
| 7 | **Test Coverage** | Unit: 100% pass, >80% coverage; Integration: 100% pass |
| 8 | **Mock Detector** | Flags tests that never import source code, tautological assertions |
| 9 | **Test Mutation Detector** | Detects assertion value changes with implementation, low assertion density |

### Blind Review System (Gate 3)

```
IMPLEMENT → BLIND REVIEW (3 parallel agents) → AGGREGATE → FIX → RE-REVIEW
               │
               ├── review-code (Sonnet)     — SOLID, patterns, maintainability
               ├── review-business (Sonnet)  — Requirements, edge cases, UX
               └── review-security (Sonnet)  — OWASP Top 10, vulnerabilities
```

Reviewers cannot see each other's findings. This prevents anchoring bias and groupthink.

### Anti-Sycophancy (Gate 4)

If all 3 reviewers unanimously approve, the system automatically spawns a Devil's Advocate reviewer to challenge assumptions. Reduces false positives by 30% (CONSENSAGENT, ACL 2025).

---

## Task System

### Task Queue (Oban-Based)

Tasks flow through a state machine:

```
pending → running → completed
                  → failed → (retry) → pending
                           → (max retries) → dead_letter
```

### Task Schema

```elixir
schema "tasks" do
  belongs_to :project, Project
  belongs_to :parent_task, Task           # Hierarchical task decomposition

  field :type, :string                    # e.g., "bootstrap", "implement", "review"
  field :priority, :integer, default: 10  # 1 = highest
  field :status, Ecto.Enum,
    values: [:pending, :running, :completed, :failed, :dead_letter]
  field :payload, :map, default: %{}      # Task-specific data (prd_id, files, etc.)
  field :result, :map                     # Output on completion
  field :error, :map                      # Error details on failure
  field :agent_id, :string                # Which agent claimed this task
  field :attempts, :integer, default: 0
  field :tokens_used, :integer, default: 0
  field :duration_ms, :integer

  timestamps()
end
```

### Task Dispatching

Tasks are dispatched via `Samgita.Workers.AgentTaskWorker` (Oban worker):

1. Task created with type, payload, priority
2. Oban job enqueued in `agent_tasks` queue (100 concurrency)
3. Worker dispatches to appropriate agent via Horde
4. Agent executes RARV cycle
5. Task marked completed or failed
6. On failure: exponential backoff retry (max 5 attempts)
7. After max retries: moved to dead_letter status

### PRD-Scoped Tasks

Tasks are scoped to PRDs via `payload->>'prd_id'` JSONB query. This enables:
- Viewing tasks for a specific PRD execution
- Multiple PRDs per project (sequential, not parallel)
- Task isolation between PRD runs

---

## Completion Council

A multi-agent voting system that determines when a project PRD is "done."

### How It Works

1. Council runs every N iterations (configurable, default: 5)
2. 3 council members vote independently:
   - **Requirements Verifier** — Are all PRD requirements met?
   - **Test Auditor** — Are tests comprehensive and passing?
   - **Devil's Advocate** — Skeptical review, find remaining issues
3. 2/3 votes required for completion
4. If unanimous COMPLETE → spawn extra Devil's Advocate review
5. Stagnation detection: if N iterations pass with no git changes, force evaluation

### Circuit Breaker

- Track failures per agent type
- Open circuit after 5 consecutive failures
- Half-open testing before recovery
- Prevents cascading failures across the system

---

## Memory System (samgita_memory)

Three-tier architecture with progressive disclosure (60-80% token reduction):

### Memory Tiers

| Tier | Storage | Purpose | Token Cost |
|---|---|---|---|
| **Working Memory** | In-process (gen_statem state) | Current task context, active reasoning | ~0 (in memory) |
| **Episodic Memory** | PostgreSQL + ETS cache | Specific events, tool results, session traces | ~500 tokens |
| **Semantic Memory** | pgvector (1536-dim) | Consolidated patterns, learned abstractions | ~100 tokens (index) |
| **Procedural Memory** | PostgreSQL | Reusable procedures, skill templates | On-demand |

### Memory Schema

```elixir
schema "sm_memories" do
  field :content, :string
  field :embedding, Pgvector.Ecto.Vector     # 1536-dim cosine similarity
  field :source_type, Ecto.Enum,
    values: [:conversation, :observation, :user_edit, :prd_event, :compaction]
  field :scope_type, Ecto.Enum,
    values: [:global, :project, :agent]
  field :scope_id, :string
  field :memory_type, Ecto.Enum,
    values: [:episodic, :semantic, :procedural]
  field :confidence, :float, default: 1.0    # Decays over time
  field :access_count, :integer, default: 0
  field :tags, {:array, :string}, default: []
  field :metadata, :map, default: %{}
  field :accessed_at, :utc_datetime

  timestamps()
end
```

### Hybrid Retrieval Pipeline (7 Stages)

```
Query → Scope Filter (ETS) → Type Filter → Tag Filter (GIN index) →
Semantic Search (pgvector cosine) → Recency Boost → Confidence Threshold →
Deduplication → Format for Context Injection
```

Scoring: `score = semantic * 0.7 + recency * 0.2 + access_frequency * 0.1`

### Task-Aware Memory Retrieval

Different task types use different memory weights (MemEvolve research, 17% improvement):

| Task Type | Episodic | Semantic | Procedural | Anti-Patterns |
|---|---|---|---|---|
| Exploration | 0.6 | 0.3 | 0.1 | 0.0 |
| Implementation | 0.15 | 0.5 | 0.35 | 0.0 |
| Debugging | 0.4 | 0.2 | 0.0 | 0.4 |
| Review | 0.3 | 0.5 | 0.0 | 0.2 |

### Confidence Decay (Oban Cron, Daily 3 AM)

| Memory Type | Decay Rate | Half-Life |
|---|---|---|
| Episodic | 0.98/day | ~34 days |
| Semantic | 0.995/day | ~138 days |
| Procedural | 0.999/day | ~693 days |

Access resets confidence to `max(current, 0.8)`. Memories below 0.1 are pruned.

### PRD Execution Tracking

```elixir
schema "sm_prd_executions" do
  field :prd_ref, :string
  field :prd_hash, :string
  field :title, :string
  field :status, Ecto.Enum,
    values: [:not_started, :in_progress, :paused, :blocked, :completed]
  field :progress, :map

  has_many :events, SamgitaMemory.PRD.Event
  has_many :decisions, SamgitaMemory.PRD.Decision
  timestamps()
end
```

Events (12 types): requirement_started, requirement_completed, decision_made, blocker_hit, blocker_resolved, test_passed, test_failed, revision, review_feedback, agent_handoff, error_encountered, rollback.

### Thinking Chains

Captures reasoning chains with revision tracking. On completion, chains are summarized and revision patterns are extracted as procedural memories.

### MCP Tools (10)

| Tool | Description |
|---|---|
| `remember` | Store a memory |
| `recall` | Retrieve relevant memories by semantic search |
| `forget` | Remove a memory |
| `prd_context` | Get full PRD execution state for resume |
| `prd_event` | Log a PRD execution event |
| `prd_decision` | Record a decision |
| `start_thinking` | Begin a reasoning chain |
| `think` | Add thought to active chain |
| `finish_thinking` | Complete chain, trigger summarization |
| `recall_reasoning` | Find similar past reasoning chains |

Token budget enforcement: default 4000 tokens max per MCP response. Truncation by relevance score.

---

## Data Model (samgita core)

### Core Schemas

| Schema | Table | Purpose |
|---|---|---|
| **Project** | `projects` | Top-level entity, identified by `git_url` (unique) |
| **Prd** | `prds` | PRD documents per project (draft → approved → in_progress → archived) |
| **Task** | `tasks` | Work items with priority, payload, hierarchical parent_task |
| **AgentRun** | `agent_runs` | Agent execution records with RARV state tracking |
| **Artifact** | `artifacts` | Generated code, docs, configs, deployments |
| **Snapshot** | `snapshots` | Periodic state checkpoints (retains last 10) |
| **Webhook** | `webhooks` | Event subscriptions with HMAC-SHA256 signatures |
| **Feature** | `features` | Feature flags with enable/disable/archive lifecycle |
| **Notification** | `notifications` | System notifications with delivery tracking |

### Project Schema

```elixir
schema "projects" do
  field :name, :string
  field :git_url, :string                    # Canonical identifier (unique)
  field :working_path, :string
  field :prd_content, :string
  field :phase, Ecto.Enum,
    values: [:bootstrap, :discovery, :architecture, :infrastructure,
             :development, :qa, :deployment, :business, :growth, :perpetual]
  field :status, Ecto.Enum,
    values: [:pending, :running, :paused, :completed, :failed]
  field :config, :map, default: %{}

  belongs_to :active_prd, Prd
  has_many :tasks, Task
  has_many :agent_runs, AgentRun
  has_many :artifacts, Artifact
  has_many :snapshots, Snapshot
  timestamps()
end
```

---

## Web Layer (samgita_web)

### Phoenix LiveView Dashboard

**Project Page** — Two-column PRD-centric layout:

```
┌──────────────────────────────────────────────────────┐
│ ← Dashboard    project-name    status  phase         │
│ git_url        ▓▓▓░░░░░░░ phase progress             │
├─────────────┬────────────────────────────────────────┤
│ PRDs        │  Selected PRD: title                   │
│ ┌─────────┐ │  [Start] [Pause] [Resume] [Restart]   │
│ │● init   │ │  [Stop] [Terminate]                    │
│ │ approved│ │                                        │
│ └─────────┘ │  ┌─ Activity Log ────────────────────┐ │
│             │  │ 14:23:01 [ORC] Entering bootstrap │ │
│ [+ New]     │  │ 14:23:02 [AGT] Planning approach  │ │
│             │  └───────────────────────────────────┘ │
│             │  Active Agents    Tasks                 │
│             │  ┌──────┐        ┌──────────────────┐  │
│             │  │pm act│        │bootstrap running │  │
│             │  └──────┘        └──────────────────┘  │
└─────────────┴────────────────────────────────────────┘
```

PRD is the unit of execution. Selecting a PRD reveals its scoped workspace: action buttons, activity log, agents, and tasks.

**Dashboard** — Overview of all projects with status, phase, and quick navigation.

**Other LiveView Pages**: Agents, MCP Servers, Skills, References.

### REST API

| Endpoint | Methods | Description |
|---|---|---|
| `/api/projects` | CRUD + pause/resume | Project management |
| `/api/projects/:id/tasks` | CRUD + retry | Task queue management |
| `/api/projects/:id/agents` | List | Agent run history |
| `/api/webhooks` | CRUD | Webhook subscriptions |
| `/api/notifications` | CRUD | Notification management |
| `/api/features` | CRUD + enable/disable/archive | Feature flags |
| `/api/health` | GET | Health check (public) |
| `/api/info` | GET | System info (public) |

Rate limited: 100 requests per 60 seconds per IP.

### Real-Time Events (PubSub)

| Event | Trigger | UI Effect |
|---|---|---|
| `:phase_changed` | Orchestrator transitions phase | Update phase progress bar |
| `:agent_state_changed` | Agent RARV cycle step | Update agent grid |
| `:agent_spawned` | New agent started | Add to agent grid |
| `:task_completed` | Task finishes | Refresh task list |
| `:activity_log` | Any significant event | Append to activity log stream |

---

## Autonomy Rules

### Core Principles (from loki-mode CONSTITUTION)

1. **Autonomy Preserves Momentum** — Decide, act, verify, adjust. No blocking on questions.
2. **Memory Matters More Than Reasoning** — Context retrieval is the bottleneck, not intelligence.
3. **Verification Builds Trust** — "It works" means "tests pass." Ship evidence, not assertions.
4. **Atomicity Enables Recovery** — Commit early, commit often. Each commit is a recovery point.
5. **Constraints Enable Speed** — Quality gates catch problems when they're cheap to fix.

### Agent Autonomy Rules (ABSOLUTE)

- **NEVER ask** — Do not output questions. Decide and act.
- **NEVER wait** — Do not pause for confirmation. Execute immediately.
- **NEVER stop** — There is always another improvement. Find it.
- **ALWAYS verify** — Code without tests is incomplete. Run tests.
- **ALWAYS commit** — Atomic commits after each task. Checkpoint progress.

### Priority Order (Conflict Resolution)

1. **Safety** — Don't break production, don't lose data, don't expose secrets
2. **Correctness** — Tests pass, specs match, contracts honored
3. **Quality** — Code review passed, standards met, maintainable
4. **Speed** — Autonomy, parallelization, minimal blocking

### Human Intervention

| Method | Effect |
|---|---|
| Pause button (UI) | Pauses after current task completes |
| Stop button (UI) | Stops project, sets status to completed |
| Terminate button (UI) | Kills all agents, marks project failed |
| Restart button (UI) | Stops and re-starts with same PRD from bootstrap |

---

## Configuration

### Config Key Mapping

| Config Key | OTP App | Purpose |
|---|---|---|
| `config :samgita, Samgita.Repo` | `:samgita` | PostgreSQL connection |
| `config :samgita, Oban` | `:samgita` | Job queues (agent_tasks, orchestration, snapshots) |
| `config :samgita, :claude_command` | `:samgita` | Claude CLI path |
| `config :samgita, :api_keys` | `:samgita` | REST API keys (empty = open access) |
| `config :samgita_memory, SamgitaMemory.Repo` | `:samgita_memory` | Memory database (same PG, needs PostgrexTypes) |
| `config :samgita_memory, Oban` | `:samgita_memory` | Memory jobs (name: SamgitaMemory.Oban) |
| `config :samgita_memory, :embedding_provider` | `:samgita_memory` | `:mock` (test) / `:anthropic` (prod) |
| `config :samgita_web, SamgitaWeb.Endpoint` | `:samgita_web` | Endpoint (port 3110) |
| `config :samgita_provider, :provider` | `:samgita_provider` | Provider module or `:mock` |
| `config :samgita_provider, :anthropic_api_key` | `:samgita_provider` | API key for Voyage embeddings |

---

## Implementation Status

### Completed

- [x] Umbrella project structure (4 apps)
- [x] Provider abstraction (samgita_provider) with Claude Code CLI integration
- [x] Core domain schemas (Project, Task, AgentRun, Prd, Artifact, Snapshot, Webhook, Feature, Notification)
- [x] Agent types module (37 types, 7 swarms, model selection)
- [x] Agent Worker gen_statem (RARV cycle state machine)
- [x] Project Orchestrator gen_statem (phase transitions)
- [x] Horde distributed supervision (AgentRegistry, AgentSupervisor)
- [x] Oban job queues (AgentTaskWorker, SnapshotWorker, WebhookWorker)
- [x] Memory system (samgita_memory) with pgvector, ETS caching, retrieval pipeline
- [x] PRD execution tracking, thinking chains, confidence decay
- [x] MCP tools (10 tools for memory, PRD, thinking)
- [x] Phoenix LiveView dashboard (project page, PRD-centric layout, activity log)
- [x] REST API with rate limiting
- [x] PubSub real-time events
- [x] Webhook delivery with HMAC-SHA256

### In Progress

- [ ] Bootstrap task worker (PRD parsing, requirement extraction, task backlog generation)
- [ ] Discovery phase implementation (competitive research, requirement analysis)
- [ ] Architecture phase (spec-first OpenAPI generation)
- [ ] Development phase orchestration (parallel task dispatch, blind review coordination)

### Planned

- [ ] Quality gates implementation (9-gate system)
- [ ] Blind review system (3 parallel reviewers + anti-sycophancy)
- [ ] Completion council (multi-agent voting)
- [ ] QA phase (test generation, security audit, load testing)
- [ ] Deployment phase (blue-green deploy, auto-rollback)
- [ ] Business operations phase
- [ ] Growth loop (perpetual optimization)
- [ ] Circuit breakers per agent type
- [ ] Git worktree parallel mode
- [ ] Skill system (composable agent configurations)

---

## Non-Goals

- **Multi-tenant SaaS** — single-user local tool, no authentication
- **Direct LLM API calls** — CLI-as-provider model only
- **Custom tool execution** — CLI tools handle their own tools; Samgita observes
- **GUI for memory editing** — dashboard is observation-only
- **CRDT/real-time sync** — PostgreSQL is the single source of truth

---

## Success Criteria

1. **End-to-end PRD pipeline** — Give it a PRD, walk away, come back to working code with tests
2. **Multi-agent parallelism** — 10+ agents working simultaneously on independent tasks
3. **Self-healing** — Agent crashes recovered by OTP supervisors within seconds
4. **Quality gates** — Code passes blind review + anti-sycophancy before acceptance
5. **Persistent memory** — Agent resumes work after restart with full context from memory system
6. **Real-time dashboard** — Live visibility into agent states, task queue, activity log
7. **Sub-500ms task dispatch** — Task creation to agent pickup latency
8. **Memory retrieval < 100ms** — ETS cache hit for active PRD context

---

## Research Foundations

| Research | Application in Samgita |
|---|---|
| **CONSENSAGENT** (ACL 2025) | Anti-sycophancy gate, blind review |
| **MemEvolve** (arXiv 2512.18746) | Task-aware memory retrieval weights |
| **Chain-of-Verification** (arXiv 2309.11495) | RARV verify step |
| **Boris Cherny** (production) | Self-verification loop (2-3x quality) |
| **Constitutional AI** (Anthropic) | Agent autonomy rules |
| **GoalAct** (arXiv) | Hierarchical task planning |

---

**Last Updated:** 2026-03-02
**Status:** Active
