defmodule Samgita.Agent.WorktreeManager do
  @moduledoc """
  Git worktree checkpoint operations for agent workers.

  Provides functions to create git checkpoints during agent task execution.
  This is a plain module (not a process) — all functions are pure or
  delegate to `Samgita.Git.Worktree`.
  """

  require Logger

  alias Samgita.Git.Worktree

  @doc """
  Returns true if `data` has a non-nil `working_path`, indicating that
  git checkpoints are applicable.
  """
  @spec should_checkpoint?(map()) :: boolean()
  def should_checkpoint?(%{working_path: path}) when not is_nil(path), do: true
  def should_checkpoint?(_data), do: false

  @doc """
  Creates a git checkpoint if `should_checkpoint?/1` is true for `data`.
  Returns `:ok` in all cases.
  """
  @spec maybe_checkpoint(map()) :: :ok
  def maybe_checkpoint(data) do
    if should_checkpoint?(data) do
      create_checkpoint(data)
    else
      :ok
    end
  end

  @doc """
  Creates a git checkpoint for the current task in `data.working_path`.

  Checks for uncommitted changes via `Worktree.has_changes?/1`, builds a
  structured commit message, and calls `Worktree.commit/2`. Logs a warning
  on failure. Always returns `:ok`.
  """
  @spec create_checkpoint(map()) :: :ok
  def create_checkpoint(data) do
    working_path = data.working_path
    task = Map.get(data, :current_task)

    if working_path && File.dir?(working_path) && Worktree.has_changes?(working_path) do
      agent_type = Map.get(data, :agent_type, "unknown")
      task_type = get_task_type(task)
      description = build_task_description(task)
      message = build_commit_message(agent_type, task_type, description)

      case Worktree.commit(working_path, message) do
        {:ok, hash} ->
          Logger.info("[WorktreeManager] Git checkpoint: #{hash}")

        {:error, reason} ->
          Logger.warning("[WorktreeManager] Git checkpoint failed: #{inspect(reason)}")
      end
    end

    :ok
  rescue
    e ->
      Logger.warning("[WorktreeManager] Git checkpoint error: #{inspect(e)}")
      :ok
  end

  @doc """
  Builds a structured git commit message for a checkpoint.

  The subject line is formatted as `[samgita] agent_type: description` and
  truncated to 72 characters. The body contains Git trailers with metadata.
  """
  @spec build_commit_message(String.t(), String.t(), String.t()) :: String.t()
  def build_commit_message(agent_type, task_type, description) do
    subject = truncate_subject("[samgita] #{agent_type}: #{description}")

    version = Application.spec(:samgita, :vsn) || "unknown"

    message = """
    #{subject}

    Agent-Type: #{agent_type}
    Task-Type: #{task_type}
    Samgita-Version: #{version}
    """

    String.trim(message)
  end

  @doc """
  Extracts a human-readable description from a task map.

  Handles both string-keyed and atom-keyed maps. Falls back to `"task"` when
  no description is available.
  """
  @spec build_task_description(map() | nil) :: String.t()
  def build_task_description(task) do
    payload = task_payload(task)

    case payload do
      %{"description" => desc} when is_binary(desc) and desc != "" -> desc
      %{description: desc} when is_binary(desc) and desc != "" -> desc
      _ -> "task"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_task_type(nil), do: "unknown"

  defp get_task_type(%{type: type}) when is_binary(type), do: type
  defp get_task_type(%{"type" => type}) when is_binary(type), do: type
  defp get_task_type(%{type: type}), do: to_string(type)
  defp get_task_type(_), do: "unknown"

  defp task_payload(nil), do: %{}

  defp task_payload(%{payload: payload}) when is_map(payload), do: payload
  defp task_payload(%{"payload" => payload}) when is_map(payload), do: payload
  defp task_payload(_), do: %{}

  defp truncate_subject(text) when byte_size(text) <= 72, do: text

  defp truncate_subject(text) do
    String.slice(text, 0, 69) <> "..."
  end
end
