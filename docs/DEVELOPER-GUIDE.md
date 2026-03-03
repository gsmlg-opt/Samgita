# Samgita Developer Guide

This guide is for developers who want to contribute to Samgita, extend its capabilities, or understand its internals for debugging and customization.

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Codebase Overview](#codebase-overview)
3. [Development Workflow](#development-workflow)
4. [Testing Strategy](#testing-strategy)
5. [Adding New Agent Types](#adding-new-agent-types)
6. [Extending the Memory System](#extending-the-memory-system)
7. [Creating Custom Providers](#creating-custom-providers)
8. [Adding LiveView Features](#adding-liveview-features)
9. [Database Migrations](#database-migrations)
10. [Debugging Tips](#debugging-tips)
11. [Performance Profiling](#performance-profiling)
12. [Contributing Guidelines](#contributing-guidelines)

---

## Development Environment Setup

### Prerequisites

Ensure you have these tools installed:

```bash
# Elixir 1.17+ and Erlang/OTP 27+
asdf install elixir 1.17.3
asdf install erlang 27.2

# PostgreSQL 14+ with pgvector
brew install postgresql@14
brew services start postgresql@14

# Build pgvector from source (required for PostgreSQL 14)
git clone https://github.com/pgvector/pgvector.git
cd pgvector
make PG_CONFIG=/opt/homebrew/opt/postgresql@14/bin/pg_config
sudo make install PG_CONFIG=/opt/homebrew/opt/postgresql@14/bin/pg_config

# Claude CLI
curl -fsSL https://claude.ai/install.sh | bash
claude login

# Bun (JavaScript runtime)
curl -fsSL https://bun.sh/install | bash

# Development tools
mix archive.install hex phx_new
```

### Initial Setup

```bash
# Clone and setup
git clone https://github.com/gsmlg-opt/Samgita.git
cd Samgita

# Install Elixir dependencies
mix deps.get

# Install frontend dependencies
cd apps/samgita_web
bun install
cd ../..

# Setup databases (creates DBs, runs migrations, seeds data)
mix ecto.setup

# Compile assets
mix assets.deploy

# Start development server with IEx
iex -S mix phx.server
```

### Editor Setup

**VS Code:**

```json
// .vscode/settings.json
{
  "elixir.projectPath": ".",
  "elixirLS.dialyzerEnabled": true,
  "elixirLS.fetchDeps": false,
  "elixirLS.mixEnv": "dev",
  "files.associations": {
    "*.ex": "elixir",
    "*.exs": "elixir",
    "*.heex": "phoenix-heex"
  }
}
```

**Recommended Extensions:**
- ElixirLS (Elixir language server)
- Phoenix Framework
- Tailwind CSS IntelliSense

---

## Codebase Overview

### Directory Structure

```
Samgita/
├── apps/
│   ├── samgita_provider/          # Provider abstraction
│   │   ├── lib/
│   │   │   ├── samgita_provider.ex
│   │   │   └── samgita_provider/
│   │   │       ├── provider.ex         # Behaviour definition
│   │   │       └── claude_code.ex      # CLI implementation
│   │   └── test/
│   │
│   ├── samgita/                    # Core domain
│   │   ├── lib/samgita/
│   │   │   ├── application.ex          # OTP application
│   │   │   ├── projects.ex             # Projects context
│   │   │   ├── tasks.ex                # Tasks context
│   │   │   ├── domain/                 # Ecto schemas
│   │   │   │   ├── project.ex
│   │   │   │   ├── task.ex
│   │   │   │   ├── agent_run.ex
│   │   │   │   ├── prd.ex
│   │   │   │   └── ...
│   │   │   ├── agent/
│   │   │   │   ├── worker.ex           # gen_statem RARV cycle
│   │   │   │   ├── types.ex            # 37 agent type definitions
│   │   │   │   └── claude.ex           # Provider wrapper
│   │   │   ├── project/
│   │   │   │   └── orchestrator.ex     # Phase state machine
│   │   │   ├── workers/                # Oban background workers
│   │   │   │   ├── agent_task_worker.ex
│   │   │   │   ├── snapshot_worker.ex
│   │   │   │   └── webhook_worker.ex
│   │   │   ├── cache.ex                # ETS + PubSub cache
│   │   │   └── repo.ex
│   │   ├── priv/
│   │   │   ├── repo/
│   │   │   │   ├── migrations/
│   │   │   │   └── seeds.exs
│   │   │   └── references/             # Reference docs (20 files)
│   │   └── test/
│   │
│   ├── samgita_memory/             # Memory system
│   │   ├── lib/samgita_memory/
│   │   │   ├── application.ex
│   │   │   ├── memories/
│   │   │   │   └── memory.ex           # pgvector schema
│   │   │   ├── prd/
│   │   │   │   ├── execution.ex
│   │   │   │   ├── event.ex
│   │   │   │   └── decision.ex
│   │   │   ├── thinking_chain.ex
│   │   │   ├── retrieval/
│   │   │   │   ├── hybrid.ex           # 7-stage retrieval
│   │   │   │   └── scorer.ex
│   │   │   ├── mcp/
│   │   │   │   └── tools.ex            # 10 MCP tools
│   │   │   ├── workers/
│   │   │   │   ├── embedding.ex
│   │   │   │   ├── compaction.ex
│   │   │   │   └── summarize.ex
│   │   │   └── repo.ex
│   │   ├── priv/repo/migrations/
│   │   └── test/
│   │
│   └── samgita_web/                # Web interface
│       ├── lib/samgita_web/
│       │   ├── application.ex
│       │   ├── endpoint.ex
│       │   ├── router.ex
│       │   ├── live/                   # 9 LiveView pages
│       │   │   ├── dashboard_live.ex
│       │   │   ├── project_form_live.ex
│       │   │   ├── project_live/
│       │   │   │   ├── index.ex
│       │   │   │   └── show.ex
│       │   │   ├── prd_chat_live.ex
│       │   │   └── ...
│       │   ├── controllers/            # REST API
│       │   │   ├── project_controller.ex
│       │   │   ├── prd_controller.ex
│       │   │   └── ...
│       │   ├── plugs/
│       │   │   ├── api_auth.ex         # API key verification
│       │   │   └── rate_limit.ex       # Token bucket limiter
│       │   ├── components/             # Phoenix components
│       │   │   └── core_components.ex
│       │   └── telemetry.ex
│       ├── assets/                     # Frontend
│       │   ├── js/
│       │   │   ├── app.ts
│       │   │   └── custom-elements.ts
│       │   ├── css/
│       │   │   └── app.css
│       │   └── package.json
│       └── test/
│
├── config/
│   ├── config.exs                      # Base config
│   ├── dev.exs                         # Development overrides
│   ├── test.exs                        # Test environment
│   ├── runtime.exs                     # Runtime env vars
│   └── prod.exs                        # Production settings
│
├── docs/                               # Documentation
│   ├── ARCHITECTURE.md
│   ├── API.md
│   ├── GETTING-STARTED.md
│   ├── DEPLOYMENT.md
│   ├── CONSTITUTION.md
│   └── ...
│
└── mix.exs                             # Root mix file
```

### Key Concepts

#### 1. Umbrella Apps

Samgita uses an Elixir umbrella project structure:

- **samgita_provider** — Standalone, no dependencies. Defines `Provider` behaviour and implements `ClaudeCode` provider.
- **samgita** — Core app. Depends on `samgita_provider`. Contains domain logic, Horde, Oban, gen_statem workers.
- **samgita_memory** — Standalone. Shares same PostgreSQL database (uses `sm_` table prefix). Provides memory and PRD tracking.
- **samgita_web** — Web layer. Depends on `samgita` and `samgita_memory`. Phoenix endpoint, LiveView, REST API.

#### 2. Configuration Namespacing

Each app has its own configuration namespace:

```elixir
# config/runtime.exs

# samgita_provider config
config :samgita_provider,
  provider: SamgitaProvider.ClaudeCode,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

# samgita config (core)
config :samgita, Samgita.Repo, database: "samgita_dev"
config :samgita, Oban, queues: [agent_tasks: 100]
config :samgita, :claude_command, System.get_env("CLAUDE_COMMAND") || "claude"

# samgita_memory config
config :samgita_memory, SamgitaMemory.Repo,
  database: "samgita_dev",  # Same DB!
  types: SamgitaMemory.PostgrexTypes

config :samgita_memory, Oban,
  name: SamgitaMemory.Oban,  # Named instance
  queues: [embeddings: 5]

# samgita_web config
config :samgita_web, SamgitaWeb.Endpoint,
  http: [port: 3110]
```

**Important:** Frontend asset tools (bun, tailwind) use the `:samgita_web` namespace:

```elixir
config :bun, samgita_web: [...]
config :tailwind, samgita_web: [...]
```

#### 3. State Machines

Two critical `gen_statem` state machines:

**Agent Worker (`Samgita.Agent.Worker`):**
```
:idle → :reason → :act → :reflect → :verify
         ↑                            │
         └────── on failure ──────────┘
```

**Project Orchestrator (`Samgita.Project.Orchestrator`):**
```
:bootstrap → :discovery → :architecture → :infrastructure →
:development → :qa → :deployment → :business → :growth → :perpetual
```

---

## Development Workflow

### Running in Development

```bash
# Standard server
mix phx.server

# With IEx (recommended)
iex -S mix phx.server

# Multi-node cluster (for testing Horde)
# Terminal 1:
iex --sname node1 --cookie samgita -S mix phx.server

# Terminal 2:
iex --sname node2 --cookie samgita -S mix phx.server

# Verify cluster in IEx:
iex(node1@localhost)> Node.list()
[:"node2@localhost"]
```

### Code Quality Tools

```bash
# Format code
mix format

# Check formatting (CI)
mix format --check-formatted

# Linting with Credo
mix credo --strict

# Type checking with Dialyzer
mix dialyzer

# Security audit
mix deps.audit

# Unused dependencies
mix deps.unlock --check-unused
```

### Hot Code Reloading

Phoenix supports hot code reloading in development:

1. Edit a `.ex` file in `lib/`
2. Save
3. Phoenix automatically recompiles
4. Browser auto-refreshes (for LiveView changes)

**Note:** Changes to `config/` require server restart.

---

## Testing Strategy

### Test Structure

```
apps/
├── samgita_provider/test/
├── samgita/test/
│   ├── samgita/
│   │   ├── projects_test.exs
│   │   ├── tasks_test.exs
│   │   ├── agent/
│   │   │   └── worker_test.exs      # Has 300s timeout tag
│   │   └── ...
│   └── support/
│       ├── data_case.ex
│       └── fixtures.ex
├── samgita_memory/test/
│   ├── samgita_memory/
│   │   ├── memories_test.exs
│   │   ├── retrieval_test.exs
│   │   └── ...
│   └── support/
│       └── data_case.ex
└── samgita_web/test/
    ├── samgita_web/
    │   ├── controllers/
    │   ├── live/
    │   └── ...
    └── support/
        ├── conn_case.ex            # Sandboxes BOTH repos
        └── fixtures.ex
```

### Running Tests

```bash
# All tests (slow, includes Worker tests with 300s timeout)
mix test

# Fast feedback loop (exclude long-running tests)
mix test --exclude moduletag:timeout

# Specific app
mix test apps/samgita_memory/test
mix test apps/samgita_web/test

# Specific file
mix test apps/samgita/test/samgita/projects_test.exs

# Specific test at line
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs:10

# With coverage
mix test --cover

# Parallel execution (default, use --max-cases to control)
mix test --max-cases 4
```

### Test Status (as of 2026-03-03)

- **samgita_memory**: 94 tests, 0 failures
- **samgita_web**: 179 tests, 0 failures
- **samgita**: 422 tests, 0 failures (3 skipped, excluding WorkerTest)
- **Total**: 695 tests, 0 failures

### Writing Tests

**Data Case (Ecto tests):**

```elixir
defmodule Samgita.ProjectsTest do
  use Samgita.DataCase

  alias Samgita.Projects

  describe "create_project/1" do
    test "creates project with valid attributes" do
      attrs = %{
        name: "test-project",
        git_url: "git@github.com:user/test.git"
      }

      assert {:ok, project} = Projects.create_project(attrs)
      assert project.name == "test-project"
      assert project.status == :pending
    end
  end
end
```

**Conn Case (Controller/LiveView tests):**

```elixir
defmodule SamgitaWeb.ProjectControllerTest do
  use SamgitaWeb.ConnCase

  describe "POST /api/projects" do
    test "creates project with valid params", %{conn: conn} do
      params = %{
        project: %{
          name: "test",
          git_url: "git@github.com:user/test.git"
        }
      }

      conn = post(conn, ~p"/api/projects", params)
      assert %{"id" => _id} = json_response(conn, 201)
    end
  end
end
```

**LiveView Test:**

```elixir
defmodule SamgitaWeb.DashboardLiveTest do
  use SamgitaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "displays project list", %{conn: conn} do
    project = project_fixture()

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ project.name
    assert has_element?(view, "#project-#{project.id}")
  end
end
```

### Test Database Management

```bash
# Create test database
MIX_ENV=test mix ecto.create

# Run migrations
MIX_ENV=test mix ecto.migrate

# Reset database (drop, create, migrate)
MIX_ENV=test mix ecto.reset

# Rollback
MIX_ENV=test mix ecto.rollback -r Samgita.Repo
MIX_ENV=test mix ecto.rollback -r SamgitaMemory.Repo
```

**Important:** `ConnCase` sandboxes both `Samgita.Repo` and `SamgitaMemory.Repo` for cross-app database isolation.

---

## Adding New Agent Types

### Step 1: Define Agent Type

Edit `apps/samgita/lib/samgita/agent/types.ex`:

```elixir
@agent_types %{
  # ... existing types ...

  custom: [:custom_agent_foo, :custom_agent_bar]
}

@agent_metadata %{
  # ... existing metadata ...

  custom_agent_foo: %{
    name: "Custom Foo Agent",
    description: "Does foo things",
    capabilities: ["capability1", "capability2"],
    model: :sonnet  # opus, sonnet, or haiku
  }
}
```

### Step 2: Add System Prompt

Create `apps/samgita/lib/samgita/agent/prompts.ex` (if doesn't exist) or add to existing:

```elixir
def system_prompt(:custom_agent_foo) do
  """
  You are a specialized agent that does foo.

  Your responsibilities:
  - Responsibility 1
  - Responsibility 2

  Context available:
  - PRD content
  - Previous task results
  - Memory system

  Output format:
  - Always commit changes
  - Write tests
  - Update documentation
  """
end
```

### Step 3: Add to Orchestrator

Edit `apps/samgita/lib/samgita/project/orchestrator.ex`:

```elixir
# Spawn agent during appropriate phase
def development(:enter, _old_state, data) do
  # ... existing agents ...

  spawn_agent(data.project, :custom_agent_foo)

  {:keep_state, data}
end
```

### Step 4: Add Tests

```elixir
# apps/samgita/test/samgita/agent/types_test.exs
test "custom_agent_foo is valid type" do
  assert :custom_agent_foo in Types.all_types()
  assert Types.metadata(:custom_agent_foo).name == "Custom Foo Agent"
end

test "custom_agent_foo spawns in development phase" do
  # ... test orchestrator spawning logic
end
```

### Step 5: Add Reference Documentation

Create `apps/samgita/priv/references/custom-agent-foo.md`:

```markdown
# Custom Foo Agent

## Purpose
Handles foo-related tasks during development.

## Capabilities
- Capability 1
- Capability 2

## Example Tasks
- Task type 1
- Task type 2

## Output Artifacts
- Artifact 1
- Artifact 2
```

---

## Extending the Memory System

### Adding New Memory Types

Memory types are defined in `apps/samgita_memory/lib/samgita_memory/memories/memory.ex`:

```elixir
# Add to enum
field :memory_type, Ecto.Enum,
  values: [:episodic, :semantic, :procedural, :custom_type]
```

Create migration:

```bash
cd apps/samgita_memory
mix ecto.gen.migration add_custom_memory_type
```

```elixir
# Migration
def change do
  execute "ALTER TYPE memory_type ADD VALUE IF NOT EXISTS 'custom_type'"
end
```

### Adding MCP Tools

Edit `apps/samgita_memory/lib/samgita_memory/mcp/tools.ex`:

```elixir
@tools [
  # ... existing tools ...

  %{
    name: "custom_tool",
    description: "Does custom thing",
    inputSchema: %{
      type: "object",
      properties: %{
        query: %{type: "string", description: "Query param"}
      },
      required: ["query"]
    }
  }
]

def execute_tool("custom_tool", %{"query" => query}) do
  # Implementation
  result = do_custom_thing(query)

  {:ok, %{
    content: [%{type: "text", text: "Result: #{result}"}]
  }}
end
```

### Custom Retrieval Strategies

Extend `apps/samgita_memory/lib/samgita_memory/retrieval/hybrid.ex`:

```elixir
def retrieve_with_custom_strategy(query, opts) do
  # Custom retrieval logic
  base_results = retrieve(query, opts)

  # Apply custom ranking
  rerank_results(base_results, opts[:custom_param])
end

defp rerank_results(results, custom_param) do
  # Custom scoring logic
  Enum.sort_by(results, &custom_score(&1, custom_param), :desc)
end
```

---

## Creating Custom Providers

### Step 1: Define Provider Behaviour Implementation

```elixir
# apps/samgita_provider/lib/samgita_provider/custom_provider.ex
defmodule SamgitaProvider.CustomProvider do
  @behaviour SamgitaProvider.Provider

  @impl true
  def query(prompt, opts \\ []) do
    # Your custom implementation
    # Could be: OpenAI API, Anthropic API, local model, etc.

    case make_api_call(prompt, opts) do
      {:ok, response} ->
        {:ok, parse_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_api_call(prompt, opts) do
    # HTTP request, CLI invocation, etc.
  end

  defp parse_response(response) do
    # Extract text from API response
  end
end
```

### Step 2: Configure Provider

```elixir
# config/dev.exs
config :samgita_provider,
  provider: SamgitaProvider.CustomProvider

# Or keep ClaudeCode as default:
config :samgita_provider,
  provider: SamgitaProvider.ClaudeCode
```

### Step 3: Add Tests

```elixir
# apps/samgita_provider/test/samgita_provider/custom_provider_test.exs
defmodule SamgitaProvider.CustomProviderTest do
  use ExUnit.Case

  alias SamgitaProvider.CustomProvider

  test "query/2 returns successful response" do
    assert {:ok, response} = CustomProvider.query("test prompt")
    assert is_binary(response)
  end
end
```

### Provider Interface Requirements

All providers must:

1. Implement `SamgitaProvider.Provider` behaviour
2. Accept `query(prompt, opts)` with options:
   - `:model` — Model identifier (string or atom)
   - `:system_prompt` — System instruction
   - `:max_turns` — Agentic turn limit
3. Return `{:ok, text}` or `{:error, reason}`
4. Handle tool execution if needed (or rely on CLI)

---

## Adding LiveView Features

### Creating a New LiveView Page

```bash
# 1. Generate LiveView module
touch apps/samgita_web/lib/samgita_web/live/my_feature_live.ex
```

```elixir
# apps/samgita_web/lib/samgita_web/live/my_feature_live.ex
defmodule SamgitaWeb.MyFeatureLive do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to PubSub events
      Phoenix.PubSub.subscribe(Samgita.PubSub, "my_feature:updates")
    end

    {:ok, assign(socket, data: load_data())}
  end

  @impl true
  def handle_event("action", %{"value" => value}, socket) do
    # Handle user interaction
    {:noreply, update(socket, :data, &process(&1, value))}
  end

  @impl true
  def handle_info({:update, new_data}, socket) do
    # Handle PubSub broadcasts
    {:noreply, assign(socket, data: new_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>My Feature</h1>
      <p><%= @data %></p>
    </div>
    """
  end

  defp load_data do
    # Load initial data
  end
end
```

### Add Route

```elixir
# apps/samgita_web/lib/samgita_web/router.ex
scope "/", SamgitaWeb do
  pipe_through :browser

  # ... existing routes ...

  live "/my-feature", MyFeatureLive, :index
end
```

### Add Navigation Link

```heex
<!-- apps/samgita_web/lib/samgita_web/components/layouts/app.html.heex -->
<nav>
  <!-- ... existing links ... -->
  <.link navigate={~p"/my-feature"}>My Feature</.link>
</nav>
```

### Real-Time Updates

```elixir
# In your context module (e.g., apps/samgita/lib/samgita/my_context.ex)
def update_thing(thing, attrs) do
  with {:ok, updated} <- do_update(thing, attrs) do
    # Broadcast to subscribers
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "my_feature:updates",
      {:update, updated}
    )

    {:ok, updated}
  end
end
```

---

## Database Migrations

### Creating Migrations

```bash
# For samgita (core)
cd apps/samgita
mix ecto.gen.migration add_my_field -r Samgita.Repo

# For samgita_memory
cd apps/samgita_memory
mix ecto.gen.migration add_memory_field -r SamgitaMemory.Repo
```

### Migration Best Practices

```elixir
defmodule Samgita.Repo.Migrations.AddMyField do
  use Ecto.Migration

  def up do
    # Prefer explicit up/down over change
    alter table(:projects) do
      add :my_field, :string
      add :my_jsonb_field, :map, default: "{}"
    end

    create index(:projects, [:my_field])
  end

  def down do
    drop index(:projects, [:my_field])

    alter table(:projects) do
      remove :my_field
      remove :my_jsonb_field
    end
  end
end
```

### Migration Tips

1. **Always provide `up` and `down`** for reversibility
2. **Add indexes for foreign keys** and frequently queried columns
3. **Use `default` values** to avoid null issues
4. **JSONB indexes** for path queries:
   ```elixir
   create index(:tasks, ["(payload->'prd_id')"], using: :gin)
   ```
5. **pgvector indexes** for similarity search:
   ```elixir
   create index(:sm_memories, [:embedding],
     using: :ivfflat,
     opclass: "vector_cosine_ops",
     options: "lists = 100"
   )
   ```

### Running Migrations

```bash
# Development
mix ecto.migrate

# Production
MIX_ENV=prod mix ecto.migrate

# Rollback (default: 1 step)
mix ecto.rollback -r Samgita.Repo

# Rollback N steps
mix ecto.rollback -r Samgita.Repo --step 3

# Rollback to specific version
mix ecto.rollback -r Samgita.Repo --to 20240101000000
```

---

## Debugging Tips

### IEx Debugging

```elixir
# In any file, add:
require IEx; IEx.pry

# When code hits this line:
iex> self()          # Current process PID
iex> Process.info(self())

# Inspect variables
iex> project
iex> inspect(project, structs: false)  # Show as map

# Call functions
iex> Samgita.Projects.get_project!(id)
iex> Samgita.Tasks.list_tasks(project_id: id)
```

### Inspecting Horde Processes

```elixir
# List all registered agents
iex> Horde.Registry.processes(Samgita.AgentRegistry)

# Lookup specific agent
iex> Horde.Registry.lookup(Samgita.AgentRegistry, {:agent, project_id, agent_id})

# Inspect agent state
iex> :sys.get_state(agent_pid)
```

### Oban Queue Inspection

```elixir
# Check queue status
iex> Oban.check_queue(queue: :agent_tasks)

# List jobs
iex> import Ecto.Query
iex> Samgita.Repo.all(from j in Oban.Job, where: j.queue == "agent_tasks")

# Cancel job
iex> Oban.cancel_job(job_id)

# Retry failed job
iex> job = Samgita.Repo.get!(Oban.Job, job_id)
iex> Oban.retry_job(job)
```

### Database Queries

```elixir
# Raw SQL
iex> Samgita.Repo.query("SELECT * FROM projects WHERE status = 'running'")

# Ecto query
iex> import Ecto.Query
iex> Samgita.Repo.all(from p in Samgita.Domain.Project, where: p.status == :running)

# With preloads
iex> Samgita.Repo.all(from p in Samgita.Domain.Project, preload: [:tasks, :agent_runs])
```

### Log Levels

```elixir
# config/dev.exs
config :logger, level: :debug  # :debug, :info, :warning, :error

# Runtime adjustment
iex> Logger.configure(level: :debug)
```

### Debugging gen_statem

```elixir
# Enable debug trace
iex> :sys.trace(agent_pid, true)

# Get current state
iex> :gen_statem.call(agent_pid, :get_state)

# Send event
iex> :gen_statem.cast(agent_pid, {:execute_task, task})

# Check state transitions
iex> :sys.get_state(agent_pid)
```

---

## Performance Profiling

### ExProf (CPU Profiling)

```elixir
# Add to mix.exs
{:exprof, "~> 0.2", only: :dev}

# In IEx
iex> :exprof.start()
iex> :exprof.profile(fn -> Samgita.Projects.list_projects() end)
```

### Benchee (Benchmarking)

```elixir
# Add to mix.exs
{:benchee, "~> 1.0", only: :dev}

# Create benchmark file: bench/retrieval_bench.exs
Benchee.run(%{
  "retrieval_hybrid" => fn ->
    SamgitaMemory.Retrieval.Hybrid.retrieve("test query", scope_id: "project-123")
  end,
  "retrieval_semantic_only" => fn ->
    SamgitaMemory.Retrieval.Semantic.retrieve("test query")
  end
})

# Run: mix run bench/retrieval_bench.exs
```

### ETS Cache Monitoring

```elixir
# Check cache size
iex> :ets.info(:samgita_cache, :size)

# List all keys
iex> :ets.tab2list(:samgita_cache)

# Memory usage
iex> :ets.info(:samgita_cache, :memory) * :erlang.system_info(:wordsize)
```

### Database Query Analysis

```sql
-- Enable query logging
SET log_statement = 'all';

-- Analyze slow queries
EXPLAIN ANALYZE SELECT * FROM tasks WHERE project_id = 'uuid';

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan;
```

---

## Contributing Guidelines

### Git Workflow

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes, commit often
git add .
git commit -m "Add feature X"

# 3. Run tests
mix test

# 4. Format and lint
mix format
mix credo --strict

# 5. Push and create PR
git push origin feature/my-feature
```

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance

**Example:**
```
feat(memory): add custom retrieval strategy

Implements configurable retrieval strategies for memory system.
Adds support for custom scoring functions.

Closes #123
```

### Code Review Checklist

- [ ] Tests pass (`mix test`)
- [ ] Code formatted (`mix format`)
- [ ] Linting clean (`mix credo --strict`)
- [ ] Documentation updated
- [ ] Changelog entry added (if applicable)
- [ ] No debugging artifacts (IO.inspect, IEx.pry)
- [ ] Migration has `up` and `down`
- [ ] New functions have @doc and @spec
- [ ] Backward compatible (or breaking change noted)

### Pull Request Template

```markdown
## Description
Brief description of changes.

## Motivation
Why is this change needed?

## Changes
- Change 1
- Change 2

## Testing
How was this tested?

## Screenshots (if UI changes)

## Checklist
- [ ] Tests pass
- [ ] Code formatted
- [ ] Documentation updated
- [ ] Breaking changes noted
```

---

## Additional Resources

### Internal Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — Deep dive into system design
- **[API.md](./API.md)** — REST API reference
- **[CONSTITUTION.md](./CONSTITUTION.md)** — Core principles and rationale
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** — Production deployment guide
- **[GETTING-STARTED.md](./GETTING-STARTED.md)** — User onboarding

### External Resources

- **Elixir Docs:** https://hexdocs.pm/elixir/
- **Phoenix Docs:** https://hexdocs.pm/phoenix/
- **Ecto Docs:** https://hexdocs.pm/ecto/
- **Horde Docs:** https://hexdocs.pm/horde/
- **Oban Docs:** https://hexdocs.pm/oban/
- **pgvector:** https://github.com/pgvector/pgvector

### Community

- **GitHub Issues:** https://github.com/gsmlg-opt/Samgita/issues
- **Discussions:** https://github.com/gsmlg-opt/Samgita/discussions

---

**Last Updated:** 2026-03-04
**Guide Version:** 1.0.0
