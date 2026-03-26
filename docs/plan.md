# Samgita Implementation Plan: loki-mode Parity

## Context

Samgita is an Elixir/OTP implementation of loki-mode — an autonomous AI system that transforms PRDs into production software via agent swarms. All phases 1-3 are complete. Remaining work is Phase 4 polish and production readiness.

---

## Status Summary

### ✅ Phase 1 — Fix Blockers (COMPLETE)
- [x] Test username env var (not hardcoded `"gao"`)
- [x] `samgita_memory` wired as dep of `samgita`
- [x] Both Repos migrate cleanly via `mix ecto.setup`

### ✅ Phase 2 — Wire End-to-End Flow (COMPLETE)
- [x] Fire-and-forget task completion fixed (`execute_task` blocks on `receive`)
- [x] PRD save target fixed (writes to `Prd` schema, not `projects.prd_content`)
- [x] CONTINUITY.md written before each RARV iteration
- [x] `working_path` tracked on Agent.Worker state

### ✅ Phase 3 — Match loki-mode Capabilities (COMPLETE)
- [x] CONTINUITY.md file-based working memory in reason state
- [x] pgvector memory dep wired into samgita app
- [x] MCP server listing reads from `~/.claude/mcp.json`
- [x] PRD approval → auto-start fires via `maybe_start_project/3`
- [x] Skills browser uses `Agent.Types.all()` (37 types, 7 swarms)
- [x] Dashboard live task progress via PubSub `{:task_stats_changed, project_id}`

---

## Phase 4 — Polish and Production Readiness

**Goal:** MCP server for memory, enhanced git commits, interactive PRD chat, full quality gate suite.

### 4.1 Expose SamgitaMemory as stdio MCP server

Add Mix task `mix samgita.mcp` that starts a stdio MCP server wrapping `SamgitaMemory.MCP.Tools`.

Register in `~/.claude/mcp.json`:
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

This makes `remember`/`recall`/`think` tools available to Claude during every RARV cycle — highest-value integration for cross-session memory.

### 4.2 Enhanced git commit messages

Match loki-mode's commit format in `Agent.Worker.commit_checkpoint/3`:

```
[samgita] eng-backend: implement user authentication

Agent-Type: eng-backend
Phase: development
Task-ID: abc123
Samgita-Version: 0.1.0
```

### 4.3 Interactive PRD chat (Claude-assisted)

Extend `PrdChatLive` with a "Chat" mode:
1. User messages → `SamgitaProvider.query/2` → streamed Claude response
2. Save exchange as `ChatMessage` records (schema exists)
3. "Generate PRD from conversation" button uses chat history as context
4. Generated PRD populated into the editor for review

### 4.4 Complete quality gate suite

- Verify `CompletionCouncil.evaluate/2` invokes Claude to check PRD completion criteria
- Confirm `TestMutationDetector` (Gate 9) correctly flags mutated assertions
- Run `mix test --include e2e` to validate full gate pipeline

---

## Success Criteria

End-to-end flow (all verified):

1. User creates project with `git_url` and `working_path`
2. User creates PRD via PrdChatLive, approves it → auto-start fires ✅
3. Orchestrator enters `:bootstrap` phase, spawns `prod-pm` ✅
4. BootstrapWorker parses PRD → task backlog in Oban ✅
5. AgentTaskWorker spawns agent via Horde, casts `assign_task` ✅
6. Agent RARV cycle: writes CONTINUITY.md → calls `claude --print` → processes output ✅
7. **Agent.Worker's `verify` state marks task `:completed` in DB and notifies Orchestrator** ✅
8. Orchestrator sees all tasks done → advances phase ✅
9. LiveView activity log streams each state transition in real time ✅
10. After development phase: blind review, quality gates, artifacts saved, git commits created ✅

**Test commands:**
```bash
mix test                 # All non-:e2e tests pass
mix test --include e2e   # Full lifecycle with Claude CLI
mix phx.server           # Dashboard at http://localhost:3110
```
