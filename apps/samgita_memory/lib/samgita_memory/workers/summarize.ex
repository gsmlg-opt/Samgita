defmodule SamgitaMemory.Workers.Summarize do
  @moduledoc """
  Oban worker for:
  1. Thinking chain summarization on completion
  2. PRD execution compaction on completion

  For thinking chains: generates a summary and extracts procedural memories
  from revision patterns.

  For PRD executions: summarizes the event log and extracts decisions as
  standalone semantic memories.
  """

  use Oban.Worker,
    queue: :summarization,
    max_attempts: 3,
    priority: 2

  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.ThinkingChain
  alias SamgitaMemory.PRD.Execution
  alias SamgitaMemory.Cache.PRDTable

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "thinking_chain", "chain_id" => chain_id}}) do
    case Repo.get(ThinkingChain, chain_id) do
      nil -> :ok
      chain -> summarize_chain(chain)
    end
  end

  def perform(%Oban.Job{args: %{"type" => "prd_execution", "execution_id" => execution_id}}) do
    case Repo.get(Execution, execution_id) do
      nil -> :ok
      execution -> compact_prd_execution(execution)
    end
  end

  def perform(_job), do: :ok

  @doc "Enqueue chain summarization."
  def enqueue_chain_summarization(chain_id) do
    %{type: "thinking_chain", chain_id: chain_id}
    |> new()
    |> Oban.insert(SamgitaMemory.Oban)
  end

  @doc "Enqueue PRD execution compaction."
  def enqueue_prd_compaction(execution_id) do
    %{type: "prd_execution", execution_id: execution_id}
    |> new()
    |> Oban.insert(SamgitaMemory.Oban)
  end

  # --- Chain Summarization ---

  defp summarize_chain(chain) do
    summary = generate_chain_summary(chain)

    chain
    |> Ecto.Changeset.change(%{summary: summary})
    |> Repo.update()

    # Extract revision patterns as procedural memories
    extract_revision_patterns(chain)

    :ok
  end

  defp generate_chain_summary(chain) do
    thoughts = chain.thoughts || []
    thought_count = length(thoughts)

    if thought_count == 0 do
      "Empty thinking chain for: #{chain.query}"
    else
      # Build summary from thoughts
      revision_count =
        Enum.count(thoughts, fn t ->
          (t["is_revision"] || t[:is_revision]) == true
        end)

      last_thought = List.last(thoughts)
      last_content = last_thought["content"] || last_thought[:content] || ""

      conclusion =
        if String.length(last_content) > 200,
          do: String.slice(last_content, 0, 200) <> "...",
          else: last_content

      parts = ["Reasoning about: #{chain.query}"]
      parts = parts ++ ["#{thought_count} thoughts"]

      parts =
        if revision_count > 0,
          do: parts ++ ["#{revision_count} revisions"],
          else: parts

      parts = parts ++ ["Conclusion: #{conclusion}"]

      Enum.join(parts, ". ")
    end
  end

  defp extract_revision_patterns(chain) do
    thoughts = chain.thoughts || []

    revisions =
      Enum.filter(thoughts, fn t ->
        (t["is_revision"] || t[:is_revision]) == true
      end)

    for revision <- revisions do
      revises = revision["revises"] || revision[:revises]
      content = revision["content"] || revision[:content] || ""

      original =
        Enum.find(thoughts, fn t ->
          (t["number"] || t[:number]) == revises
        end)

      original_content =
        if original, do: original["content"] || original[:content] || "unknown", else: "unknown"

      memory_content =
        "When reasoning about '#{chain.query}', initial approach " <>
          "'#{truncate(original_content, 100)}' was revised to " <>
          "'#{truncate(content, 100)}'"

      SamgitaMemory.Memories.store(memory_content,
        source: {:observation, chain.id},
        scope: {chain.scope_type, chain.scope_id},
        type: :procedural,
        tags: ["revision-pattern"],
        metadata: %{
          chain_id: chain.id,
          original_thought: revises,
          revision_thought: revision["number"] || revision[:number]
        }
      )
    end
  end

  # --- PRD Execution Compaction ---

  defp compact_prd_execution(execution) do
    execution = Repo.preload(execution, [:events, :decisions])

    # Generate compact narrative from events
    summary = generate_prd_summary(execution)

    # Extract decisions as standalone semantic memories
    for decision <- execution.decisions do
      SamgitaMemory.Memories.store(
        "Decision for #{execution.title || execution.prd_ref}: #{decision.decision}. " <>
          "Reason: #{decision.reason || "not specified"}",
        source: {:prd_event, execution.id},
        scope: {:global, nil},
        type: :semantic,
        tags: ["prd-decision", execution.prd_ref],
        metadata: %{
          execution_id: execution.id,
          requirement_id: decision.requirement_id,
          alternatives: decision.alternatives
        }
      )
    end

    # Store the summary as a semantic memory
    SamgitaMemory.Memories.store(summary,
      source: {:compaction, execution.id},
      scope: {:global, nil},
      type: :semantic,
      tags: ["prd-summary", execution.prd_ref],
      metadata: %{
        execution_id: execution.id,
        event_count: length(execution.events),
        decision_count: length(execution.decisions)
      }
    )

    # Invalidate ETS cache
    PRDTable.invalidate(execution.id)

    :ok
  end

  defp generate_prd_summary(execution) do
    events = execution.events || []
    decisions = execution.decisions || []

    completed =
      Enum.count(events, fn e ->
        to_string(e.type) == "requirement_completed"
      end)

    failed =
      Enum.count(events, fn e ->
        to_string(e.type) == "test_failed" or to_string(e.type) == "error_encountered"
      end)

    "PRD '#{execution.title || execution.prd_ref}' completed. " <>
      "#{length(events)} events, #{length(decisions)} decisions. " <>
      "#{completed} requirements completed, #{failed} issues encountered."
  end

  defp truncate(text, max) when is_binary(text) and byte_size(text) > max do
    String.slice(text, 0, max) <> "..."
  end

  defp truncate(text, _max), do: text
end
