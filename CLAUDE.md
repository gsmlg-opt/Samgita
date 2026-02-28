# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Samgita is a distributed multi-agent orchestration system built on Elixir/OTP. It transforms Product Requirements Documents into software through coordinated AI agent swarms running on the BEAM VM. Inspired by [loki-mode](https://github.com/asklokesh/loki-mode).

No authentication system by design — single-tenant, access controlled at infrastructure level (see `docs/CONSTITUTION.md`).

## Umbrella Structure

```
apps/
├── samgita_provider/ # Provider abstraction wrapping Claude Code CLI via ClaudeAgentSDK
├── samgita/          # Core business logic, Repo, Oban, Horde, PubSub
├── samgita_memory/   # Memory system with pgvector, PRD tracking, thinking chains
└── samgita_web/      # Phoenix web layer, LiveView, REST API
```

**Dependency graph**: `samgita_provider` (standalone) ← `samgita` ← `samgita_web`; `samgita_memory` (standalone)

## Development Commands

```bash
mix deps.get                          # Fetch all umbrella deps
mix ecto.setup                        # Create DB + migrate + seed
mix phx.server                        # Start server on port 3110
iex -S mix phx.server                 # Start with IEx shell

mix test                              # Run all tests (all apps)
mix test apps/samgita/test/samgita/projects_test.exs        # Single file
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs:10  # Single test

mix format                            # Format all apps
mix format --check-formatted          # CI check
mix credo --strict                    # Linting
mix dialyzer                          # Type checking

mix ecto.gen.migration name -r Samgita.Repo          # New migration (samgita app)
mix ecto.gen.migration name -r SamgitaMemory.Repo    # New migration (memory app)
mix ecto.migrate                      # Run migrations (both repos)
mix ecto.rollback -r Samgita.Repo     # Rollback samgita
mix ecto.rollback -r SamgitaMemory.Repo  # Rollback memory
```

## Architecture

### Config Key Mapping

| Config key | OTP app | Purpose |
|---|---|---|
| `config :samgita, Samgita.Repo` | `:samgita` | Database |
| `config :samgita, Oban` | `:samgita` | Job queues (agent_tasks, orchestration, snapshots) |
| `config :samgita, :claude_command` | `:samgita` | Claude CLI path |
| `config :samgita, :api_keys` | `:samgita` | REST API keys |
| `config :samgita_memory, SamgitaMemory.Repo` | `:samgita_memory` | Memory database (same PG, needs `PostgrexTypes`) |
| `config :samgita_memory, Oban` | `:samgita_memory` | Memory jobs (name: `SamgitaMemory.Oban`) |
| `config :samgita_memory, :embedding_provider` | `:samgita_memory` | `:mock` (test) / `:anthropic` (prod) |
| `config :samgita_web, SamgitaWeb.Endpoint` | `:samgita_web` | Endpoint/port |
| `config :samgita_web, dev_routes:` | `:samgita_web` | Dev dashboard |
| `config :samgita_provider, :provider` | `:samgita_provider` | Provider module or `:mock` |
| `config :samgita_provider, :anthropic_api_key` | `:samgita_provider` | API key (for Voyage embeddings) |
| `config :bun, samgita_web:` | `:bun` | JS bundler |
| `config :tailwind, samgita_web:` | `:tailwind` | CSS |

### Supervision Trees

**Samgita.Application** (core app):
```
Samgita.Repo
DNSCluster
Cluster.Supervisor (libcluster)
Phoenix.PubSub (name: Samgita.PubSub)
Finch (name: Samgita.Finch)
Samgita.Cache (ETS with TTL + PubSub invalidation)
Horde.Registry (Samgita.AgentRegistry)
Horde.DynamicSupervisor (Samgita.AgentSupervisor)
Oban (queues: agent_tasks:100, orchestration:10, snapshots:5)
```

**SamgitaMemory.Application** (memory app):
```
SamgitaMemory.Repo (separate Repo, same Postgres DB)
SamgitaMemory.Cache.Supervisor
├── MemoryTable (ETS LRU, max 10k entries)
└── PrdTable (ETS LRU, max 100 entries)
SamgitaMemory.Formation.Supervisor (telemetry handlers)
Oban (name: SamgitaMemory.Oban, queues: embeddings:5, compaction:2, summarization:3)
```

**SamgitaWeb.Application** (web app):
```
SamgitaWeb.Telemetry
SamgitaWeb.Endpoint
```

### gen_statem State Machines

**Agent Worker** (`apps/samgita/lib/samgita/agent/worker.ex`):
```
:idle → :reason → :act → :reflect → :verify
         ↑                            │
         └────── on failure ──────────┘
```
Uses Horde.Registry for distributed naming. RARV cycle is the core execution model.

**Project Orchestrator** (`apps/samgita/lib/samgita/project/orchestrator.ex`):
```
:bootstrap → :discovery → :architecture → :infrastructure →
:development → :qa → :deployment → :business → :growth → :perpetual
```
Manages project lifecycle phases and coordinates agent spawning.

### Claude Integration (SamgitaProvider)

**SamgitaProvider** (`apps/samgita_provider/`) — provider abstraction:
- Invokes `claude` CLI directly via `System.cmd/3` in print mode with JSON output
- Used by `Samgita.Agent.Claude`, `PlaygroundLive`, and `PrdChatLive`
- All Claude Code tools available automatically (CLI manages its own tools)
- `:mock` atom provider for tests (returns `"mock response"`)
- CLI command configurable via `config :samgita_provider, :claude_command`
- See `docs/claude-integration.md` for full documentation

### Oban Workers

**samgita app:**
- **AgentTaskWorker** — queue: `agent_tasks`, max attempts: 5. Dispatches tasks to agent workers via Horde.
- **SnapshotWorker** — queue: `snapshots`, max attempts: 3. Periodic state snapshots, retains last 10.
- **WebhookWorker** — queue: `agent_tasks`, max attempts: 5. Delivers webhooks with HMAC-SHA256 signatures.

**samgita_memory app** (uses named Oban instance `SamgitaMemory.Oban`):
- **Embedding** — queue: `embeddings`. Generates vector embeddings (mock or Anthropic Voyage API).
- **Compaction** — queue: `compaction`, cron: daily 3 AM. Confidence decay (episodic 0.98/day, semantic 0.995, procedural 0.999) and pruning below 0.1.
- **Summarize** — queue: `summarization`. Thinking chain summaries + PRD execution compaction.

### Web Layer

**LiveView pages** (10): Dashboard, ProjectForm, Project detail, PrdChat, Agents, MCP, Skills, References (index+show), Playground

**REST API**: `/api/projects` (CRUD + pause/resume), `/api/projects/:id/tasks`, `/api/projects/:id/agents`, `/api/webhooks`, `/api/notifications`, `/api/features` (CRUD + enable/disable/archive). Rate limited (100 req/60s via `SamgitaWeb.Plugs.RateLimit`).

### Data Model

Core Ecto schemas in `apps/samgita/lib/samgita/domain/`:
- **Project** — `git_url` is canonical identifier (unique), phases: bootstrap→perpetual
- **Task** — hierarchical (parent_task_id), tracks attempts/tokens/duration
- **AgentRun** — tracks node, pid, metrics across 37 agent types
- **Artifact** — generated code/docs/configs
- **Memory** — legacy (superseded by samgita_memory)
- **Snapshot** — periodic state checkpoints
- **Webhook** — event subscriptions
- **Prd** / **ChatMessage** — interactive PRD creation via chat
- **Feature** — feature flags with enable/disable/archive lifecycle
- **Notification** — system notifications with status transitions

**samgita_memory schemas** (table prefix `sm_` to avoid collision):
- **Memories.Memory** — episodic/semantic/procedural with 1536-dim pgvector embeddings
- **Memories.ThinkingChain** — reasoning chain capture with revision tracking
- **PRD.Execution** — PRD execution state tracking
- **PRD.Event** — event sourcing (12 event types)
- **PRD.Decision** — decision records with alternatives

### Memory System (`samgita_memory`)

Standalone app providing persistent memory with vector similarity search.

**Hybrid Retrieval Pipeline** (7 stages): scope filter → type filter → tag filter → semantic search (cosine similarity) → recency boost → confidence threshold → deduplication.

Configurable weights: semantic 0.7, recency 0.2, access frequency 0.1.

**MCP Tools** (10 tools defined in `SamgitaMemory.MCP.Tools`):
- `remember` / `recall` / `forget` — memory CRUD
- `prd_context` / `prd_event` / `prd_decision` — PRD execution tracking
- `start_thinking` / `think` / `finish_thinking` / `recall_reasoning` — thinking chains

Token budget truncation (default 4000 tokens) prevents oversized MCP responses.

**pgvector Notes:**
- Requires `Postgrex.Types.define/3` with `Pgvector.Extensions.Vector` in `SamgitaMemory.PostgrexTypes`
- pgvector extension must be built from source for PostgreSQL 14 (brew packages cover 17/18 only)
- Ecto `update_all` can't do multiplicative updates — use raw SQL for confidence decay

## Critical Constraints

- Use `gen_statem` for Orchestrator and Agent workers (not GenServer)
- Postgres as single source of truth (not Mnesia)
- Oban for distributed task queue
- Horde for process distribution
- Phoenix.PubSub for real-time updates
- LiveView for UI (not polling)
- No authentication system (infrastructure-level access control)
- `git_url` is the canonical project identifier

## Frontend & UI Conventions

- **Tailwind CSS** for all styling, Typography plugin (`prose` classes) for content
- **@duskmoon-dev** npm packages for UI components (e.g., `@duskmoon-dev/el-markdown` for markdown rendering)
- Custom Elements registered in `apps/samgita_web/assets/js/custom-elements.ts`
- **Bun** as JS bundler (not npm/webpack), TypeScript enabled
- Frontend assets live in `apps/samgita_web/` — `package.json` references deps via `../../deps/` paths

## Agent Types (37)

Defined in `apps/samgita/lib/samgita/agent/types.ex` across 7 swarms:
- **Engineering** (8): eng-frontend, eng-backend, eng-database, eng-mobile, eng-api, eng-qa, eng-perf, eng-infra
- **Operations** (8): ops-devops, ops-sre, ops-security, ops-monitor, ops-incident, ops-release, ops-cost, ops-compliance
- **Business** (8): biz-marketing, biz-sales, biz-finance, biz-legal, biz-support, biz-hr, biz-investor, biz-partnerships
- **Data** (3): data-ml, data-eng, data-analytics
- **Product** (3): prod-pm, prod-design, prod-techwriter
- **Growth** (4): growth-hacker, growth-community, growth-success, growth-lifecycle
- **Review** (3): review-code, review-business, review-security

Reference docs in `apps/samgita/priv/references/` (20 markdown files from loki-mode).

## Important References

- **PRD.md** — Product requirements, data models, API spec
- **PLAN.md** — 5-phase implementation plan
- **docs/CONSTITUTION.md** — Security model and architectural constraints
- **loki-mode/** — Original implementation (gitignored, for reference)
- **examples/** — SamgitaProvider usage examples
