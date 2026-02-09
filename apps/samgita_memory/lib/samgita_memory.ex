defmodule SamgitaMemory do
  @moduledoc """
  Public API for the Samgita Memory System.

  Provides persistent, queryable memory for Claude Code agents with:
  - Episodic, semantic, and procedural memory types
  - PRD execution tracking with event sourcing
  - Thinking chain capture and retrieval
  - Hybrid retrieval pipeline (scope + tag + semantic + recency)
  - ETS hot caching with Postgres/pgvector persistence
  """

  alias SamgitaMemory.Memories
  alias SamgitaMemory.PRD
  alias SamgitaMemory.Memories.ThinkingChain

  # --- Memory CRUD ---

  @doc "Store a new memory fact"
  @spec store(String.t(), keyword()) :: {:ok, Memories.Memory.t()} | {:error, term()}
  def store(content, opts \\ []) do
    Memories.store(content, opts)
  end

  @doc "Retrieve memories relevant to a query"
  @spec retrieve(String.t(), keyword()) :: [Memories.Memory.t()]
  def retrieve(query, opts \\ []) do
    Memories.retrieve(query, opts)
  end

  @doc "Explicitly forget a memory"
  @spec forget(String.t()) :: :ok | {:error, :not_found}
  def forget(memory_id) do
    Memories.forget(memory_id)
  end

  @doc "Update confidence or metadata on existing memory"
  @spec reinforce(String.t(), keyword()) :: {:ok, Memories.Memory.t()} | {:error, term()}
  def reinforce(memory_id, opts \\ []) do
    Memories.reinforce(memory_id, opts)
  end

  # --- PRD Execution ---

  @doc "Start or resume tracking a PRD execution"
  @spec start_prd(String.t(), keyword()) :: {:ok, PRD.Execution.t()}
  def start_prd(prd_ref, opts \\ []) do
    PRD.start_execution(prd_ref, opts)
  end

  @doc "Get current state of a PRD execution with progress and recent events"
  @spec get_prd_context(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def get_prd_context(prd_id, opts \\ []) do
    PRD.get_context(prd_id, opts)
  end

  @doc "Append an event to a PRD execution"
  @spec append_prd_event(String.t(), map()) :: {:ok, PRD.Event.t()}
  def append_prd_event(prd_id, event_attrs) do
    PRD.append_event(prd_id, event_attrs)
  end

  @doc "Record a decision made during PRD execution"
  @spec record_prd_decision(String.t(), map()) :: {:ok, PRD.Decision.t()}
  def record_prd_decision(prd_id, decision_attrs) do
    PRD.record_decision(prd_id, decision_attrs)
  end

  @doc "Update PRD execution status"
  @spec update_prd_status(String.t(), atom()) :: {:ok, PRD.Execution.t()}
  def update_prd_status(prd_id, status) do
    PRD.update_status(prd_id, status)
  end

  # --- Thinking Chains ---

  @doc "Start a new thinking chain"
  @spec start_chain(String.t(), keyword()) :: {:ok, ThinkingChain.t()}
  def start_chain(query, opts \\ []) do
    ThinkingChain.start(query, opts)
  end

  @doc "Add a thought to an active chain"
  @spec add_thought(String.t(), map()) :: {:ok, ThinkingChain.t()}
  def add_thought(chain_id, thought) do
    ThinkingChain.add_thought(chain_id, thought)
  end

  @doc "Complete a chain — triggers summarization and memory extraction"
  @spec complete_chain(String.t()) :: {:ok, ThinkingChain.t()}
  def complete_chain(chain_id) do
    ThinkingChain.complete(chain_id)
  end

  @doc "Retrieve similar past thinking chains"
  @spec recall_reasoning(String.t(), keyword()) :: [ThinkingChain.t()]
  def recall_reasoning(query, opts \\ []) do
    ThinkingChain.recall(query, opts)
  end
end
