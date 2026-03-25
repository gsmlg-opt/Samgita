# PRD: Samgita — Autonomous Multi-Agent Orchestration System

**One sentence:** Submit a PRD, walk away, come back to production-ready code with tests and CI/CD.

Samgita is an Elixir/OTP reimplementation of [loki-mode](https://github.com/asklokesh/loki-mode). It replaces 8,766 lines of bash orchestration with OTP supervision trees, Oban job queues, Horde distributed processes, PostgreSQL persistence, and Phoenix LiveView real-time dashboards.

---

## Problem

Building software from a PRD requires coordinating dozens of specialized tasks across agents working in parallel. Current approaches fail:

| Approach | Failure Mode |
|---|---|
| Single-agent assistants | Sequential, hits context limits, no self-healing |
| loki-mode (bash/Python) | Fragile state, no fault tolerance, no real-time observability |
| Direct LLM API calls | Must reimplement tool execution, loses CLI-native capabilities |

Samgita solves this by treating Claude CLI as a supervised OTP process — getting all of Claude Code's capabilities (file tools, MCP, Task tool) while adding OTP-grade fault tolerance, distributed supervision, and a real-time observability dashboard.

---

## Core Workflow

```
PRD
 │
 ▼
Bootstrap ──► Discovery ──► Architecture ──► Infrastructure
                                                    │
                                                    ▼
                                            Development (RARV loop)
                                                    │
                                                    ▼
                                            QA (9 quality gates)
                                                    │
                                                    ▼
                                   Deployment ──► Business ──► Growth ──► Perpetual
```

### The RARV Cycle

The atomic unit of all agent work. Every Claude invocation follows:

```
REASON  — Read CONTINUITY.md + memory context, identify highest-priority unblocked task
   │
   ▼
ACT     — Execute: write code, run commands, generate artifacts, commit atomically
   │
   ▼
REFLECT — Did it work? Update working memory, record learnings to samgita_memory
   │
   ▼
VERIFY  — Run tests, check compilation, validate against spec
   │
   ├──[PASS]──► Mark task complete (DB), notify Orchestrator, return to REASON
   │
   └──[FAIL]──► Capture error as episodic memory, rollback if needed
                3 failures → simpler approach
                5 failures → dead-letter queue, move on
```

Implemented as a `gen_statem` state machine in `Samgita.Agent.Worker`:
```
:idle → :reason → :act → :reflect → :verify
          ↑                              │
          └────────── on failure ────────┘
```

---

## Architecture

### Umbrella Apps

```
apps/
├── samgita_provider/   # Claude CLI invocation (System.cmd, JSON output parsing)
├── samgita/            # Core: Orchestrator, Agent.Worker, Oban workers, domain schemas
├── samgita_memory/     # pgvector memory (episodic/semantic/procedural), MCP tools
└── samgita_web/        # Phoenix LiveView dashboard, REST API
```

Dependency order: `samgita_provider` ← `samgita` ← `samgita_web`; `samgita_memory` standalone (shared Postgres, `sm_` table prefix).

### Provider Model

Samgita does **not** call LLM APIs directly. It orchestrates the Claude CLI as a supervised OTP process:

```
Agent.Worker (gen_statem)
  → SamgitaProvider.ClaudeCode.query/2
  → System.cmd("claude", ["--print", "--output-format", "json",
                          "--dangerously-skip-permissions",
                          "--no-session-persistence", "-p", prompt])
  → Parse JSON response
  → RARV cycle decides next action
```

The CLI handles tool execution, context management, conversation state, rate limiting, and model selection internally. Samgita handles **orchestration**.

### Supervision Tree (per project)

```
Horde.DynamicSupervisor (Samgita.AgentSupervisor)
└── Samgita.Project.Supervisor
    ├── Samgita.Project.Orchestrator (gen_statem, phase state machine)
    └── [Agent Workers via Horde — spawned on demand]
        └── Samgita.Agent.Worker (gen_statem, RARV cycle)
```

On crash, OTP supervisors restart agents. On system restart, `Project.Recovery` restores running projects from database state.

---

## Agent Model

### 37 Agent Types, 7 Swarms

| Swarm | Agents |
|---|---|
| Engineering (8) | eng-frontend, eng-backend, eng-database, eng-mobile, eng-api, eng-qa, eng-perf, eng-infra |
| Operations (8) | ops-devops, ops-sre, ops-security, ops-monitor, ops-incident, ops-release, ops-cost, ops-compliance |
| Business (8) | biz-marketing, biz-sales, biz-finance, biz-legal, biz-support, biz-hr, biz-investor, biz-partnerships |
| Data (3) | data-ml, data-eng, data-analytics |
| Product (3) | prod-pm, prod-design, prod-techwriter |
| Growth (4) | growth-hacker, growth-community, growth-success, growth-lifecycle |
| Review (3) | review-code, review-business, review-security |

### Model Tiers

| Tier | Model | Use Case |
|---|---|---|
| Planning | Opus | prod-pm, eng-infra (architecture, PRD analysis) |
| Development | Sonnet | eng-*, ops-*, biz-*, data-*, growth-* (implementation) |
| Fast | Haiku | eng-qa, review-* (tests, linting, docs) |

---

## Project Lifecycle

### Phases

| Phase | Key Output |
|---|---|
| Bootstrap | Working directory, validated PRD, initial task backlog |
| Discovery | Requirements analysis, competitive research, refined backlog |
| Architecture | OpenAPI spec, tech stack decision, project scaffolding |
| Infrastructure | CI/CD, database provisioning, monitoring |
| Development | Source code, tests, git commits (RARV loop per task) |
| QA | 9 quality gates passed, security audit, load testing |
| Deployment | Blue-green release, smoke tests, auto-rollback on failure |
| Business | Marketing site, billing, legal docs, support system |
| Growth | A/B testing, performance tuning, user feedback loops |
| Perpetual | Dependency updates, security patches, feature refinement |

### Phase Transitions (Orchestrator gen_statem)

Advance requires: all tasks `:completed`, quality gates passed, git checkpoint created, no unresolved critical/high issues. Stagnation detection at 5 iterations with no progress.

---

## Quality Gates — 9-Gate System

| Gate | Name | Block Condition |
|---|---|---|
| 1 | Input Guardrails | Prompt injection, constraint violation |
| 2 | Static Analysis | Lint/type/compile errors |
| 3 | Blind Review | 3 independent reviewers (code, business-logic, security) find defects |
| 4 | Anti-Sycophancy | Unanimous approval without challenge → spawn devil's advocate |
| 5 | Output Guardrails | Secrets exposed, spec non-compliance |
| 6 | Severity Blocking | Critical/High/Medium issues unresolved |
| 7 | Test Coverage | Tests fail OR coverage < 80% |
| 8 | Mock Detector | Tests never import source, tautological assertions |
| 9 | Test Mutation Detector | Assertion values changed alongside implementation |

Blind review: 3 reviewers run in parallel, cannot see each other's findings (prevents anchoring bias). Anti-sycophancy: if all 3 approve unanimously, devil's advocate reviewer spawned automatically (CONSENSAGENT, ACL 2025 — reduces false positives 30%).

---

## Memory System (samgita_memory)

### Three Tiers

| Tier | Storage | Purpose |
|---|---|---|
| Working | `.samgita/CONTINUITY.md` file in project | Per-iteration Claude context (written before each RARV cycle) |
| Episodic | PostgreSQL `sm_memories` | Specific events, tool results, session traces |
| Semantic | pgvector 1536-dim embeddings | Consolidated patterns, learned abstractions |
| Procedural | PostgreSQL `sm_memories` | Reusable procedures, skill templates |

### Retrieval Pipeline (7 stages)

```
Query → Scope Filter → Type Filter → Tag Filter (GIN index) →
Semantic Search (pgvector cosine) → Recency Boost → Confidence Threshold →
Deduplication → Inject into RARV prompt
```

Score: `semantic × 0.7 + recency × 0.2 + access_frequency × 0.1`

### Memory Lifecycle

- **Capture**: Agent.Worker's `reflect` state stores episodic memories after each task
- **Retrieval**: `reason` state fetches relevant memories, writes CONTINUITY.md
- **Decay**: Oban cron daily at 3 AM (episodic: 0.98/day, semantic: 0.995/day, procedural: 0.999/day)
- **Pruning**: Memories below 0.1 confidence removed

### MCP Integration

`SamgitaMemory.MCP.Tools` exposes 10 tools via stdio MCP server (`mix samgita.mcp`). Register in `~/.claude/mcp.json` so Claude has `remember`/`recall`/`think` available during every RARV cycle.

| Tool | Purpose |
|---|---|
| `remember` / `recall` / `forget` | Memory CRUD |
| `prd_context` / `prd_event` / `prd_decision` | PRD execution tracking |
| `start_thinking` / `think` / `finish_thinking` / `recall_reasoning` | Thinking chains |

---

## Task System

Tasks flow through:
```
pending → running → completed
                 → failed → (retry, max 5) → dead_letter
```

Tasks dispatched via `Samgita.Workers.AgentTaskWorker` (Oban, `agent_tasks` queue, 100 concurrency). **Task completion is driven by Agent.Worker** after RARV verify step, not by the Oban dispatcher.

---

## Web Layer

### Phoenix LiveView Dashboard

**Project Page** — PRD-centric layout:
```
┌─────────────────────────────────────────────────┐
│ ← Dashboard   project-name   status   phase     │
│ git_url        ▓▓▓░░░░ phase progress            │
├──────────────┬──────────────────────────────────┤
│ PRDs         │  Selected PRD: title              │
│ ┌──────────┐ │  [Start] [Pause] [Resume] [Stop]  │
│ │● approved│ │                                   │
│ └──────────┘ │  ┌─ Activity Log ───────────────┐ │
│              │  │ 14:23 [ORC] Entering bootstrap│ │
│ [+ New PRD]  │  │ 14:24 [AGT] Claude CLI called │ │
│              │  └──────────────────────────────┘ │
│              │  Agents          Tasks             │
│              │  [pm:act] ...    bootstrap:done    │
└──────────────┴──────────────────────────────────┘
```

PRD is the unit of execution. Activity log streams in real time via PubSub.

### Other Pages
- **Dashboard** — All projects, live task progress counts
- **Agents** — Active agent runs with RARV state
- **MCP Servers** — Lists servers from `~/.claude/mcp.json`
- **Skills** — 37 agent types with descriptions (from `Agent.Types.all()`)
- **References** — Browse 20 reference markdown files

### REST API

`/api/projects` (CRUD + pause/resume/start/stop/restart/terminate), `/api/projects/:id/tasks`, `/api/projects/:id/agents`, `/api/webhooks`, `/api/notifications`, `/api/features`. Rate limited: 100 req/60s per IP.

---

## Autonomy Rules

1. **NEVER ask** — Decide and act. Questions block the pipeline.
2. **NEVER wait** — Execute immediately.
3. **ALWAYS verify** — Code without passing tests is incomplete.
4. **ALWAYS commit** — Atomic git checkpoint after each task.
5. **Conflict priority**: Safety > Correctness > Quality > Speed

---

## Implementation Status

### Built and Working

- [x] Umbrella structure (4 apps), devenv.nix setup
- [x] Claude CLI provider (System.cmd, JSON output, error classification)
- [x] Agent.Worker gen_statem — full RARV cycle with circuit breaker
- [x] Project.Orchestrator gen_statem — 10-phase lifecycle, stagnation detection, pause/resume
- [x] Horde distributed supervision (AgentRegistry + AgentSupervisor)
- [x] Oban workers: AgentTaskWorker, BootstrapWorker, SnapshotWorker, WebhookWorker, QualityGateWorker
- [x] 9 quality gates: input/output guardrails, blind review, anti-sycophancy, coverage, mock/mutation detectors
- [x] Completion council (multi-agent voting, 2/3 required)
- [x] samgita_memory: pgvector embeddings, 7-stage retrieval, 3-tier memory, MCP tools
- [x] PRD execution tracking (event sourcing, 12 event types), thinking chains
- [x] Phoenix LiveView (8 pages), REST API (10 controllers), PubSub events
- [x] Git worktree operations, commit with agent metadata
- [x] Webhook delivery with HMAC-SHA256
- [x] Project.Recovery (restart running projects on boot)
- [x] All 12 database migrations

### Fixed (previously blocking)

- [x] `AgentTaskWorker` synchronous wait — uses `Process.monitor` + `receive` with 10min timeout
- [x] CONTINUITY.md written in `reason` state before each Claude invocation
- [x] `samgita_memory` wired as umbrella dep of `samgita`
- [x] PRD saves to `Prd` schema via `Samgita.Prds` (not `projects.prd_content`)
- [x] `config/test.exs` uses `System.get_env("USER", "postgres")` instead of hardcoded username
- [x] McpLive reads from `~/.claude/mcp.json` dynamically
- [x] SkillsLive uses `Agent.Types.all()` for real agent type data
- [x] PrdChatLive auto-starts project on PRD approval via `maybe_start_project/3`

### Planned Enhancements

- [ ] `mix samgita.mcp` — expose memory as stdio MCP server for Claude
- [ ] Interactive PRD chat (Claude-assisted PRD authoring in PrdChatLive)
- [ ] Live task progress on Dashboard (per-project PubSub subscriptions)
- [ ] Enhanced git commit trailers with agent metadata

---

## Non-Goals

- Multi-tenant SaaS or authentication (infrastructure-level access control only)
- Direct LLM API calls (CLI-as-provider only)
- GUI for memory editing (observation-only dashboard)
- CRDT real-time sync (PostgreSQL is the single source of truth)

---

## Success Criteria

1. Submit a PRD → walk away → return to working code with tests in the target git repo
2. 10+ agents working simultaneously on independent tasks (Horde + Oban concurrency: 100)
3. Agent crash → OTP supervisor restarts it within seconds, task retried automatically
4. All 9 quality gates pass before phase advances to QA
5. Activity log streams every state transition in real time via LiveView
6. Agents resume work after system restart with full memory context from samgita_memory
7. Task dispatch latency < 500ms (Oban claim to agent pickup)
8. Memory retrieval < 100ms (ETS cache hit for active project context)

---

**Last Updated:** 2026-03-26
**Status:** Active Development — see [docs/plan.md](plan.md) for the implementation roadmap
