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

  def category_color("Agents"), do: "bg-purple-100 text-purple-800 border-purple-300"
  def category_color("Research"), do: "bg-blue-100 text-blue-800 border-blue-300"
  def category_color("Architecture"), do: "bg-green-100 text-green-800 border-green-300"
  def category_color("Business"), do: "bg-orange-100 text-orange-800 border-orange-300"
  def category_color("Operations"), do: "bg-red-100 text-red-800 border-red-300"
  def category_color("Integration"), do: "bg-cyan-100 text-cyan-800 border-cyan-300"
  def category_color("Optimization"), do: "bg-yellow-100 text-yellow-800 border-yellow-300"
  def category_color("Quality"), do: "bg-pink-100 text-pink-800 border-pink-300"
  def category_color(_), do: "bg-zinc-100 text-zinc-800 border-zinc-300"
end
