# Samgita — Project Constitution

## Purpose

Samgita is an Elixir/Phoenix reimplementation of [loki-mode](https://github.com/asklokesh/loki-mode) — a multi-agent autonomous coding system that transforms a PRD (Product Requirements Document) into a fully built, tested, and deployed product with zero human intervention.

**In one sentence:** Samgita replaces loki-mode's shell scripts, flat files, and CLI wrappers with OTP processes, PostgreSQL, and Phoenix, while preserving the PRD-to-deployed-product autonomous workflow.

---

## Why Elixir Replaces Node/Shell/Python

| loki-mode Pain Point | Samgita Solution |
|---|---|
| 100+ agents managed via shell scripts and flat file state | OTP supervised processes, gen_statem, message passing |
| `.loki/state/`, `.loki/queue/`, `.loki/memory/` as flat files | PostgreSQL + Ecto, database-as-source-of-truth |
| Hand-rolled circuit breakers, dead letter queues, retry in bash | OTP supervisors, Horde distributed supervision, Oban job queues |
| Separate FastAPI dashboard reading flat files | Phoenix LiveView — reactive UI over the same runtime |
| Shells out to different CLI tools with ad-hoc process management | OTP-supervised CLI processes with structured I/O, backpressure, and lifecycle management |
| 3-tier file-based memory system | `samgita_memory` with pgvector for semantic search |
| Rate limit handling via `sleep` + exponential backoff in bash | GenServer-level backpressure, supervised retry strategies |

---

## Core Workflow

The fundamental pipeline Samgita must preserve:

```
PRD → Discovery → Architecture → Development (RARV loop) → QA → Deployment → Growth
```

### RARV Cycle

The atomic unit of agent work. Every agent iteration follows:

```
1. REASON  — Read context, continuity state, identify next task
2. ACT     — Execute task via tools (file ops, shell, search)
3. REFLECT — Update state, record learnings, identify improvements
4. VERIFY  — Run tests, check compilation, validate against spec
   └─ IF FAIL → capture error, update learnings, rollback if needed, retry from REASON
```

### Autonomous Properties

- **Multi-agent parallel execution** — multiple agents working simultaneously, not sequential
- **Self-healing on failures** — automatic retry, state checkpoints, rollback capability
- **Perpetual improvement** — no "finished" state; continuous optimization after PRD completion
- **Zero babysitting** — auto-resume on rate limits, recover from crashes, run until stopped

---

## Agent Architecture

### Agent Types (Swarms)

Organized into specialized swarms, spawned on demand based on project complexity:

| Swarm | Purpose | Examples |
|---|---|---|
| **Engineering** | Code implementation | frontend, backend, database, mobile, api, qa, perf, infra |
| **Operations** | Infrastructure & reliability | devops, sre, security, monitoring, incident, release, cost, compliance |
| **Business** | Non-technical operations | marketing, sales, finance, legal, support, hr, investor, partnerships |
| **Data** | Data pipeline & ML | ml, engineering, analytics |
| **Product** | Product management | pm, design, tech-writer |
| **Growth** | User acquisition & retention | hacker, community, success, lifecycle |
| **Review** | Quality assurance | code-review, business-review, security-review |
| **Orchestration** | Coordination | planner, sub-planner, judge, coordinator |

Simple projects use 5–10 agents. Complex projects spawn 100+.

### Quality Gates

Every code change passes through parallel review:

1. **Input/output guardrails** — validate tool call parameters and results
2. **Static analysis** — linting, type checking, compilation
3. **Blind review** — independent code review without seeing other reviews
4. **Anti-sycophancy** — devil's advocate on unanimous approvals
5. **Severity blocking** — critical/high issues block; low/cosmetic get TODO comments
6. **Test coverage** — unit, integration, E2E verification
7. **Security audit** — vulnerability scanning, OWASP checks

---

## Project Lifecycle Phases

| Phase | Description |
|---|---|
| **0. Bootstrap** | Initialize project structure, state, configuration |
| **1. Discovery** | Parse PRD, competitive research, requirements extraction |
| **2. Architecture** | Tech stack selection, system design with self-reflection |
| **3. Infrastructure** | Provision cloud, CI/CD, monitoring setup |
| **4. Development** | Implement with TDD, parallel code review, RARV loop |
| **5. QA** | Quality gates, security audit, load testing |
| **6. Deployment** | Blue-green deploy, auto-rollback on errors |
| **7. Business** | Marketing, sales, legal, support setup |
| **8. Growth** | Continuous optimization, A/B testing, feedback loops |
| **9. Perpetual** | Never-ending improvement cycle |

---

## Technical Architecture

### Umbrella Structure

```
apps/
  samgita_provider/  — Provider abstraction wrapping Claude Code CLI via ClaudeAgentSDK
  samgita/           — Core domain: projects, tasks, agent runs, RARV worker, supervision
  samgita_memory/    — pgvector memory, PRD tracking, thinking chains, MCP tools
  samgita_web/       — Phoenix LiveView UI, REST API, playground chat
```

### Infrastructure Stack

| Component | Technology | Purpose |
|---|---|---|
| Runtime | Elixir/OTP | Process supervision, fault tolerance, concurrency |
| Database | PostgreSQL + pgvector | Persistence, semantic memory |
| Job Queue | Oban | Background tasks, scheduled work, retries |
| Distribution | Horde + libcluster | Distributed agent supervision across nodes |
| Web | Phoenix LiveView | Reactive UI, real-time dashboard |
| LLM Provider | Claude Code CLI, Codex CLI | Supervised Port processes wrapping CLI tools |

### Dependency Direction

```
samgita_data ← samgita_core ← samgita_server ← samgita_web
                    ↑
              samgita_plugin (MCP, LSP, external tools)
              samgita_provider (CLI process supervision — Claude Code, Codex)
```

---

## Provider Architecture — CLI-First

**Samgita does NOT call LLM APIs directly.** It orchestrates CLI tools as supervised processes.

The providers are:

| Provider | CLI Tool | Feature Level |
|---|---|---|
| **Claude Code** | `claude` CLI | Full — parallel agents, Task tool, MCP, streaming |
| **OpenAI Codex** | `codex` CLI | Degraded — sequential, no Task tool |

Each provider is an OTP-supervised Port or process. Samgita sends prompts/instructions to the CLI, receives structured output (text, tool calls, status), and manages the lifecycle (start, stop, rate limit backoff, crash recovery).

**Why CLI, not API:**

- The CLI tools handle their own tool execution, context management, and conversation state
- Claude Code CLI supports `--dangerously-skip-permissions` for autonomous file/shell operations
- The CLI tools manage their own rate limiting, token counting, and model selection
- Samgita's job is **orchestration** — deciding which agent does what, when, in parallel — not reimplementing what the CLIs already do

**OTP advantage over shell scripts:** loki-mode spawns CLI processes via bash and manages them with PIDs in flat files. Samgita wraps each CLI invocation in a supervised process with proper lifecycle, stdout/stderr streaming, exit code handling, and automatic restart on failure.

```
Samgita Agent Worker (gen_statem)
  → spawns Claude CLI as supervised Port
  → sends task prompt via stdin / CLI args
  → receives streaming output via stdout
  → parses tool calls, results, completion
  → RARV cycle decides next action
  → repeat or terminate
```

---

## Tool System

The CLI providers (Claude Code, Codex) handle their own tool execution — file read/write, bash, grep, etc. Samgita does NOT re-execute tools that the CLI already handles.

Samgita's tool concerns are:

1. **Observability** — intercept/parse CLI output to know what tools were called and their results
2. **Permission gating** — approve/deny destructive operations before the CLI executes them
3. **Side effect propagation** — broadcast `:file_changed` events so plugins (LSP, diagnostics) can react
4. **Orchestration-level tools** — tools the CLI doesn't provide: agent coordination, memory queries, project state management

### CLI-Provided Tools (executed by the CLI, observed by Samgita)

| Tool | Purpose |
|---|---|
| `file_read` | Read file contents |
| `file_write` | Write full file content |
| `file_edit` | Targeted search/replace edit |
| `bash_exec` | Execute shell command |
| `grep` | Recursive text search |
| `glob` | Find files matching pattern |
| `list_dir` | List directory contents |

### Plugin Tools

Dynamically registered via plugin system:

- **MCP tools** — namespaced `mcp_*`, discovered at runtime via MCP protocol
- **LSP tools** — namespaced `lsp_*`, expose language server capabilities as agent tools
- **Custom tools** — any module implementing the Tool behaviour

### Side Effect Pipeline

Tools declare side effects statically. The executor broadcasts them via PubSub. Subscribers (LSP plugins, UI) react asynchronously. The agent loop never blocks on side effects.

```
file_edit executed → broadcasts :file_changed
  → LSP plugin receives → sends didChange to language server → publishes diagnostics
  → UI receives → shows diagnostic indicators
```

---

## Memory System

Three-tier architecture with progressive disclosure:

| Tier | Storage | Purpose |
|---|---|---|
| **Working Memory** | In-process state | Current task context, active reasoning |
| **Episodic Memory** | PostgreSQL | Specific events, tool results, conversation history |
| **Semantic Memory** | pgvector | Consolidated patterns, learned abstractions |
| **Procedural Memory** | Skills/SKILL.md | Reusable procedures, agent role definitions |

Progressive disclosure reduces context usage by 60–80%: load index first (~100 tokens), timeline on demand (~500 tokens), full details only when needed.

---

## Skill System

Skills replace hard-coded agent types with composable, scoped configurations:

- **Global skills** — available to all projects
- **Project skills** — scoped to specific project
- **Session selection** — user chooses which skills apply per session

Each skill defines: system prompt fragment, tool allowlist, config overrides.

This maps to loki-mode's `SKILL.md` + `skills/` progressive disclosure architecture.

---

## No Authentication or Account System

**Decision:** Samgita does not implement user authentication, account management, or access control systems.

**Rationale:**

1. **Deployment Model**: Samgita is designed to be deployed as a local or private development tool, not a multi-tenant SaaS application.
2. **Access Model**: Anyone who can access the Samgita instance is inherently trusted and has full administrative privileges. Access control is enforced at the infrastructure/network level (firewall, VPN, localhost binding), not at the application level.
3. **Simplicity**: Removing authentication complexity allows the system to focus on its core mission: orchestrating AI agent swarms for software development.
4. **Zero Configuration**: No user registration, password management, session handling, or permission systems to configure or maintain.
5. **Self-Hosted Philosophy**: Samgita follows the self-hosted/personal tool philosophy where the deployment owner controls physical access to the system.

**Implications:**

- No login/logout flows
- No user profiles or preferences stored in database
- No role-based access control (RBAC)
- No API keys or authentication tokens for web interface
- All actions in audit logs are attributed to "system" or identified by session/IP

**Security Model:**

Security is provided through:
- **Network isolation**: Run on localhost or behind VPN/firewall
- **Infrastructure access control**: SSH keys, server access permissions
- **Physical security**: Control of the machine running Samgita
- **API rate limiting**: Prevent abuse from rogue scripts/bots
- **Audit logging**: Track all actions for accountability

**When This Decision Should Be Revisited:**

This decision should be reconsidered if:
- Samgita becomes a hosted service offering
- Multiple organizations need to share a single deployment
- Compliance requirements mandate user-level access tracking
- Community requests strongly favor multi-user support

Until then, **anyone who can access Samgita is an admin**.

---

## Validation Criteria

A correct implementation of Samgita must satisfy:

1. **PRD-to-product pipeline works end-to-end** — give it a PRD, walk away, come back to working code
2. **RARV cycle is the atomic unit** — every agent iteration reasons, acts, reflects, verifies
3. **Multi-agent parallelism** — agents work simultaneously, not sequentially
4. **Self-healing** — automatic retry on failures, state checkpoints, rollback capability
5. **Perpetual mode** — continues optimizing after initial completion
6. **CLI-as-provider** — orchestrates Claude Code CLI and Codex CLI as supervised OTP processes; does not reimplement LLM API calls
7. **Real-time observability** — live dashboard showing agent status, task queue, progress
8. **Database-as-source-of-truth** — no flat file state management
9. **Fault tolerance via OTP** — supervisor trees handle crashes, not bash retry loops
10. **Multi-provider support** — not locked to one CLI; supports Claude Code CLI and Codex CLI through provider abstraction

---

## What This Is NOT

- **Not a chat UI wrapper** — it's an autonomous system that happens to have a chat interface
- **Not a single-agent tool** — the value is in multi-agent orchestration and parallel execution
- **Not a framework** — it's a complete application; extensibility via plugins, not subclassing
- **Not a platform** — single-user local tool, no auth, no marketplace, no multi-tenancy

---

## Additional Principles

### Git as Source of Truth

Projects are identified by their `git_url`, not by internal database IDs. This allows projects to be portable across deployments and machines.

### Postgres Over Mnesia

All persistent state lives in PostgreSQL, not in-memory or distributed Erlang databases. This eliminates split-brain scenarios and simplifies backup/recovery.

### Distributed by Design

Samgita uses Horde for process distribution and Oban for job distribution, allowing horizontal scaling without code changes.

### RARV Cycle is Sacred

The Reason-Act-Reflect-Verify cycle is the fundamental workflow pattern for all agents. This structure cannot be bypassed or short-circuited.

### Claude CLI Over Direct API

Samgita invokes the `claude` CLI tool directly (via `System.cmd/3`) instead of calling LLM APIs. This reuses host authentication and simplifies deployment.

---

## Enforcement

These principles are enforced through:
- Code review and pull request guidelines
- Architectural Decision Records (ADRs) for major changes
- This constitution document as the authoritative reference

Any changes to these core principles require explicit discussion and documentation updates.

---

**Last Updated:** 2026-02-27
**Status:** Active
