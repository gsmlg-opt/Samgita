defmodule Samgita.Quality.TestMutationDetector do
  @moduledoc """
  Quality Gate 9: Test Mutation Detector.

  Detects assertion gaming patterns where tests appear to pass
  but don't actually verify meaningful behavior:

  - Tests that only check return values are tuples/maps without content
  - Tests with no variable bindings from the code under test
  - Tests that catch all errors and pass regardless
  - Tests with overly broad pattern matches
  """

  alias Samgita.Quality.Gate

  @doc """
  Scan test files in a project directory for assertion gaming.

  Returns a Gate.result() with findings for suspicious patterns.
  """
  @spec scan(String.t(), keyword()) :: Gate.result()
  def scan(working_path, _opts \\ []) do
    start = System.monotonic_time(:millisecond)

    findings =
      if working_path && File.dir?(working_path) do
        test_dir = Path.join(working_path, "test")

        if File.dir?(test_dir) do
          find_test_files(test_dir)
          |> Enum.flat_map(&analyze_test_file/1)
        else
          []
        end
      else
        []
      end

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    %{
      gate: 9,
      name: "Test Mutation Detector",
      verdict: verdict,
      findings: findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc """
  Analyze a single test file for assertion gaming patterns.
  """
  @spec analyze_test_file(String.t()) :: [Gate.finding()]
  def analyze_test_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        findings = []
        findings = check_catch_all_rescue(findings, content, file_path)
        findings = check_broad_pattern_match(findings, content, file_path)
        findings = check_empty_test_blocks(findings, content, file_path)
        findings

      {:error, _} ->
        []
    end
  end

  defp find_test_files(test_dir) do
    Path.wildcard(Path.join(test_dir, "**/*_test.exs"))
  end

  defp check_catch_all_rescue(findings, content, file_path) do
    # Detect: rescue _ -> :ok or rescue _ -> assert true
    catch_all_count =
      Regex.scan(~r/rescue\s+_\s*->\s*(:ok|assert\s+true|nil)/, content)
      |> length()

    if catch_all_count > 0 do
      [
        %{
          gate: 9,
          severity: :low,
          message: "#{catch_all_count} catch-all rescue block(s) that silently pass",
          file: relative_path(file_path),
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp check_broad_pattern_match(findings, content, file_path) do
    # Detect: assert {:ok, _} = ... (too broad) vs assert {:ok, %{field: value}} = ...
    broad_matches =
      Regex.scan(~r/assert\s+\{:ok,\s*_\}\s*=/, content)
      |> length()

    # Only flag if ALL ok-assertions are broad
    specific_matches =
      Regex.scan(~r/assert\s+\{:ok,\s*%\{/, content)
      |> length()

    if broad_matches > 3 and specific_matches == 0 do
      [
        %{
          gate: 9,
          severity: :low,
          message: "#{broad_matches} broad {:ok, _} pattern matches without value inspection",
          file: relative_path(file_path),
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp check_empty_test_blocks(findings, content, file_path) do
    # Detect test blocks with no body or only comments
    empty_tests =
      Regex.scan(~r/test\s+"[^"]+"\s+do\s*\n\s*end/, content)
      |> length()

    if empty_tests > 0 do
      [
        %{
          gate: 9,
          severity: :medium,
          message: "#{empty_tests} empty test block(s) with no assertions",
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
    Path.basename(file_path)
  end
end
