defmodule Samgita.Git.Worktree do
  @moduledoc """
  Git worktree management for parallel agent workspaces.

  Creates isolated worktrees per agent so multiple agents can work
  on the same repository concurrently without file conflicts.
  Each worktree gets its own branch and working directory.
  """

  require Logger

  @worktree_base_dir ".samgita-worktrees"

  @doc """
  Create a worktree for an agent. Returns the worktree path.

  The worktree is created from the current HEAD of the main working directory.
  Each agent gets a dedicated branch: `samgita/<agent_type>/<short_id>`.
  """
  @spec create(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def create(repo_path, agent_type, task_id) do
    short_id = String.slice(task_id, 0, 8)
    branch_name = "samgita/#{agent_type}/#{short_id}"
    worktree_path = worktree_path(repo_path, agent_type, short_id)

    # Ensure parent directory exists
    File.mkdir_p!(Path.dirname(worktree_path))

    case System.cmd(
           "git",
           ["-C", repo_path, "worktree", "add", "-b", branch_name, worktree_path],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("[Worktree] Created #{worktree_path} on branch #{branch_name}")
        {:ok, worktree_path}

      {output, _} ->
        # Branch may already exist, try without -b
        case System.cmd(
               "git",
               ["-C", repo_path, "worktree", "add", worktree_path, branch_name],
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            Logger.info("[Worktree] Attached #{worktree_path} to existing branch #{branch_name}")
            {:ok, worktree_path}

          {err, _} ->
            Logger.error("[Worktree] Failed to create: #{output} / #{err}")
            {:error, :worktree_creation_failed}
        end
    end
  end

  @doc """
  Remove a worktree after task completion.
  """
  @spec remove(String.t(), String.t()) :: :ok | {:error, term()}
  def remove(repo_path, worktree_path) do
    case System.cmd(
           "git",
           ["-C", repo_path, "worktree", "remove", "--force", worktree_path],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.info("[Worktree] Removed #{worktree_path}")
        :ok

      {err, _} ->
        Logger.warning("[Worktree] Failed to remove #{worktree_path}: #{err}")
        # Try manual cleanup
        File.rm_rf(worktree_path)
        prune(repo_path)
        :ok
    end
  end

  @doc """
  Commit changes in a worktree.
  """
  @spec commit(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def commit(worktree_path, message) do
    with {_, 0} <- System.cmd("git", ["-C", worktree_path, "add", "-A"], stderr_to_stdout: true),
         {output, 0} <-
           System.cmd("git", ["-C", worktree_path, "commit", "-m", message],
             stderr_to_stdout: true
           ) do
      # Extract commit hash
      case Regex.run(~r/\[.+ ([a-f0-9]+)\]/, output) do
        [_, hash] -> {:ok, hash}
        _ -> {:ok, "unknown"}
      end
    else
      {output, _} ->
        if String.contains?(output, "nothing to commit") do
          {:ok, "no_changes"}
        else
          {:error, output}
        end
    end
  end

  @doc """
  Merge a worktree branch back into the main branch.
  """
  @spec merge(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def merge(repo_path, worktree_branch, target_branch \\ "main") do
    with {_, 0} <-
           System.cmd("git", ["-C", repo_path, "checkout", target_branch], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd(
             "git",
             [
               "-C",
               repo_path,
               "merge",
               "--no-ff",
               worktree_branch,
               "-m",
               "Merge #{worktree_branch}"
             ],
             stderr_to_stdout: true
           ) do
      :ok
    else
      {err, _} ->
        Logger.error("[Worktree] Merge failed: #{err}")
        {:error, :merge_failed}
    end
  end

  @doc """
  List all active worktrees for a repository.
  """
  @spec list(String.t()) :: [{String.t(), String.t()}]
  def list(repo_path) do
    case System.cmd("git", ["-C", repo_path, "worktree", "list", "--porcelain"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n\n", trim: true)
        |> Enum.map(fn block ->
          lines = String.split(block, "\n", trim: true)
          path = lines |> Enum.find(&String.starts_with?(&1, "worktree ")) |> parse_field()
          branch = lines |> Enum.find(&String.starts_with?(&1, "branch ")) |> parse_field()
          {path, branch}
        end)

      _ ->
        []
    end
  end

  @doc """
  Prune stale worktree entries.
  """
  @spec prune(String.t()) :: :ok
  def prune(repo_path) do
    System.cmd("git", ["-C", repo_path, "worktree", "prune"], stderr_to_stdout: true)
    :ok
  end

  @doc """
  Check if a path has uncommitted changes.
  """
  @spec has_changes?(String.t()) :: boolean()
  def has_changes?(path) do
    case System.cmd("git", ["-C", path, "status", "--porcelain"], stderr_to_stdout: true) do
      {"", 0} -> false
      {output, 0} -> String.trim(output) != ""
      _ -> false
    end
  end

  # Internal helpers

  defp worktree_path(repo_path, agent_type, short_id) do
    Path.join([repo_path, @worktree_base_dir, "#{agent_type}-#{short_id}"])
  end

  defp parse_field(nil), do: nil

  defp parse_field(line) do
    case String.split(line, " ", parts: 2) do
      [_, value] -> value
      _ -> nil
    end
  end
end
