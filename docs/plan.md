# Samgita Implementation Plan: loki-mode Parity

## Context

Samgita is an Elixir/OTP implementation of loki-mode — an autonomous AI system that transforms PRDs into production software via agent swarms. The codebase is architecturally complete. All critical blockers have been resolved (see "Fixed" section in `docs/prd.md`).

This plan documents the original four phases. Remaining work focuses on enhancements and loki-mode parity.

---

## Gap Analysis

### ~~Critical Bug — Fire-and-Forget Task Completion~~ (FIXED)

**RESOLVED:** `AgentTaskWorker.execute_task/2` now uses `Process.monitor` + `receive` to wait synchronously for the Worker to complete the RARV cycle. Task completion is driven by `Worker.complete_and_notify/1` after the verify state, not by the dispatcher.

Files:
- `apps/samgita/lib/samgita/workers/agent_task_worker.ex`
- `apps/samgita/lib/samgita/agent/worker.ex`

### ~~Missing CONTINUITY.md~~ (FIXED)

**RESOLVED:** `Worker.write_continuity_file/2` now writes `.samgita/CONTINUITY.md` to the project's working directory in the `reason` state before each RARV iteration, including episodic/semantic memory and session learnings.

### Disconnected Memory Systems

`samgita_memory` (pgvector semantic search, 1536-dim embeddings) is **not listed** as a dependency of `apps/samgita/mix.exs`. Agents use the simpler `Samgita.Project.Memory` GenServer with no vector similarity. The two memory systems are disjoint.

### PRD Save Target Bug

`Agent.Worker.update_and_broadcast_prd/3` calls `Projects.update_prd(project, result)`, which writes to the legacy `projects.prd_content` column. The UI renders from `Prd` schema records. Agent-generated PRD output is invisible to the UI.

### Hardcoded Test Username

`config/test.exs` has `username: "gao"`. Fails for any other developer.

### Stub UIs

- `McpLive` returns 3 hardcoded fake MCP servers
- `SkillsLive` returns hardcoded skill data
- Neither connects to real data sources

### No PRD Approval → Auto-Start

After approving a PRD in PrdChatLive, the user must manually navigate to ProjectLive and click Start. No auto-trigger exists.

---

## Phase 1 — Fix Blockers (System Boots, Tests Pass)

**Goal:** `mix phx.server` starts cleanly, `mix ecto.setup` migrates both repos, `mix test` passes all non-`:e2e` tests.

### 1.1 Fix hardcoded test username

**File:** `config/test.exs`

Change:
```elixir
username: "gao"
```
To:
```elixir
username: System.get_env("POSTGRES_USER", System.get_env("USER", "postgres"))
```

### 1.2 Commit staged dependency changes

The staged `apps/samgita_web/mix.exs` and unstaged `mix.lock` need to be committed together. Run `mix deps.get && mix compile` to verify no compilation errors.

### 1.3 Verify DB setup

```bash
mix ecto.setup  # Both Samgita.Repo and SamgitaMemory.Repo must migrate cleanly
```

Confirm pgvector extension installed by `20260209000001_create_memories.exs`.

### Verification

```bash
mix phx.server    # Starts on port 3110, no errors
mix test          # All non-:e2e tests pass
```

---

## Phase 2 — Wire End-to-End Flow (PRD → Claude Output)

**Goal:** Submit a PRD, start a project, watch Claude CLI get invoked, see task output in LiveView.

### 2.1 Fix fire-and-forget task completion (CRITICAL)

**Strategy:** Agent.Worker drives task completion, not AgentTaskWorker.

**In `apps/samgita/lib/samgita/agent/worker.ex`** — in the `verify` state success branch (around `handle_task_completion/1`):

```elixir
# After handle_task_completion(data):
complete_db_task(data.current_task)
notify_orchestrator_task_done(data.project_id, task_id_from(data.current_task))
```

Add private functions:
```elixir
defp complete_db_task(task) do
  Samgita.Projects.complete_task(task.id)
end

defp notify_orchestrator_task_done(project_id, task_id) do
  Samgita.Project.Orchestrator.task_completed(project_id, task_id)
end
```

**In `apps/samgita/lib/samgita/workers/agent_task_worker.ex`** — remove `mark_task_completed` and `notify_orchestrator` from `execute_task_pipeline`. Keep only:
1. Transition task to `:running` status
2. Spawn/find agent via Horde
3. Cast `assign_task` to agent

### 2.2 Fix PRD save target

**File:** `apps/samgita/lib/samgita/agent/worker.ex`

In `update_and_broadcast_prd/3`, replace:
```elixir
Samgita.Projects.update_prd(project, result)
```
With:
```elixir
case Samgita.Prds.get_active_prd(project.id) do
  %Prd{} = prd -> Samgita.Prds.update_prd(prd, %{content: result})
  nil -> Samgita.Projects.update_prd(project, result)  # fallback
end
```

### 2.3 Verify Claude CLI in PATH

In devenv shell: `which claude`. If not found, set in `config/dev.exs`:
```elixir
config :samgita_provider, :claude_command, "/path/to/claude"
```

### 2.4 Set `working_path` on projects

`Agent.Worker.get_working_path/1` requires `project.working_path` for git checkpoints. The ProjectForm UI must accept and save a `working_path` field pointing to a local git repository.

### Verification

1. Create project: `git_url` = local git repo, `working_path` = same path
2. Create and approve a PRD
3. Click Start
4. Activity log streams: `"Entering phase: bootstrap"` → `"Spawning agents"` → `"Executing task via Claude CLI"`
5. Tasks transition to `:completed` after agent returns to `:idle`
6. Orchestrator advances to `:discovery` phase

---

## Phase 3 — Match loki-mode Capabilities

**Goal:** Persistent working memory, semantic memory in agents, real MCP listing, auto-start.

### 3.1 CONTINUITY.md — File-based working memory

**File:** `apps/samgita/lib/samgita/agent/worker.ex`

Add `write_continuity_file/1` called from `reason` state before transitioning to `act`:

```elixir
defp write_continuity_file(data) do
  path = Path.join([data.working_path, ".samgita", "CONTINUITY.md"])
  File.mkdir_p!(Path.dirname(path))

  content = """
  # Samgita Continuity
  Phase: #{data.phase} | Agent: #{data.agent_type} | Iteration: #{data.iteration}
  Task: #{task_description(data.current_task)}

  ## Memory Context
  #{format_memories(data.memory_context)}

  ## Recent Artifacts
  #{format_recent_artifacts(data.project_id)}
  """

  File.write!(path, content)
end
```

This file persists in the project's working directory, giving Claude file-based context matching loki-mode's `.loki/CONTINUITY.md`.

### 3.2 Wire pgvector memory into agents

**File:** `apps/samgita/mix.exs`

Add dependency:
```elixir
{:samgita_memory, in_umbrella: true}
```

**File:** `apps/samgita/lib/samgita/agent/worker.ex`

In `fetch_memory_context/1`, replace `Project.Memory` GenServer call with:
```elixir
SamgitaMemory.Memories.search(query, scope_id: project_id, limit: 10)
```

### 3.3 MCP server listing from Claude config

**File:** `apps/samgita_web/lib/samgita_web/live/mcp_live/index.ex`

Replace hardcoded stub:
```elixir
defp list_mcp_servers do
  ["~/.claude/mcp.json", "~/.claude.json"]
  |> Enum.map(&Path.expand/1)
  |> Enum.find_value([], fn path ->
    case File.read(path) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> get_in(["mcpServers"])
        |> then(fn servers -> servers && format_servers(servers) end)
      _ -> nil
    end
  end)
end
```

### 3.4 PRD approval → auto-start

**File:** `apps/samgita_web/lib/samgita_web/live/prd_chat_live/index.ex`

After PRD save with `:approved` status:
```elixir
if prd.status == :approved do
  Projects.start_project(project.id, prd.id)
  push_navigate(socket, to: ~p"/projects/#{project.id}")
end
```

### 3.5 Skills browser from Agent.Types

**File:** `apps/samgita_web/lib/samgita_web/live/skills_live/index.ex`

Replace hardcoded list:
```elixir
def mount(_params, _session, socket) do
  skills = Samgita.Agent.Types.all()
  {:ok, assign(socket, skills: skills)}
end
```

### 3.6 Dashboard live task progress

**File:** `apps/samgita_web/lib/samgita_web/live/dashboard_live/index.ex`

Subscribe each project to `"project:#{id}:tasks"` PubSub topic. Handle `task_completed` events by updating the project's task counter without re-fetching all projects.

---

## Phase 4 — Polish and Production Readiness

**Goal:** MCP server for memory, git commit metadata, interactive PRD chat, full quality gate suite.

### 4.1 Expose SamgitaMemory as stdio MCP server

Add Mix task `mix samgita.mcp` that starts a stdio MCP server wrapping `SamgitaMemory.MCP.Tools`. Register in `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "samgita-memory": {
      "command": "mix",
      "args": ["samgita.mcp"],
      "cwd": "/path/to/samgita"
    }
  }
}
```

This makes `remember`/`recall`/`think` tools available to Claude during every RARV cycle — the highest-value integration, giving agents persistent cross-session memory.

### 4.2 Enhanced git commit messages

**File:** `apps/samgita/lib/samgita/agent/worker.ex` — `commit_checkpoint/3`

Match loki-mode's commit format:
```
[samgita] eng-backend: implement user authentication

Agent-Type: eng-backend
Phase: development
Task-ID: abc123
Samgita-Version: 0.1.0
```

### 4.3 Interactive PRD chat (Claude-assisted)

**File:** `apps/samgita_web/lib/samgita_web/live/prd_chat_live/index.ex`

Add "Chat" mode alongside the editor:
1. User messages → `SamgitaProvider.query/2` → streamed Claude response
2. Save exchange as `ChatMessage` records (schema already exists)
3. "Generate PRD from conversation" button uses chat history as context
4. Generated PRD populated into the editor for review

### 4.4 Complete quality gate suite

- Verify `CompletionCouncil.evaluate/2` invokes Claude to check PRD completion criteria
- Confirm `TestMutationDetector` (Gate 9) correctly flags mutated assertions
- Run `mix test --include e2e` to validate full gate pipeline

---

## Success Criteria

End-to-end flow:

1. User creates project with `git_url` and `working_path`
2. User creates PRD via PrdChatLive, approves it → auto-start fires
3. Orchestrator enters `:bootstrap` phase, spawns `prod-pm`
4. BootstrapWorker parses PRD → task backlog in Oban
5. AgentTaskWorker spawns agent via Horde, casts `assign_task`
6. Agent RARV cycle: writes CONTINUITY.md → calls `claude --print` → processes output
7. **Agent.Worker's `verify` state marks task `:completed` in DB and notifies Orchestrator**
8. Orchestrator sees all tasks done → advances phase
9. LiveView activity log streams each state transition in real time
10. After development phase: blind review, quality gates, artifacts saved, git commits created
11. `[samgita] eng-*: ...` commits visible in the target repo

**Test commands:**
```bash
mix test                 # All non-:e2e tests pass
mix test --include e2e   # Full lifecycle with Claude CLI
mix phx.server           # Dashboard at http://localhost:3110
```

---

## Critical Files

| File | Change |
|------|--------|
| `apps/samgita/lib/samgita/agent/worker.ex` | Add task completion callback in `verify` state; fix PRD save target; add CONTINUITY.md writing; wire pgvector memory |
| `apps/samgita/lib/samgita/workers/agent_task_worker.ex` | Remove premature task completion; keep only agent spawn + `:running` transition |
| `apps/samgita/mix.exs` | Add `{:samgita_memory, in_umbrella: true}` |
| `config/test.exs` | Replace hardcoded `username: "gao"` with env var |
| `apps/samgita_web/lib/samgita_web/live/mcp_live/index.ex` | Read from `~/.claude/mcp.json` |
| `apps/samgita_web/lib/samgita_web/live/skills_live/index.ex` | Use `Agent.Types.all()` |
| `apps/samgita_web/lib/samgita_web/live/prd_chat_live/index.ex` | Auto-start on approval; Claude chat mode |
| `apps/samgita_web/lib/samgita_web/live/dashboard_live/index.ex` | Live task progress via PubSub |
