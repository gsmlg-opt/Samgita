defmodule Samgita.Quality.CompletionCouncilTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.CompletionCouncil

  describe "members/0" do
    test "returns 3 council members" do
      assert length(CompletionCouncil.members()) == 3
    end

    test "members have required fields" do
      Enum.each(CompletionCouncil.members(), fn m ->
        assert Map.has_key?(m, :role)
        assert Map.has_key?(m, :agent_type)
        assert Map.has_key?(m, :focus)
      end)
    end

    test "has correct roles" do
      roles = Enum.map(CompletionCouncil.members(), & &1.role)
      assert :requirements_verifier in roles
      assert :test_auditor in roles
      assert :devils_advocate in roles
    end
  end

  describe "evaluate/3 with mock provider" do
    test "returns a council result" do
      prd = "# Simple PRD\n\n## Features\n- Feature 1"
      status = "Phase: development, Tasks: 5 completed"

      {:ok, result} = CompletionCouncil.evaluate(prd, status, timeout: 5_000)

      assert result.verdict in [:complete, :incomplete, :stagnated]
      assert is_list(result.votes)
      assert length(result.votes) == 3
      assert is_boolean(result.unanimous)
      assert is_boolean(result.quorum_met)
    end

    test "each vote has required structure" do
      {:ok, result} = CompletionCouncil.evaluate("# PRD", "status", timeout: 5_000)

      Enum.each(result.votes, fn vote ->
        assert Map.has_key?(vote, :role)
        assert Map.has_key?(vote, :vote)
        assert Map.has_key?(vote, :reasoning)
        assert Map.has_key?(vote, :remaining_issues)
        assert vote.vote in [:complete, :incomplete, :abstain]
        assert is_binary(vote.reasoning)
        assert is_list(vote.remaining_issues)
      end)
    end
  end

  describe "check_stagnation/2" do
    test "returns :ok when below threshold" do
      assert :ok == CompletionCouncil.check_stagnation(3)
      assert :ok == CompletionCouncil.check_stagnation(4)
    end

    test "returns :stagnated at threshold" do
      assert :stagnated == CompletionCouncil.check_stagnation(5)
    end

    test "returns :stagnated above threshold" do
      assert :stagnated == CompletionCouncil.check_stagnation(10)
    end

    test "custom threshold" do
      assert :ok == CompletionCouncil.check_stagnation(2, 3)
      assert :stagnated == CompletionCouncil.check_stagnation(3, 3)
    end
  end
end
