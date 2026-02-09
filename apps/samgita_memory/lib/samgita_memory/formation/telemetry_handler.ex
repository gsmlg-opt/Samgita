defmodule SamgitaMemory.Formation.TelemetryHandler do
  @moduledoc """
  Telemetry event handler for implicit memory formation.

  Listens to agent/PRD telemetry events and creates memories automatically.
  """

  alias SamgitaMemory.Memories
  alias SamgitaMemory.PRD

  @events [
    [:prd, :requirement, :completed],
    [:prd, :requirement, :failed],
    [:prd, :decision, :made],
    [:prd, :blocker, :hit],
    [:prd, :blocker, :resolved],
    [:thinking, :chain, :completed],
    [:thinking, :revision],
    [:agent, :error],
    [:agent, :handoff]
  ]

  @doc "Attach all telemetry handlers."
  def attach do
    :telemetry.attach_many(
      "samgita-memory-formation",
      @events,
      &handle_event/4,
      nil
    )
  end

  @doc "Detach handlers."
  def detach do
    :telemetry.detach("samgita-memory-formation")
  end

  def handle_event([:prd, :requirement, :completed], measurements, metadata, _config) do
    if prd_id = metadata[:prd_id] do
      PRD.append_event(prd_id, %{
        type: :requirement_completed,
        requirement_id: metadata[:requirement_id],
        summary: metadata[:summary] || "Requirement completed",
        detail: %{
          duration_ms: measurements[:duration],
          files_changed: metadata[:files_changed],
          tests_added: metadata[:tests_added]
        },
        agent_id: metadata[:agent_id]
      })
    end

    if summary = metadata[:summary] do
      Memories.store(summary,
        source: {:prd_event, metadata[:prd_id]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :episodic,
        tags: ["prd", metadata[:requirement_id] || "unknown"]
      )
    end
  end

  def handle_event([:prd, :requirement, :failed], _measurements, metadata, _config) do
    if prd_id = metadata[:prd_id] do
      PRD.append_event(prd_id, %{
        type: :test_failed,
        requirement_id: metadata[:requirement_id],
        summary: metadata[:summary] || "Requirement failed",
        detail: metadata[:detail] || %{},
        agent_id: metadata[:agent_id]
      })
    end

    if summary = metadata[:summary] do
      Memories.store("Failed: #{summary}. Reason: #{metadata[:reason] || "unknown"}",
        source: {:prd_event, metadata[:prd_id]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :episodic,
        tags: ["prd", "failure", metadata[:requirement_id] || "unknown"]
      )
    end
  end

  def handle_event([:prd, :decision, :made], _measurements, metadata, _config) do
    if prd_id = metadata[:prd_id] do
      PRD.record_decision(prd_id, %{
        requirement_id: metadata[:requirement_id],
        decision: metadata[:decision],
        reason: metadata[:reason],
        alternatives: metadata[:alternatives] || [],
        agent_id: metadata[:agent_id]
      })
    end
  end

  def handle_event([:prd, :blocker, :hit], _measurements, metadata, _config) do
    if prd_id = metadata[:prd_id] do
      PRD.append_event(prd_id, %{
        type: :blocker_hit,
        requirement_id: metadata[:requirement_id],
        summary: metadata[:summary] || "Blocker encountered",
        detail: metadata[:detail] || %{},
        agent_id: metadata[:agent_id]
      })
    end
  end

  def handle_event([:prd, :blocker, :resolved], _measurements, metadata, _config) do
    if prd_id = metadata[:prd_id] do
      PRD.append_event(prd_id, %{
        type: :blocker_resolved,
        requirement_id: metadata[:requirement_id],
        summary: metadata[:summary] || "Blocker resolved",
        detail: metadata[:detail] || %{},
        agent_id: metadata[:agent_id]
      })
    end

    if resolution = metadata[:resolution] do
      Memories.store("Resolved blocker: #{resolution}",
        source: {:observation, metadata[:prd_id]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :procedural,
        tags: ["blocker-resolution"]
      )
    end
  end

  def handle_event([:thinking, :chain, :completed], _measurements, metadata, _config) do
    if chain_id = metadata[:chain_id] do
      SamgitaMemory.Workers.Summarize.enqueue_chain_summarization(chain_id)
    end
  end

  def handle_event([:thinking, :revision], _measurements, metadata, _config) do
    if metadata[:topic] && metadata[:original] && metadata[:revised] do
      Memories.store(
        "When reasoning about #{metadata.topic}, initial approach " <>
          "'#{metadata.original}' needed revision to '#{metadata.revised}' " <>
          "because: #{metadata[:reason] || "unspecified"}",
        source: {:observation, metadata[:chain_id]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :procedural,
        tags: ["revision-pattern", metadata[:topic] || "unknown"]
      )
    end
  end

  def handle_event([:agent, :error], _measurements, metadata, _config) do
    if summary = metadata[:summary] do
      Memories.store("Agent error: #{summary}",
        source: {:observation, metadata[:agent_id]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :episodic,
        tags: ["error", metadata[:error_type] || "unknown"]
      )
    end
  end

  def handle_event([:agent, :handoff], _measurements, metadata, _config) do
    if summary = metadata[:summary] do
      Memories.store("Agent handoff: #{summary}",
        source: {:observation, metadata[:from_agent]},
        scope: {:project, metadata[:project] || "unknown"},
        type: :episodic,
        tags: ["handoff"]
      )
    end
  end
end
