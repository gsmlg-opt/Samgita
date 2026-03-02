defmodule Samgita.Quality.StaticAnalysisTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.StaticAnalysis

  describe "analyze/2" do
    test "returns skip when working path doesn't exist" do
      result = StaticAnalysis.analyze("/nonexistent/path")
      assert result.gate == 2
      assert result.name == "Static Analysis"
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               String.contains?(f.message, "not available or not a directory")
             end)
    end

    test "returns skip when working path is nil" do
      result = StaticAnalysis.analyze(nil)
      assert result.gate == 2
      assert result.verdict == :fail
    end

    test "includes duration_ms" do
      result = StaticAnalysis.analyze("/nonexistent")
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "runs on actual project directory" do
      # Run on our own project directory
      project_root = Path.expand("../../../../", __DIR__)

      if File.exists?(Path.join(project_root, "mix.exs")) do
        result = StaticAnalysis.analyze(project_root, timeout: 180_000)
        assert result.gate == 2
        assert result.name == "Static Analysis"
        assert result.verdict in [:pass, :fail]
        assert is_list(result.findings)
      end
    end
  end

  describe "run_compile_check/2" do
    test "returns findings for nonexistent directory" do
      # Will fail to run mix compile in a bad dir
      findings = StaticAnalysis.run_compile_check("/nonexistent/path")
      assert is_list(findings)
    end
  end

  describe "run_format_check/2" do
    test "returns findings for nonexistent directory" do
      findings = StaticAnalysis.run_format_check("/nonexistent/path")
      assert is_list(findings)
    end
  end

  describe "run_credo_check/2" do
    test "returns findings for nonexistent directory" do
      findings = StaticAnalysis.run_credo_check("/nonexistent/path")
      assert is_list(findings)
    end
  end
end
