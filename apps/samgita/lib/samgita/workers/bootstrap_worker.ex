defmodule Samgita.Workers.BootstrapWorker do
  @moduledoc """
  Oban worker that bootstraps a project from a PRD.

  Parses PRD content, extracts requirements, and generates a structured
  task backlog. This is the first step in the autonomous pipeline:
  PRD → tasks → agent dispatch → development.
  """

  use Oban.Worker,
    queue: :orchestration,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :executing]]

  require Logger

  alias Samgita.Projects
  alias Samgita.Workers.AgentTaskWorker

  @impl true
  def perform(%Oban.Job{args: %{"project_id" => project_id, "prd_id" => prd_id}}) do
    Logger.info("[BootstrapWorker] Starting bootstrap for project #{project_id}, PRD #{prd_id}")

    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, prd} <- get_prd(project, prd_id),
         {:ok, tasks} <- generate_task_backlog(project, prd) do
      task_count = length(tasks)

      Logger.info(
        "[BootstrapWorker] Generated #{task_count} tasks for project #{project_id}"
      )

      # Enqueue all tasks via Oban
      enqueued = enqueue_tasks(project_id, prd_id, tasks)

      # Notify orchestrator of expected task count
      notify_orchestrator(project_id, length(enqueued))

      broadcast_activity(
        project_id,
        "Bootstrap complete: #{length(enqueued)} tasks enqueued from PRD"
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("[BootstrapWorker] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Parse PRD content and generate a structured task backlog.

  Returns a list of task descriptors: `%{type, agent_type, priority, description, payload}`.
  """
  def generate_task_backlog(project, prd) do
    prd_content = prd.content || ""

    # Extract sections from markdown PRD
    sections = parse_prd_sections(prd_content)

    # Generate tasks from sections
    tasks =
      []
      |> add_analysis_tasks(sections, project)
      |> add_architecture_tasks(sections, project)
      |> add_implementation_tasks(sections, project)
      |> add_testing_tasks(sections, project)
      |> add_documentation_tasks(sections, project)

    {:ok, tasks}
  end

  ## PRD Parsing

  defp parse_prd_sections(content) do
    # Split by markdown headers and categorize
    lines = String.split(content, "\n")

    {sections, current_section, current_lines} =
      Enum.reduce(lines, {%{}, nil, []}, fn line, {sections, current, lines} ->
        case parse_header(line) do
          {:header, level, title} when level <= 2 ->
            sections =
              if current do
                Map.put(sections, current, Enum.reverse(lines))
              else
                sections
              end

            {sections, normalize_section_name(title), []}

          _ ->
            {sections, current, [line | lines]}
        end
      end)

    # Don't forget the last section
    if current_section do
      Map.put(sections, current_section, Enum.reverse(current_lines))
    else
      sections
    end
  end

  defp parse_header(line) do
    trimmed = String.trim(line)

    case Regex.run(~r/^(\#{1,6})\s+(.+)$/, trimmed) do
      [_, hashes, title] -> {:header, String.length(hashes), String.trim(title)}
      _ -> :not_header
    end
  end

  defp normalize_section_name(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  ## Task Generation

  defp add_analysis_tasks(tasks, sections, project) do
    analysis_task = %{
      type: "analysis",
      agent_type: "prod-pm",
      priority: 1,
      description: "Analyze PRD and extract detailed requirements",
      payload: %{
        "project_name" => project.name,
        "git_url" => project.git_url,
        "working_path" => project.working_path,
        "section_count" => map_size(sections),
        "section_names" => Map.keys(sections)
      }
    }

    [analysis_task | tasks]
  end

  defp add_architecture_tasks(tasks, sections, project) do
    arch_sections =
      Enum.filter(Map.keys(sections), fn key ->
        String.contains?(key, "architect") or
          String.contains?(key, "technical") or
          String.contains?(key, "stack") or
          String.contains?(key, "design")
      end)

    if arch_sections != [] or has_technical_content?(sections) do
      arch_task = %{
        type: "architecture",
        agent_type: "eng-infra",
        priority: 2,
        description: "Design system architecture based on PRD requirements",
        payload: %{
          "project_name" => project.name,
          "relevant_sections" => arch_sections
        }
      }

      [arch_task | tasks]
    else
      tasks
    end
  end

  defp add_implementation_tasks(tasks, sections, project) do
    # Extract feature requirements from sections
    features = extract_features(sections)

    feature_tasks =
      features
      |> Enum.with_index(1)
      |> Enum.map(fn {feature, idx} ->
        %{
          type: "implement",
          agent_type: agent_for_feature(feature),
          priority: 3 + div(idx, 5),
          description: "Implement: #{feature}",
          payload: %{
            "project_name" => project.name,
            "feature" => feature,
            "working_path" => project.working_path
          }
        }
      end)

    feature_tasks ++ tasks
  end

  defp add_testing_tasks(tasks, _sections, project) do
    test_task = %{
      type: "test",
      agent_type: "eng-qa",
      priority: 8,
      description: "Generate test suite for implemented features",
      payload: %{
        "project_name" => project.name,
        "working_path" => project.working_path
      }
    }

    [test_task | tasks]
  end

  defp add_documentation_tasks(tasks, _sections, project) do
    doc_task = %{
      type: "documentation",
      agent_type: "prod-techwriter",
      priority: 9,
      description: "Generate project documentation",
      payload: %{
        "project_name" => project.name,
        "working_path" => project.working_path
      }
    }

    [doc_task | tasks]
  end

  ## Feature Extraction

  defp extract_features(sections) do
    sections
    |> Enum.flat_map(fn {_name, lines} ->
      lines
      |> Enum.filter(&is_feature_line?/1)
      |> Enum.map(&extract_feature_text/1)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(50)
  end

  defp is_feature_line?(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, "- [ ]") or
      String.starts_with?(trimmed, "- [x]") or
      String.starts_with?(trimmed, "* ") or
      String.starts_with?(trimmed, "- ") or
      Regex.match?(~r/^\d+\.\s/, trimmed)
  end

  defp extract_feature_text(line) do
    line
    |> String.trim()
    |> String.replace(~r/^[-*]\s*\[[ x]\]\s*/, "")
    |> String.replace(~r/^[-*]\s*/, "")
    |> String.replace(~r/^\d+\.\s*/, "")
    |> String.trim()
    |> case do
      "" -> nil
      text when byte_size(text) < 10 -> nil
      text -> text
    end
  end

  defp has_technical_content?(sections) do
    Enum.any?(sections, fn {_name, lines} ->
      Enum.any?(lines, fn line ->
        String.contains?(String.downcase(line), ["api", "database", "endpoint", "schema"])
      end)
    end)
  end

  defp agent_for_feature(feature) do
    feature_lower = String.downcase(feature)

    cond do
      String.contains?(feature_lower, ["ui", "frontend", "component", "page", "view"]) ->
        "eng-frontend"

      String.contains?(feature_lower, ["api", "endpoint", "rest", "graphql"]) ->
        "eng-api"

      String.contains?(feature_lower, ["database", "schema", "migration", "query"]) ->
        "eng-database"

      String.contains?(feature_lower, ["deploy", "ci", "cd", "docker"]) ->
        "ops-devops"

      String.contains?(feature_lower, ["security", "auth", "permission"]) ->
        "ops-security"

      String.contains?(feature_lower, ["test", "spec", "coverage"]) ->
        "eng-qa"

      true ->
        "eng-backend"
    end
  end

  ## Task Enqueuing

  defp enqueue_tasks(project_id, prd_id, task_descriptors) do
    task_descriptors
    |> Enum.sort_by(& &1.priority)
    |> Enum.reduce([], fn descriptor, acc ->
      payload =
        Map.merge(descriptor.payload, %{"prd_id" => prd_id})

      case Projects.create_task(project_id, %{
             type: descriptor.type,
             priority: descriptor.priority,
             payload: payload,
             status: :pending
           }) do
        {:ok, task} ->
          case Oban.insert(
                 AgentTaskWorker.new(%{
                   task_id: task.id,
                   project_id: project_id,
                   agent_type: descriptor.agent_type
                 })
               ) do
            {:ok, _job} -> [task | acc]
            {:error, reason} ->
              Logger.warning("[BootstrapWorker] Failed to enqueue task: #{inspect(reason)}")
              acc
          end

        {:error, reason} ->
          Logger.warning("[BootstrapWorker] Failed to create task: #{inspect(reason)}")
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp notify_orchestrator(project_id, task_count) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        Samgita.Project.Orchestrator.set_phase_task_count(pid, task_count)

      [] ->
        Logger.debug("[BootstrapWorker] No orchestrator found for #{project_id}")
    end
  end

  defp get_prd(project, prd_id) do
    case Samgita.Repo.get_by(Samgita.Domain.Prd, id: prd_id, project_id: project.id) do
      nil -> {:error, :prd_not_found}
      prd -> {:ok, prd}
    end
  end

  defp broadcast_activity(project_id, message) do
    entry =
      Samgita.Events.build_log_entry(:orchestrator, "bootstrap", :completed, message)

    Samgita.Events.activity_log(project_id, entry)
  end
end
