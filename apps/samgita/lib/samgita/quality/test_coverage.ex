defmodule Samgita.Quality.TestCoverage do
  @moduledoc """
  Quality Gate 7: Test Coverage.

  Runs the project's test suite and evaluates results:
  - All tests must pass (0 failures)
  - Optionally checks coverage percentage (via mix test --cover)
  - Reports test count, failure count, and duration
  """

  require Logger

  alias Samgita.Quality.Gate

  @default_timeout 300_000

  @doc """
  Run the test suite for a project and return gate results.

  Options:
  - `:timeout` - max time for test run (default 300s)
  - `:cover` - whether to run with --cover (default false)
  - `:min_coverage` - minimum coverage % to pass (default 0, meaning just tests passing)
  """
  @spec run(String.t(), keyword()) :: Gate.result()
  def run(working_path, opts \\ []) do
    start = System.monotonic_time(:millisecond)
    timeout = opts[:timeout] || @default_timeout
    cover = opts[:cover] || false

    findings =
      if working_path && File.dir?(working_path) do
        run_tests(working_path, timeout, cover, opts)
      else
        [
          %{
            gate: 7,
            severity: :medium,
            message: "Working path not available: #{inspect(working_path)}",
            file: nil,
            line: nil
          }
        ]
      end

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    %{
      gate: 7,
      name: "Test Coverage",
      verdict: verdict,
      findings: findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  defp run_tests(working_path, timeout, cover, opts) do
    args =
      if cover do
        ["test", "--cover"]
      else
        ["test"]
      end

    try do
      task =
        Task.async(fn ->
          System.cmd("mix", args,
            cd: working_path,
            stderr_to_stdout: true,
            env: [{"MIX_ENV", "test"}]
          )
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, exit_code}} ->
          parse_test_output(output, exit_code, cover, opts)

        nil ->
          [
            %{
              gate: 7,
              severity: :high,
              message: "Test suite timed out after #{div(timeout, 1000)}s",
              file: nil,
              line: nil
            }
          ]
      end
    rescue
      e ->
        Logger.warning("[TestCoverage] Failed to run tests: #{inspect(e)}")

        [
          %{
            gate: 7,
            severity: :medium,
            message: "Failed to execute test suite: #{Exception.message(e)}",
            file: nil,
            line: nil
          }
        ]
    end
  end

  defp parse_test_output(output, exit_code, cover, opts) do
    findings = []

    # Parse test summary line: "X tests, Y failures"
    {tests, failures} = extract_test_counts(output)

    findings =
      if failures > 0 do
        failed_tests = extract_failed_tests(output)

        base_finding = %{
          gate: 7,
          severity: :critical,
          message: "#{failures} test failure(s) out of #{tests} tests",
          file: nil,
          line: nil
        }

        failure_findings =
          Enum.map(failed_tests, fn {file, line, name} ->
            %{
              gate: 7,
              severity: :high,
              message: "Failed: #{name}",
              file: file,
              line: line
            }
          end)

        [base_finding | failure_findings] ++ findings
      else
        findings
      end

    # Check for compilation errors
    findings =
      if exit_code != 0 and failures == 0 do
        [
          %{
            gate: 7,
            severity: :critical,
            message: "Test suite exited with code #{exit_code} (compilation error?)",
            file: nil,
            line: nil
          }
          | findings
        ]
      else
        findings
      end

    # Parse coverage if requested
    findings =
      if cover do
        coverage = extract_coverage(output)
        min_coverage = opts[:min_coverage] || 0

        if coverage && coverage < min_coverage do
          [
            %{
              gate: 7,
              severity: :medium,
              message: "Test coverage #{coverage}% below minimum #{min_coverage}%",
              file: nil,
              line: nil
            }
            | findings
          ]
        else
          findings
        end
      else
        findings
      end

    findings
  end

  defp extract_test_counts(output) do
    case Regex.run(~r/(\d+)\s+tests?,\s*(\d+)\s+failures?/, output) do
      [_, tests, failures] ->
        {String.to_integer(tests), String.to_integer(failures)}

      nil ->
        {0, 0}
    end
  end

  defp extract_failed_tests(output) do
    # Match patterns like "  1) test name (Module)\n     test/path.exs:123"
    Regex.scan(~r/\d+\)\s+(.+?)\n\s+(\S+\.exs):(\d+)/, output)
    |> Enum.map(fn
      [_, name, file, line_str] ->
        {line, _} = Integer.parse(line_str)
        {file, line, String.trim(name)}

      _ ->
        {nil, nil, "unknown test"}
    end)
  end

  defp extract_coverage(output) do
    case Regex.run(~r/(\d+(?:\.\d+)?)%\s+\|\s+Total/, output) do
      [_, pct] ->
        {value, _} = Float.parse(pct)
        value

      nil ->
        # Try alternate format
        case Regex.run(~r/Coverage:\s*(\d+(?:\.\d+)?)%/, output) do
          [_, pct] ->
            {value, _} = Float.parse(pct)
            value

          nil ->
            nil
        end
    end
  end
end
