defmodule Samgita.Agent.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.PromptBuilder

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp base_context(overrides \\ %{}) do
    Map.merge(
      %{
        learnings: ["learned A", "learned B"],
        agent_type: "eng-backend",
        task_count: 3,
        project_info:
          "\n## Project: TestProject\nWorking directory: /tmp/test\nPhase: development\n",
        prd_context: "\n## PRD: My PRD\nSome PRD content\n",
        memory_learnings: ["Procedure: always run tests"]
      },
      overrides
    )
  end

  defp bootstrap_task do
    %{
      "type" => "bootstrap",
      "payload" => %{
        "project_name" => "Acme",
        "git_url" => "https://github.com/acme/app",
        "working_path" => "/tmp/acme",
        "prd_title" => "Acme PRD",
        "prd_content" => "Build the Acme widget."
      }
    }
  end

  defp prd_task do
    %{
      "type" => "generate-prd",
      "payload" => %{
        "project_name" => "Acme",
        "git_url" => "https://github.com/acme/app",
        "working_path" => "",
        "existing_prd" => "Draft PRD here."
      }
    }
  end

  defp analysis_task do
    %{
      "type" => "analysis",
      "payload" => %{"description" => "Analyze auth module"}
    }
  end

  defp architecture_task do
    %{
      "type" => "architecture",
      "payload" => %{"description" => "Design data layer"}
    }
  end

  defp implement_task do
    %{
      "type" => "implement",
      "payload" => %{"description" => "Add user registration"}
    }
  end

  defp review_task do
    %{
      "type" => "review",
      "payload" => %{"description" => "Review PR #42"}
    }
  end

  defp test_task do
    %{
      "type" => "test",
      "payload" => %{"description" => "Cover edge cases in parser"}
    }
  end

  defp generic_task do
    %{
      "type" => "deploy",
      "payload" => %{"description" => "Deploy to staging"}
    }
  end

  # -------------------------------------------------------------------
  # task_type/1
  # -------------------------------------------------------------------

  describe "task_type/1" do
    test "extracts type from string-keyed map" do
      assert PromptBuilder.task_type(%{"type" => "analysis"}) == "analysis"
    end

    test "extracts type from atom-keyed map" do
      assert PromptBuilder.task_type(%{type: "implement"}) == "implement"
    end

    test "returns unknown for missing type" do
      assert PromptBuilder.task_type(%{}) == "unknown"
    end

    test "returns unknown for nil" do
      assert PromptBuilder.task_type(nil) == "unknown"
    end
  end

  # -------------------------------------------------------------------
  # task_description/1
  # -------------------------------------------------------------------

  describe "task_description/1" do
    test "extracts description from string-keyed payload" do
      task = %{"payload" => %{"description" => "Do the thing"}}
      assert PromptBuilder.task_description(task) == "Do the thing"
    end

    test "extracts description from atom-keyed payload" do
      task = %{payload: %{"description" => "Other thing"}}
      assert PromptBuilder.task_description(task) == "Other thing"
    end

    test "returns empty string when no description" do
      assert PromptBuilder.task_description(%{"payload" => %{}}) == ""
    end

    test "returns empty string when no payload" do
      assert PromptBuilder.task_description(%{}) == ""
    end
  end

  # -------------------------------------------------------------------
  # task_payload/1
  # -------------------------------------------------------------------

  describe "task_payload/1" do
    test "extracts payload from string-keyed map" do
      assert PromptBuilder.task_payload(%{"payload" => %{"a" => 1}}) == %{"a" => 1}
    end

    test "extracts payload from atom-keyed map" do
      assert PromptBuilder.task_payload(%{payload: %{"b" => 2}}) == %{"b" => 2}
    end

    test "returns empty map when no payload" do
      assert PromptBuilder.task_payload(%{}) == %{}
    end
  end

  # -------------------------------------------------------------------
  # format_learnings/1
  # -------------------------------------------------------------------

  describe "format_learnings/1" do
    test "formats combined learnings and memory_learnings" do
      ctx = %{learnings: ["A"], memory_learnings: ["B"]}
      result = PromptBuilder.format_learnings(ctx)
      assert result == "- A\n- B"
    end

    test "returns 'None yet.' when both lists are empty" do
      assert PromptBuilder.format_learnings(%{learnings: [], memory_learnings: []}) ==
               "None yet."
    end

    test "handles nil learnings gracefully" do
      assert PromptBuilder.format_learnings(%{learnings: nil, memory_learnings: nil}) ==
               "None yet."
    end

    test "handles missing keys gracefully" do
      assert PromptBuilder.format_learnings(%{}) == "None yet."
    end
  end

  # -------------------------------------------------------------------
  # build/2 — bootstrap
  # -------------------------------------------------------------------

  describe "build/2 bootstrap" do
    test "includes agent type and project name" do
      prompt = PromptBuilder.build(bootstrap_task(), base_context())
      assert prompt =~ "Backend Engineer"
      assert prompt =~ "Bootstrap Project \"Acme\""
    end

    test "uses working_path when present" do
      prompt = PromptBuilder.build(bootstrap_task(), base_context())
      assert prompt =~ "Working directory: /tmp/acme"
    end

    test "falls back to git_url when working_path is empty" do
      task = put_in(bootstrap_task(), ["payload", "working_path"], "")
      prompt = PromptBuilder.build(task, base_context())
      assert prompt =~ "Repository: https://github.com/acme/app"
    end

    test "includes PRD title and content" do
      prompt = PromptBuilder.build(bootstrap_task(), base_context())
      assert prompt =~ "## PRD: Acme PRD"
      assert prompt =~ "Build the Acme widget."
    end

    test "includes instructions section" do
      prompt = PromptBuilder.build(bootstrap_task(), base_context())
      assert prompt =~ "## Instructions"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — prd
  # -------------------------------------------------------------------

  describe "build/2 prd" do
    test "includes agent type and project name" do
      prompt = PromptBuilder.build(prd_task(), base_context())
      assert prompt =~ "Backend Engineer"
      assert prompt =~ "Generate Product Requirements Document"
      assert prompt =~ "\"Acme\""
    end

    test "includes existing PRD section when provided" do
      prompt = PromptBuilder.build(prd_task(), base_context())
      assert prompt =~ "Existing PRD (refine/expand this)"
      assert prompt =~ "Draft PRD here."
    end

    test "omits existing PRD section when nil" do
      task = put_in(prd_task(), ["payload", "existing_prd"], nil)
      prompt = PromptBuilder.build(task, base_context())
      refute prompt =~ "Existing PRD"
    end

    test "uses git_url when working_path is empty" do
      prompt = PromptBuilder.build(prd_task(), base_context())
      assert prompt =~ "Repository: https://github.com/acme/app"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — analysis
  # -------------------------------------------------------------------

  describe "build/2 analysis" do
    test "includes description and learnings" do
      prompt = PromptBuilder.build(analysis_task(), base_context())
      assert prompt =~ "Analyze auth module"
      assert prompt =~ "- learned A"
      assert prompt =~ "- Procedure: always run tests"
    end

    test "includes project and PRD context" do
      prompt = PromptBuilder.build(analysis_task(), base_context())
      assert prompt =~ "## Project: TestProject"
      assert prompt =~ "## PRD: My PRD"
    end

    test "includes discovery analysis instructions" do
      prompt = PromptBuilder.build(analysis_task(), base_context())
      assert prompt =~ "Discovery Analysis"
      assert prompt =~ "Findings Summary"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — architecture
  # -------------------------------------------------------------------

  describe "build/2 architecture" do
    test "includes description and learnings" do
      prompt = PromptBuilder.build(architecture_task(), base_context())
      assert prompt =~ "Design data layer"
      assert prompt =~ "- learned A"
    end

    test "includes architecture-specific instructions" do
      prompt = PromptBuilder.build(architecture_task(), base_context())
      assert prompt =~ "Architecture Design"
      assert prompt =~ "Component Overview"
      assert prompt =~ "API Contracts"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — implement
  # -------------------------------------------------------------------

  describe "build/2 implement" do
    test "includes description and learnings" do
      prompt = PromptBuilder.build(implement_task(), base_context())
      assert prompt =~ "Add user registration"
      assert prompt =~ "- learned B"
    end

    test "includes implementation instructions" do
      prompt = PromptBuilder.build(implement_task(), base_context())
      assert prompt =~ "## Task: Implementation"
      assert prompt =~ "Quality Requirements"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — review
  # -------------------------------------------------------------------

  describe "build/2 review" do
    test "includes description and learnings" do
      prompt = PromptBuilder.build(review_task(), base_context())
      assert prompt =~ "Review PR #42"
      assert prompt =~ "- learned A"
    end

    test "includes review-specific instructions" do
      prompt = PromptBuilder.build(review_task(), base_context())
      assert prompt =~ "Code Review"
      assert prompt =~ "PASS/FAIL/NEEDS_CHANGES"
      assert prompt =~ "Security Findings"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — test
  # -------------------------------------------------------------------

  describe "build/2 test" do
    test "includes description and learnings" do
      prompt = PromptBuilder.build(test_task(), base_context())
      assert prompt =~ "Cover edge cases in parser"
      assert prompt =~ "- learned A"
    end

    test "includes testing-specific instructions" do
      prompt = PromptBuilder.build(test_task(), base_context())
      assert prompt =~ "## Task: Testing"
      assert prompt =~ "Boundary value testing"
      assert prompt =~ "Coverage"
    end
  end

  # -------------------------------------------------------------------
  # build/2 — generic (fallback)
  # -------------------------------------------------------------------

  describe "build/2 generic" do
    test "includes task type and description" do
      prompt = PromptBuilder.build(generic_task(), base_context())
      assert prompt =~ "Type: deploy"
      assert prompt =~ "Deploy to staging"
    end

    test "includes learnings" do
      prompt = PromptBuilder.build(generic_task(), base_context())
      assert prompt =~ "- learned A"
    end

    test "falls back to inspect(payload) when no description" do
      task = %{"type" => "custom", "payload" => %{"foo" => "bar"}}
      prompt = PromptBuilder.build(task, base_context())
      assert prompt =~ ~s("foo" => "bar")
    end
  end

  # -------------------------------------------------------------------
  # Graceful nil / empty context handling
  # -------------------------------------------------------------------

  describe "graceful nil/empty context" do
    test "build works with empty context map" do
      prompt = PromptBuilder.build(analysis_task(), %{})
      assert prompt =~ "Discovery Analysis"
      assert prompt =~ "None yet."
    end

    test "build works with nil project_info and prd_context" do
      ctx = %{project_info: nil, prd_context: nil, learnings: nil, memory_learnings: nil}
      prompt = PromptBuilder.build(analysis_task(), ctx)
      assert prompt =~ "Discovery Analysis"
      assert prompt =~ "None yet."
    end

    test "build works with unknown agent_type" do
      ctx = base_context(%{agent_type: "nonexistent-type"})
      prompt = PromptBuilder.build(analysis_task(), ctx)
      assert prompt =~ "nonexistent-type"
    end
  end
end
