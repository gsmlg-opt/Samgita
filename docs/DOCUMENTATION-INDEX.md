# Samgita Documentation Index

Welcome to the Samgita documentation. This index will help you find the information you need.

## Quick Links

- **[Getting Started](./GETTING-STARTED.md)** — First-time setup and your first project
- **[Architecture](./ARCHITECTURE.md)** — System design and technical architecture
- **[API Reference](./API.md)** — Complete REST API documentation
- **[Deployment Guide](./DEPLOYMENT.md)** — Production deployment instructions
- **[Constitution](./CONSTITUTION.md)** — Core design principles and rationale
- **[Claude Integration](./claude-integration.md)** — Provider architecture details

---

## Documentation by Role

### For New Users

Start here if you're new to Samgita:

1. **[Getting Started Guide](./GETTING-STARTED.md)**
   - Installation and setup
   - Creating your first project
   - Understanding the dashboard
   - Working with PRDs
   - Common workflows

2. **[README.md](../README.md)**
   - Project overview
   - Quick installation
   - Basic usage
   - Feature highlights

### For Developers

Building on or extending Samgita:

1. **[Architecture Guide](./ARCHITECTURE.md)**
   - System overview
   - Umbrella structure
   - Supervision trees
   - Agent model (RARV cycle)
   - Task system
   - Memory system
   - Database schema
   - Performance considerations

2. **[Claude Integration](./claude-integration.md)**
   - Provider abstraction
   - ClaudeCode implementation
   - Configuration
   - Usage patterns
   - Error handling

3. **[CLAUDE.md](../CLAUDE.md)** (Project instructions for Claude)
   - Development commands
   - Key patterns
   - Config mappings
   - Testing guidelines

### For Integrators

Building integrations with Samgita:

1. **[API Reference](./API.md)**
   - REST endpoints
   - Request/response formats
   - Webhook events
   - Authentication
   - Rate limiting
   - Client examples (Python, cURL)

2. **[Webhooks](#webhooks)**
   - Event types
   - Payload formats
   - Signature verification
   - Best practices

### For Operators

Deploying and managing Samgita:

1. **[Deployment Guide](./DEPLOYMENT.md)**
   - Production requirements
   - Building releases
   - Environment configuration
   - Docker deployment
   - Systemd service
   - Cloud platforms (Fly.io, Render)
   - Security hardening
   - Monitoring & logging
   - Backup & recovery
   - Scaling strategies

2. **[Getting Started - Troubleshooting](./GETTING-STARTED.md#troubleshooting)**
   - Common issues
   - Debug procedures
   - Log analysis

---

## Documentation by Topic

### Core Concepts

#### RARV Cycle

The fundamental unit of agent work: **Reason → Act → Reflect → Verify**

- **Reason:** Load context, identify task
- **Act:** Execute via LLM provider
- **Reflect:** Update memory, record learnings
- **Verify:** Run tests, validate output, retry on failure

See: [Architecture - Agent Model](./ARCHITECTURE.md#agent-model)

#### Agent Types

37 specialized agent types across 7 swarms:

- **Engineering** (8 agents): frontend, backend, database, mobile, api, qa, perf, infra
- **Operations** (8 agents): devops, sre, security, monitor, incident, release, cost, compliance
- **Business** (8 agents): marketing, sales, finance, legal, support, hr, investor, partnerships
- **Data** (3 agents): ml, eng, analytics
- **Product** (3 agents): pm, design, techwriter
- **Growth** (4 agents): hacker, community, success, lifecycle
- **Review** (3 agents): code, business, security

See: [Architecture - Agent Model](./ARCHITECTURE.md#agent-types--model-selection)

#### Project Lifecycle Phases

```
Bootstrap → Discovery → Architecture → Infrastructure →
Development → QA → Deployment → Business → Growth → Perpetual
```

Each phase has specific completion criteria and spawns appropriate agents.

See: [PRD.md](../PRD.md#project-lifecycle-phases)

#### Memory System

Three-tier architecture:

- **Working Memory:** In-process (gen_statem state)
- **Episodic Memory:** PostgreSQL (recent events, specific facts)
- **Semantic Memory:** pgvector (patterns, abstractions)
- **Procedural Memory:** Skills, templates

Hybrid retrieval combines semantic similarity, recency, and access frequency.

See: [Architecture - Memory System](./ARCHITECTURE.md#memory-system)

### Architecture

#### Umbrella Structure

4 independent OTP applications:

- `samgita_provider` — Provider abstraction (standalone)
- `samgita` — Core domain logic
- `samgita_memory` — Memory system (standalone, shared DB)
- `samgita_web` — Web interface

See: [Architecture - Umbrella Structure](./ARCHITECTURE.md#umbrella-structure)

#### Provider Model (CLI-as-Provider)

Samgita orchestrates CLI tools (Claude Code, Codex) as supervised OTP processes instead of calling LLM APIs directly.

**Why CLI?**
- Tools handled by CLI (Read, Write, Edit, Bash, etc.)
- Authentication managed by CLI
- Context tracking built-in
- Rate limiting automatic

See: [Claude Integration](./claude-integration.md) | [Constitution - Provider Architecture](./CONSTITUTION.md#provider-architecture--cli-first)

#### Supervision Trees

- **Samgita.Application:** Repo, PubSub, Cache, Horde (Registry + DynamicSupervisor), Oban
- **SamgitaMemory.Application:** Repo, Cache, Oban (named instance)
- **SamgitaWeb.Application:** Telemetry, Endpoint

Agents run as `gen_statem` processes supervised by Horde for distributed fault tolerance.

See: [Architecture - Supervision Trees](./ARCHITECTURE.md#supervision-trees)

#### Database Schema

**Core tables:**
- `projects` — Top-level entity, identified by `git_url` (unique)
- `prds` — Product requirements documents
- `tasks` — Work items with priority, payload, hierarchical structure
- `agent_runs` — Agent execution records with RARV state
- `artifacts` — Generated code, docs, configs
- `snapshots` — Periodic state checkpoints
- `webhooks` — Event subscriptions
- `features` — Feature flags
- `notifications` — System notifications

**Memory tables** (sm_ prefix):
- `sm_memories` — 1536-dim pgvector embeddings
- `sm_prd_executions` — PRD execution tracking
- `sm_prd_events` — Event sourcing (12 event types)
- `sm_thinking_chains` — Reasoning chain capture

See: [Architecture - Database Schema](./ARCHITECTURE.md#database-schema)

### Development

#### Running Tests

```bash
# All tests
mix test

# Specific app
mix test apps/samgita_memory/test

# Specific file
mix test apps/samgita/test/samgita/projects_test.exs

# Specific test
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs:10

# With coverage
mix test --cover
```

See: [CLAUDE.md - Development Commands](../CLAUDE.md#development-commands)

#### Code Quality

```bash
# Format code
mix format

# Check formatting (CI)
mix format --check-formatted

# Linting
mix credo --strict

# Type checking
mix dialyzer
```

#### Database Migrations

```bash
# Create migration (samgita app)
mix ecto.gen.migration name -r Samgita.Repo

# Create migration (memory app)
mix ecto.gen.migration name -r SamgitaMemory.Repo

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback -r Samgita.Repo
mix ecto.rollback -r SamgitaMemory.Repo
```

### Configuration

#### Config Key Mapping

| Config Key | OTP App | Purpose |
|---|---|---|
| `config :samgita, Samgita.Repo` | `:samgita` | Database |
| `config :samgita, Oban` | `:samgita` | Job queues |
| `config :samgita, :claude_command` | `:samgita` | Claude CLI path |
| `config :samgita, :api_keys` | `:samgita` | REST API keys |
| `config :samgita_memory, SamgitaMemory.Repo` | `:samgita_memory` | Memory database |
| `config :samgita_memory, Oban` | `:samgita_memory` | Memory jobs (named instance) |
| `config :samgita_memory, :embedding_provider` | `:samgita_memory` | `:mock` or `:anthropic` |
| `config :samgita_web, SamgitaWeb.Endpoint` | `:samgita_web` | Endpoint/port |
| `config :samgita_provider, :provider` | `:samgita_provider` | Provider module or `:mock` |
| `config :samgita_provider, :anthropic_api_key` | `:samgita_provider` | API key |

See: [CLAUDE.md - Architecture](../CLAUDE.md#architecture)

#### Environment Variables

Production environment variables:

- `DATABASE_URL` — PostgreSQL connection
- `SECRET_KEY_BASE` — Phoenix secret (generate with `mix phx.gen.secret`)
- `PHX_HOST` — Public hostname
- `PORT` — HTTP port (default: 3110)
- `ANTHROPIC_API_KEY` — For embeddings (Voyage API)
- `CLAUDE_COMMAND` — Path to Claude CLI (default: "claude")
- `API_KEYS` — Comma-separated API keys (empty = no auth)

See: [Deployment - Environment Configuration](./DEPLOYMENT.md#environment-variables)

### API

#### Authentication

API keys configured via `config :samgita, :api_keys`.

**Important:** When empty (`[]`), all requests pass through (no auth). This is default for dev/test.

Production: Set `API_KEYS=key1,key2,key3` environment variable.

See: [API - Authentication](./API.md)

#### Rate Limiting

Default: 100 requests per 60 seconds per IP.

Headers returned:
- `X-RateLimit-Limit: 100`
- `X-RateLimit-Remaining: 95`
- `X-RateLimit-Reset: 1709481825`

See: [API - Rate Limiting](./API.md#rate-limiting)

#### Webhooks

Event-driven notifications via HTTP POST with HMAC-SHA256 signatures.

**Event types:**
- Project: `created`, `started`, `paused`, `completed`, `failed`
- Phase: `phase_changed`
- Agent: `spawned`, `state_changed`, `failed`, `completed`
- Task: `created`, `started`, `completed`, `failed`
- PRD: `created`, `approved`, `completed`

See: [API - Webhook Payloads](./API.md#webhook-payloads)

### Security

#### No Authentication System

**By design**, Samgita has no user authentication or account system.

**Access model:** Anyone who can access the application is an administrator with full privileges.

**Security:** Enforced at infrastructure level (firewall, VPN, SSH keys, localhost binding), not application level.

See: [Constitution - No Authentication](./CONSTITUTION.md#no-authentication-or-account-system) | [README - Security Model](../README.md#security--access-model)

#### Deployment Security

- Run on localhost for personal use
- Use firewall rules to restrict network access
- Deploy behind VPN for team access
- Use reverse proxy with authentication if needed
- **Never expose directly to public internet** without additional security layers

See: [Deployment - Security Hardening](./DEPLOYMENT.md#security-hardening)

### Troubleshooting

Common issues and solutions:

- **Server won't start:** Check database connection, port availability, environment variables
- **Database connection errors:** Verify PostgreSQL running, check credentials, ensure pgvector installed
- **Claude CLI not found:** Install Claude CLI, verify `which claude`, set `CLAUDE_COMMAND` env var
- **Agents not spawning:** Check Horde registry, Oban queues, review logs
- **Memory issues (pgvector):** Install pgvector from source for PostgreSQL 14
- **Frontend assets not loading:** Install bun, run `mix assets.deploy`

See: [Getting Started - Troubleshooting](./GETTING-STARTED.md#troubleshooting) | [Deployment - Troubleshooting](./DEPLOYMENT.md#troubleshooting)

---

## Reference Materials

### Project Files

- **[README.md](../README.md)** — Project overview and quick start
- **[PRD.md](../PRD.md)** — Product Requirements Document (comprehensive spec)
- **[CLAUDE.md](../CLAUDE.md)** — Project instructions for Claude Code
- **[LICENSE](../LICENSE)** — AGPL License

### Code Organization

```
apps/
├── samgita_provider/      # Provider abstraction
│   ├── lib/
│   │   ├── samgita_provider.ex
│   │   ├── samgita_provider/
│   │   │   ├── provider.ex         # Behaviour
│   │   │   └── claude_code.ex      # Implementation
│   └── test/
│
├── samgita/               # Core domain
│   ├── lib/samgita/
│   │   ├── application.ex
│   │   ├── projects.ex             # Context
│   │   ├── tasks.ex                # Context
│   │   ├── domain/                 # Ecto schemas
│   │   ├── agent/
│   │   │   ├── worker.ex           # gen_statem RARV cycle
│   │   │   ├── types.ex            # 37 agent types
│   │   │   └── claude.ex           # Provider wrapper
│   │   ├── project/
│   │   │   └── orchestrator.ex     # gen_statem phase machine
│   │   ├── workers/                # Oban workers
│   │   ├── cache.ex                # ETS + PubSub
│   │   └── repo.ex
│   ├── priv/repo/migrations/
│   └── test/
│
├── samgita_memory/        # Memory system
│   ├── lib/samgita_memory/
│   │   ├── application.ex
│   │   ├── memories/
│   │   │   └── memory.ex           # pgvector schema
│   │   ├── prd/
│   │   │   ├── execution.ex
│   │   │   ├── event.ex
│   │   │   └── decision.ex
│   │   ├── thinking_chain.ex
│   │   ├── retrieval/              # Hybrid retrieval
│   │   ├── mcp/
│   │   │   └── tools.ex            # 10 MCP tools
│   │   ├── workers/                # Oban workers
│   │   └── repo.ex
│   ├── priv/repo/migrations/
│   └── test/
│
└── samgita_web/           # Web interface
    ├── lib/samgita_web/
    │   ├── application.ex
    │   ├── endpoint.ex
    │   ├── router.ex
    │   ├── live/                   # 9 LiveView pages
    │   ├── controllers/            # REST API
    │   ├── plugs/                  # ApiAuth, RateLimit
    │   ├── components/             # UI components
    │   └── telemetry.ex
    ├── assets/                     # Frontend assets
    │   ├── js/
    │   ├── css/
    │   └── package.json
    ├── priv/static/
    └── test/
```

### Key Modules

| Module | Purpose | Type |
|--------|---------|------|
| `Samgita.Application` | Core OTP supervisor | Application |
| `Samgita.Projects` | Project management context | Context |
| `Samgita.Tasks` | Task queue management | Context |
| `Samgita.Agent.Worker` | RARV cycle state machine | gen_statem |
| `Samgita.Project.Orchestrator` | Phase transition machine | gen_statem |
| `Samgita.Agent.Claude` | Provider wrapper | Module |
| `SamgitaProvider` | Provider abstraction | Module |
| `SamgitaProvider.ClaudeCode` | Claude CLI integration | Module |
| `SamgitaMemory.Memories.Memory` | Memory schema | Schema |
| `SamgitaMemory.Retrieval.Hybrid` | Memory retrieval pipeline | Module |
| `SamgitaMemory.MCP.Tools` | MCP tool definitions | Module |
| `SamgitaWeb.Endpoint` | Phoenix endpoint | Endpoint |
| `SamgitaWeb.Router` | Route definitions | Router |
| `SamgitaWeb.DashboardLive.Index` | Dashboard LiveView | LiveView |
| `SamgitaWeb.ProjectLive.Index` | Project detail LiveView | LiveView |

---

## External Resources

- **GitHub Repository:** https://github.com/gsmlg-opt/Samgita
- **loki-mode (inspiration):** https://github.com/asklokesh/loki-mode
- **Claude Code CLI:** https://claude.ai/code
- **Phoenix Framework:** https://phoenixframework.org/
- **Horde (distributed supervision):** https://github.com/derekkraan/horde
- **Oban (background jobs):** https://github.com/sorentwo/oban
- **pgvector:** https://github.com/pgvector/pgvector

---

## Contributing

See [loki-mode/CONTRIBUTING.md](../loki-mode/CONTRIBUTING.md) for contribution guidelines.

---

## Glossary

- **RARV Cycle:** Reason → Act → Reflect → Verify — the atomic unit of agent work
- **PRD:** Product Requirements Document
- **Agent:** Specialized AI worker (one of 37 types)
- **Swarm:** Group of related agents (Engineering, Operations, Business, etc.)
- **Orchestrator:** gen_statem managing project lifecycle phases
- **Provider:** LLM integration abstraction (ClaudeCode, Codex)
- **Memory System:** Persistent context storage with semantic search
- **Horde:** Distributed process registry and supervisor
- **Oban:** Background job queue and scheduler
- **pgvector:** PostgreSQL extension for vector similarity search
- **LiveView:** Phoenix real-time UI framework
- **Umbrella:** Elixir multi-app project structure

---

**Last Updated:** 2026-03-03
**Documentation Version:** 1.0.0
