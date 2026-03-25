defmodule Samgita.Quality.BlindReviewTest do
  use ExUnit.Case, async: false

  alias Samgita.Quality.BlindReview

  setup do
    Mox.set_mox_global(self())
    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)
    :ok
  end

  describe "reviewers/0" do
    test "returns 3 reviewers" do
      assert length(BlindReview.reviewers()) == 3
    end

    test "reviewers have correct agent types" do
      types = Enum.map(BlindReview.reviewers(), & &1.agent_type)
      assert "review-code" in types
      assert "review-business" in types
      assert "review-security" in types
    end

    test "each reviewer has a focus area" do
      Enum.each(BlindReview.reviewers(), fn r ->
        assert is_binary(r.focus)
        assert String.length(r.focus) > 10
      end)
    end
  end

  describe "review/2 with mock provider" do
    test "returns a gate 3 result" do
      diff = """
      + def hello, do: "world"
      """

      {:ok, result} = BlindReview.review(diff, timeout: 5_000)

      assert result.gate == 3
      assert result.name == "Blind Review"
      assert result.verdict in [:pass, :fail]
      assert is_list(result.findings)
      assert result.duration_ms >= 0
    end

    test "handles empty diff" do
      {:ok, result} = BlindReview.review("", timeout: 5_000)
      assert result.gate == 3
    end
  end

  describe "response parsing" do
    # Test the parsing logic indirectly through the module
    test "findings have correct structure from mock responses" do
      diff = "def vulnerable_function, do: :ok"
      {:ok, result} = BlindReview.review(diff, timeout: 5_000)

      Enum.each(result.findings, fn finding ->
        assert Map.has_key?(finding, :gate)
        assert Map.has_key?(finding, :severity)
        assert Map.has_key?(finding, :message)
        assert finding.gate == 3
        assert finding.severity in [:critical, :high, :medium, :low, :cosmetic]
      end)
    end
  end
end
