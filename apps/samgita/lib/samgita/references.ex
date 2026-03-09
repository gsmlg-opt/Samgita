defmodule Samgita.References do
  @moduledoc """
  Context for managing reference documentation from loki-mode.
  """

  @references_dir "references"

  @references %{
    "agents.md" => %{
      title: "Agent Type Definitions",
      category: "Agents",
      description: "Complete specifications for all 37 specialized agent types"
    },
    "agent-types.md" => %{
      title: "Agent Types Reference",
      category: "Agents",
      description: "Agent capabilities and dynamic scaling rules"
    },
    "advanced-patterns.md" => %{
      title: "Advanced Patterns",
      category: "Research",
      description: "2025 research patterns (MAR, Iter-VF, GoalAct)"
    },
    "business-ops.md" => %{
      title: "Business Operations",
      category: "Business",
      description: "Business operation workflows and patterns"
    },
    "competitive-analysis.md" => %{
      title: "Competitive Analysis",
      category: "Research",
      description: "Auto-Claude, MemOS, Dexter comparison"
    },
    "confidence-routing.md" => %{
      title: "Confidence Routing",
      category: "Architecture",
      description: "Model selection by confidence levels"
    },
    "core-workflow.md" => %{
      title: "Core Workflow",
      category: "Architecture",
      description: "RARV cycle and autonomy rules"
    },
    "cursor-learnings.md" => %{
      title: "Cursor Learnings",
      category: "Research",
      description: "Cursor scaling patterns at 100+ agent scale"
    },
    "deployment.md" => %{
      title: "Deployment",
      category: "Operations",
      description: "Cloud deployment instructions and patterns"
    },
    "lab-research-patterns.md" => %{
      title: "Lab Research Patterns",
      category: "Research",
      description: "DeepMind + Anthropic: Constitutional AI, debate"
    },
    "mcp-integration.md" => %{
      title: "MCP Integration",
      category: "Integration",
      description: "Model Context Protocol server capabilities"
    },
    "memory-system.md" => %{
      title: "Memory System",
      category: "Architecture",
      description: "Episodic/semantic memory architecture"
    },
    "multi-provider.md" => %{
      title: "Multi-Provider",
      category: "Integration",
      description: "Claude, OpenAI, Gemini provider support"
    },
    "openai-patterns.md" => %{
      title: "OpenAI Patterns",
      category: "Research",
      description: "OpenAI Agents SDK: guardrails, tripwires, handoffs"
    },
    "production-patterns.md" => %{
      title: "Production Patterns",
      category: "Operations",
      description: "HN 2025: What actually works in production"
    },
    "prompt-repetition.md" => %{
      title: "Prompt Repetition",
      category: "Optimization",
      description: "Haiku prompt optimization patterns"
    },
    "quality-control.md" => %{
      title: "Quality Control",
      category: "Quality",
      description: "Code review, anti-sycophancy, guardrails"
    },
    "sdlc-phases.md" => %{
      title: "SDLC Phases",
      category: "Architecture",
      description: "Full Software Development Lifecycle workflow"
    },
    "task-queue.md" => %{
      title: "Task Queue",
      category: "Architecture",
      description: "Queue system, circuit breakers, priority handling"
    },
    "tool-orchestration.md" => %{
      title: "Tool Orchestration",
      category: "Architecture",
      description: "ToolOrchestra-inspired efficiency & rewards"
    }
  }

  def list_references do
    @references
    |> Enum.map(fn {filename, metadata} ->
      Map.put(metadata, :filename, filename)
    end)
    |> Enum.sort_by(& &1.title)
  end

  def list_by_category do
    list_references()
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {category, _} -> category end)
  end

  def get_reference(filename) do
    case Map.get(@references, filename) do
      nil ->
        {:error, :not_found}

      metadata ->
        path = Path.join(:code.priv_dir(:samgita), Path.join(@references_dir, filename))

        case File.read(path) do
          {:ok, content} ->
            {:ok, Map.merge(metadata, %{filename: filename, content: content})}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def category_badge_color("Agents"), do: "secondary"
  def category_badge_color("Research"), do: "primary"
  def category_badge_color("Architecture"), do: "success"
  def category_badge_color("Business"), do: "tertiary"
  def category_badge_color("Operations"), do: "error"
  def category_badge_color("Integration"), do: "info"
  def category_badge_color("Optimization"), do: "warning"
  def category_badge_color("Quality"), do: "secondary"
  def category_badge_color(_), do: ""
end
