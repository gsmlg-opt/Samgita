defmodule Samgita.Quality.TestCoverageTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.TestCoverage

  describe "run/2" do
    test "returns skip when working path doesn't exist" do
      result = TestCoverage.run("/nonexistent/path")
      assert result.gate == 7
      assert result.name == "Test Coverage"
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               String.contains?(f.message, "not available")
             end)
    end

    test "returns skip when working path is nil" do
      result = TestCoverage.run(nil)
      assert result.gate == 7
      assert result.verdict == :fail
    end

    test "includes duration_ms" do
      result = TestCoverage.run("/nonexistent")
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end
end
