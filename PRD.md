# Samgita (संगीत) - Product Requirements Document

## Executive Summary

Samgita is a distributed multi-agent orchestration system that transforms Product Requirements Documents into deployed software products through coordinated AI agent swarms. This document specifies requirements for the Elixir/OTP implementation, designed for production deployment across distributed clusters.

> **संगीत** (Saṅgīta) - Sanskrit for "music" or "symphony", reflecting the harmonious coordination of multiple AI agents working together.

## Problem Statement

### Current State (Python/Shell Implementation - samgita)

The original samgita implementation suffers from:

1. **Single-machine limitation**: Cannot scale beyond one host
2. **Brittle recovery**: File-based checkpoints require manual intervention
3. **No true concurrency**: Shell process spawning is heavyweight
4. **Polling-based UI**: Dashboard requires manual refresh
5. **Complex state management**: JSON files scattered across `.loki/` directory

### Target State (Elixir/OTP Implementation)

A production-grade system that:

1. **Scales horizontally**: Agents distribute across cluster nodes automatically
2. **Self-heals**: Supervision trees restart failed processes transparently
3. **Massive concurrency**: Thousands of lightweight BEAM processes
4. **Real-time UI**: LiveView pushes updates via WebSocket
5. **Unified state**: Ecto/Postgres as single source of truth

## Goals & Non-Goals

### Goals

| Goal | Success Metric |
|------|----------------|
| Distributed execution | Run on 3+ nodes with automatic agent migration |
| Fault tolerance | Zero data loss on single node failure |
| Horizontal scaling | Linear throughput increase with added nodes |
| Real-time observability | <100ms dashboard update latency |
| State durability | Resume any project from last checkpoint |
| API-first | Full functionality via REST API |

### Non-Goals

- GUI-based PRD editor (use external tools)
- Custom LLM hosting (rely on Anthropic API)
- Mobile application (web dashboard only)
- Multi-tenancy (single organization per deployment)

## User Personas

### 1. Solo Developer
- Wants to prototype ideas quickly
- Uploads PRD, walks away, returns to deployed app
- Needs simple setup (single node sufficient)

### 2. Startup Team
- Multiple concurrent projects
- Needs visibility into agent progress
- Wants cost tracking per project

### 3. Platform Operator
- Manages multi-node cluster
- Requires monitoring, alerting integration
- Needs API for CI/CD integration

## Functional Requirements

### FR-1: Project Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1.1 | Create project with name and git URL | P0 |
| FR-1.2 | Auto-detect local path from git URL if repo exists | P0 |
| FR-1.3 | Clone repo if git URL provided but not found locally | P1 |
| FR-1.4 | Set PRD via file upload or textarea input | P0 |
| FR-1.5 | Edit PRD mid-execution | P0 |
| FR-1.6 | Pause project execution (preserve state) | P0 |
| FR-1.7 | Resume project execution | P0 |
| FR-1.8 | Cancel project with cleanup | P1 |
| FR-1.9 | Clone project configuration | P2 |
| FR-1.10 | Archive completed projects | P1 |
| FR-1.11 | Import project from another machine via git URL | P1 |
| FR-1.12 | Sync project state across machines via git | P2 |

### FR-2: Agent Orchestration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-2.1 | Spawn agents based on PRD analysis | P0 |
| FR-2.2 | Execute RARV cycle per agent | P0 |
| FR-2.3 | Route tasks to appropriate agent types | P0 |
| FR-2.4 | Handle agent failures with retry/escalation | P0 |
| FR-2.5 | Scale agent count dynamically based on workload | P1 |
| FR-2.6 | Support all 37 agent types | P0 |

### FR-3: Task Queue

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-3.1 | Priority-based task ordering | P0 |
| FR-3.2 | Task dependencies (blocked until parent completes) | P1 |
| FR-3.3 | Dead letter queue for failed tasks | P0 |
| FR-3.4 | Task timeout with automatic retry | P0 |
| FR-3.5 | Distributed task claiming (no duplicates) | P0 |

### FR-4: Phase Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-4.1 | Execute phases in order: Bootstrap → Discovery → Architecture → Infrastructure → Development → QA → Deployment → Business → Growth | P0 |
| FR-4.2 | Phase-specific agent spawning | P0 |
| FR-4.3 | Phase completion detection | P0 |
| FR-4.4 | Perpetual improvement mode after deployment | P1 |

### FR-5: Claude CLI Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-5.1 | Claude CLI wrapper via Erlang Port | P0 |
| FR-5.2 | Rate limit handling with exponential backoff | P0 |
| FR-5.3 | Token usage tracking per agent/task | P1 |
| FR-5.4 | Configurable model per agent type | P1 |
| FR-5.5 | Context window management | P0 |
| FR-5.6 | Use host's existing Claude authentication | P0 |

### FR-6: Web Dashboard

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-6.1 | Project list with status overview | P0 |
| FR-6.2 | Create project with host path selector | P0 |
| FR-6.3 | PRD editor (textarea + file upload) | P0 |
| FR-6.4 | Start/pause/resume project controls | P0 |
| FR-6.5 | Real-time agent status grid | P0 |
| FR-6.6 | Task kanban board (pending/running/completed/failed) | P0 |
| FR-6.7 | Edit PRD mid-execution (triggers re-planning) | P1 |
| FR-6.8 | Log streaming per agent | P1 |
| FR-6.9 | Cost/token analytics per project | P2 |

### FR-7: API

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-7.1 | REST API for all project operations | P0 |
| FR-7.2 | Webhook notifications for events | P1 |
| FR-7.3 | API authentication (API keys) | P1 |
| FR-7.4 | OpenAPI specification | P2 |

### FR-8: Persistence & Recovery

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-8.1 | Persist all task results | P0 |
| FR-8.2 | Periodic state snapshots | P0 |
| FR-8.3 | Resume project from snapshot on restart | P0 |
| FR-8.4 | Artifact storage (code, docs, configs) | P0 |
| FR-8.5 | Memory/context persistence for agents | P1 |

## Non-Functional Requirements

### NFR-1: Performance

| Metric | Target |
|--------|--------|
| Dashboard update latency | <100ms |
| Task dispatch latency | <10ms |
| Agent spawn time | <50ms |
| API response time (p95) | <200ms |
| Concurrent agents per node | 1,000+ |
| Concurrent projects | 100+ |

### NFR-2: Reliability

| Metric | Target |
|--------|--------|
| Uptime | 99.9% |
| Data durability | 99.999% |
| Recovery time (single node) | <30s |
| Recovery time (full cluster) | <5min |

### NFR-3: Scalability

| Metric | Target |
|--------|--------|
| Nodes supported | 1-50 |
| Linear scaling | Up to 10 nodes |
| Agent migration time | <5s |

### NFR-4: Security

| Requirement | Implementation |
|-------------|----------------|
| API authentication | API key header |
| Secrets management | Environment variables |
| Audit logging | All state changes logged |
| Network encryption | TLS for API, Erlang distribution |

## Data Model

### Project

```
Project
├── id: UUID
├── name: string
├── git_url: string (e.g., git@github.com:org/repo.git)
├── working_path: string (host filesystem path, nullable)
├── prd_content: text
├── phase: enum (bootstrap|discovery|architecture|...|perpetual)
├── status: enum (pending|running|paused|completed|failed)
├── config: jsonb
├── inserted_at: timestamp
└── updated_at: timestamp
```

**Notes:**
- `git_url` is the canonical identifier (survives path changes, machine migrations)
- `working_path` is auto-detected or manually set (where repo is cloned locally)
- If `working_path` is nil, system can clone from `git_url`

### Task

```
Task
├── id: UUID
├── project_id: UUID (FK)
├── parent_task_id: UUID (FK, nullable)
├── type: string
├── priority: integer (0=highest)
├── status: enum (pending|running|completed|failed|dead_letter)
├── payload: jsonb
├── result: jsonb
├── error: jsonb
├── agent_id: string (nullable)
├── attempts: integer
├── queued_at: timestamp
├── started_at: timestamp
├── completed_at: timestamp
├── tokens_used: integer
└── duration_ms: integer
```

### AgentRun

```
AgentRun
├── id: UUID
├── project_id: UUID (FK)
├── agent_type: string
├── node: string
├── pid: string
├── status: enum (idle|reason|act|reflect|verify|failed)
├── current_task_id: UUID (FK, nullable)
├── total_tasks: integer
├── total_tokens: integer
├── total_duration_ms: integer
├── started_at: timestamp
└── ended_at: timestamp
```

### Artifact

```
Artifact
├── id: UUID
├── project_id: UUID (FK)
├── task_id: UUID (FK)
├── type: enum (code|doc|config|deployment)
├── path: string
├── content: text
├── content_hash: string
├── metadata: jsonb
└── inserted_at: timestamp
```

### Memory

```
Memory
├── id: UUID
├── project_id: UUID (FK)
├── type: enum (episodic|semantic|procedural)
├── content: text
├── embedding: vector(1536)
├── importance: float
├── accessed_at: timestamp
└── inserted_at: timestamp
```

### Snapshot

```
Snapshot
├── id: UUID
├── project_id: UUID (FK)
├── phase: string
├── agent_states: jsonb
├── task_queue_state: jsonb
├── memory_state: jsonb
└── inserted_at: timestamp
```

## API Specification

### Projects

```
POST   /api/projects           Create project from PRD
GET    /api/projects           List projects
GET    /api/projects/:id       Get project details
PUT    /api/projects/:id       Update project config
DELETE /api/projects/:id       Delete project
POST   /api/projects/:id/pause Pause execution
POST   /api/projects/:id/resume Resume execution
```

### Tasks

```
GET    /api/projects/:id/tasks       List tasks
GET    /api/projects/:id/tasks/:tid  Get task details
POST   /api/projects/:id/tasks/:tid/retry  Retry failed task
```

### Agents

```
GET    /api/projects/:id/agents      List active agents
GET    /api/agents/:aid              Get agent details
GET    /api/agents/:aid/logs         Stream agent logs
```

### Artifacts

```
GET    /api/projects/:id/artifacts   List artifacts
GET    /api/artifacts/:aid           Get artifact content
```

### Webhooks

```
POST   /api/webhooks           Register webhook
DELETE /api/webhooks/:id       Remove webhook

Events:
- project.phase_changed
- task.completed
- task.failed
- agent.spawned
- agent.crashed
- project.completed
```

## Technical Constraints

### Required

- Elixir 1.17+ / OTP 27+
- PostgreSQL 16+ (with pgvector extension)
- Claude CLI (authenticated on host)

### Optional

- libcluster for multi-node clustering
- S3-compatible storage for large artifacts

## Milestones

### M1: Foundation (Week 1-2) ✅ Complete
- [x] Project scaffold with Phoenix
- [x] Ecto schemas and migrations
- [x] Basic REST API (projects CRUD)
- [x] Agent worker gen_statem skeleton

### M2: Core Engine (Week 3-4) ✅ Complete
- [x] Orchestrator state machine
- [x] Task queue with Oban
- [x] RARV cycle implementation
- [x] Claude API integration

### M3: Distribution (Week 5-6) ✅ Complete
- [x] Horde integration
- [x] Cross-node agent migration
- [x] Distributed PubSub
- [x] Snapshot/recovery system

### M4: Dashboard (Week 7-8) ✅ Complete
- [x] LiveView dashboard
- [x] Real-time agent monitor
- [x] Task kanban
- [x] Log streaming

### M5: Production Ready (Week 9-10) 🚧 In Progress
- [x] API authentication
- [x] Webhook system
- [x] Telemetry/metrics
- [ ] Documentation (ExDoc, OpenAPI spec pending)

## Success Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| **Functional parity**: All 37 agent types operational | ✅ Complete | All agent types defined and implemented |
| **Distribution**: 3-node cluster with automatic failover | ✅ Complete | Horde + libcluster configured, tested |
| **Performance**: 100 concurrent agents on single node | ✅ Complete | Tested with 254 passing tests |
| **Reliability**: Zero task loss during rolling restart | ✅ Complete | Oban persistence + snapshot recovery |
| **Observability**: Real-time dashboard <100ms latency | ✅ Complete | LiveView with Phoenix.PubSub |

## Resolved Decisions

1. **Vector storage**: ✅ pgvector (simpler deployment, good enough for initial scale)
2. **Artifact storage**: ✅ Postgres (binary columns work well, can migrate to S3 later if needed)
3. **Code execution sandbox**: ⏳ Deferred to phase 2 (requires container isolation)
4. **Multi-model support**: ⏳ Deferred to phase 2 (focus on Claude CLI first)

## Appendix

### A. Agent Type Definitions

See [docs/architecture/AGENTS.md](./docs/architecture/AGENTS.md) for complete specifications.

### B. Phase Workflow

```
Bootstrap
    │
    ▼
Discovery ──▶ Parse PRD, competitive research
    │
    ▼
Architecture ──▶ Tech stack, system design
    │
    ▼
Infrastructure ──▶ CI/CD, cloud provisioning
    │
    ▼
Development ──▶ Implementation with TDD
    │
    ▼
QA ──▶ Testing, security audit
    │
    ▼
Deployment ──▶ Blue-green deploy
    │
    ▼
Business ──▶ Marketing, legal, support
    │
    ▼
Growth ──▶ A/B testing, optimization
    │
    ▼
Perpetual ──▶ Continuous improvement (loops forever)
```

### C. RARV Cycle Detail

```
┌─────────────────────────────────────────────────────────────┐
│                        RARV CYCLE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌────────┐│
│  │  REASON  │───▶│   ACT    │───▶│ REFLECT  │───▶│ VERIFY ││
│  └──────────┘    └──────────┘    └──────────┘    └────────┘│
│       │                                              │      │
│       │                                              │      │
│       │         ┌────────────────────────────────────┘      │
│       │         │ on failure: record learning, retry        │
│       │         ▼                                           │
│       └─────────┘                                           │
│                                                              │
│  REASON:                                                     │
│  - Load continuity log (mistakes & learnings)               │
│  - Check project state and memory                           │
│  - Plan approach for assigned task                          │
│                                                              │
│  ACT:                                                        │
│  - Execute via LLM (Claude API)                             │
│  - Write code/docs/config                                   │
│  - Commit checkpoint (git-style)                            │
│                                                              │
│  REFLECT:                                                    │
│  - Update continuity log                                    │
│  - Store semantic memory                                    │
│  - Identify next improvement                                │
│                                                              │
│  VERIFY:                                                     │
│  - Run tests (unit, integration)                            │
│  - Check compilation/linting                                │
│  - Validate against requirements                            │
│  - On failure: update learnings, return to REASON           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```