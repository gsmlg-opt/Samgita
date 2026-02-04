<!--
  Sync Impact Report - Constitution Update

  Version Change: None → 1.0.0 (Initial creation from existing docs/CONSTITUTION.md)

  Modified Principles:
  - None (initial version)

  Added Sections:
  - Core Principles (5 principles migrated from docs/CONSTITUTION.md)
  - Technology Stack & Constraints
  - Development Workflow & Quality Gates
  - Governance

  Removed Sections:
  - None

  Templates Requiring Updates:
  ✅ plan-template.md - Constitution Check section already present, aligns with principles
  ✅ spec-template.md - No changes needed, specification format is principle-agnostic
  ✅ tasks-template.md - No changes needed, task structure supports all principles

  Follow-up TODOs:
  - None - all placeholders filled

  Rationale for Version 1.0.0:
  This is the initial migration of Samgita's architectural principles from docs/CONSTITUTION.md
  into the speckit template format. Since this is the first version establishing the constitution
  in the .specify/memory/ location, we start at 1.0.0.
-->

# Samgita Constitution

## Core Principles

### I. No Authentication or Account System (NON-NEGOTIABLE)

**Decision**: Samgita does NOT implement user authentication, account management, or access control systems at the application level.

**Rules**:
- MUST NOT create user models, authentication flows, or session management
- MUST NOT implement login/logout, registration, or password management
- MUST NOT add role-based access control (RBAC) or permission systems
- MUST enforce access control at infrastructure level (firewall, VPN, SSH, localhost binding)
- All audit logs attribute actions to "system" or identify by session/IP

**Rationale**:
1. **Deployment Model**: Self-hosted personal/team tool, not multi-tenant SaaS
2. **Access Model**: Infrastructure-level access control; anyone who can reach the app is admin
3. **Simplicity**: Focus on agent orchestration, not access management
4. **Zero Configuration**: No user setup, password management, or permission configuration
5. **Self-Hosted Philosophy**: Deployment owner controls physical/network access

**When to Revisit**: If Samgita becomes a hosted service, requires multi-organization isolation, or compliance mandates user-level tracking.

### II. Git as Source of Truth

**Decision**: Projects are identified and tracked by their `git_url`, not internal database IDs.

**Rules**:
- MUST use `git_url` (e.g., `git@github.com:org/repo.git`) as canonical project identifier
- MUST allow projects to be portable across deployments and machines using the same git URL
- MUST auto-detect local git repository paths when git URL matches
- MUST clone repositories automatically if git URL provided but not found locally
- MAY store `working_path` as cached location, but git_url is authoritative

**Rationale**:
- Enables cross-machine project migration (same git URL, different deployment)
- State syncs via git commits, continues from last phase on new machine
- Snapshots stored in Postgres, not tied to local filesystem
- Aligns with developer mental model (projects = git repos)

### III. Postgres Over Mnesia (NON-NEGOTIABLE)

**Decision**: All persistent state MUST live in PostgreSQL. Erlang/Elixir distributed databases (Mnesia, DETS) are prohibited for authoritative data.

**Rules**:
- MUST use Postgres as single source of truth for all persistent data
- MUST use Ecto schemas for all persistent entities
- MAY use ETS for hot/runtime caching with Postgres snapshots for recovery
- MUST NOT use Mnesia or DETS for authoritative data
- MUST use pgvector for memory/semantic search persistence

**Rationale**:
- Eliminates split-brain scenarios in distributed clusters
- Simplifies backup, recovery, and replication strategies
- Standard tooling for monitoring, migrations, and administration
- Postgres ACID guarantees prevent data corruption across node failures

### IV. RARV Cycle is Sacred (NON-NEGOTIABLE)

**Decision**: The Reason-Act-Reflect-Verify cycle is the fundamental workflow pattern for all agents. This structure cannot be bypassed or short-circuited.

**Rules**:
- MUST implement agent workers as `gen_statem` (NOT GenServer)
- MUST define explicit state transitions: `:idle → :reason → :act → :reflect → :verify`
- MUST retry from `:reason` state on verification failure (`:verify → :reason`)
- MUST commit checkpoints after `:act` state
- MUST update memory during `:reflect` state
- MUST run tests/validation during `:verify` state

**Rationale**:
- Provides auditability: each phase transition is explicit and logged
- Enforces failure isolation: verification failures don't corrupt action state
- Enables recovery: restart from last checkpoint in RARV cycle
- Mirrors human software development process (plan → code → review → test)

### V. Claude CLI Over Direct API

**Decision**: Samgita uses Claude Code CLI (via ClaudeAgentSDK/Erlang Port) instead of direct Anthropic API calls for agent execution.

**Rules**:
- MUST use Claude CLI via Erlang Port for agent interactions
- MUST reuse host's existing Claude authentication (OAuth or API key)
- MAY provide ClaudeAPI module for advanced use cases requiring direct control
- MUST NOT require users to configure separate API keys for Samgita
- MUST handle CLI process lifecycle (spawn, monitor, restart)

**Rationale**:
- Simpler deployment: no API key management or distribution
- Reuses existing authentication flow developers already trust
- Inherits all Claude Code tools automatically
- Aligns with ADR-004 (Use Claude CLI via Erlang Port)

**When ClaudeAPI is Appropriate**:
- Production systems requiring fine-grained API control
- Custom tool implementations beyond Claude Code's tool set
- Minimizing external process dependencies

## Technology Stack & Constraints

### Approved Technologies

**Backend**:
- Elixir 1.17+ on Erlang/OTP 27+
- Phoenix 1.7+ (LiveView for real-time UI)
- Ecto 3.11+ with PostgreSQL 14+
- Horde for distributed process registry/supervisor
- Oban for distributed job queue

**Frontend**:
- Phoenix LiveView for real-time dashboards
- Tailwind CSS for styling
- `@duskmoon-dev` npm packages for UI components (markdown rendering, custom elements)
- Web Components (Custom Elements) for reusable functionality

**Infrastructure**:
- PostgreSQL + pgvector for persistence and semantic memory
- Phoenix.PubSub (pg adapter) for cross-node communication
- Systemd for production service management
- libcluster for automatic cluster formation

### Prohibited Technologies

- ❌ Mnesia or DETS for authoritative data storage
- ❌ GenServer for RARV cycle agents (use `gen_statem`)
- ❌ Direct Anthropic API calls for primary agent workflow (use Claude CLI)
- ❌ File-based state management for critical data (use Postgres + Oban + ETS)
- ❌ User authentication libraries (no accounts system)

### Performance Targets

| Metric | Target |
|--------|--------|
| Dashboard update latency | <100ms |
| Task dispatch latency | <10ms |
| Agent spawn time | <50ms |
| API response (p95) | <200ms |
| Concurrent agents per node | 1,000+ |
| Concurrent projects | 100+ |
| Uptime | 99.9% |
| Recovery (single node failure) | <30s |

## Development Workflow & Quality Gates

### Supervision Tree Structure

All features MUST adhere to this supervision hierarchy:

```
Samgita.Application
├── Samgita.Repo (Ecto)
├── Phoenix.PubSub (pg adapter)
├── Horde.Registry (Samgita.AgentRegistry)
├── Horde.DynamicSupervisor (Samgita.ProjectSupervisor)
│   └── per project:
│       Samgita.Project.Supervisor
│       ├── Orchestrator (gen_statem) - phase management
│       ├── Memory (GenServer) - context/learnings
│       └── Agent workers (gen_statem) - RARV cycle
├── Oban (distributed job queue)
└── SamgitaWeb.Endpoint
```

### Agent State Machine Pattern

All agent workers MUST implement this state machine:

```elixir
defmodule Samgita.Agent.Worker do
  @behaviour :gen_statem

  # States: :idle, :reason, :act, :reflect, :verify

  def callback_mode, do: :state_functions

  def idle(:cast, :start_task, data) do
    {:next_state, :reason, data, [{:next_event, :internal, :load_context}]}
  end

  def reason(:internal, :load_context, data) do
    # Load continuity log, identify approach
    {:next_state, :act, updated_data}
  end

  def act(:internal, :execute, data) do
    # Execute via Claude CLI, commit checkpoint
    {:next_state, :reflect, updated_data}
  end

  def reflect(:internal, :update_memory, data) do
    # Update memory, record learnings
    {:next_state, :verify, updated_data}
  end

  def verify(:internal, :validate, data) do
    case run_tests(data) do
      :ok -> {:next_state, :idle, data}
      :error -> {:next_state, :reason, data, [{:next_event, :internal, :retry}]}
    end
  end
end
```

### Data Model Constraints

**Core Entities** (Ecto schemas):
- `Project` - git_url (canonical ID), working_path, prd_content, phase, status
- `Task` - priority, status, payload, agent assignments
- `AgentRun` - agent_type, node, pid, status, metrics
- `Artifact` - code, docs, configs generated by agents
- `Memory` - episodic/semantic/procedural with pgvector embeddings
- `Snapshot` - periodic state checkpoints for recovery

**Schema Rules**:
- MUST use `timestamps()` macro for all schemas
- MUST include `git_url` reference for project-scoped entities
- MUST use UUID primary keys for distributed safety
- MAY cache frequently-accessed data in ETS with Postgres backing

### Testing Requirements

**Test Structure**:
```
test/
├── samgita/
│   ├── agent/        # Agent RARV cycle unit tests
│   ├── project/      # Project management tests
│   └── memory/       # Memory system tests
├── samgita_web/
│   └── live/         # LiveView integration tests
└── support/
    ├── fixtures/     # Test data factories
    └── conn_case.ex  # Test helpers (NO user auth helpers)
```

**Coverage Requirements**:
- MUST achieve >80% line coverage for core modules
- MUST test all RARV state transitions
- MUST test distributed scenarios (multi-node)
- MAY skip coverage for Phoenix boilerplate

### Git Workflow

**Commits**:
- Use conventional commits: `type(scope): description`
- Types: `feat|fix|docs|style|refactor|test|chore`
- Omit "Co-Authored-By: Claude" trailer (per CLAUDE.md)
- Omit "Generated with Claude Code" from messages

**Branches**:
- Main branch: `main` (protected)
- Feature branches: `###-feature-name` (speckit pattern)
- PRs merge to `main` after review

## Governance

### Amendment Procedure

1. **Proposal**: Open GitHub issue with `constitution-amendment` label
2. **Discussion**: Community feedback period (minimum 7 days)
3. **Vote**: Project maintainers approve/reject
4. **Implementation**: Update this file with version bump
5. **Propagation**: Update dependent templates (plan, spec, tasks)
6. **Migration**: Document breaking changes, provide migration path

### Versioning Policy

Constitution follows semantic versioning:
- **MAJOR**: Backward-incompatible principle removals/redefinitions (e.g., allowing authentication system)
- **MINOR**: New principles added or materially expanded guidance
- **PATCH**: Clarifications, wording improvements, typo fixes

### Compliance Review

- All PRs MUST verify compliance with Core Principles
- Architecture Decision Records (ADRs) MUST reference constitution principles
- Complexity violations (e.g., adding 4th project) MUST be justified in plan.md "Complexity Tracking" section
- Annual constitution review to ensure principles remain relevant

### Enforcement

These principles are enforced through:
- Code review and pull request guidelines
- Architectural Decision Records (ADRs) for major changes
- This constitution as authoritative reference
- CI/CD checks for prohibited technologies (e.g., Mnesia imports)

Any changes to Core Principles (Section I-V) require explicit discussion and unanimous maintainer approval.

---

**Version**: 1.0.0 | **Ratified**: 2026-02-04 | **Last Amended**: 2026-02-04
