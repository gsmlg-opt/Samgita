defmodule Samgita.Git.WorktreeTest do
  use ExUnit.Case, async: true

  alias Samgita.Git.Worktree

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    # Create a temporary git repo
    repo_path = Path.join(tmp_dir, "test-repo")
    File.mkdir_p!(repo_path)

    System.cmd("git", ["-C", repo_path, "init"], stderr_to_stdout: true)

    System.cmd("git", ["-C", repo_path, "config", "user.email", "test@test.com"],
      stderr_to_stdout: true
    )

    System.cmd("git", ["-C", repo_path, "config", "user.name", "Test"], stderr_to_stdout: true)

    # Create initial commit (worktrees need at least one commit)
    File.write!(Path.join(repo_path, "README.md"), "# Test Repo\n")
    System.cmd("git", ["-C", repo_path, "add", "-A"], stderr_to_stdout: true)
    System.cmd("git", ["-C", repo_path, "commit", "-m", "Initial commit"], stderr_to_stdout: true)

    %{repo_path: repo_path}
  end

  test "create/3 creates a worktree with new branch", %{repo_path: repo_path} do
    assert {:ok, wt_path} = Worktree.create(repo_path, "eng-backend", "task-12345678")
    assert File.dir?(wt_path)
    assert File.exists?(Path.join(wt_path, "README.md"))
  end

  test "create/3 creates worktree at expected path", %{repo_path: repo_path} do
    {:ok, wt_path} = Worktree.create(repo_path, "eng-frontend", "abcdef12-3456")
    assert String.contains?(wt_path, ".samgita-worktrees")
    assert String.contains?(wt_path, "eng-frontend")
  end

  test "list/1 shows active worktrees", %{repo_path: repo_path} do
    {:ok, _} = Worktree.create(repo_path, "eng-backend", "task-aaa")
    worktrees = Worktree.list(repo_path)
    # Main repo + our worktree
    assert length(worktrees) >= 2
  end

  test "commit/2 commits changes in worktree", %{repo_path: repo_path} do
    {:ok, wt_path} = Worktree.create(repo_path, "eng-backend", "task-bbb")

    # Make a change
    File.write!(Path.join(wt_path, "new_file.ex"), "defmodule NewFile do\nend\n")

    assert {:ok, hash} = Worktree.commit(wt_path, "Add new file")
    assert hash != "no_changes"
  end

  test "commit/2 returns no_changes when nothing to commit", %{repo_path: repo_path} do
    {:ok, wt_path} = Worktree.create(repo_path, "eng-backend", "task-ccc")

    assert {:ok, "no_changes"} = Worktree.commit(wt_path, "Empty commit")
  end

  test "has_changes?/1 detects modifications", %{repo_path: repo_path} do
    {:ok, wt_path} = Worktree.create(repo_path, "eng-backend", "task-ddd")

    refute Worktree.has_changes?(wt_path)

    File.write!(Path.join(wt_path, "change.txt"), "hello")
    assert Worktree.has_changes?(wt_path)
  end

  test "remove/2 cleans up worktree", %{repo_path: repo_path} do
    {:ok, wt_path} = Worktree.create(repo_path, "eng-backend", "task-eee")
    assert File.dir?(wt_path)

    assert :ok = Worktree.remove(repo_path, wt_path)
    refute File.dir?(wt_path)
  end

  test "prune/1 succeeds", %{repo_path: repo_path} do
    assert :ok = Worktree.prune(repo_path)
  end
end
