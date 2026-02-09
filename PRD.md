# PRD: Samgita Memory System

## Overview

A persistent, queryable memory system for Claude Code agents operating within the Samgita umbrella. The system provides episodic, semantic, and procedural memory types with PRD execution tracking, enabling agents to recall prior work, avoid repeating mistakes, and resume interrupted workflows with full situational awareness.

The core is an OTP application with ETS hot caching and Postgres/pgvector persistence. It exposes an MCP interface for external Claude Code agents and direct Elixir function calls for internal Samgita modules.

---

## Problem Statement

Claude Code agents lose all context between sessions. When a PRD is partially implemented and work resumes later, the agent starts from zero — re-reading files, re-discovering architectural decisions, and potentially contradicting prior work. Current workarounds (CLAUDE.md, CONTINUITY.md) are flat files that grow unbounded, can't be queried by relevance, and don't distinguish between active context and stale information.

### What This Solves

1. **PRD continuity** — agents resume work on a PRD knowing exactly what's done, what's blocked, what decisions were made, and what failed
2. **Cross-session learning** — mistakes and patterns persist across sessions and projects
3. **Context budget management** — relevant memories are retrieved by query, not loaded in bulk
4. **Multi-machine consistency** — memory is centralized in Postgres, accessible from any development machine via MCP

---

## Architecture

### System Boundary

```
samgita_umbrella/
├── samgita_memory/           # This PRD — core memory OTP app
│   ├── lib/
│   │   ├── samgita_memory/
│   │   │   ├── memories/     # Ecto schemas + context functions
│   │   │   ├── prd/          # PRD execution tracking
│   │   │   ├── retrieval/    # Hybrid search pipeline
│   │   │   ├── formation/    # Memory creation from telemetry
│   │   │   ├── compaction/   # Decay, summarization, pruning
│   │   │   └── cache/        # ETS hot cache management
│   │   └── samgita_memory.ex # Public API
│   ├── test/
│   └── mix.exs
├── samgita_mcp/              # MCP transport layer (separate app)
│   └── (exposes memory as MCP tools)
└── samgita_web/              # LiveView dashboards (separate app)
    └── (memory inspection UI)
```

### Supervision Tree

```
SamgitaMemory.Application
├── SamgitaMemory.Repo                    # Ecto repo (Postgres + pgvector)
├── SamgitaMemory.Cache.Supervisor
│   ├── SamgitaMemory.Cache.MemoryTable   # ETS for recent memories
│   └── SamgitaMemory.Cache.PRDTable      # ETS for active PRD executions
├── SamgitaMemory.Formation.Supervisor
│   └── (telemetry handlers registered on init)
├── Oban                                  # Async jobs
│   ├── SamgitaMemory.Workers.Embedding   # Generate embeddings
│   ├── SamgitaMemory.Workers.Compaction  # Decay + prune
│   └── SamgitaMemory.Workers.Summarize   # Chain/PRD summarization
└── SamgitaMemory.Retrieval.Pipeline      # GenServer for retrieval coordination
```

---

## Data Model

### Memory Schema

```elixir
# samgita_memory/lib/samgita_memory/memories/memory.ex

schema "memories" do
  field :content, :string                    # the fact or knowledge
  field :embedding, Pgvector.Ecto.Vector     # 1536-dim for semantic search
  field :source_type, Ecto.Enum,
    values: [:conversation, :observation, :user_edit, :prd_event, :compaction]
  field :source_id, :string                  # reference to origin
  field :scope_type, Ecto.Enum,
    values: [:global, :project, :agent]
  field :scope_id, :string                   # project path, agent id, or nil for global
  field :memory_type, Ecto.Enum,
    values: [:episodic, :semantic, :procedural]
  field :confidence, :float, default: 1.0    # decays over time
  field :access_count, :integer, default: 0
  field :tags, {:array, :string}, default: []
  field :metadata, :map, default: %{}        # flexible payload

  timestamps()
  field :accessed_at, :utc_datetime          # last retrieval time
end
```

#### Indexes

```sql
CREATE INDEX memories_scope_idx ON memories (scope_type, scope_id);
CREATE INDEX memories_tags_idx ON memories USING gin (tags);
CREATE INDEX memories_type_idx ON memories (memory_type);
CREATE INDEX memories_confidence_idx ON memories (confidence) WHERE confidence > 0.3;
CREATE INDEX memories_embedding_idx ON memories
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

### PRD Execution Schema

```elixir
# samgita_memory/lib/samgita_memory/prd/execution.ex

schema "prd_executions" do
  field :prd_ref, :string                    # file path or git SHA
  field :prd_hash, :string                   # content hash for change detection
  field :title, :string
  field :status, Ecto.Enum,
    values: [:not_started, :in_progress, :paused, :blocked, :completed]

  has_many :events, SamgitaMemory.PRD.Event
  has_many :decisions, SamgitaMemory.PRD.Decision

  # Materialized from events — never written directly
  field :progress, :map, default: %{
    completed: [],
    in_progress: [],
    blocked: [],
    not_started: []
  }

  timestamps()
end
```

### PRD Event Schema

```elixir
# samgita_memory/lib/samgita_memory/prd/event.ex

schema "prd_events" do
  belongs_to :execution, SamgitaMemory.PRD.Execution

  field :type, Ecto.Enum, values: [
    :requirement_started,
    :requirement_completed,
    :decision_made,
    :blocker_hit,
    :blocker_resolved,
    :test_passed,
    :test_failed,
    :revision,
    :review_feedback,
    :agent_handoff,
    :error_encountered,
    :rollback
  ]
  field :requirement_id, :string             # traces to PRD section
  field :summary, :string                    # human-readable description
  field :detail, :map, default: %{}          # structured payload
  field :agent_id, :string                   # which agent performed this
  field :thinking_chain_id, :string          # link to reasoning chain if any

  timestamps()
end
```

### PRD Decision Schema

```elixir
# samgita_memory/lib/samgita_memory/prd/decision.ex

schema "prd_decisions" do
  belongs_to :execution, SamgitaMemory.PRD.Execution

  field :requirement_id, :string
  field :decision, :string                   # what was decided
  field :reason, :string                     # why
  field :alternatives, {:array, :string}, default: []  # what was rejected
  field :agent_id, :string

  timestamps()
end
```

### Thinking Chain Schema

```elixir
# samgita_memory/lib/samgita_memory/memories/thinking_chain.ex

schema "thinking_chains" do
  field :scope_type, Ecto.Enum, values: [:global, :project, :agent]
  field :scope_id, :string
  field :query, :string                      # what initiated the chain
  field :summary, :string                    # distilled after completion
  field :embedding, Pgvector.Ecto.Vector     # for retrieval of similar chains
  field :status, Ecto.Enum, values: [:active, :completed, :abandoned]
  field :thoughts, {:array, :map}, default: []
  # Each thought: %{number: int, content: string, is_revision: bool,
  #                  revises: int | nil, branch_id: string | nil}

  field :metadata, :map, default: %{}
  timestamps()
end
```

---

## Public API

### SamgitaMemory — Core Interface

```elixir
defmodule SamgitaMemory do
  @moduledoc "Public API for the memory system"

  # --- Memory CRUD ---

  @doc "Store a new memory fact"
  @spec store(String.t(), keyword()) :: {:ok, Memory.t()} | {:error, term()}
  def store(content, opts \\ [])
  # opts: source: {type, id}, scope: {type, id}, type: :episodic | :semantic | :procedural,
  #       tags: [String.t()], metadata: map()
  # Enqueues embedding generation via Oban worker

  @doc "Retrieve memories relevant to a query"
  @spec retrieve(String.t(), keyword()) :: [Memory.t()]
  def retrieve(query, opts \\ [])
  # opts: scope: {type, id}, type: atom(), tags: [String.t()],
  #       limit: integer(), min_confidence: float()
  # Runs hybrid retrieval pipeline: tag filter → semantic search → recency boost

  @doc "Explicitly forget a memory"
  @spec forget(String.t()) :: :ok | {:error, :not_found}
  def forget(memory_id)

  @doc "Update confidence or metadata on existing memory"
  @spec reinforce(String.t(), keyword()) :: {:ok, Memory.t()} | {:error, term()}
  def reinforce(memory_id, opts \\ [])

  # --- PRD Execution ---

  @doc "Start or resume tracking a PRD execution"
  @spec start_prd(String.t(), keyword()) :: {:ok, PRD.Execution.t()}
  def start_prd(prd_ref, opts \\ [])
  # If execution exists for this prd_ref, returns it. Otherwise creates new.
  # opts: title: String.t()

  @doc "Get current state of a PRD execution with progress and recent events"
  @spec get_prd_context(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def get_prd_context(prd_id, opts \\ [])
  # Returns: %{execution: ..., progress: ..., recent_events: [...],
  #             decisions: [...], learnings: [...], blockers: [...]}
  # opts: event_limit: integer(), include_decisions: boolean()

  @doc "Append an event to a PRD execution"
  @spec append_prd_event(String.t(), map()) :: {:ok, PRD.Event.t()}
  def append_prd_event(prd_id, event_attrs)

  @doc "Record a decision made during PRD execution"
  @spec record_prd_decision(String.t(), map()) :: {:ok, PRD.Decision.t()}
  def record_prd_decision(prd_id, decision_attrs)

  @doc "Update PRD execution status"
  @spec update_prd_status(String.t(), atom()) :: {:ok, PRD.Execution.t()}
  def update_prd_status(prd_id, status)

  # --- Thinking Chains ---

  @doc "Start a new thinking chain"
  @spec start_chain(String.t(), keyword()) :: {:ok, ThinkingChain.t()}
  def start_chain(query, opts \\ [])

  @doc "Add a thought to an active chain"
  @spec add_thought(String.t(), map()) :: {:ok, ThinkingChain.t()}
  def add_thought(chain_id, thought)

  @doc "Complete a chain — triggers summarization and memory extraction"
  @spec complete_chain(String.t()) :: {:ok, ThinkingChain.t()}
  def complete_chain(chain_id)

  @doc "Retrieve similar past thinking chains"
  @spec recall_reasoning(String.t(), keyword()) :: [ThinkingChain.t()]
  def recall_reasoning(query, opts \\ [])
end
```

---

## Retrieval Pipeline

The retrieval pipeline is the critical path — it determines what context an agent receives.

### Pipeline Stages

```
retrieve(query, scope: {:project, "samgita"}, limit: 10)
│
├─ 1. Scope Filter (ETS)
│     Filter by scope_type + scope_id
│     Sub-millisecond, eliminates cross-project contamination
│
├─ 2. Tag Filter (optional, Postgres GIN index)
│     If tags specified, intersect with tag index
│
├─ 3. Semantic Search (Postgres pgvector)
│     Cosine similarity on query embedding vs stored embeddings
│     Returns top-k * 3 candidates (over-fetch for reranking)
│
├─ 4. Recency Boost
│     score = semantic_score * 0.7 + recency_score * 0.2 + access_score * 0.1
│     recency_score = 1.0 / (1.0 + days_since_creation / 30)
│     access_score = 1.0 / (1.0 + days_since_access / 7)
│
├─ 5. Confidence Threshold
│     Drop memories with confidence < min_confidence (default 0.3)
│
├─ 6. Deduplication
│     If two memories have cosine similarity > 0.95, keep higher confidence one
│
└─ 7. Format for Context Injection
      Truncate to fit token budget, most relevant first
      Return as structured list with memory IDs for feedback tracking
```

### Embedding Generation

Embeddings are generated asynchronously via Oban worker after memory creation:

```elixir
# SamgitaMemory.Workers.Embedding
# Uses Anthropic API or a local model (configurable)
# Retries with exponential backoff on failure
# Memories are retrievable by tag/scope before embedding completes
# Once embedding is ready, memory becomes semantically searchable
```

### Configuration

```elixir
config :samgita_memory,
  embedding_provider: :anthropic,          # :anthropic | :local
  embedding_model: "voyage-3",             # or local model path
  embedding_dimensions: 1536,
  retrieval_default_limit: 10,
  retrieval_min_confidence: 0.3,
  retrieval_semantic_weight: 0.7,
  retrieval_recency_weight: 0.2,
  retrieval_access_weight: 0.1,
  cache_max_memories: 10_000,
  cache_max_prd_executions: 100
```

---

## Memory Formation

### Explicit Formation

Direct calls to `SamgitaMemory.store/2` — user or agent explicitly says "remember this."

### Implicit Formation via Telemetry

Agents emit telemetry events. Memory formation handlers decide what to persist.

#### Telemetry Events to Handle

| Event | Memory Created |
|-------|---------------|
| `[:prd, :requirement, :completed]` | Episodic: "Completed req-X: summary" |
| `[:prd, :requirement, :failed]` | Episodic + Procedural learning |
| `[:prd, :decision, :made]` | Stored as PRD Decision + semantic memory |
| `[:prd, :blocker, :hit]` | Episodic: blocker context |
| `[:prd, :blocker, :resolved]` | Procedural: how it was resolved |
| `[:thinking, :chain, :completed]` | Summarized chain → semantic memory |
| `[:thinking, :revision]` | Procedural: revision pattern signal |
| `[:agent, :error]` | Episodic: what went wrong |
| `[:agent, :handoff]` | Episodic: handoff context |

#### Handler Implementation

```elixir
defmodule SamgitaMemory.Formation.TelemetryHandler do
  def handle_event([:prd, :requirement, :completed], measurements, metadata, _config) do
    SamgitaMemory.append_prd_event(metadata.prd_id, %{
      type: :requirement_completed,
      requirement_id: metadata.requirement_id,
      summary: metadata.summary,
      detail: %{
        duration_ms: measurements[:duration],
        files_changed: metadata[:files_changed],
        tests_added: metadata[:tests_added]
      },
      agent_id: metadata[:agent_id]
    })

    # Also create a semantic memory for cross-project retrieval
    SamgitaMemory.store(metadata.summary,
      source: {:prd_event, metadata.prd_id},
      scope: {:project, metadata.project},
      type: :episodic,
      tags: ["prd", metadata.requirement_id]
    )
  end

  def handle_event([:thinking, :revision], _measurements, metadata, _config) do
    # A revision is a learning signal
    SamgitaMemory.store(
      "When reasoning about #{metadata.topic}, initial approach " <>
      "'#{metadata.original}' needed revision to '#{metadata.revised}' " <>
      "because: #{metadata.reason}",
      source: {:observation, metadata.chain_id},
      scope: {:project, metadata.project},
      type: :procedural,
      tags: ["revision-pattern", metadata.topic]
    )
  end
end
```

---

## Compaction and Lifecycle

### Confidence Decay

Oban cron job runs daily:

```elixir
# SamgitaMemory.Workers.Compaction

# Decay formula: new_confidence = confidence * decay_rate
# decay_rate depends on memory type:
#   episodic:   0.98/day (half-life ~34 days)
#   semantic:   0.995/day (half-life ~138 days)
#   procedural: 0.999/day (half-life ~693 days)
#
# Access resets confidence to max(current, 0.8)
# Explicit reinforcement sets confidence to 1.0
# Memories below 0.1 confidence are pruned
```

### PRD Execution Compaction

When a PRD execution is marked `:completed`:

1. Oban job summarizes the full event log into a compact narrative
2. Extracts decisions and learnings as standalone semantic memories
3. Moves full event log from ETS to cold Postgres storage
4. Keeps summary + decisions in hot cache for fast retrieval

### Thinking Chain Summarization

When a chain completes:

1. Oban job generates a summary via LLM call (Haiku for cost efficiency)
2. Summary gets an embedding for future semantic retrieval
3. Full thought list stays in Postgres but not in ETS
4. If the chain had revisions, extract procedural memories from the revision patterns

---

## MCP Interface

Exposed via `samgita_mcp` app (SSE transport over Phoenix endpoint).

### Tools

| Tool | Maps To | Description |
|------|---------|-------------|
| `recall` | `SamgitaMemory.retrieve/2` | Retrieve relevant memories for a query |
| `remember` | `SamgitaMemory.store/2` | Explicitly store a memory |
| `forget` | `SamgitaMemory.forget/1` | Remove a memory |
| `prd_context` | `SamgitaMemory.get_prd_context/2` | Get full PRD execution state for resume |
| `prd_event` | `SamgitaMemory.append_prd_event/2` | Log a PRD execution event |
| `prd_decision` | `SamgitaMemory.record_prd_decision/2` | Record a decision |
| `think` | `SamgitaMemory.add_thought/2` | Add thought to active chain |
| `start_thinking` | `SamgitaMemory.start_chain/2` | Begin a new reasoning chain |
| `finish_thinking` | `SamgitaMemory.complete_chain/1` | Complete chain, trigger summarization |
| `recall_reasoning` | `SamgitaMemory.recall_reasoning/2` | Find similar past reasoning |

### Token Budget Awareness

The MCP layer enforces a configurable token budget (default: 4000 tokens) on responses. When retrieval returns more content than fits:

1. Rank by relevance score
2. Include highest-ranked memories in full
3. For remaining, include only `content` field (drop metadata)
4. If still over budget, truncate list and append `{truncated: true, total: N}`

---

## ETS Cache Strategy

### Memory Cache

- **Table**: `:memory_cache`, type `:set`, read concurrency enabled
- **Key**: `{scope_type, scope_id, memory_id}`
- **Eviction**: LRU-based, max 10,000 entries
- **Population**: on access (read-through cache)
- **Invalidation**: on update, on delete, on confidence drop below threshold

### PRD Execution Cache

- **Table**: `:prd_cache`, type `:set`
- **Key**: `prd_id`
- **Contents**: full execution struct with recent events (last 50) and all decisions
- **Population**: on first access or on event append
- **Eviction**: on completion + compaction, or LRU at 100 entries

---

## Database Migrations

### Migration 1: Core Memory Tables

```elixir
def change do
  execute "CREATE EXTENSION IF NOT EXISTS vector"

  create table(:memories, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :content, :text, null: false
    add :embedding, :vector, size: 1536
    add :source_type, :string, null: false
    add :source_id, :string
    add :scope_type, :string, null: false
    add :scope_id, :string
    add :memory_type, :string, null: false
    add :confidence, :float, default: 1.0, null: false
    add :access_count, :integer, default: 0, null: false
    add :tags, {:array, :string}, default: []
    add :metadata, :map, default: %{}
    add :accessed_at, :utc_datetime

    timestamps()
  end

  # Indexes as specified in Data Model section
end
```

### Migration 2: PRD Execution Tables

```elixir
def change do
  create table(:prd_executions, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :prd_ref, :string, null: false
    add :prd_hash, :string
    add :title, :string
    add :status, :string, default: "not_started", null: false
    add :progress, :map, default: %{}

    timestamps()
  end

  create unique_index(:prd_executions, [:prd_ref])

  create table(:prd_events, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :execution_id, references(:prd_executions, type: :binary_id), null: false
    add :type, :string, null: false
    add :requirement_id, :string
    add :summary, :text, null: false
    add :detail, :map, default: %{}
    add :agent_id, :string
    add :thinking_chain_id, :binary_id

    timestamps()
  end

  create index(:prd_events, [:execution_id])
  create index(:prd_events, [:requirement_id])

  create table(:prd_decisions, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :execution_id, references(:prd_executions, type: :binary_id), null: false
    add :requirement_id, :string
    add :decision, :text, null: false
    add :reason, :text
    add :alternatives, {:array, :string}, default: []
    add :agent_id, :string

    timestamps()
  end

  create index(:prd_decisions, [:execution_id])
end
```

### Migration 3: Thinking Chains

```elixir
def change do
  create table(:thinking_chains, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :scope_type, :string, null: false
    add :scope_id, :string
    add :query, :text
    add :summary, :text
    add :embedding, :vector, size: 1536
    add :status, :string, default: "active", null: false
    add :thoughts, {:array, :map}, default: []
    add :metadata, :map, default: %{}

    timestamps()
  end

  create index(:thinking_chains, [:scope_type, :scope_id])
  create index(:thinking_chains, [:status])
end
```

---

## Implementation Plan

### Phase 1: Core Memory (Priority: Highest)

1. Create `samgita_memory` OTP app in umbrella
2. Migrations 1-3
3. Ecto schemas for Memory, PRD Execution, PRD Event, PRD Decision, ThinkingChain
4. `SamgitaMemory` public API — `store/2`, `retrieve/2`, `forget/1`
5. Basic retrieval: scope filter + tag filter (no semantic search yet)
6. Tests: unit tests for all CRUD operations, retrieval with scope isolation

### Phase 2: PRD Execution Tracking (Priority: High)

1. `start_prd/2`, `get_prd_context/2`, `append_prd_event/2`, `record_prd_decision/2`
2. Progress materialization from events
3. ETS cache for active PRD executions
4. Telemetry handler for PRD events
5. Tests: PRD lifecycle — create, add events, resume, complete

### Phase 3: Semantic Search (Priority: High)

1. Oban worker for embedding generation
2. pgvector cosine similarity queries
3. Hybrid retrieval pipeline (full 7-stage pipeline)
4. Recency boost and confidence threshold
5. Tests: retrieval relevance, deduplication, scoring

### Phase 4: Thinking Chains (Priority: Medium)

1. `start_chain/2`, `add_thought/2`, `complete_chain/1`, `recall_reasoning/2`
2. Oban worker for chain summarization on completion
3. Revision pattern extraction for procedural memory
4. Tests: chain lifecycle, similar chain retrieval

### Phase 5: Compaction and Lifecycle (Priority: Medium)

1. Confidence decay Oban cron job
2. PRD execution compaction on completion
3. Memory pruning below threshold
4. Access-based confidence reinforcement
5. Tests: decay math, compaction correctness, pruning

### Phase 6: MCP Interface (Priority: Medium)

1. MCP tool definitions in `samgita_mcp`
2. SSE transport via Phoenix endpoint
3. Token budget truncation logic
4. Tests: MCP tool roundtrip, budget enforcement

---

## Non-Goals (Explicit Exclusions)

- **Real-time sync between machines** — Postgres is the sync point, no CRDT or replication protocol
- **Multi-user memory** — single user (Jonathan), no access control or tenant isolation
- **Automatic PRD parsing** — agents manually call `prd_event` and `prd_decision`, no NLP extraction from PRD markdown
- **GUI for memory editing** — LiveView dashboard is observation-only in v1 (read, not write)
- **Local embedding model** — v1 uses Anthropic API for embeddings, local model is future work

---

## Testing Strategy

### Unit Tests

- Memory CRUD with scope isolation (project A memories not visible in project B)
- PRD event ordering and progress materialization
- Retrieval pipeline stages in isolation
- Confidence decay math
- ETS cache population and eviction

### Integration Tests

- Full retrieval pipeline: store → embed → retrieve by semantic similarity
- PRD lifecycle: start → events → decisions → resume → complete → compact
- Thinking chain: start → thoughts → complete → summarize → recall similar
- Telemetry → memory formation end-to-end

### Property Tests

- Retrieval always returns results within scope
- Confidence monotonically decreases without access
- PRD progress is always consistent with events
- Compaction preserves all decisions (never loses decisions)

---

## Configuration

```elixir
# config/config.exs
config :samgita_memory, SamgitaMemory.Repo,
  database: "samgita_memory",
  extensions: [{Pgvector.Extensions.Vector, []}]

config :samgita_memory, Oban,
  repo: SamgitaMemory.Repo,
  queues: [
    embeddings: 5,
    compaction: 2,
    summarization: 3
  ],
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 3 * * *", SamgitaMemory.Workers.Compaction}  # 3am daily decay
    ]}
  ]

config :samgita_memory,
  embedding_provider: :anthropic,
  embedding_dimensions: 1536,
  retrieval_default_limit: 10,
  retrieval_min_confidence: 0.3,
  cache_max_memories: 10_000,
  cache_max_prd_executions: 100
```

---

## Success Criteria

1. An agent can call `prd_context` and receive a complete summary of prior work on a PRD in under 100ms (ETS hit) or under 500ms (Postgres)
2. Semantic retrieval returns relevant memories with precision > 0.8 on a test corpus of 1000 memories
3. PRD progress is always consistent with events — no orphaned or contradictory state
4. Confidence decay runs without impacting query latency
5. A full PRD lifecycle (create → 50 events → complete → compact) takes < 5 seconds total
6. MCP tool responses stay under the configured token budget
7. Cross-project memory isolation: memories scoped to project A never appear in project B queries