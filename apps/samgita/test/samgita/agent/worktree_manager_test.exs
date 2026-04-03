defmodule Samgita.Agent.WorktreeManagerTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.WorktreeManager

  # ---------------------------------------------------------------------------
  # build_commit_message/3
  # ---------------------------------------------------------------------------

  describe "build_commit_message/3" do
    test "contains [samgita] prefix and agent type in subject" do
      msg = WorktreeManager.build_commit_message("eng-backend", "feature", "add user auth")

      assert String.starts_with?(msg, "[samgita] eng-backend: add user auth")
    end

    test "includes Agent-Type trailer" do
      msg = WorktreeManager.build_commit_message("eng-frontend", "bug", "fix button layout")

      assert msg =~ "Agent-Type: eng-frontend"
    end

    test "includes Task-Type trailer" do
      msg = WorktreeManager.build_commit_message("ops-devops", "deploy", "release v2")

      assert msg =~ "Task-Type: deploy"
    end

    test "includes Samgita-Version trailer" do
      msg = WorktreeManager.build_commit_message("data-ml", "train", "retrain model")

      assert msg =~ "Samgita-Version:"
    end

    test "subject line is truncated to 72 chars when description is long" do
      long_desc = String.duplicate("x", 100)
      msg = WorktreeManager.build_commit_message("eng-backend", "feature", long_desc)

      subject_line = msg |> String.split("\n") |> List.first()
      assert String.length(subject_line) <= 72
      assert String.ends_with?(subject_line, "...")
    end

    test "subject line is not truncated when it fits within 72 chars" do
      msg = WorktreeManager.build_commit_message("eng-qa", "test", "short desc")

      subject_line = msg |> String.split("\n") |> List.first()
      refute String.ends_with?(subject_line, "...")
    end
  end

  # ---------------------------------------------------------------------------
  # build_task_description/1
  # ---------------------------------------------------------------------------

  describe "build_task_description/1" do
    test "extracts description from string-keyed payload" do
      task = %{payload: %{"description" => "implement login page"}}

      assert WorktreeManager.build_task_description(task) == "implement login page"
    end

    test "extracts description from atom-keyed payload" do
      task = %{payload: %{description: "fix memory leak"}}

      assert WorktreeManager.build_task_description(task) == "fix memory leak"
    end

    test "returns fallback when description key is missing" do
      task = %{payload: %{"other_key" => "value"}}

      assert WorktreeManager.build_task_description(task) == "task"
    end

    test "returns fallback for nil task" do
      assert WorktreeManager.build_task_description(nil) == "task"
    end

    test "returns fallback when task has no payload" do
      assert WorktreeManager.build_task_description(%{type: "feature"}) == "task"
    end

    test "returns fallback when description is empty string" do
      task = %{payload: %{"description" => ""}}

      assert WorktreeManager.build_task_description(task) == "task"
    end
  end

  # ---------------------------------------------------------------------------
  # should_checkpoint?/1
  # ---------------------------------------------------------------------------

  describe "should_checkpoint?/1" do
    test "returns true when working_path is set" do
      data = %{working_path: "/tmp/some-worktree"}

      assert WorktreeManager.should_checkpoint?(data) == true
    end

    test "returns false when working_path is nil" do
      data = %{working_path: nil}

      assert WorktreeManager.should_checkpoint?(data) == false
    end

    test "returns false when working_path key is absent" do
      data = %{agent_type: "eng-backend"}

      assert WorktreeManager.should_checkpoint?(data) == false
    end
  end
end
