# Samgita Architecture Guide

This document provides an in-depth look at Samgita's technical architecture, design decisions, and implementation patterns.

## Table of Contents

1. [System Overview](#system-overview)
2. [Umbrella Structure](#umbrella-structure)
3. [Supervision Trees](#supervision-trees)
4. [Agent Model](#agent-model)
5. [Task System](#task-system)
6. [Memory System](#memory-system)
7. [Provider Architecture](#provider-architecture)
8. [Database Schema](#database-schema)
9. [Web Layer](#web-layer)
10. [Distribution & Clustering](#distribution--clustering)
11. [Quality Gates](#quality-gates)
12. [Performance Considerations](#performance-considerations)

---

## System Overview

Samgita is a **distributed multi-agent orchestration system** built on Elixir/OTP. It transforms Product Requirements Documents (PRDs) into deployed software through coordinated AI agent swarms.

### Core Design Principles

1. **CLI-as-Provider** — Orchestrate Claude Code CLI as supervised processes, not direct LLM API calls
2. **RARV Cycle** — Reason → Act → Reflect → Verify is the atomic unit of agent work
3. **PostgreSQL as Source of Truth** — Database-first architecture, not flat files
4. **OTP for Fault Tolerance** — Supervision trees handle crashes, not bash retry loops
5. **Real-Time Observability** — LiveView dashboard with Phoenix PubSub events
6. **Distributed by Default** — Horde for process distribution, Oban for job distribution

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   Phoenix Application (OTP)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────────────┐  ┌────────────────────┐                 │
│  │   samgita_web      │  │  samgita_memory    │                 │
│  │   (LiveView/API)   │  │  (pgvector/MCP)    │                 │
│  └──────┬─────────────┘  └────────┬───────────┘                 │
│         │                          │                             │
│         └──────────┬───────────────┘                             │
│                    │                                             │
│         ┌──────────▼──────────────┐                              │
│         │     samgita (core)      │                              │
│         │  Projects, Tasks, RARV  │                              │
│         └──────────┬──────────────┘                              │
│                    │                                             │
│         ┌──────────▼──────────────┐                              │
│         │  samgita_provider       │                              │
│         │  (ClaudeCode via CLI)   │                              │
│         └─────────────────────────┘                              │
│                                                                   │
├─────────────────────────────────────────────────────────────────┤
│  Infrastructure Layer                                            │
├─────────────────────────────────────────────────────────────────┤
│  PostgreSQL + pgvector  │  Horde Registry  │  Oban Job Queue    │
│  Phoenix.PubSub         │  ETS Cache       │  Finch HTTP Client │
└─────────────────────────────────────────────────────────────────┘
```

---

## Umbrella Structure

Samgita is an umbrella project with 4 independent OTP applications:

```
apps/
├── samgita_provider/      # Provider abstraction (standalone)
├── samgita/               # Core domain logic
├── samgita_memory/        # Memory system (standalone, shared DB)
└── samgita_web/           # Web interface
```

### Dependency Graph

```
samgita_provider  (standalone, no deps)
       ↑
       │
   samgita  ←───── samgita_web
       ↑
       │
samgita_memory  (standalone, shared DB)
```

### App Responsibilities

| App | Purpose | Key Modules |
|-----|---------|-------------|
| **samgita_provider** | LLM provider abstraction | `SamgitaProvider`, `ClaudeCode`, `Provider` behaviour |
| **samgita** | Core orchestration | `Projects`, `Tasks`, `Agent.Worker`, `Orchestrator` |
| **samgita_memory** | Persistent memory | `Memories.Memory`, `PRD.Execution`, `ThinkingChain`, MCP tools |
| **samgita_web** | User interface | LiveView pages, REST API, PubSub consumers |

### Configuration Isolation

Each app has its own configuration namespace:

```elixir
# samgita_provider
config :samgita_provider, :provider, SamgitaProvider.ClaudeCode
config :samgita_provider, :anthropic_api_key, System.get_env("ANTHROPIC_API_KEY")

# samgita
config :samgita, Samgita.Repo, database: "samgita_dev"
config :samgita, Oban, queues: [agent_tasks: 100, orchestration: 10]
config :samgita, :claude_command, "claude"

# samgita_memory
config :samgita_memory, SamgitaMemory.Repo,
  database: "samgita_dev",  # Same DB, different Repo
  types: SamgitaMemory.PostgrexTypes  # Required for pgvector
config :samgita_memory, Oban, name: SamgitaMemory.Oban  # Named instance
config :samgita_memory, :embedding_provider, :anthropic

# samgita_web
config :samgita_web, SamgitaWeb.Endpoint, http: [port: 3110]
config :bun, samgita_web: [...]
config :tailwind, samgita_web: [...]
```

---

## Supervision Trees

### Root Supervisors

Samgita has 3 root application supervisors:

**1. Samgita.Application (core)**

```elixir
children = [
  Samgita.Repo,
  DNSCluster,
  {Cluster.Supervisor, [topologies, [name: Samgita.ClusterSupervisor]]},
  {Phoenix.PubSub, name: Samgita.PubSub},
  {Finch, name: Samgita.Finch},
  Samgita.Cache,
  {Horde.Registry, [name: Samgita.AgentRegistry, keys: :unique]},
  {Horde.DynamicSupervisor, [name: Samgita.AgentSupervisor, strategy: :one_for_one]},
  {Oban, Application.fetch_env!(:samgita, Oban)}
]
```

**2. SamgitaMemory.Application (memory)**

```elixir
children = [
  SamgitaMemory.Repo,
  SamgitaMemory.Cache.Supervisor,
  SamgitaMemory.Formation.Supervisor,
  {Oban, Application.fetch_env!(:samgita_memory, Oban)}
]
```

**3. SamgitaWeb.Application (web)**

```elixir
children = [
  SamgitaWeb.Telemetry,
  SamgitaWeb.Endpoint
]
```

### Agent Supervision Hierarchy

```
Horde.DynamicSupervisor (Samgita.AgentSupervisor)
  │
  └─ per agent: Samgita.Agent.Worker (gen_statem)
       ├─ State: :idle, :reason, :act, :reflect, :verify
       ├─ RARV cycle execution
       └─ Provider invocation via Port
```

Agents are registered in Horde with naming pattern:
```elixir
{:via, Horde.Registry, {Samgita.AgentRegistry, {:agent, project_id, agent_id}}}
```

This enables:
- Distributed agent lookup across nodes
- Automatic failover on node crashes
- Process migration during deployments

### Project Orchestrator

The orchestrator is a `gen_statem` state machine managing project lifecycle:

```elixir
:bootstrap → :discovery → :architecture → :infrastructure →
:development → :qa → :deployment → :business → :growth → :perpetual
```

**State Transitions:**

Each phase transition requires:
1. All phase tasks completed
2. Quality gates passed (if applicable)
3. Git checkpoint created
4. Phase completion event recorded

**Orchestrator Module:**
```elixir
defmodule Samgita.Project.Orchestrator do
  @behaviour :gen_statem

  def callback_mode, do: [:state_functions, :state_enter]

  # Phase implementations
  def bootstrap(:enter, _old_state, data), do: ...
  def bootstrap(:cast, {:task_completed, task}, data), do: ...
  def discovery(:enter, _old_state, data), do: ...
  # ... etc
end
```

---

## Agent Model

### The RARV Cycle

Every agent follows the Reason-Act-Reflect-Verify cycle:

```
┌─────────────────────────────────────────────────────────┐
│                    RARV State Machine                    │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  :idle ──task──▶ :reason ──▶ :act ──▶ :reflect ──▶ :verify
│                    ▲                                 │    │
│                    └────────on failure───────────────┘    │
│                                                           │
│  Retry Logic:                                            │
│  - 1-3 attempts: Retry with error context               │
│  - 4th attempt: Try simpler approach                    │
│  - 5th attempt: Dead letter queue, move to next task    │
└─────────────────────────────────────────────────────────┘
```

**State Functions:**

```elixir
defmodule Samgita.Agent.Worker do
  @behaviour :gen_statem

  # REASON: Analyze context, identify task
  def reason(:enter, _old_state, data) do
    task = fetch_highest_priority_task(data)
    context = load_relevant_memories(data.project_id, task)
    {:next_state, :act, %{data | task: task, context: context}}
  end

  # ACT: Execute via provider
  def act(:enter, _old_state, data) do
    {:ok, result} = SamgitaProvider.query(
      build_prompt(data.task, data.context),
      system_prompt: agent_system_prompt(data.agent_type),
      model: model_for_agent(data.agent_type)
    )
    {:next_state, :reflect, %{data | result: result}}
  end

  # REFLECT: Update memory, record learnings
  def reflect(:enter, _old_state, data) do
    update_working_memory(data.result)
    extract_learnings(data.result)
    {:next_state, :verify, data}
  end

  # VERIFY: Run tests, validate output
  def verify(:enter, _old_state, data) do
    case validate_result(data.result) do
      :ok ->
        mark_task_complete(data.task)
        {:next_state, :idle, data}

      {:error, reason} ->
        increment_attempts(data.task)
        if data.task.attempts >= 5 do
          move_to_dead_letter(data.task)
          {:next_state, :idle, data}
        else
          {:next_state, :reason, %{data | error: reason}}
        end
    end
  end
end
```

### Agent Types & Model Selection

**37 agent types across 7 swarms:**

```elixir
# apps/samgita/lib/samgita/agent/types.ex
@agent_types %{
  engineering: [:eng_frontend, :eng_backend, :eng_database, :eng_mobile,
                :eng_api, :eng_qa, :eng_perf, :eng_infra],
  operations: [:ops_devops, :ops_sre, :ops_security, :ops_monitor,
               :ops_incident, :ops_release, :ops_cost, :ops_compliance],
  business: [:biz_marketing, :biz_sales, :biz_finance, :biz_legal,
             :biz_support, :biz_hr, :biz_investor, :biz_partnerships],
  data: [:data_ml, :data_eng, :data_analytics],
  product: [:prod_pm, :prod_design, :prod_techwriter],
  growth: [:growth_hacker, :growth_community, :growth_success, :growth_lifecycle],
  review: [:review_code, :review_business, :review_security]
}

@model_selection %{
  opus: [:prod_pm, :eng_infra],  # Planning, architecture
  sonnet: [:eng_frontend, :eng_backend, :eng_api, :eng_database,
           :ops_devops, :ops_sre, :data_ml],  # Implementation
  haiku: [:eng_qa, :ops_monitor, :review_code]  # Fast tasks
}
```

### Agent Spawning

Agents are spawned on demand by the orchestrator:

```elixir
# Phase-specific agent spawning
def bootstrap_agents(project) do
  spawn_agent(project, :prod_pm)      # Parse PRD
  spawn_agent(project, :eng_infra)    # Setup structure
end

def development_agents(project) do
  # Parallel implementation
  spawn_agent(project, :eng_frontend)
  spawn_agent(project, :eng_backend)
  spawn_agent(project, :eng_database)
  spawn_agent(project, :eng_api)
  spawn_agent(project, :eng_qa)       # Test generation
end

defp spawn_agent(project, agent_type) do
  Horde.DynamicSupervisor.start_child(
    Samgita.AgentSupervisor,
    {Samgita.Agent.Worker, [project: project, type: agent_type]}
  )
end
```

---

## Task System

### Task Schema

```elixir
schema "tasks" do
  belongs_to :project, Project
  belongs_to :parent_task, Task  # Hierarchical decomposition

  field :type, :string            # bootstrap, implement, review, etc.
  field :priority, :integer       # 1 = highest
  field :status, Ecto.Enum        # pending, running, completed, failed, dead_letter
  field :payload, :map            # Task-specific data (prd_id, files, etc.)
  field :result, :map             # Output on completion
  field :error, :map              # Error details on failure
  field :agent_id, :string        # Which agent claimed this task
  field :attempts, :integer       # Retry counter
  field :tokens_used, :integer    # LLM token consumption
  field :duration_ms, :integer    # Execution time

  timestamps()
end
```

### Task State Machine

```
pending → running → completed
                  → failed → (retry) → pending
                           → (max retries) → dead_letter
```

### Oban Integration

Tasks are dispatched via Oban workers:

```elixir
# apps/samgita/lib/samgita/workers/agent_task_worker.ex
defmodule Samgita.Workers.AgentTaskWorker do
  use Oban.Worker, queue: :agent_tasks, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    task = Tasks.get_task!(task_id)
    agent = find_or_spawn_agent(task)

    # Send task to agent via gen_statem cast
    :gen_statem.cast(agent, {:execute_task, task})

    :ok
  end
end
```

**Oban Configuration:**

```elixir
config :samgita, Oban,
  repo: Samgita.Repo,
  queues: [
    agent_tasks: 100,      # High concurrency for agent work
    orchestration: 10,     # Phase management
    snapshots: 5           # State checkpointing
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # Keep 7 days
    {Oban.Plugins.Cron, crontab: [
      {"0 3 * * *", Samgita.Workers.SnapshotWorker}  # Daily 3 AM
    ]}
  ]
```

### Task Hierarchies

Tasks can be decomposed into subtasks:

```elixir
# Parent task
task = %Task{
  type: "implement_feature",
  payload: %{feature: "user_auth"}
}

# Child tasks
subtask_1 = %Task{
  parent_task_id: task.id,
  type: "implement_schema",
  payload: %{schema: "User"}
}

subtask_2 = %Task{
  parent_task_id: task.id,
  type: "implement_controller",
  payload: %{controller: "SessionController"}
}

subtask_3 = %Task{
  parent_task_id: task.id,
  type: "write_tests",
  payload: %{test_file: "session_controller_test.exs"}
}
```

Parent task completes only when all children complete.

---

## Memory System

### Architecture

The memory system (`samgita_memory`) provides persistent context across agent sessions.

```
┌────────────────────────────────────────────────────────┐
│            Memory Retrieval Pipeline                   │
├────────────────────────────────────────────────────────┤
│                                                         │
│  Query → Scope Filter → Type Filter → Tag Filter →    │
│          Semantic Search → Recency Boost →              │
│          Confidence Threshold → Deduplication           │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### Three-Tier Memory

| Tier | Storage | Lifespan | Access Pattern |
|------|---------|----------|----------------|
| **Working** | gen_statem state | Session | Direct access |
| **Episodic** | PostgreSQL + ETS | Days-weeks | Recent events, specific facts |
| **Semantic** | pgvector (1536-dim) | Months | Patterns, abstractions, generalizations |
| **Procedural** | PostgreSQL | Years | Skills, templates, reusable procedures |

### Memory Schema

```elixir
# apps/samgita_memory/lib/samgita_memory/memories/memory.ex
schema "sm_memories" do
  field :content, :string
  field :embedding, Pgvector.Ecto.Vector  # 1536 dimensions
  field :source_type, Ecto.Enum,
    values: [:conversation, :observation, :user_edit, :prd_event, :compaction]
  field :scope_type, Ecto.Enum,
    values: [:global, :project, :agent]
  field :scope_id, :string
  field :memory_type, Ecto.Enum,
    values: [:episodic, :semantic, :procedural]
  field :confidence, :float, default: 1.0  # Decays over time
  field :access_count, :integer, default: 0
  field :tags, {:array, :string}
  field :metadata, :map
  field :accessed_at, :utc_datetime

  timestamps()
end
```

### Hybrid Retrieval

Combines semantic similarity with recency and access frequency:

```elixir
# apps/samgita_memory/lib/samgita_memory/retrieval/hybrid.ex
def retrieve(query, opts \\ []) do
  scope_id = Keyword.fetch!(opts, :scope_id)
  memory_type = Keyword.get(opts, :memory_type)
  limit = Keyword.get(opts, :limit, 10)

  # 1. Scope filter (ETS cache)
  candidates = ETS.lookup(:memory_table, scope_id)

  # 2. Type filter
  candidates = filter_by_type(candidates, memory_type)

  # 3. Semantic search (pgvector)
  embedding = embed(query)
  candidates = cosine_similarity(candidates, embedding)

  # 4. Scoring
  candidates
  |> Enum.map(&score_memory(&1, query))
  |> Enum.sort_by(& &1.score, :desc)
  |> Enum.take(limit)
end

defp score_memory(memory, _query) do
  semantic_score = memory.cosine_similarity
  recency_score = recency_boost(memory.inserted_at)
  access_score = access_frequency_boost(memory.access_count)

  score = semantic_score * 0.7 + recency_score * 0.2 + access_score * 0.1
  %{memory | score: score * memory.confidence}
end
```

### Confidence Decay

Memories decay over time based on type:

```elixir
# apps/samgita_memory/lib/samgita_memory/workers/compaction.ex
def perform(_job) do
  # Decay rates per type
  decay_rates = %{
    episodic: 0.98,    # Half-life: ~34 days
    semantic: 0.995,   # Half-life: ~138 days
    procedural: 0.999  # Half-life: ~693 days
  }

  # Apply decay
  Repo.query!("""
    UPDATE sm_memories
    SET confidence = confidence * $1
    WHERE memory_type = $2
  """, [decay_rates[type], type])

  # Prune low confidence
  Repo.delete_all(from m in Memory, where: m.confidence < 0.1)
end
```

Access resets confidence: `max(current_confidence, 0.8)`

### MCP Tools

Memory system exposes 10 MCP tools:

```elixir
# apps/samgita_memory/lib/samgita_memory/mcp/tools.ex
@tools [
  %{name: "remember", description: "Store a memory", ...},
  %{name: "recall", description: "Retrieve relevant memories", ...},
  %{name: "forget", description: "Remove a memory", ...},
  %{name: "prd_context", description: "Get PRD execution state", ...},
  %{name: "prd_event", description: "Log PRD event", ...},
  %{name: "prd_decision", description: "Record decision", ...},
  %{name: "start_thinking", description: "Begin reasoning chain", ...},
  %{name: "think", description: "Add thought to chain", ...},
  %{name: "finish_thinking", description: "Complete chain", ...},
  %{name: "recall_reasoning", description: "Find similar reasoning", ...}
]
```

Agents invoke these via the Claude CLI's MCP support.

---

## Provider Architecture

### CLI-as-Provider Model

Samgita does **not** call LLM APIs directly. It orchestrates CLI tools as supervised processes.

```
Agent Worker (gen_statem)
     │
     └─▶ SamgitaProvider.query(prompt, opts)
              │
              ├─▶ :mock → "mock response"
              │
              └─▶ ClaudeCode → System.cmd("claude", [...])
                      │
                      └─▶ --print --output-format json
                          --model sonnet
                          --system-prompt "You are..."
                          --dangerously-skip-permissions
                          "What is 2+2?"
```

### Provider Behaviour

```elixir
# apps/samgita_provider/lib/samgita_provider/provider.ex
defmodule SamgitaProvider.Provider do
  @callback query(prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
end
```

### ClaudeCode Implementation

```elixir
# apps/samgita_provider/lib/samgita_provider/claude_code.ex
defmodule SamgitaProvider.ClaudeCode do
  @behaviour SamgitaProvider.Provider

  def query(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, "sonnet")
    system_prompt = Keyword.get(opts, :system_prompt, default_prompt())
    max_turns = Keyword.get(opts, :max_turns, 10)

    args = [
      "--print",
      "--output-format", "json",
      "--model", model,
      "--system-prompt", system_prompt,
      "--max-turns", to_string(max_turns),
      "--dangerously-skip-permissions",
      "--no-session-persistence",
      prompt
    ]

    case System.cmd(claude_command(), args, stderr_to_stdout: true) do
      {output, 0} ->
        parse_response(output)

      {error, _} ->
        handle_error(error)
    end
  end

  defp parse_response(json_output) do
    json_output
    |> Jason.decode!()
    |> Map.get("result")
    |> then(&{:ok, &1})
  rescue
    _ -> {:error, "Failed to parse CLI output"}
  end
end
```

### Why CLI, Not API?

| Concern | CLI Approach | Direct API Approach |
|---------|--------------|---------------------|
| **Tool execution** | CLI handles (Read, Write, Edit, Bash, Glob, etc.) | Must reimplement all tools |
| **Authentication** | CLI manages (OAuth, API key) | Must implement auth flow |
| **Context management** | CLI tracks conversation | Must track history manually |
| **Rate limiting** | CLI handles backoff | Must implement rate limiter |
| **Model selection** | CLI abstracts | Must hardcode model names |
| **Streaming** | CLI supports | Must handle SSE/WebSocket |
| **MCP support** | CLI provides | Must implement MCP client |

**OTP Advantage:** Supervised Port process vs. bash PID files

---

## Database Schema

### Core Tables

**Projects:**
```sql
CREATE TABLE projects (
  id UUID PRIMARY KEY,
  name VARCHAR NOT NULL,
  git_url VARCHAR UNIQUE NOT NULL,  -- Canonical identifier
  working_path VARCHAR,
  prd_content TEXT,
  phase VARCHAR NOT NULL,  -- bootstrap, discovery, etc.
  status VARCHAR NOT NULL,  -- pending, running, paused, completed, failed
  config JSONB DEFAULT '{}',
  active_prd_id UUID REFERENCES prds(id),
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_phase ON projects(phase);
```

**Tasks:**
```sql
CREATE TABLE tasks (
  id UUID PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  parent_task_id UUID REFERENCES tasks(id),
  type VARCHAR NOT NULL,
  priority INTEGER DEFAULT 10,
  status VARCHAR NOT NULL,
  payload JSONB DEFAULT '{}',
  result JSONB,
  error JSONB,
  agent_id VARCHAR,
  attempts INTEGER DEFAULT 0,
  tokens_used INTEGER DEFAULT 0,
  duration_ms INTEGER,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_tasks_project_status ON tasks(project_id, status);
CREATE INDEX idx_tasks_prd_id ON tasks USING GIN ((payload->'prd_id'));
CREATE INDEX idx_tasks_priority ON tasks(priority);
```

**Agent Runs:**
```sql
CREATE TABLE agent_runs (
  id UUID PRIMARY KEY,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  agent_type VARCHAR NOT NULL,
  agent_id VARCHAR NOT NULL,
  status VARCHAR NOT NULL,
  node VARCHAR,
  pid VARCHAR,
  metrics JSONB DEFAULT '{}',
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_agent_runs_project_type ON agent_runs(project_id, agent_type);
```

### Memory Tables (sm_ prefix)

**Memories:**
```sql
CREATE TABLE sm_memories (
  id UUID PRIMARY KEY,
  content TEXT NOT NULL,
  embedding vector(1536),  -- pgvector type
  source_type VARCHAR NOT NULL,
  scope_type VARCHAR NOT NULL,
  scope_id VARCHAR NOT NULL,
  memory_type VARCHAR NOT NULL,
  confidence FLOAT DEFAULT 1.0,
  access_count INTEGER DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  metadata JSONB DEFAULT '{}',
  accessed_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_sm_memories_scope ON sm_memories(scope_type, scope_id);
CREATE INDEX idx_sm_memories_type ON sm_memories(memory_type);
CREATE INDEX idx_sm_memories_tags ON sm_memories USING GIN(tags);
CREATE INDEX idx_sm_memories_embedding ON sm_memories USING ivfflat(embedding vector_cosine_ops);
```

**PRD Executions:**
```sql
CREATE TABLE sm_prd_executions (
  id UUID PRIMARY KEY,
  prd_ref VARCHAR NOT NULL,
  prd_hash VARCHAR NOT NULL,
  title VARCHAR,
  status VARCHAR NOT NULL,
  progress JSONB DEFAULT '{}',
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_sm_prd_executions_ref ON sm_prd_executions(prd_ref);
```

### Oban Tables

Oban creates its own tables for job management:

```sql
CREATE TABLE oban_jobs (
  id BIGSERIAL PRIMARY KEY,
  state VARCHAR NOT NULL DEFAULT 'available',
  queue VARCHAR NOT NULL,
  worker VARCHAR NOT NULL,
  args JSONB NOT NULL DEFAULT '{}',
  errors JSONB[] DEFAULT ARRAY[]::JSONB[],
  attempt INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 20,
  inserted_at TIMESTAMP NOT NULL,
  scheduled_at TIMESTAMP NOT NULL,
  attempted_at TIMESTAMP,
  completed_at TIMESTAMP,
  discarded_at TIMESTAMP,
  priority INTEGER DEFAULT 0,
  tags VARCHAR[] DEFAULT ARRAY[]::VARCHAR[],
  meta JSONB DEFAULT '{}'
);
```

---

## Web Layer

### Phoenix LiveView Pages

**9 LiveView pages:**

1. **DashboardLive** — Project overview, status grid
2. **ProjectFormLive** — Create/edit projects
3. **ProjectLive** — Single project detail with PRDs
4. **PrdChatLive** — Interactive PRD creation/editing
5. **AgentsLive** — Agent type reference
6. **McpLive** — MCP server status
7. **SkillsLive** — Skill system (future)
8. **ReferencesLive (Index)** — Browse reference docs
9. **ReferencesLive (Show)** — Display single reference

### Real-Time Updates

All pages use Phoenix.PubSub for real-time updates:

```elixir
defmodule SamgitaWeb.ProjectLive.Index do
  use SamgitaWeb, :live_view

  def mount(%{"id" => project_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Samgita.PubSub, "project:#{project_id}")
    end

    {:ok, assign(socket, project: load_project(project_id))}
  end

  def handle_info({:phase_changed, new_phase}, socket) do
    {:noreply, update(socket, :project, &%{&1 | phase: new_phase})}
  end

  def handle_info({:agent_state_changed, agent_id, state}, socket) do
    {:noreply, update_agent_in_grid(socket, agent_id, state)}
  end
end
```

**Event Topics:**
- `project:#{project_id}` — Project-level events
- `agent:#{agent_id}` — Agent state changes
- `task:#{task_id}` — Task updates
- `prd:#{prd_id}` — PRD execution events

### REST API

API implemented via Phoenix controllers with JSON responses.

**Key Controllers:**
- `ProjectController` — CRUD, pause/resume
- `PrdController` — PRD management
- `TaskController` — Task listing, retry
- `AgentRunController` — Agent history
- `WebhookController` — Event subscriptions
- `NotificationController` — Alert management
- `FeatureController` — Feature flags

**Plugs:**
- `ApiAuth` — API key verification
- `RateLimit` — Token bucket rate limiter

---

## Distribution & Clustering

### Horde for Process Distribution

Agents use Horde for distributed registration:

```elixir
# Start agent on any node
{:ok, pid} = Horde.DynamicSupervisor.start_child(
  Samgita.AgentSupervisor,
  {Samgita.Agent.Worker, [project: project, type: :eng_backend]}
)

# Lookup agent from any node
{:ok, pid} = Horde.Registry.lookup(
  Samgita.AgentRegistry,
  {:agent, project_id, agent_id}
)

# Agent automatically migrates on node failure
```

### libcluster for Node Discovery

```elixir
# config/runtime.exs
topologies = [
  local: [
    strategy: Cluster.Strategy.Epmd,
    config: [hosts: [:"node1@localhost", :"node2@localhost"]]
  ]
]

config :libcluster,
  topologies: topologies
```

**Multi-node deployment:**

```bash
# Node 1
iex --sname node1 --cookie samgita -S mix phx.server

# Node 2 (joins automatically)
iex --sname node2 --cookie samgita -S mix phx.server

# Verify cluster
iex(node1@localhost)> Node.list()
[:"node2@localhost"]
```

### Oban for Job Distribution

Oban distributes jobs across nodes automatically:

```elixir
# Enqueue on node1
%{task_id: task_id}
|> Samgita.Workers.AgentTaskWorker.new()
|> Oban.insert()

# Executes on node1 or node2 depending on queue availability
```

---

## Quality Gates

### 9-Gate System

Every code change passes through:

1. **Input Guardrails** — Validate task parameters, detect prompt injection
2. **Static Analysis** — Linting (credo), type checking (dialyzer), compilation
3. **Blind Review** — 3 parallel reviewers (code, business, security)
4. **Anti-Sycophancy** — Devil's advocate on unanimous approval
5. **Output Guardrails** — Secret detection, spec compliance
6. **Severity Blocking** — Critical/High/Medium = BLOCK
7. **Test Coverage** — Unit tests 100% pass, >80% coverage
8. **Mock Detector** — Flag tests that never import source
9. **Test Mutation** — Detect weak assertions

### Blind Review Implementation

```elixir
def blind_review(artifact) do
  reviewers = [:review_code, :review_business, :review_security]

  # Spawn 3 agents in parallel
  tasks = Enum.map(reviewers, fn type ->
    Task.async(fn ->
      spawn_reviewer(artifact, type)
    end)
  end)

  # Wait for all reviews
  reviews = Task.await_many(tasks, 60_000)

  # Aggregate findings
  aggregate_reviews(reviews)
end

defp aggregate_reviews(reviews) do
  all_approve? = Enum.all?(reviews, &(&1.decision == :approve))

  if all_approve? do
    # Anti-sycophancy gate
    spawn_devil_advocate(reviews)
  else
    # At least one rejection
    {:reject, extract_issues(reviews)}
  end
end
```

---

## Performance Considerations

### ETS Caching

Hot data cached in ETS with PubSub invalidation:

```elixir
# apps/samgita/lib/samgita/cache.ex
def get_or_fetch(key, fetch_fn) do
  case :ets.lookup(:samgita_cache, key) do
    [{^key, value, expires_at}] when expires_at > now() ->
      value

    _ ->
      value = fetch_fn.()
      :ets.insert(:samgita_cache, {key, value, now() + @ttl})
      value
  end
end

def invalidate(key) do
  :ets.delete(:samgita_cache, key)
  Phoenix.PubSub.broadcast(Samgita.PubSub, "cache", {:invalidate, key})
end
```

### Connection Pooling

```elixir
# Ecto connection pool
config :samgita, Samgita.Repo,
  pool_size: 10

# Finch HTTP pool
config :samgita, Samgita.Finch,
  pools: %{
    default: [size: 25]
  }
```

### Oban Tuning

```elixir
config :samgita, Oban,
  queues: [
    agent_tasks: [limit: 100, paused: false],
    orchestration: [limit: 10, paused: false],
    snapshots: [limit: 5, paused: false]
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]
```

### Database Indexes

Critical indexes for performance:

```sql
-- Fast project lookup by git_url
CREATE UNIQUE INDEX idx_projects_git_url ON projects(git_url);

-- Fast task queries by status
CREATE INDEX idx_tasks_project_status ON tasks(project_id, status);

-- JSONB path for PRD-scoped tasks
CREATE INDEX idx_tasks_prd_id ON tasks USING GIN ((payload->'prd_id'));

-- Vector similarity search
CREATE INDEX idx_sm_memories_embedding ON sm_memories
  USING ivfflat(embedding vector_cosine_ops)
  WITH (lists = 100);
```

---

## Monitoring & Observability

### Telemetry Events

Samgita emits structured telemetry:

```elixir
:telemetry.execute(
  [:samgita, :agent, :rarv_cycle],
  %{duration: duration_ms, tokens: tokens_used},
  %{agent_type: :eng_backend, project_id: project_id}
)

:telemetry.execute(
  [:samgita, :task, :completed],
  %{duration: duration_ms},
  %{task_type: task.type, success: true}
)
```

### Metrics Collection

```elixir
# apps/samgita_web/lib/samgita_web/telemetry.ex
def metrics do
  [
    # Agent metrics
    summary("samgita.agent.rarv_cycle.duration"),
    counter("samgita.agent.spawned.count"),
    counter("samgita.agent.failed.count"),

    # Task metrics
    summary("samgita.task.completed.duration"),
    counter("samgita.task.retry.count"),

    # Provider metrics
    summary("samgita.provider.query.duration"),
    counter("samgita.provider.tokens.count")
  ]
end
```

---

**Last Updated:** 2026-03-03
**Version:** 1.0.0
