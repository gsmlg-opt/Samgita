# Getting Started with Samgita

This guide will help you set up and run your first autonomous software development project with Samgita.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [First Project](#first-project)
5. [Understanding the Dashboard](#understanding-the-dashboard)
6. [Working with PRDs](#working-with-prds)
7. [Monitoring Progress](#monitoring-progress)
8. [Common Workflows](#common-workflows)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, ensure you have the following installed:

### Required

- **Elixir 1.17+** and **Erlang/OTP 27+**
  ```bash
  # macOS
  brew install elixir

  # Ubuntu
  wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
  sudo dpkg -i erlang-solutions_2.0_all.deb
  sudo apt-get update
  sudo apt-get install elixir
  ```

- **PostgreSQL 14+**
  ```bash
  # macOS
  brew install postgresql@14
  brew services start postgresql@14

  # Ubuntu
  sudo apt-get install postgresql-14
  ```

- **Claude CLI** (for Claude Code provider)
  ```bash
  curl -fsSL https://claude.ai/install.sh | bash
  claude login  # Follow OAuth flow
  ```

### Optional

- **Bun** (JavaScript runtime, auto-installed by mix setup)
- **Git** (for project repository management)

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/gsmlg-opt/Samgita.git
cd Samgita
```

### 2. Install Dependencies

```bash
# Fetch Elixir dependencies
mix deps.get

# Install frontend dependencies (automatic via bun)
cd apps/samgita_web
bun install
cd ../..
```

### 3. Configure Database

Edit `config/dev.exs` if you need custom database settings:

```elixir
# Default configuration
config :samgita, Samgita.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "samgita_dev",
  port: 5432
```

### 4. Create and Migrate Database

```bash
# Create database
mix ecto.create

# Run migrations for both repos
mix ecto.migrate

# (Optional) Load seed data
mix run priv/repo/seeds.exs
```

### 5. Start the Server

```bash
# Development mode with auto-reload
mix phx.server

# Or with IEx shell for debugging
iex -S mix phx.server
```

The dashboard will be available at **http://localhost:3110**

---

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# PostgreSQL
DATABASE_URL=ecto://postgres:postgres@localhost/samgita_dev

# Claude CLI path (optional, defaults to "claude")
CLAUDE_COMMAND=claude

# Anthropic API key (for embeddings in samgita_memory)
ANTHROPIC_API_KEY=sk-ant-...

# Web server port (optional, defaults to 3110)
PORT=3110

# API keys for REST API (comma-separated, empty = open access)
API_KEYS=

# Max concurrent agents (optional, defaults to 100)
MAX_CONCURRENT_AGENTS=100
```

### Application Configuration

Key configuration files:

- `config/config.exs` — Base configuration
- `config/dev.exs` — Development overrides
- `config/test.exs` — Test environment
- `config/runtime.exs` — Runtime environment variables
- `config/prod.exs` — Production settings

### Provider Configuration

Choose your LLM provider in `config/config.exs`:

```elixir
# Use Claude Code CLI (default)
config :samgita_provider, provider: SamgitaProvider.ClaudeCode

# Or use mock for testing
config :samgita_provider, provider: :mock
```

### Memory System Configuration

Configure the embedding provider:

```elixir
# Production: Anthropic Voyage embeddings
config :samgita_memory, :embedding_provider, :anthropic

# Test: Mock embeddings
config :samgita_memory, :embedding_provider, :mock
```

---

## First Project

Let's create your first autonomous development project.

### Step 1: Access the Dashboard

Open http://localhost:3110 in your browser. You'll see the main dashboard.

### Step 2: Create a New Project

1. Click **"+ New Project"** in the top right
2. Fill in the project form:
   - **Name:** `my-first-app`
   - **Git URL:** `git@github.com:yourusername/my-first-app.git` (or leave blank for local)
   - **Working Path:** `/Users/yourname/projects/my-first-app` (auto-detected if git URL exists)

3. Click **"Create Project"**

### Step 3: Create a PRD

After creating the project, you'll be redirected to the project page.

1. Click **"+ New PRD"** in the left sidebar
2. You can either:
   - **Write inline:** Use the markdown editor
   - **Upload:** Drag and drop a `.md` file

**Example PRD:**
```markdown
# My First App

## Overview
A simple todo list application with user authentication.

## Features

### User Authentication
- Sign up with email/password
- Login/logout
- Password reset

### Todo Management
- Create todos with title and description
- Mark todos as complete/incomplete
- Delete todos
- Filter by status (all/active/completed)

## Tech Stack
- Backend: Phoenix/Elixir
- Frontend: Phoenix LiveView
- Database: PostgreSQL
- Testing: ExUnit

## Quality Requirements
- 80%+ test coverage
- All tests passing
- Linting checks passed
- Security audit clean
```

3. Click **"Save & Start"**

### Step 4: Watch It Work

Samgita will now:

1. **Bootstrap** — Initialize project structure
2. **Discovery** — Parse PRD, extract requirements
3. **Architecture** — Design system architecture
4. **Development** — Implement features with tests
5. **QA** — Run quality gates
6. **Deployment** — Prepare for deployment

Watch the **Activity Log** in real-time as agents work through the RARV cycle.

---

## Understanding the Dashboard

### Project Page Layout

```
┌────────────────────────────────────────────────────────┐
│  ← Dashboard    my-first-app    Running  Development   │
│  git@github.com:user/my-first-app.git   ▓▓▓▓░░ 40%     │
├──────────────┬─────────────────────────────────────────┤
│  PRDs        │  Active PRD: Initial Requirements       │
│  ┌────────┐  │  [Start] [Pause] [Resume] [Restart]     │
│  │● v1.0  │  │  [Stop] [Terminate]                     │
│  │ active │  │                                          │
│  └────────┘  │  ┌─ Activity Log ──────────────────┐    │
│              │  │ 14:23:01 [ORC] Bootstrap phase  │    │
│  [+ New]     │  │ 14:23:05 [AGT] Spawning agents  │    │
│              │  │ 14:23:08 [ENG] Creating files   │    │
│              │  └─────────────────────────────────┘    │
│              │                                          │
│              │  Active Agents (5)    Tasks (12/45)     │
│              │  ┌─────────────┐    ┌─────────────┐     │
│              │  │pm    reason │    │bootstrap ✓  │     │
│              │  │be    act    │    │discovery ... │     │
│              │  │fe    idle   │    │arch     pend │     │
│              │  └─────────────┘    └─────────────┘     │
└──────────────┴─────────────────────────────────────────┘
```

### Key Elements

1. **PRD List (Left Sidebar):**
   - All PRDs for this project
   - Status indicator (● = active)
   - Click to switch PRD context

2. **Action Buttons:**
   - **Start** — Begin execution from current phase
   - **Pause** — Gracefully stop after current tasks
   - **Resume** — Continue from last checkpoint
   - **Restart** — Reset to bootstrap and start over
   - **Stop** — Mark project as completed
   - **Terminate** — Emergency stop, mark as failed

3. **Activity Log:**
   - Real-time event stream
   - Color-coded by source:
     - `[ORC]` — Orchestrator (phase transitions)
     - `[AGT]` — Agent lifecycle events
     - `[ENG]` — Engineering agents
     - `[OPS]` — Operations agents
     - `[QA]` — Quality assurance

4. **Active Agents Grid:**
   - Shows currently running agents
   - State indicator: `reason`, `act`, `reflect`, `verify`, `idle`
   - Click for detailed agent trace

5. **Tasks Panel:**
   - Task completion progress
   - Click to see task details
   - Filter by status

---

## Working with PRDs

### PRD Structure

A well-formed PRD should include:

```markdown
# Project Title

## Overview
Brief description of the product.

## Features
List of features with sub-bullets for requirements.

### Feature 1
- Requirement 1.1
- Requirement 1.2

### Feature 2
- Requirement 2.1

## Tech Stack (Optional)
- Backend: ...
- Frontend: ...
- Database: ...

## Quality Requirements (Optional)
- Test coverage: 80%+
- Performance: < 200ms p95
- Security: OWASP compliance

## Non-Functional Requirements (Optional)
- Accessibility: WCAG 2.1 AA
- Browser support: Chrome, Firefox, Safari
```

### PRD Best Practices

1. **Be specific** — "User can upload profile photo (max 5MB, JPG/PNG)" vs. "User profile"
2. **Include success criteria** — "Login response time < 300ms" vs. "Fast login"
3. **Specify constraints** — "Max 100 todos per user" vs. "Unlimited todos"
4. **Define edge cases** — "Handle duplicate emails gracefully" vs. just "Email signup"
5. **State non-goals** — "No social login (out of scope for v1)"

### Editing PRDs Mid-Flight

If you need to update requirements while the project is running:

1. Click **"Edit"** on the active PRD
2. Make your changes in the markdown editor
3. Click **"Save"**
4. Samgita will:
   - Pause current work
   - Re-analyze the updated PRD
   - Generate new tasks for added requirements
   - Resume execution

---

## Monitoring Progress

### Real-Time Updates

The dashboard uses Phoenix LiveView for real-time updates. No page refresh needed.

**Events broadcasted:**
- Phase transitions (`bootstrap` → `discovery`)
- Agent state changes (`idle` → `reason` → `act`)
- Task completions
- Quality gate results

### Phase Progress

Each phase has specific completion criteria:

| Phase | Completion Criteria |
|-------|---------------------|
| **Bootstrap** | Project structure created, git initialized |
| **Discovery** | Requirements extracted, task backlog generated |
| **Architecture** | Tech stack selected, OpenAPI spec created |
| **Infrastructure** | CI/CD configured, cloud resources provisioned |
| **Development** | All features implemented with tests |
| **QA** | 9 quality gates passed |
| **Deployment** | Blue-green deploy successful |
| **Business** | Marketing, legal, support setup |
| **Growth** | A/B testing framework, analytics |
| **Perpetual** | Continuous optimization loop |

### Checking Logs

**Via Dashboard:**
- Activity log shows high-level events
- Click an agent to see detailed RARV trace
- Click a task to see execution logs

**Via Command Line:**
```bash
# All logs
tail -f log/dev.log

# Filter by project
grep "project_id=550e8400" log/dev.log

# Filter by agent
grep "eng-backend" log/dev.log
```

**Via IEx Console:**
```elixir
# Attach to running server
iex --sname debug --remsh samgita@localhost

# Inspect project state
project = Samgita.Projects.get_project!("550e8400-...")
project.status
project.phase

# List active agents
Horde.Registry.processes(Samgita.AgentRegistry)
```

---

## Common Workflows

### Pausing and Resuming

**Pause for changes:**
```
1. Click "Pause" on project page
2. Wait for agents to complete current tasks
3. Make changes (edit PRD, update config)
4. Click "Resume"
```

**Resume after restart:**
```
1. Stop server: Ctrl+C
2. Start server: mix phx.server
3. Navigate to project page
4. Click "Resume" — picks up from last checkpoint
```

### Cross-Machine Migration

Work on the same project across multiple machines:

**Machine 1:**
```bash
# Create project with git URL
git_url: git@github.com:user/my-app.git

# Work proceeds, state saved to database and git
```

**Machine 2:**
```bash
# Clone Samgita
git clone https://github.com/gsmlg-opt/Samgita.git
cd Samgita
mix deps.get
mix ecto.setup

# Import project (same git URL)
# Navigate to dashboard → New Project
# Enter SAME git URL: git@github.com:user/my-app.git

# Samgita detects existing project and syncs state
# Click "Resume" to continue from where Machine 1 left off
```

### Running Multiple Projects

```bash
# Projects run concurrently
# Each has its own agent pool and task queue

# Create multiple projects in dashboard
Project 1: my-web-app (10 agents)
Project 2: api-backend (8 agents)
Project 3: mobile-app (5 agents)

# Total: 23 agents running in parallel
# Limited by MAX_CONCURRENT_AGENTS config (default: 100)
```

### Manual Intervention

If an agent gets stuck or a task fails repeatedly:

**Via Dashboard:**
1. Navigate to Tasks panel
2. Find the failed task
3. Click "Retry" to re-queue

**Via API:**
```bash
curl -X POST http://localhost:3110/api/projects/$PROJECT_ID/tasks/$TASK_ID/retry
```

**Via IEx:**
```elixir
task = Samgita.Tasks.get_task!("task-id")
Samgita.Tasks.retry_task(task)
```

---

## Troubleshooting

### Server Won't Start

**Error:** `(Mix) Could not start application samgita`

**Solutions:**
```bash
# 1. Check database connection
psql -U postgres -h localhost
\l  # Should show samgita_dev

# 2. Run migrations
mix ecto.migrate

# 3. Check port availability
lsof -i :3110
# Kill if occupied: kill -9 <PID>

# 4. Clean build
mix deps.clean --all
mix deps.get
mix compile
```

### Database Connection Errors

**Error:** `** (Postgrex.Error) FATAL (invalid_catalog_name): database "samgita_dev" does not exist`

**Solution:**
```bash
mix ecto.create
mix ecto.migrate
```

**Error:** `** (DBConnection.ConnectionError) connection not available`

**Solutions:**
```bash
# 1. Check PostgreSQL is running
brew services list  # macOS
systemctl status postgresql  # Linux

# 2. Start PostgreSQL
brew services start postgresql@14  # macOS
sudo systemctl start postgresql  # Linux

# 3. Check connection settings in config/dev.exs
```

### Claude CLI Not Found

**Error:** `** (ErlangError) Erlang error: :enoent` when calling SamgitaProvider

**Solutions:**
```bash
# 1. Install Claude CLI
curl -fsSL https://claude.ai/install.sh | bash

# 2. Verify installation
which claude
claude --version

# 3. Login
claude login

# 4. Test provider
mix run -e "IO.inspect SamgitaProvider.query('Hello')"
```

### Agents Not Spawning

**Symptom:** Project stuck in bootstrap/discovery, no agents visible

**Diagnosis:**
```elixir
# Check Horde registry
iex -S mix phx.server
Horde.Registry.processes(Samgita.AgentRegistry)
# Should show agent processes

# Check Oban queues
Oban.check_queue(queue: :agent_tasks)
```

**Solutions:**
```bash
# 1. Restart Oban
iex> Oban.start_queue(queue: :agent_tasks)

# 2. Check for errors in logs
tail -f log/dev.log | grep ERROR

# 3. Manually trigger task dispatch
iex> project = Samgita.Projects.get_project!("id")
iex> Samgita.Orchestrator.bootstrap(project)
```

### Memory Issues (pgvector)

**Error:** `** (Postgrex.Error) ERROR (undefined_function): function pgvector_in(cstring, oid, integer) does not exist`

**Solution:**
```bash
# pgvector extension not installed
# PostgreSQL 14 requires building from source

# macOS
brew install postgresql@14
git clone https://github.com/pgvector/pgvector.git
cd pgvector
make PG_CONFIG=/opt/homebrew/opt/postgresql@14/bin/pg_config
sudo make install PG_CONFIG=/opt/homebrew/opt/postgresql@14/bin/pg_config

# Then in psql:
CREATE EXTENSION vector;
```

### Frontend Assets Not Loading

**Error:** 404 on `/assets/app.js`

**Solutions:**
```bash
# 1. Install bun dependencies
cd apps/samgita_web
bun install

# 2. Build assets
mix assets.deploy

# 3. Check bun is installed
which bun
bun --version

# 4. If bun missing:
curl -fsSL https://bun.sh/install | bash
```

### Rate Limit Errors

**Error:** Claude API rate limit exceeded

**Solutions:**
```bash
# 1. Reduce concurrent agents
# config/runtime.exs
config :samgita, max_concurrent_agents: 10

# 2. Use exponential backoff (automatic)
# Check agent retry attempts
iex> Samgita.Tasks.list_tasks(project_id: "id", status: :failed)

# 3. Upgrade Claude API tier
# See https://claude.ai/pricing
```

---

## Next Steps

Now that you have Samgita running:

1. **Read the Architecture Guide** — Understand how the system works (`docs/ARCHITECTURE.md`)
2. **Explore the API** — Build integrations (`docs/API.md`)
3. **Review Agent Types** — Learn about the 37 specialized agents (`apps/samgita/lib/samgita/agent/types.ex`)
4. **Study the Memory System** — Understand persistent context (`apps/samgita_memory/`)
5. **Check Quality Gates** — See how code review works (`docs/QUALITY-GATES.md`)

---

## Getting Help

- **GitHub Issues:** https://github.com/gsmlg-opt/Samgita/issues
- **Documentation:** All docs in `docs/` directory
- **Code Examples:** `examples/` directory
- **Constitution:** `docs/CONSTITUTION.md` for architectural principles

---

**Last Updated:** 2026-03-03
