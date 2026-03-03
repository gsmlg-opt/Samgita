defmodule Samgita.Workers.BootstrapWorker do
  @moduledoc """
  Oban worker that bootstraps a project from a PRD.

  Parses PRD content, extracts requirements, milestones, and generates
  a structured task backlog with dependencies. This is the first step
  in the autonomous pipeline: PRD → tasks → agent dispatch → development.

  ## PRD Parsing

  The worker extracts structured data from markdown PRDs:
  - **Sections**: H1/H2 headers become named sections
  - **Milestones**: Sections matching milestone/phase patterns become parent tasks
  - **Features**: Bullet points and numbered lists become implementation tasks
  - **Metadata**: Goals, tech stack, and milestones populate `prd.metadata`
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
         :ok <- extract_and_save_metadata(prd),
         {:ok, tasks} <- generate_task_backlog(project, prd) do
      task_count = length(tasks)

      Logger.info("[BootstrapWorker] Generated #{task_count} tasks for project #{project_id}")

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
  Milestones extracted from PRD become parent tasks with features as children.
  """
  def generate_task_backlog(project, prd) do
    prd_content = prd.content || ""

    # Extract sections from markdown PRD
    sections = parse_prd_sections(prd_content)

    # Extract milestones for dependency tracking
    milestones = extract_milestones(sections)

    # Generate tasks from sections
    tasks =
      []
      |> add_analysis_tasks(sections, project)
      |> add_architecture_tasks(sections, project)
      |> add_milestone_tasks(milestones, sections, project)
      |> add_implementation_tasks(sections, project, milestones)
      |> add_testing_tasks(sections, project)
      |> add_documentation_tasks(sections, project)

    {:ok, tasks}
  end

  ## PRD Parsing

  defp parse_prd_sections(content) do
    lines = String.split(content, "\n")

    {sections, current_section, current_lines} =
      Enum.reduce(lines, {%{}, nil, []}, fn line, acc ->
        process_prd_line(line, acc)
      end)

    finalize_prd_sections(sections, current_section, current_lines)
  end

  defp process_prd_line(line, {sections, current, lines}) do
    case parse_header(line) do
      {:header, level, title} when level <= 2 ->
        sections = save_current_prd_section(sections, current, lines)
        {sections, normalize_section_name(title), []}

      _ ->
        {sections, current, [line | lines]}
    end
  end

  defp save_current_prd_section(sections, nil, _lines), do: sections

  defp save_current_prd_section(sections, current, lines),
    do: Map.put(sections, current, Enum.reverse(lines))

  defp finalize_prd_sections(sections, nil, _lines), do: sections

  defp finalize_prd_sections(sections, current_section, current_lines) do
    Map.put(sections, current_section, Enum.reverse(current_lines))
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

  ## Metadata Extraction

  defp extract_and_save_metadata(prd) do
    content = prd.content || ""
    sections = parse_prd_sections(content)

    metadata = %{
      "goals" => extract_goals(sections),
      "tech_stack" => extract_tech_stack(sections),
      "milestones" => Enum.map(extract_milestones(sections), fn m -> m.title end),
      "non_functional" => extract_non_functional(sections),
      "parsed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Samgita.Prds.update_prd(prd, %{metadata: Map.merge(prd.metadata || %{}, metadata)}) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp extract_goals(sections) do
    goal_keys =
      Enum.filter(Map.keys(sections), fn key ->
        String.contains?(key, "goal") or String.contains?(key, "objective") or
          String.contains?(key, "success")
      end)

    goal_keys
    |> Enum.flat_map(fn key -> Map.get(sections, key, []) end)
    |> Enum.filter(&feature_line?/1)
    |> Enum.map(&extract_feature_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(10)
  end

  defp extract_tech_stack(sections) do
    tech_keys =
      Enum.filter(Map.keys(sections), fn key ->
        String.contains?(key, "technical") or String.contains?(key, "stack") or
          String.contains?(key, "technology") or String.contains?(key, "architect")
      end)

    tech_keys
    |> Enum.flat_map(fn key -> Map.get(sections, key, []) end)
    |> Enum.filter(&feature_line?/1)
    |> Enum.map(&extract_feature_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(20)
  end

  defp extract_non_functional(sections) do
    nfr_keys =
      Enum.filter(Map.keys(sections), fn key ->
        String.contains?(key, "non_functional") or String.contains?(key, "performance") or
          String.contains?(key, "security") or String.contains?(key, "scalab")
      end)

    nfr_keys
    |> Enum.flat_map(fn key -> Map.get(sections, key, []) end)
    |> Enum.filter(&feature_line?/1)
    |> Enum.map(&extract_feature_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(10)
  end

  ## Milestone Extraction

  @doc """
  Extract milestones/phases from PRD sections.

  Looks for sections that represent development phases or milestones
  (e.g., "Milestones", "Phases", "Roadmap") and extracts ordered items.
  """
  def extract_milestones(sections) do
    milestone_keys =
      Enum.filter(Map.keys(sections), fn key ->
        String.contains?(key, "milestone") or String.contains?(key, "phase") or
          String.contains?(key, "roadmap") or String.contains?(key, "timeline") or
          String.contains?(key, "deliverable") or String.contains?(key, "sprint")
      end)

    milestone_keys
    |> Enum.flat_map(fn key -> Map.get(sections, key, []) end)
    |> Enum.filter(&feature_line?/1)
    |> Enum.map(&extract_feature_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {title, idx} ->
      %{title: title, order: idx, features: extract_milestone_features(title, sections)}
    end)
    |> Enum.take(20)
  end

  defp extract_milestone_features(milestone_title, sections) do
    milestone_lower = String.downcase(milestone_title)

    # Find features that semantically belong to this milestone
    all_features = extract_features(sections)

    Enum.filter(all_features, fn feature ->
      feature_lower = String.downcase(feature)

      # Check for keyword overlap between milestone and feature
      milestone_words =
        milestone_lower |> String.split(~r/\W+/, trim: true) |> Enum.reject(&(byte_size(&1) < 4))

      Enum.any?(milestone_words, fn word -> String.contains?(feature_lower, word) end)
    end)
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

  defp add_milestone_tasks(tasks, milestones, _sections, project) do
    milestone_tasks =
      milestones
      |> Enum.map(fn milestone ->
        %{
          type: "milestone",
          agent_type: "prod-pm",
          priority: 2 + milestone.order,
          description: "Milestone #{milestone.order}: #{milestone.title}",
          payload: %{
            "project_name" => project.name,
            "milestone_order" => milestone.order,
            "milestone_title" => milestone.title,
            "feature_count" => length(milestone.features)
          }
        }
      end)

    milestone_tasks ++ tasks
  end

  defp add_implementation_tasks(tasks, sections, project, milestones) do
    # Extract feature requirements from sections
    features = extract_features(sections)

    # Build a map of feature -> milestone_title for dependency linking
    feature_to_milestone =
      milestones
      |> Enum.flat_map(fn m ->
        Enum.map(m.features, fn f -> {f, "Milestone #{m.order}: #{m.title}"} end)
      end)
      |> Map.new()

    feature_tasks =
      features
      |> Enum.with_index(1)
      |> Enum.map(fn {feature, idx} ->
        base_priority = if milestones == [], do: 3 + div(idx, 5), else: 10 + idx

        task = %{
          type: "implement",
          agent_type: agent_for_feature(feature),
          priority: base_priority,
          description: "Implement: #{feature}",
          payload: %{
            "project_name" => project.name,
            "feature" => feature,
            "working_path" => project.working_path
          }
        }

        # Link to parent milestone if applicable
        case Map.get(feature_to_milestone, feature) do
          nil -> task
          milestone_desc -> Map.put(task, :parent_milestone, milestone_desc)
        end
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
      |> Enum.filter(&feature_line?/1)
      |> Enum.map(&extract_feature_text/1)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(50)
  end

  defp feature_line?(line) do
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

  @agent_keyword_map [
    {"eng-frontend", ~w(ui frontend component page view css layout responsive)},
    {"eng-api", ~w(api endpoint rest graphql webhook route)},
    {"eng-database", ~w(database schema migration query model table index)},
    {"eng-mobile", ["mobile", "ios", "android", "react native", "flutter"]},
    {"ops-devops", ~w(deploy ci cd docker kubernetes k8s infrastructure terraform)},
    {"ops-security", ~w(security auth permission encrypt jwt oauth rbac)},
    {"ops-monitor", ~w(monitor alert log metric observ)},
    {"eng-qa", ~w(test spec coverage e2e integration)},
    {"eng-perf", ~w(performance cache optim latency load)},
    {"data-ml", ["ml", "machine learning", "model", "training", "ai"]},
    {"data-analytics", ~w(analytics report dashboard chart metric)}
  ]

  defp agent_for_feature(feature) do
    feature_lower = String.downcase(feature)

    Enum.find_value(@agent_keyword_map, "eng-backend", fn {agent, keywords} ->
      if String.contains?(feature_lower, keywords), do: agent
    end)
  end

  ## Task Enqueuing

  defp enqueue_tasks(project_id, prd_id, task_descriptors) do
    sorted = Enum.sort_by(task_descriptors, & &1.priority)

    {milestone_map, milestone_tasks} = create_milestone_tasks(sorted, project_id, prd_id)
    other_tasks = create_other_tasks(sorted, project_id, prd_id, milestone_map)

    Enum.reverse(milestone_tasks ++ other_tasks)
  end

  defp create_milestone_tasks(sorted, project_id, prd_id) do
    sorted
    |> Enum.filter(fn d -> d.type == "milestone" end)
    |> Enum.reduce({%{}, []}, fn descriptor, {map, acc} ->
      create_milestone_task(descriptor, project_id, prd_id, map, acc)
    end)
  end

  defp create_milestone_task(descriptor, project_id, prd_id, map, acc) do
    payload = Map.merge(descriptor.payload, %{"prd_id" => prd_id})

    case Projects.create_task(project_id, %{
           type: descriptor.type,
           priority: descriptor.priority,
           payload: payload,
           status: :pending
         }) do
      {:ok, task} ->
        {Map.put(map, descriptor.description, task.id), [task | acc]}

      {:error, reason} ->
        Logger.warning("[BootstrapWorker] Failed to create milestone: #{inspect(reason)}")
        {map, acc}
    end
  end

  defp create_other_tasks(sorted, project_id, prd_id, milestone_map) do
    sorted
    |> Enum.reject(fn d -> d.type == "milestone" end)
    |> Enum.reduce([], fn descriptor, acc ->
      create_and_enqueue_task(descriptor, project_id, prd_id, milestone_map, acc)
    end)
  end

  defp create_and_enqueue_task(descriptor, project_id, prd_id, milestone_map, acc) do
    payload = Map.merge(descriptor.payload, %{"prd_id" => prd_id})
    parent_task_id = get_parent_task_id(descriptor, milestone_map)

    task_attrs = %{
      type: descriptor.type,
      priority: descriptor.priority,
      payload: payload,
      status: :pending
    }

    task_attrs =
      if parent_task_id,
        do: Map.put(task_attrs, :parent_task_id, parent_task_id),
        else: task_attrs

    case Projects.create_task(project_id, task_attrs) do
      {:ok, task} ->
        enqueue_agent_task(task, project_id, descriptor.agent_type, acc)

      {:error, reason} ->
        Logger.warning("[BootstrapWorker] Failed to create task: #{inspect(reason)}")
        acc
    end
  end

  defp get_parent_task_id(descriptor, milestone_map) do
    case Map.get(descriptor, :parent_milestone) do
      nil -> nil
      milestone_desc -> Map.get(milestone_map, milestone_desc)
    end
  end

  defp enqueue_agent_task(task, project_id, agent_type, acc) do
    case Oban.insert(
           AgentTaskWorker.new(%{
             task_id: task.id,
             project_id: project_id,
             agent_type: agent_type
           })
         ) do
      {:ok, _job} ->
        [task | acc]

      {:error, reason} ->
        Logger.warning("[BootstrapWorker] Failed to enqueue task: #{inspect(reason)}")
        acc
    end
  end

  defp notify_orchestrator(project_id, task_count) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        :gen_statem.call(pid, {:set_phase_task_count, task_count})

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
