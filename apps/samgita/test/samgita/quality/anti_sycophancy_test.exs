defmodule Samgita.Quality.AntiSycophancyTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.AntiSycophancy

  describe "should_challenge?/1" do
    test "returns true for empty findings (unanimous pass)" do
      assert AntiSycophancy.should_challenge?([])
    end

    test "returns true when only cosmetic findings" do
      findings = [
        %{gate: 3, severity: :cosmetic, message: "Minor style issue", file: nil, line: nil}
      ]

      assert AntiSycophancy.should_challenge?(findings)
    end

    test "returns false when medium severity findings exist" do
      findings = [
        %{gate: 3, severity: :medium, message: "Missing error handling", file: nil, line: nil}
      ]

      refute AntiSycophancy.should_challenge?(findings)
    end

    test "returns false when critical severity findings exist" do
      findings = [
        %{gate: 3, severity: :critical, message: "SQL injection", file: nil, line: nil}
      ]

      refute AntiSycophancy.should_challenge?(findings)
    end

    test "returns false when low severity findings exist" do
      findings = [
        %{gate: 3, severity: :low, message: "Could improve naming", file: nil, line: nil}
      ]

      refute AntiSycophancy.should_challenge?(findings)
    end
  end

  describe "challenge/3" do
    test "returns gate 4 result structure" do
      result = AntiSycophancy.challenge("some diff", [], timeout: 1)
      assert result.gate == 4
      assert result.name == "Anti-Sycophancy"
      assert result.verdict in [:pass, :fail]
      assert is_list(result.findings)
      assert is_integer(result.duration_ms)
    end

    test "includes duration_ms" do
      result = AntiSycophancy.challenge("code", [], timeout: 1)
      assert result.duration_ms >= 0
    end
  end
end
