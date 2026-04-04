defmodule Samgita.Agent.ContextAssembler do
  @moduledoc """
  Assembles context and memory for agent workers.

  Extracts the context/memory assembly logic from `Samgita.Agent.Worker` into
  a standalone module so it can be tested independently and reused.

  The main entry point is `assemble/1`, which takes a data map and returns
  a context map with project info, PRD context, memory, and learnings.
  """

  require Logger

  alias Samgita.Prds
  alias Samgita.Project.Memory
  alias Samgita.Projects

  @doc """
  Assembles a full context map from worker data.

  Expects a map with at least:
    - `:project_id` — the project UUID
    - `:agent_type` — atom or string agent type
    - `:task_count` — number of tasks completed
    - `:learnings` — list of session learnings

  Returns a map with keys:
    - `:learnings` — the session learnings list
    - `:agent_type` — agent type
    - `:task_count` — task count
    - `:project_info` — formatted project info string
    - `:prd_context` — formatted PRD context string
    - `:memory_learnings` — filtered procedural + semantic memory items
    - `:memory_context` — raw memory context map from Memory.get_context/1
  """
  def assemble(data) do
    project_id = data[:project_id]
    memory_context = fetch_memory_context(project_id)

    %{
      learnings: data[:learnings] || [],
      agent_type: data[:agent_type],
      task_count: data[:task_count] || 0,
      project_info: fetch_project_info(project_id),
      prd_context: fetch_prd_context(data[:prd_id]),
      memory_learnings: filter_memory_learnings(memory_context),
      memory_context: memory_context,
      received_messages: data[:received_messages] || []
    }
  end

  @doc """
  Writes `.samgita/CONTINUITY.md` into the given working path.

  Creates the `.samgita/` directory if it does not exist. The `context` map
  should contain the keys produced by `assemble/1` plus optional
  `:retry_count` and `:current_task_description`.

  Returns `:ok` or `{:error, reason}`.
  """
  def write_continuity_file(working_path, context) do
    dir = Path.join(working_path, ".samgita")
    File.mkdir_p!(dir)

    content = build_continuity_content(context)
    path = Path.join(dir, "CONTINUITY.md")
    File.write(path, content)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Builds the CONTINUITY.md content string from a context map.

  Pure function — performs no I/O.

  The context map should include:
    - `:agent_type`
    - `:task_count`
    - `:retry_count` (defaults to 0)
    - `:current_task_description` (defaults to "unknown")
    - `:memory_context` — map with `:episodic` and `:semantic` lists
    - `:learnings` — list of session learning strings
  """
  def build_continuity_content(context) do
    agent_type = context[:agent_type] || "unknown"
    task_count = context[:task_count] || 0
    retry_count = context[:retry_count] || 0
    task_desc = context[:current_task_description] || "unknown"
    memory_context = context[:memory_context] || %{}
    learnings = context[:learnings] || []

    episodic_lines = format_memory_section(memory_context, :episodic)
    semantic_lines = format_memory_section(memory_context, :semantic)
    learnings_lines = format_list_section(learnings)

    """
    # Samgita Continuity
    Agent: #{agent_type} | Task Count: #{task_count} | Retries: #{retry_count}
    Current Task: #{task_desc}

    ## Episodic Memory
    #{episodic_lines}

    ## Semantic Knowledge
    #{semantic_lines}

    ## Session Learnings
    #{learnings_lines}
    """
  end

  defp format_memory_section(memory_context, key) do
    memory_context
    |> Map.get(key, [])
    |> Enum.take(5)
    |> Enum.map_join("\n", fn m -> "- #{m.content}" end)
    |> then(fn
      "" -> "(none)"
      lines -> lines
    end)
  end

  defp format_list_section(items) do
    items
    |> Enum.take(5)
    |> Enum.map_join("\n", fn l -> "- #{l}" end)
    |> then(fn
      "" -> "(none)"
      lines -> lines
    end)
  end

  @doc """
  Persists a learning as an episodic memory entry for the given project.

  Delegates to `Samgita.Project.Memory.add_memory/4` with type `:episodic`.
  Returns `{:ok, memory}` or `{:error, reason}`.
  """
  def persist_learning(project_id, learning) do
    Memory.add_memory(project_id, :episodic, learning)
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  @doc "Format received inter-agent messages as a context string."
  @spec format_received_messages(list()) :: String.t() | nil
  def format_received_messages([]), do: nil

  def format_received_messages(messages) when is_list(messages) do
    messages
    |> Enum.take(10)
    |> Enum.map_join("\n", fn msg ->
      sender = msg[:sender_agent_id] || "unknown"
      type = msg[:message_type] || "notify"
      content = msg[:content] || ""
      "- [#{type}] from #{sender}: #{content}"
    end)
  end

  @doc """
  Filters procedural and semantic entries from a memory context map.

  Returns a combined list of formatted strings, capped at 5 entries.
  """
  def filter_memory_learnings(%{procedural: procedural, semantic: semantic}) do
    procedures = Enum.map(procedural, fn m -> "Procedure: #{m.content}" end)
    semantics = Enum.map(semantic, fn m -> "Knowledge: #{m.content}" end)
    Enum.take(procedures ++ semantics, 5)
  end

  def filter_memory_learnings(_), do: []

  # --- Private helpers ---

  defp fetch_memory_context(project_id) do
    Memory.get_context(project_id)
  catch
    :exit, _ -> %{episodic: [], semantic: [], procedural: []}
  end

  defp fetch_project_info(project_id) do
    case Projects.get_project(project_id) do
      {:ok, project} ->
        build_project_info_string(project)

      _ ->
        ""
    end
  rescue
    _ -> ""
  end

  defp build_project_info_string(project) do
    working_path = project.working_path || ""
    git_url = project.git_url || ""

    location =
      if working_path != "",
        do: "Working directory: #{working_path}",
        else: "Repository: #{git_url}"

    """

    ## Project: #{project.name}
    #{location}
    Phase: #{project.phase}
    """
  end

  defp fetch_prd_context(nil), do: ""

  defp fetch_prd_context(prd_id) do
    case Prds.get_prd(prd_id) do
      {:ok, prd} ->
        build_prd_context_string(prd)

      _ ->
        ""
    end
  rescue
    _ -> ""
  end

  defp build_prd_context_string(prd) do
    content = String.slice(prd.content || "", 0, 2000)

    """

    ## PRD: #{prd.title}
    #{content}
    """
  end
end
