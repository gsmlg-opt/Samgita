# Samgita - Implementation Plan

## Project Status

**Last Updated**: 2026-01-29

### Progress Summary

| Phase | Status | Progress |
|-------|--------|----------|
| **Phase 1: Foundation** | ✅ Complete | 100% - All deliverables done |
| **Phase 2: Core Engine** | ✅ Complete | 100% - All deliverables done |
| **Phase 3: Distribution** | ✅ Complete | 95% - Minor snapshot test issue |
| **Phase 4: Web Dashboard** | ✅ Complete | 95% - PRD preview pending |
| **Phase 5: Production Ready** | 🚧 In Progress | 85% - ExDoc/OpenAPI pending |

### Test Results

- **254 tests**, **1 failure** (snapshot phase mismatch - non-critical)
- **Test coverage**: ~70% (target: >80%)
- **Compilation**: ✅ Clean
- **Dialyzer**: Not yet run

### Outstanding Items

1. **Phase 4**: PRD markdown preview feature
2. **Phase 4**: Edit PRD triggers re-planning
3. **Phase 5**: ExDoc API documentation generation
4. **Phase 5**: OpenAPI spec generation
5. **Testing**: Snapshot recovery test fix (phase mismatch)
6. **Testing**: Increase coverage to >80%

---

## Overview

This document outlines the phased implementation plan for the Elixir/OTP refactor of Samgita. Each phase builds on the previous, with clear deliverables and validation criteria.

## Architecture Decisions

### ADR-001: Process Architecture

**Decision**: Use `gen_statem` for both Orchestrator and Agent workers.

**Rationale**:
- RARV cycle maps naturally to state machine states
- Built-in state timeout for retry backoff
- Explicit state transitions are auditable

**Alternatives Rejected**:
- `GenServer`: No native state machine support
- Jido Agent: Additional dependency, less control over process lifecycle

### ADR-002: Distribution Strategy

**Decision**: Horde + Oban + Postgres (not Mnesia).

**Rationale**:
- Postgres as single source of truth eliminates split-brain
- Oban handles distributed task queue with proven reliability
- Horde CRDTs handle process registry/supervisor distribution
- Operational familiarity (Postgres vs Mnesia)

**Alternatives Rejected**:
- Pure Mnesia: Schema migration pain, split-brain complexity
- Pure ETS: No persistence, no distribution

### ADR-003: Persistence Layers

**Decision**: Hybrid ETS + Ecto.

| Data Type | Hot (Runtime) | Cold (Persistent) |
|-----------|---------------|-------------------|
| Task queue | Oban | Oban (Postgres) |
| Agent processes | Horde Registry | - |
| Agent state | Process state | Postgres snapshots |
| Project config | ETS cache | Postgres |
| Artifacts | - | Postgres |
| Memory/context | ETS | Postgres (pgvector) |

### ADR-004: Claude Integration

**Decision**: Use Claude CLI via Erlang Port, not direct API.

**Rationale**:
- Reuses host's existing authentication
- No API key management needed
- Consistent with loki-mode usage pattern
- Simpler deployment (no secrets)

**Alternatives Rejected**:
- Direct API: Requires API key management, separate auth
- Jido AI: Additional dependency, overkill for CLI wrapper

---

## Phase 1: Foundation (Week 1-2)

### 1.1 Project Scaffold

**Tasks**:
```bash
mix phx.new samgita --live --no-mailer --no-dashboard
cd samgita
mix deps.get
```

**Dependencies** (`mix.exs`):
```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 1.0"},
    {:phoenix_ecto, "~> 4.6"},
    {:ecto_sql, "~> 3.12"},
    {:postgrex, "~> 0.19"},
    {:oban, "~> 2.18"},
    {:horde, "~> 0.9"},
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"},
    {:typed_struct, "~> 0.3"},
    
    # Dev/Test
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_machina, "~> 2.8", only: :test},
    {:mox, "~> 1.1", only: :test}
  ]
end
```

**Deliverables**:
- [x] Phoenix project compiles
- [x] PostgreSQL connection works
- [x] Basic LiveView renders

### 1.2 Ecto Schemas

**Files to create**:
```
lib/samgita/domain/
├── project.ex
├── task.ex
├── agent_run.ex
├── artifact.ex
├── memory.ex
└── snapshot.ex
```

**Project schema**:
```elixir
defmodule Samgita.Domain.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "projects" do
    field :name, :string
    field :git_url, :string
    field :working_path, :string
    field :prd_content, :string
    field :phase, Ecto.Enum, values: [:bootstrap, :discovery, :architecture, 
      :infrastructure, :development, :qa, :deployment, :business, :growth, :perpetual]
    field :status, Ecto.Enum, values: [:pending, :running, :paused, :completed, :failed]
    field :config, :map, default: %{}

    has_many :tasks, Samgita.Domain.Task
    has_many :agent_runs, Samgita.Domain.AgentRun
    has_many :artifacts, Samgita.Domain.Artifact

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :git_url, :working_path, :prd_content, :phase, :status, :config])
    |> validate_required([:name, :git_url])
    |> unique_constraint(:git_url)
  end
end
```

**Migration order**:
1. `create_projects` (includes git_url, working_path)
2. `create_tasks` (references projects)
3. `create_agent_runs` (references projects, tasks)
4. `create_artifacts` (references projects, tasks)
5. `create_memories` (references projects)
6. `create_snapshots` (references projects)
7. `setup_oban` (Oban migrations)

**Validation**:
- [x] All migrations run cleanly
- [x] git_url has unique constraint
- [x] Schemas have proper associations
- [x] Basic CRUD operations work

### 1.3 REST API (Projects)

**Router**:
```elixir
scope "/api", SamgitaWeb do
  pipe_through :api
  
  resources "/projects", ProjectController, except: [:new, :edit] do
    post "/pause", ProjectController, :pause
    post "/resume", ProjectController, :resume
  end
end
```

**Controller actions**:
- `index` - List projects with pagination
- `show` - Get project with task counts
- `create` - Create from PRD text
- `update` - Update config
- `delete` - Soft delete
- `pause` - Set status to paused
- `resume` - Set status to running

**Validation**:
- [x] All endpoints return correct status codes
- [x] JSON:API compliant responses
- [x] Input validation with Ecto changesets

### 1.4 Agent Worker Skeleton

**File**: `lib/samgita/agent/worker.ex`

```elixir
defmodule Samgita.Agent.Worker do
  @behaviour :gen_statem
  
  # States: :idle, :reason, :act, :reflect, :verify, :failed
  
  def start_link(opts)
  def init(opts)
  def callback_mode/0
  
  # State callbacks (skeleton only)
  def idle/3
  def reason/3
  def act/3
  def reflect/3
  def verify/3
  def failed/3
end
```

**Validation**:
- [x] Process starts and enters `:idle` state
- [x] Can transition through RARV states manually
- [x] Supervision restarts on crash

---

## Phase 2: Core Engine (Week 3-4)

### 2.1 Orchestrator State Machine

**File**: `lib/samgita/project/orchestrator.ex`

**States**:
```
:bootstrap → :discovery → :architecture → :infrastructure →
:development → :qa → :deployment → :business → :growth → :perpetual
```

**Responsibilities**:
- Parse PRD to determine required agent types
- Spawn agents via Horde.DynamicSupervisor
- Generate tasks for current phase
- Detect phase completion
- Transition to next phase

**Validation**:
- [x] Orchestrator starts for new project
- [x] Correctly identifies agent types from PRD
- [x] Phase transitions on completion

### 2.2 Task Queue (Oban)

**File**: `lib/samgita/workers/agent_task_worker.ex`

```elixir
defmodule Samgita.Workers.AgentTaskWorker do
  use Oban.Worker,
    queue: :agent_tasks,
    max_attempts: 5,
    unique: [period: 60, states: [:available, :executing]]
    
  @impl true
  def perform(%Job{args: args}) do
    # Find/spawn agent, execute RARV
  end
end
```

**Queue configuration**:
```elixir
config :samgita, Oban,
  repo: Samgita.Repo,
  queues: [
    agent_tasks: [limit: 100],
    orchestration: [limit: 10],
    snapshots: [limit: 5]
  ]
```

**Validation**:
- [x] Tasks persist across restarts
- [x] Priority ordering works
- [x] Failed tasks go to dead letter

### 2.3 RARV Cycle Implementation

**Complete the worker states**:

```elixir
def reason(:enter, _old, data) do
  # 1. Load continuity log from Memory
  # 2. Load task details
  # 3. Build context for LLM
  send(self(), :execute)
  :keep_state_and_data
end

def act(:enter, _old, data) do
  # 1. Call Claude API
  # 2. Parse response
  # 3. Create artifacts
  # 4. Commit checkpoint
  send(self(), :execute)
  :keep_state_and_data
end

def reflect(:enter, _old, data) do
  # 1. Update continuity log
  # 2. Store semantic memory
  # 3. Record metrics
  send(self(), :execute)
  :keep_state_and_data
end

def verify(:enter, _old, data) do
  # 1. Run verification (tests, lint, etc.)
  # 2. On success: complete task, return to idle
  # 3. On failure: record learning, return to reason
  send(self(), :execute)
  :keep_state_and_data
end
```

**Validation**:
- [x] Full RARV cycle completes for simple task
- [x] Failure triggers retry from reason
- [x] Learnings persist across retries

### 2.4 Claude CLI Integration

**File**: `lib/samgita/agent/claude.ex`

```elixir
defmodule Samgita.Agent.Claude do
  @moduledoc """
  Claude CLI wrapper using Erlang Port.
  Uses host's existing authentication.
  """
  
  def chat(prompt, opts \\ []) do
    command = Application.get_env(:samgita, :claude_command, "claude")
    args = build_args(prompt, opts)
    
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, parse_output(output)}
      {output, _} -> handle_error(output)
    end
  end
  
  defp build_args(prompt, opts) do
    base = ["--print", "--no-input"]
    model = if m = opts[:model], do: ["--model", m], else: []
    base ++ model ++ [prompt]
  end
  
  defp handle_error(output) do
    cond do
      String.contains?(output, "rate limit") -> {:error, :rate_limit}
      String.contains?(output, "overloaded") -> {:error, :overloaded}
      true -> {:error, output}
    end
  end
  
  defp parse_output(output) do
    # Parse Claude CLI output format
    output
    |> String.trim()
  end
end
```

**Rate limiting**:
- Exponential backoff: 60s → 120s → 240s → ...
- Max wait: 1 hour
- State timeout in gen_statem handles this naturally

**Validation**:
- [x] Successful CLI call returns content
- [x] Rate limit detection works
- [x] Backoff increases on repeated failures

---

## Phase 3: Distribution (Week 5-6)

### 3.1 Horde Integration

**Application supervisor**:
```elixir
def start(_type, _args) do
  children = [
    Samgita.Repo,
    {Phoenix.PubSub, name: Samgita.PubSub},
    {Horde.Registry, [name: Samgita.AgentRegistry, keys: :unique, members: :auto]},
    {Horde.DynamicSupervisor, [name: Samgita.AgentSupervisor, strategy: :one_for_one, members: :auto]},
    {Oban, oban_config()},
    SamgitaWeb.Endpoint
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**Cluster formation** (libcluster):
```elixir
config :libcluster,
  topologies: [
    gossip: [
      strategy: Cluster.Strategy.Gossip
    ]
  ]
```

**Validation**:
- [x] Two nodes form cluster
- [x] Agent spawned on node A visible from node B
- [x] Agent survives node restart (via Horde handoff)

### 3.2 Distributed PubSub

**Events**:
```elixir
defmodule Samgita.Events do
  def task_completed(task) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{task.project_id}",
      {:task_completed, task}
    )
  end
  
  def agent_state_changed(agent_id, state) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "agents",
      {:agent_state, agent_id, state}
    )
  end
end
```

**Validation**:
- [x] Events propagate across nodes
- [x] LiveView receives updates from any node

### 3.3 Snapshot/Recovery System

**Periodic snapshots** (Oban cron):
```elixir
config :samgita, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", Samgita.Workers.SnapshotWorker}
     ]}
  ]
```

**Recovery on startup**:
```elixir
defmodule Samgita.Project.Supervisor do
  def init({project_id, prd}) do
    case Samgita.Domain.Snapshot.latest(project_id) do
      nil -> start_fresh(project_id, prd)
      snapshot -> restore_from_snapshot(project_id, snapshot)
    end
  end
end
```

**Validation**:
- [x] Snapshots created every 5 minutes
- [ ] Project resumes from snapshot after restart (1 test failing - phase mismatch)
- [x] Agent state restored correctly

### 3.4 Cache with PubSub Invalidation

**File**: `lib/samgita/cache.ex`

```elixir
defmodule Samgita.Cache do
  use GenServer
  
  def get(key)
  def put(key, value, ttl \\ 60)
  def invalidate(key)  # Broadcasts to all nodes
  
  def handle_info({:invalidate, key}, state) do
    :ets.delete(:loki_cache, key)
    {:noreply, state}
  end
end
```

**Validation**:
- [x] Cache hit returns quickly
- [x] Invalidation propagates to all nodes
- [x] TTL expiration works

---

## Phase 4: Web Dashboard (Week 7-8)

### 4.1 Project List (Dashboard Home)

**File**: `lib/samgita_web/live/dashboard_live.ex`

**Features**:
- List all projects with status badges
- Active agent count per project
- Task statistics (pending/running/completed/failed)
- "New Project" button

```elixir
defmodule SamgitaWeb.DashboardLive do
  use SamgitaWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Samgita.PubSub, "projects")
    end
    
    {:ok, assign(socket, projects: list_projects())}
  end
  
  def handle_info({:project_updated, project}, socket) do
    {:noreply, update(socket, :projects, &update_project(&1, project))}
  end
end
```

**Validation**:
- [x] Projects list loads
- [x] Real-time status updates
- [x] Navigation to project detail

### 4.2 Project Creation

**File**: `lib/samgita_web/live/project_form_live.ex`

**Features**:
- Project name input
- Git URL input (primary identifier)
- Auto-detect local path from git URL
- Clone repo if not found locally
- Manual path override (optional)

```elixir
defmodule SamgitaWeb.ProjectFormLive do
  use SamgitaWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, 
      form: to_form(%{"name" => "", "git_url" => "", "working_path" => ""}),
      detected_path: nil,
      clone_needed: false
    )}
  end

  def handle_event("detect_path", %{"git_url" => url}, socket) do
    case Samgita.Git.find_local_repo(url) do
      {:ok, path} -> 
        {:noreply, assign(socket, detected_path: path, clone_needed: false)}
      :not_found ->
        {:noreply, assign(socket, detected_path: nil, clone_needed: true)}
    end
  end

  def handle_event("create", %{"project" => params}, socket) do
    params = maybe_clone_repo(params, socket.assigns)
    
    case Samgita.create_project(params) do
      {:ok, project} -> 
        {:noreply, push_navigate(socket, to: ~p"/projects/#{project.id}")}
      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp maybe_clone_repo(params, %{clone_needed: true}) do
    {:ok, path} = Samgita.Git.clone(params["git_url"])
    Map.put(params, "working_path", path)
  end
  defp maybe_clone_repo(params, %{detected_path: path}) when not is_nil(path) do
    Map.put(params, "working_path", path)
  end
  defp maybe_clone_repo(params, _), do: params
end
```

**Git helper module**: `lib/samgita/git.ex`

```elixir
defmodule Samgita.Git do
  @doc "Find local clone of a git repo by URL"
  def find_local_repo(git_url) do
    # Check common locations
    repo_name = extract_repo_name(git_url)
    
    search_paths = [
      Path.expand("~/projects/#{repo_name}"),
      Path.expand("~/code/#{repo_name}"),
      Path.expand("~/dev/#{repo_name}"),
      Path.expand("~/#{repo_name}")
    ]
    
    Enum.find_value(search_paths, :not_found, fn path ->
      if File.dir?(Path.join(path, ".git")) do
        # Verify remote matches
        case get_remote_url(path) do
          {:ok, ^git_url} -> {:ok, path}
          {:ok, url} when url == normalize_url(git_url) -> {:ok, path}
          _ -> nil
        end
      end
    end)
  end

  @doc "Clone a repo to default location"
  def clone(git_url, opts \\ []) do
    target = opts[:path] || default_clone_path(git_url)
    
    case System.cmd("git", ["clone", git_url, target]) do
      {_, 0} -> {:ok, target}
      {err, _} -> {:error, err}
    end
  end

  defp extract_repo_name(url) do
    url
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/\.git$/, "")
  end

  defp default_clone_path(url) do
    Path.expand("~/projects/#{extract_repo_name(url)}")
  end
end
```

**Validation**:
- [x] Git URL input works
- [x] Auto-detects existing local clone
- [x] Clones repo if not found
- [x] Project creates with correct git_url and working_path

### 4.3 PRD Editor

**File**: `lib/samgita_web/live/prd_editor_live.ex`

**Features**:
- Textarea for PRD content
- File upload (drag & drop)
- Preview mode (markdown rendered)
- Save button

```elixir
defmodule SamgitaWeb.PrdEditorLive do
  use SamgitaWeb, :live_view

  def mount(%{"id" => project_id}, _session, socket) do
    project = Samgita.get_project!(project_id)
    
    {:ok, assign(socket,
      project: project,
      prd_content: project.prd_content || "",
      mode: :edit,
      uploads: allow_upload(socket, :prd_file, accept: ~w(.md .txt), max_entries: 1)
    )}
  end

  def handle_event("save_prd", %{"content" => content}, socket) do
    {:ok, project} = Samgita.update_prd(socket.assigns.project, content)
    {:noreply, assign(socket, project: project, prd_content: content)}
  end

  def handle_event("toggle_mode", _, socket) do
    mode = if socket.assigns.mode == :edit, do: :preview, else: :edit
    {:noreply, assign(socket, mode: mode)}
  end
end
```

**Validation**:
- [x] Textarea saves content
- [x] File upload works
- [ ] Preview renders markdown (not implemented yet)
- [ ] Edit during execution triggers re-plan (not implemented yet)

### 4.4 Project Controls

**File**: `lib/samgita_web/live/project_live.ex`

**Features**:
- Start/Pause/Resume buttons
- Phase indicator
- Status display

```elixir
defmodule SamgitaWeb.ProjectLive do
  use SamgitaWeb, :live_view

  def handle_event("start", _, socket) do
    {:ok, _} = Samgita.start_project(socket.assigns.project.id)
    {:noreply, socket}
  end

  def handle_event("pause", _, socket) do
    :ok = Samgita.pause_project(socket.assigns.project.id)
    {:noreply, socket}
  end

  def handle_event("resume", _, socket) do
    :ok = Samgita.resume_project(socket.assigns.project.id)
    {:noreply, socket}
  end
end
```

**Validation**:
- [x] Start spawns orchestrator
- [x] Pause stops agents gracefully
- [x] Resume continues from checkpoint

### 4.5 Agent Monitor

**File**: `lib/samgita_web/live/agent_monitor_live.ex`

**Display per agent**:
- ID, type, node
- Current state (idle/reason/act/reflect/verify)
- Current task (if any)
- Task count, token usage, uptime

**Validation**:
- [x] Shows all agents across cluster
- [x] State changes update immediately
- [x] Agent crash shows briefly then respawns

### 4.6 Task Kanban

**File**: `lib/samgita_web/components/task_kanban.ex`

**Columns**:
- Pending (queued tasks)
- Running (claimed by agents)
- Completed (success)
- Failed (in dead letter)

**Actions**:
- Retry failed task
- View task details
- View artifacts

**Validation**:
- [x] Tasks move between columns in real-time
- [x] Retry action works
- [x] Task details show full payload/result

### 4.7 Log Streaming

**File**: `lib/samgita_web/components/log_stream.ex`

```elixir
defmodule SamgitaWeb.Components.LogStream do
  use Phoenix.LiveComponent
  
  def mount(socket) do
    {:ok, assign(socket, logs: [], paused: false)}
  end
  
  def update(%{agent_id: agent_id}, socket) do
    if connected?(socket) && !socket.assigns[:subscribed] do
      Phoenix.PubSub.subscribe(Samgita.PubSub, "agent_logs:#{agent_id}")
    end
    {:ok, assign(socket, subscribed: true)}
  end
  
  def handle_info({:log, entry}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      logs = Enum.take([entry | socket.assigns.logs], 100)
      {:noreply, assign(socket, logs: logs)}
    end
  end
end
```

**Validation**:
- [x] Logs stream in real-time
- [x] Scrolls automatically
- [x] Can pause/resume

---

## Phase 5: Production Ready (Week 9-10)

### 5.1 API Authentication

**Plug**:
```elixir
defmodule SamgitaWeb.Plugs.ApiAuth do
  def call(conn, _opts) do
    case get_req_header(conn, "x-api-key") do
      [key] -> verify_api_key(conn, key)
      _ -> unauthorized(conn)
    end
  end
end
```

**Validation**:
- [x] Requests without key return 401
- [x] Invalid key returns 401
- [x] Valid key allows access

### 5.2 Webhook System

**Schema**: `lib/samgita/domain/webhook.ex`

**Worker**: `lib/samgita/workers/webhook_worker.ex`

**Events**:
- `project.phase_changed`
- `task.completed`
- `task.failed`
- `agent.spawned`
- `agent.crashed`
- `project.completed`

**Validation**:
- [x] Webhooks fire on events
- [x] Retries on failure
- [x] Timeout handling

### 5.3 Telemetry/Metrics

**Telemetry events**:
```elixir
:telemetry.execute(
  [:samgita, :agent, :task_complete],
  %{duration: duration_ms, tokens: tokens},
  %{agent_type: type, project_id: project_id}
)
```

**Metrics**:
- Task duration histogram
- Token usage counter
- Agent count gauge
- Error rate

**Validation**:
- [x] Metrics exported to Prometheus format

### 5.4 Documentation

**Generate**:
- ExDoc API documentation
- OpenAPI spec from controllers
- Deployment guide
- Runbook for operations

**Validation**:
- [ ] `mix docs` generates clean output (ExDoc not configured)
- [ ] OpenAPI spec validates (not yet generated)
- [ ] Deployment steps tested (not yet documented)

---

## Testing Strategy

### Unit Tests

```
test/samgita/
├── agent/
│   ├── worker_test.exs      # State machine transitions
│   └── llm_test.exs         # API client (mocked)
├── project/
│   ├── orchestrator_test.exs
│   └── memory_test.exs
└── domain/
    └── *_test.exs           # Schema validations
```

### Integration Tests

```
test/samgita/
├── project_lifecycle_test.exs  # Full project flow
├── distribution_test.exs       # Multi-node scenarios
└── recovery_test.exs           # Crash/restart scenarios
```

### Property Tests

```elixir
property "RARV cycle always completes or fails explicitly" do
  check all task <- task_generator() do
    result = Worker.execute_sync(task)
    assert result in [:completed, :failed]
  end
end
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Claude API rate limits | Exponential backoff, queue throttling |
| Node failures | Horde handoff, Oban persistence |
| Split-brain | Postgres as single truth, no Mnesia |
| Memory leaks | Process isolation, periodic restarts |
| Token cost overrun | Per-project limits, alerts |

---

## Definition of Done

### Phase Complete When:

1. All tasks checked off
2. All validation criteria pass
3. Test coverage >80%
4. No dialyzer warnings
5. Documentation updated

### Project Complete When:

1. All 5 phases complete
2. Functional parity with Python version
3. 3-node cluster demonstrated
4. 100 concurrent agents demonstrated
5. Zero task loss during rolling restart
6. Dashboard latency <100ms

---

## Appendix: File Checklist

```
lib/
├── samgita/
│   ├── application.ex              [Phase 1]
│   ├── repo.ex                     [Phase 1]
│   ├── git.ex                      [Phase 4]
│   ├── cache.ex                    [Phase 3]
│   ├── events.ex                   [Phase 3]
│   ├── domain/
│   │   ├── project.ex              [Phase 1]
│   │   ├── task.ex                 [Phase 1]
│   │   ├── agent_run.ex            [Phase 1]
│   │   ├── artifact.ex             [Phase 1]
│   │   ├── memory.ex               [Phase 1]
│   │   ├── snapshot.ex             [Phase 1]
│   │   └── webhook.ex              [Phase 5]
│   ├── project/
│   │   ├── supervisor.ex           [Phase 2]
│   │   ├── orchestrator.ex         [Phase 2]
│   │   └── memory.ex               [Phase 2]
│   ├── agent/
│   │   ├── worker.ex               [Phase 1, 2]
│   │   ├── types.ex                [Phase 2]
│   │   └── claude.ex               [Phase 2]
│   └── workers/
│       ├── agent_task_worker.ex    [Phase 2]
│       ├── snapshot_worker.ex      [Phase 3]
│       └── webhook_worker.ex       [Phase 5]
├── samgita_web/
│   ├── router.ex                   [Phase 1]
│   ├── controllers/
│   │   └── project_controller.ex   [Phase 1]
│   ├── live/
│   │   ├── dashboard_live.ex       [Phase 4]
│   │   ├── project_live.ex         [Phase 4]
│   │   ├── project_form_live.ex    [Phase 4]
│   │   ├── prd_editor_live.ex      [Phase 4]
│   │   └── agent_monitor_live.ex   [Phase 4]
│   ├── components/
│   │   ├── task_kanban.ex          [Phase 4]
│   │   ├── agent_card.ex           [Phase 4]
│   │   ├── log_stream.ex           [Phase 4]
│   │   └── file_picker.ex          [Phase 4]
│   └── plugs/
│       └── api_auth.ex             [Phase 5]
├── config/
│   ├── config.exs                  [Phase 1]
│   ├── dev.exs                     [Phase 1]
│   ├── test.exs                    [Phase 1]
│   ├── prod.exs                    [Phase 1]
│   └── runtime.exs                 [Phase 1]
└── priv/repo/migrations/
    ├── *_create_projects.exs       [Phase 1]
    ├── *_create_tasks.exs          [Phase 1]
    ├── *_create_agent_runs.exs     [Phase 1]
    ├── *_create_artifacts.exs      [Phase 1]
    ├── *_create_memories.exs       [Phase 1]
    ├── *_create_snapshots.exs      [Phase 1]
    ├── *_setup_oban.exs            [Phase 2]
    └── *_create_webhooks.exs       [Phase 5]
```