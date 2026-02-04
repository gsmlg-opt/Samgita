# Samgita (संगीत)

<p align="center">
  <img src="assets/static/images/icon.png" alt="Samgita Icon" width="200" />
</p>

<p align="center">
  <a href="https://github.com/gsmlg-opt/Samgita"><img src="https://img.shields.io/badge/GitHub-gsmlg--dev%2FSamgita-blue?logo=github" alt="GitHub" /></a>
  <a href="https://elixir-lang.org/"><img src="https://img.shields.io/badge/Elixir-1.17%2B-purple?logo=elixir" alt="Elixir" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License" /></a>
</p>

<p align="center">
Distributed multi-agent orchestration system for autonomous software development, built on Elixir/OTP.
</p>

> **संगीत** (Saṅgīta) - Sanskrit for "music" or "symphony". Just as a symphony coordinates many instruments into harmony, Samgita orchestrates AI agents into cohesive software development.

## Overview

Samgita transforms a Product Requirements Document (PRD) into a fully built, tested, and deployed product through coordinated AI agent swarms. Inspired by [loki-mode](https://github.com/asklokesh/loki-mode), this Elixir implementation leverages OTP's actor model for true distributed execution across multiple machines.

The system orchestrates 37 specialized agent types across 6 swarms (Engineering, Operations, Business, Data, Product, Growth), each running as supervised processes that can crash, recover, and migrate across nodes transparently.

## UI Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Dashboard                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Projects                                    [+ New]    │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │  📁 my-saas-app      Running   ████████░░ 80%           │    │
│  │     git@github.com:myorg/my-saas-app.git                │    │
│  │  📁 api-backend      Paused    ██████░░░░ 60%           │    │
│  │     git@github.com:myorg/api-backend.git                │    │
│  │  📁 landing-page     Complete  ██████████ 100%          │    │
│  │     git@github.com:myorg/landing-page.git               │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Project: my-saas-app                         │
│  Git:  git@github.com:myorg/my-saas-app.git                     │
│  Path: /home/user/projects/my-saas-app (auto-detected)          │
│  Phase: Development                    [Pause] [Edit PRD]       │
├─────────────────────────────────────────────────────────────────┤
│  PRD Editor                          │  Agents (12 active)      │
│  ┌─────────────────────────────┐    │  ┌───────────────────┐    │
│  │ # My SaaS App               │    │  │ eng-backend  :act │    │
│  │                             │    │  │ eng-frontend :idle│    │
│  │ ## Features                 │    │  │ eng-api     :verify│   │
│  │ - User auth                 │    │  │ ops-devops   :act │    │
│  │ - Dashboard                 │    │  └───────────────────┘    │
│  │ - Billing                   │    │                           │
│  └─────────────────────────────┘    │  Tasks: 45/120 complete   │
└─────────────────────────────────────────────────────────────────┘
```

**Key interactions:**
- **New Project**: Enter git URL → auto-detect local path or clone → set PRD
- **Start**: Begin agent orchestration from current phase
- **Pause**: Gracefully stop all agents, save checkpoints
- **Resume**: Continue from last checkpoint
- **Edit PRD**: Modify requirements mid-flight (triggers re-planning)
- **Import**: Enter same git URL on another machine to continue work

### Why Elixir?

| Capability | Python/Shell | Elixir/OTP |
|------------|--------------|------------|
| Concurrent agents | Process spawning, manual | Lightweight processes, native |
| Fault tolerance | Script restarts | Supervision trees, automatic |
| Distribution | Not supported | Native clustering |
| State recovery | File checkpoints | Process state + Ecto snapshots |
| Task queue | File-based JSON | Oban (distributed, persistent) |
| Real-time UI | HTML + polling | LiveView (WebSocket, reactive) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Phoenix Application                         │
├─────────────────────────────────────────────────────────────────┤
│  LiveView Dashboard          │  REST API                        │
│  - Agent Monitor             │  - PRD Upload                    │
│  - Task Kanban               │  - Project CRUD                  │
│  - Real-time Logs            │  - Webhook Events                │
├─────────────────────────────────────────────────────────────────┤
│                      Horde (Distributed)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Orchestrator│  │   Swarm     │  │   Worker    │              │
│  │ (gen_statem)│──│ Supervisors │──│  Agents     │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
├─────────────────────────────────────────────────────────────────┤
│  Oban (Task Queue)  │  Ecto/Postgres  │  Phoenix.PubSub         │
└─────────────────────────────────────────────────────────────────┘
```

### Supervision Tree

```
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub (pg adapter for clustering)
├── Horde.Registry (Samgita.AgentRegistry)
├── Horde.DynamicSupervisor (Samgita.ProjectSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem) ─ phase management
│       ├── Memory (GenServer) ─ context/learnings
│       └── Agent workers (gen_statem) ─ RARV cycle
├── Oban (distributed job queue)
└── SamgitaWeb.Endpoint
```

### RARV Cycle (Agent State Machine)

Each agent executes a Reason-Act-Reflect-Verify cycle:

```
:idle ──task──▶ :reason ──▶ :act ──▶ :reflect ──▶ :verify
                  ▲                                  │
                  └────────on failure────────────────┘
```

- **Reason**: Load context, continuity log, identify approach
- **Act**: Execute via LLM (Claude), commit checkpoint
- **Reflect**: Update memory, record learnings
- **Verify**: Run tests, validate output, retry if failed

## Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| Runtime | Elixir 1.17+ / OTP 27+ | Actor model, fault tolerance |
| Web | Phoenix 1.7+ | API, LiveView dashboard |
| Database | PostgreSQL 16+ | Persistent state, Oban backend |
| Task Queue | Oban 2.18+ | Distributed job processing |
| Process Distribution | Horde | Cross-node registry/supervisor |
| LLM | Claude CLI / API | ClaudeAgent (CLI) or ClaudeAPI (HTTP) |
| Caching | ETS + PubSub | Local cache with cluster invalidation |

## Claude Integration

Samgita provides two modules for Claude integration:

### ClaudeAgent (`lib/claude_agent.ex`)

Wraps Claude Code CLI as a subprocess, matching the architecture of `@anthropic-ai/claude-agent-sdk`.

**Features:**
- Uses Claude Code's built-in authentication (OAuth or API key)
- All Claude Code tools available automatically (Read, Write, Edit, Bash, Glob, Grep, etc.)
- Stateful conversation support
- Aligns with ADR-004 (Use Claude CLI via Erlang Port)

**Use when:**
- Rapid prototyping and development
- You need all Claude Code tools immediately
- You already use Claude Code CLI
- You want CLI-managed authentication

**Example:**
```elixir
# Simple query
{:ok, response} = ClaudeAgent.query(
  "You are a calculator",
  "What is 42 * 137?"
)

# Conversational agent
agent = ClaudeAgent.new("You are a helpful coding assistant")
{:ok, response, agent} = ClaudeAgent.ask(agent, "List all .ex files")
{:ok, response, agent} = ClaudeAgent.ask(agent, "Read the first file")
```

See `lib/claude_agent/README.md` and `examples/claude_agent_example.exs` for details.

### ClaudeAPI (`lib/claude_api.ex`)

Direct HTTP client for Anthropic Messages API with custom tool implementations.

**Features:**
- Fine-grained control over API calls
- Custom tool implementations (Read, Write, Edit, Bash, Glob, Grep)
- No external dependencies (besides API key)
- RARV cycle orchestration built-in

**Use when:**
- Building production systems
- You need precise control over API calls
- You want to minimize external dependencies
- You need custom tool implementations

**Example:**
```elixir
# Simple query
{:ok, response} = ClaudeAPI.query(
  "You are a calculator",
  "What is 42 * 137?"
)

# Conversational agent
agent = ClaudeAPI.new("You are a helpful coding assistant")
{:ok, response, agent} = ClaudeAPI.ask(agent, "List all .ex files")
{:ok, response, agent} = ClaudeAPI.ask(agent, "Read the first file")
```

See `lib/claude_api/README.md` and `examples/claude_api_example.exs` for details.

## Getting Started

### Prerequisites

- Elixir 1.17+
- PostgreSQL 16+
- Claude CLI (install: `curl -fsSL https://claude.ai/install.sh | bash`)

### Installation

```bash
# Clone repository
git clone https://github.com/gsmlg-opt/Samgita.git
cd Samgita

# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start server
mix phx.server
```

Open http://localhost:3110

### Configuration

```elixir
# config/runtime.exs
config :samgita,
  claude_command: System.get_env("CLAUDE_COMMAND") || "claude",
  default_model: "claude-sonnet-4-5-20250514",
  max_concurrent_agents: 100,
  task_timeout_ms: 300_000

# HTTP port for web dashboard (default: 3110)
config :samgita, SamgitaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || "3110")]
```

### Usage

1. **Create Project**
   - Click "New Project"
   - Enter project name
   - Enter git URL (e.g., `git@github.com:myorg/myapp.git`)
   - System auto-detects local path or clones if needed

2. **Set PRD**
   - Upload a `.md` file, or
   - Paste PRD content directly in textarea

3. **Start Orchestration**
   - Click "Start" to begin
   - Watch agents spawn and execute in real-time

4. **Control Execution**
   - **Pause**: Stop agents gracefully, preserve state
   - **Resume**: Continue from last checkpoint
   - **Edit PRD**: Modify requirements (triggers re-planning)

5. **Cross-Machine Migration**
   - Import project on new machine using same git URL
   - State syncs via git, continues from last phase

## Project Structure

```
samgita/
├── lib/
│   ├── samgita/
│   │   ├── application.ex
│   │   ├── git.ex                 # Git repo detection/cloning
│   │   ├── project/
│   │   │   ├── supervisor.ex      # Per-project supervision
│   │   │   ├── orchestrator.ex    # Phase state machine
│   │   │   └── memory.ex          # Context/learnings store
│   │   ├── agent/
│   │   │   ├── worker.ex          # RARV state machine
│   │   │   ├── types.ex           # 37 agent type definitions
│   │   │   └── claude.ex          # Claude CLI wrapper (Port)
│   │   ├── domain/
│   │   │   ├── project.ex         # Ecto schema
│   │   │   ├── task.ex
│   │   │   ├── artifact.ex
│   │   │   └── agent_run.ex
│   │   ├── workers/               # Oban workers
│   │   │   ├── agent_task.ex
│   │   │   └── snapshot.ex
│   │   └── cache.ex               # ETS + PubSub invalidation
│   ├── samgita_web/
│   │   ├── live/
│   │   │   ├── dashboard_live.ex      # Project list, overview
│   │   │   ├── project_live.ex        # Single project view
│   │   │   ├── project_form_live.ex   # Create/edit project
│   │   │   ├── prd_editor_live.ex     # PRD textarea/upload
│   │   │   └── agent_monitor_live.ex  # Agent status grid
│   │   ├── components/
│   │   │   ├── task_kanban.ex         # Task board component
│   │   │   ├── agent_card.ex          # Agent status card
│   │   │   └── log_stream.ex          # Real-time logs
│   │   └── controllers/
│   │       └── project_controller.ex   # REST API
│   └── samgita.ex
├── priv/
│   └── repo/migrations/
├── test/
├── config/
└── mix.exs
```

## Agent Types (37)

### Engineering Swarm
`eng-frontend` `eng-backend` `eng-database` `eng-mobile` `eng-api` `eng-qa` `eng-perf` `eng-infra`

### Operations Swarm
`ops-devops` `ops-sre` `ops-security` `ops-monitor` `ops-incident` `ops-release` `ops-cost` `ops-compliance`

### Business Swarm
`biz-marketing` `biz-sales` `biz-finance` `biz-legal` `biz-support` `biz-hr` `biz-investor` `biz-partnerships`

### Data Swarm
`data-ml` `data-eng` `data-analytics`

### Product Swarm
`prod-pm` `prod-design` `prod-techwriter`

### Growth Swarm
`growth-hacker` `growth-community` `growth-success` `growth-lifecycle`

## Development

```bash
# Run tests
mix test

# Run with clustering (multiple nodes)
iex --sname node1 -S mix phx.server
iex --sname node2 -S mix phx.server

# Quality checks
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Running

### Development

```bash
# Start with IEx for debugging
iex -S mix phx.server

# Open dashboard
open http://localhost:3110
```

### Production

```bash
# Build release
MIX_ENV=prod mix release

# Start
_build/prod/rel/samgita/bin/samgita start
```

### Systemd Service (Optional)

```ini
# /etc/systemd/system/samgita.service
[Unit]
Description=Samgita Agent Orchestrator
After=network.target postgresql.service

[Service]
Type=simple
User=samgita
WorkingDirectory=/opt/samgita
ExecStart=/opt/samgita/bin/samgita start
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### Multi-Node (Optional)

```bash
# Node 1
iex --sname node1 --cookie samgita -S mix phx.server

# Node 2 (joins automatically via libcluster)
iex --sname node2 --cookie samgita -S mix phx.server
```

## Documentation

- [PRD.md](./PRD.md) - Product requirements
- [PLAN.md](./PLAN.md) - Implementation plan
- [docs/architecture/](./docs/architecture/) - Technical architecture
- [docs/decisions/](./docs/decisions/) - Architecture Decision Records

## License

AGPL License - see [LICENSE](./LICENSE) for details.

## Acknowledgments

- Original [loki-mode](https://github.com/asklokesh/loki-mode) by Lokesh Mure
- [Horde](https://github.com/derekkraan/horde) distributed supervisor
- [Oban](https://github.com/sorentwo/oban) background jobs
