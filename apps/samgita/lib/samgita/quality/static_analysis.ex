defmodule Samgita.Quality.StaticAnalysis do
  @moduledoc """
  Quality Gate 2: Static Analysis.

  Runs static analysis tools on the project codebase:
  - `mix compile --warnings-as-errors` — compilation check
  - `mix format --check-formatted` — code formatting
  - `mix credo --strict` — linting (if available)

  Each tool produces findings that are aggregated into a gate result.
  """

  require Logger

  alias Samgita.Quality.Gate

  @doc """
  Run static analysis on a project's working directory.

  Returns a Gate.result() with findings from all analysis tools.
  """
  @spec analyze(String.t(), keyword()) :: Gate.result()
  def analyze(working_path, opts \\ []) do
    start = System.monotonic_time(:millisecond)
    timeout = opts[:timeout] || 120_000

    findings =
      if working_path && File.dir?(working_path) do
        [
          run_compile_check(working_path, timeout),
          run_format_check(working_path, timeout),
          run_credo_check(working_path, timeout)
        ]
        |> List.flatten()
      else
        [
          %{
            gate: 2,
            severity: :medium,
            message: "Working path not available or not a directory: #{inspect(working_path)}",
            file: nil,
            line: nil
          }
        ]
      end

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    %{
      gate: 2,
      name: "Static Analysis",
      verdict: verdict,
      findings: findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc "Run only the compilation check."
  @spec run_compile_check(String.t(), non_neg_integer()) :: [Gate.finding()]
  def run_compile_check(working_path, timeout \\ 60_000) do
    case run_mix_cmd(working_path, ["compile", "--warnings-as-errors"], timeout) do
      {:ok, _output} ->
        []

      {:error, output, exit_code} ->
        parse_compile_output(output, exit_code)
    end
  end

  @doc "Run only the format check."
  @spec run_format_check(String.t(), non_neg_integer()) :: [Gate.finding()]
  def run_format_check(working_path, timeout \\ 60_000) do
    case run_mix_cmd(working_path, ["format", "--check-formatted"], timeout) do
      {:ok, _output} ->
        []

      {:error, output, _exit_code} ->
        parse_format_output(output)
    end
  end

  @doc "Run only the credo check."
  @spec run_credo_check(String.t(), timeout :: non_neg_integer()) :: [Gate.finding()]
  def run_credo_check(working_path, timeout \\ 60_000) do
    case run_mix_cmd(working_path, ["credo", "--strict", "--format", "json"], timeout) do
      {:ok, output} ->
        parse_credo_json(output)

      {:error, output, _exit_code} ->
        parse_credo_json(output)
    end
  end

  ## Internal

  defp run_mix_cmd(working_path, args, timeout) do
    task =
      Task.async(fn ->
        System.cmd("mix", args,
          cd: working_path,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}]
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, exit_code}} ->
        {:error, output, exit_code}

      nil ->
        {:error, "Command timed out after #{timeout}ms", 1}
    end
  rescue
    e ->
      Logger.warning("[StaticAnalysis] Command failed: #{inspect(e)}")
      {:error, "Failed to execute: #{Exception.message(e)}", 1}
  end

  defp parse_compile_output(output, _exit_code) do
    warnings =
      output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "warning:"))
      |> Enum.map(fn line ->
        {file, line_num} = extract_file_line(line)

        %{
          gate: 2,
          severity: :medium,
          message: "[compile] #{String.trim(line)}",
          file: file,
          line: line_num
        }
      end)

    errors =
      output
      |> String.split("\n")
      |> Enum.filter(&(String.contains?(&1, "error:") or String.contains?(&1, "** (")))
      |> Enum.map(fn line ->
        {file, line_num} = extract_file_line(line)

        %{
          gate: 2,
          severity: :critical,
          message: "[compile] #{String.trim(line)}",
          file: file,
          line: line_num
        }
      end)

    case {errors, warnings} do
      {[], []} ->
        [
          %{
            gate: 2,
            severity: :medium,
            message: "[compile] Compilation failed with warnings-as-errors",
            file: nil,
            line: nil
          }
        ]

      _ ->
        errors ++ warnings
    end
  end

  defp parse_format_output(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&(String.contains?(&1, ".ex") or String.contains?(&1, ".exs")))
    |> Enum.map(fn line ->
      file = line |> String.trim() |> String.replace(~r/^\*\*\s*/, "")

      %{
        gate: 2,
        severity: :low,
        message: "[format] File not formatted: #{file}",
        file: file,
        line: nil
      }
    end)
    |> case do
      [] ->
        if String.contains?(output, "not formatted") do
          [
            %{
              gate: 2,
              severity: :low,
              message: "[format] Code formatting issues detected",
              file: nil,
              line: nil
            }
          ]
        else
          []
        end

      findings ->
        findings
    end
  end

  defp parse_credo_json(output) do
    case Jason.decode(output) do
      {:ok, %{"issues" => issues}} when is_list(issues) ->
        Enum.map(issues, fn issue ->
          severity = credo_priority_to_severity(issue["priority"])
          file = get_in(issue, ["filename"])
          line = get_in(issue, ["line_no"])
          message = get_in(issue, ["message"]) || get_in(issue, ["check"])

          %{
            gate: 2,
            severity: severity,
            message: "[credo] #{message}",
            file: file,
            line: line
          }
        end)

      _ ->
        # Credo might not be installed or output isn't JSON
        parse_credo_text(output)
    end
  end

  defp parse_credo_text(output) do
    if credo_not_available?(output) do
      []
    else
      parse_credo_text_issues(output)
    end
  end

  defp credo_not_available?(output) do
    String.contains?(output, "could not be found") or
      String.contains?(output, "not available")
  end

  defp parse_credo_text_issues(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&Regex.match?(~r/\[.\]\s/, &1))
    |> Enum.map(&parse_credo_text_line/1)
  end

  defp parse_credo_text_line(line) do
    severity = extract_credo_severity(line)

    %{
      gate: 2,
      severity: severity,
      message: "[credo] #{String.trim(line)}",
      file: nil,
      line: nil
    }
  end

  defp extract_credo_severity(line) do
    cond do
      String.contains?(line, "[F]") -> :high
      String.contains?(line, "[C]") -> :medium
      String.contains?(line, "[W]") -> :low
      String.contains?(line, "[R]") -> :cosmetic
      true -> :low
    end
  end

  defp credo_priority_to_severity(priority) when is_integer(priority) do
    cond do
      priority >= 20 -> :high
      priority >= 10 -> :medium
      priority >= 1 -> :low
      true -> :cosmetic
    end
  end

  defp credo_priority_to_severity(_), do: :low

  defp extract_file_line(line) do
    case Regex.run(~r/([^\s:]+\.exs?):(\d+)/, line) do
      [_, file, line_str] ->
        {line_num, _} = Integer.parse(line_str)
        {file, line_num}

      _ ->
        {nil, nil}
    end
  end
end
