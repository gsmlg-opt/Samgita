defmodule Samgita.Quality.MockDetector do
  @moduledoc """
  Quality Gate 8: Mock Detector.

  Analyzes test files to detect tests that may be trivially passing
  because they never import or reference the module under test.

  Checks:
  - Test files that don't alias/import any source modules
  - Test modules that only assert on hardcoded values
  - Test files with no assertions at all
  """

  alias Samgita.Quality.Gate

  @doc """
  Scan test files in a project directory for mock-only tests.

  Returns a Gate.result() with findings for suspicious test files.
  """
  @spec scan(String.t(), keyword()) :: Gate.result()
  def scan(working_path, _opts \\ []) do
    start = System.monotonic_time(:millisecond)

    findings =
      if working_path && File.dir?(working_path) do
        test_dir = Path.join(working_path, "test")

        if File.dir?(test_dir) do
          find_test_files(test_dir)
          |> Enum.flat_map(&analyze_test_file(&1, working_path))
        else
          []
        end
      else
        [
          %{
            gate: 8,
            severity: :low,
            message: "Working path not available: #{inspect(working_path)}",
            file: nil,
            line: nil
          }
        ]
      end

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    %{
      gate: 8,
      name: "Mock Detector",
      verdict: verdict,
      findings: findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc """
  Analyze a single test file for mock-only patterns.
  """
  @spec analyze_test_file(String.t(), String.t()) :: [Gate.finding()]
  def analyze_test_file(file_path, _working_path) do
    case File.read(file_path) do
      {:ok, content} ->
        findings = []
        findings = check_no_assertions(findings, content, file_path)
        findings = check_no_source_references(findings, content, file_path)
        findings = check_only_hardcoded_assertions(findings, content, file_path)
        findings

      {:error, _} ->
        []
    end
  end

  defp find_test_files(test_dir) do
    Path.wildcard(Path.join(test_dir, "**/*_test.exs"))
  end

  defp check_no_assertions(findings, content, file_path) do
    has_assert = String.contains?(content, "assert")
    has_refute = String.contains?(content, "refute")
    has_expect = String.contains?(content, "expect")

    if not has_assert and not has_refute and not has_expect do
      [
        %{
          gate: 8,
          severity: :medium,
          message: "Test file has no assertions",
          file: relative_path(file_path),
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp check_no_source_references(findings, content, file_path) do
    # A test should reference at least one source module via alias, import, or direct use
    has_alias = Regex.match?(~r/alias\s+\w+\./, content)
    has_import = Regex.match?(~r/import\s+\w+\./, content)
    has_use = Regex.match?(~r/use\s+\w+\.\w+/, content)
    has_module_call = Regex.match?(~r/\w+\.\w+\./, content)

    # Skip test_helper and support files
    is_helper =
      String.contains?(file_path, "test_helper") or String.contains?(file_path, "support")

    if not is_helper and not has_alias and not has_import and not has_use and not has_module_call do
      [
        %{
          gate: 8,
          severity: :low,
          message: "Test file doesn't reference any source modules",
          file: relative_path(file_path),
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp check_only_hardcoded_assertions(findings, content, file_path) do
    # Check for tests that only assert on literals like `assert true`, `assert 1 == 1`
    literal_asserts =
      Regex.scan(~r/assert\s+(true|false|1\s*==\s*1|"[^"]*"\s*==\s*"[^"]*")/, content)

    all_asserts = Regex.scan(~r/assert\s+/, content)

    if all_asserts != [] and length(literal_asserts) == length(all_asserts) do
      [
        %{
          gate: 8,
          severity: :medium,
          message:
            "All assertions are on hardcoded values (#{length(literal_asserts)} assertions)",
          file: relative_path(file_path),
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp relative_path(file_path) do
    # Return just the filename for readability
    Path.basename(file_path)
  end
end
