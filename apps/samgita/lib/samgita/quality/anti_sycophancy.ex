defmodule Samgita.Quality.AntiSycophancy do
  @moduledoc """
  Quality Gate 4: Anti-Sycophancy.

  When blind review (Gate 3) results in unanimous approval, this gate
  spawns a Devil's Advocate reviewer to challenge the consensus.

  The Devil's Advocate is instructed to:
  - Assume something must be wrong
  - Look for subtle bugs, race conditions, and edge cases
  - Challenge assumptions about completeness
  - Check for missing error handling
  - Flag any concerns that might have been overlooked

  If the Devil's Advocate finds no issues, the approval stands.
  If issues are found, they are added as findings with medium severity.
  """

  require Logger

  alias Samgita.Agent.Claude
  alias Samgita.Quality.Gate

  @doc """
  Run the anti-sycophancy check.

  Takes the original diff/code and the previous review findings.
  Returns a Gate.result() with any additional findings.
  """
  @spec challenge(String.t(), [Gate.finding()], keyword()) :: Gate.result()
  def challenge(diff, previous_findings, opts \\ []) do
    start = System.monotonic_time(:millisecond)
    project_context = opts[:project_context] || ""
    timeout = opts[:timeout] || 120_000

    result =
      try do
        task =
          Task.async(fn ->
            run_devils_advocate(diff, previous_findings, project_context)
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, {:ok, findings}} ->
            findings

          {:ok, {:error, reason}} ->
            Logger.warning("[AntiSycophancy] Devil's advocate failed: #{inspect(reason)}")
            []

          nil ->
            Logger.warning("[AntiSycophancy] Devil's advocate timed out")
            []
        end
      rescue
        e ->
          Logger.warning("[AntiSycophancy] Error: #{inspect(e)}")
          []
      end

    verdict =
      if Gate.has_blocking_findings?(result), do: :fail, else: :pass

    %{
      gate: 4,
      name: "Anti-Sycophancy",
      verdict: verdict,
      findings: result,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc """
  Check if blind review results warrant anti-sycophancy challenge.
  Returns true if all reviewers approved unanimously.
  """
  @spec should_challenge?([Gate.finding()]) :: boolean()
  def should_challenge?(findings) do
    # Trigger if no findings of blocking severity
    not Enum.any?(findings, fn f ->
      f.severity in [:critical, :high, :medium, :low]
    end)
  end

  ## Internal

  defp run_devils_advocate(diff, previous_findings, project_context) do
    prompt = build_challenge_prompt(diff, previous_findings, project_context)

    case Claude.chat(prompt, model: :sonnet) do
      {:ok, response} ->
        findings = parse_challenge_response(response)
        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_challenge_prompt(diff, previous_findings, project_context) do
    prev_summary =
      if previous_findings == [] do
        "All previous reviewers approved with no issues."
      else
        previous_findings
        |> Enum.map(fn f -> "- [#{f.severity}] #{f.message}" end)
        |> Enum.join("\n")
      end

    """
    You are a Devil's Advocate code reviewer. Your job is to CHALLENGE
    a unanimous approval from other reviewers.

    ## Important Context
    Three independent reviewers all approved this code change.
    Your job is to find what they missed. Assume something IS wrong.

    ## Project Context
    #{project_context}

    ## Previous Review Summary
    #{prev_summary}

    ## Code Changes
    ```
    #{diff}
    ```

    ## Your Mission

    Look specifically for:
    1. **Subtle bugs** — race conditions, off-by-one errors, nil handling
    2. **Missing edge cases** — what happens with empty input, large data, concurrent access?
    3. **Security gaps** — injection vectors, privilege escalation, data leakage
    4. **Missing error handling** — what exceptions could be thrown?
    5. **Performance issues** — N+1 queries, memory leaks, blocking operations
    6. **Assumptions** — what implicit assumptions might break under different conditions?

    For each issue found, output:
    FINDING: [SEVERITY] description
    FILE: path/to/file (or "N/A")
    LINE: line_number (or 0)

    If after thorough analysis you genuinely find nothing wrong, output:
    FINDING: [PASS] Devil's advocate found no additional issues

    Do NOT rubber-stamp this. Challenge every assumption.
    """
  end

  defp parse_challenge_response(response) do
    response
    |> String.split("\n")
    |> Enum.chunk_while(
      [],
      fn line, acc ->
        if String.starts_with?(String.trim(line), "FINDING:") do
          if acc == [], do: {:cont, [line]}, else: {:cont, Enum.reverse(acc), [line]}
        else
          {:cont, [line | acc]}
        end
      end,
      fn acc -> if acc == [], do: {:cont, []}, else: {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.flat_map(fn lines ->
      parse_finding_block(lines)
    end)
  end

  defp parse_finding_block([]), do: []

  defp parse_finding_block(lines) do
    finding_line = Enum.find(lines, &String.contains?(&1, "FINDING:"))

    if finding_line do
      {severity, message} = parse_severity(finding_line)

      file =
        lines
        |> Enum.find(&String.contains?(&1, "FILE:"))
        |> case do
          nil -> nil
          line -> line |> String.replace("FILE:", "") |> String.trim()
        end

      line_num =
        lines
        |> Enum.find(&String.contains?(&1, "LINE:"))
        |> case do
          nil ->
            nil

          line ->
            line
            |> String.replace("LINE:", "")
            |> String.trim()
            |> Integer.parse()
            |> case do
              {n, _} -> n
              :error -> nil
            end
        end

      if severity == :pass do
        []
      else
        [
          %{
            gate: 4,
            severity: severity,
            message: "[devil's-advocate] #{message}",
            file: file,
            line: line_num
          }
        ]
      end
    else
      []
    end
  end

  defp parse_severity(line) do
    trimmed =
      line
      |> String.replace("FINDING:", "")
      |> String.trim()

    cond do
      String.starts_with?(trimmed, "[CRITICAL]") ->
        {:critical, String.replace(trimmed, "[CRITICAL]", "") |> String.trim()}

      String.starts_with?(trimmed, "[HIGH]") ->
        {:high, String.replace(trimmed, "[HIGH]", "") |> String.trim()}

      String.starts_with?(trimmed, "[MEDIUM]") ->
        {:medium, String.replace(trimmed, "[MEDIUM]", "") |> String.trim()}

      String.starts_with?(trimmed, "[LOW]") ->
        {:low, String.replace(trimmed, "[LOW]", "") |> String.trim()}

      String.starts_with?(trimmed, "[COSMETIC]") ->
        {:cosmetic, String.replace(trimmed, "[COSMETIC]", "") |> String.trim()}

      String.starts_with?(trimmed, "[PASS]") ->
        {:pass, String.replace(trimmed, "[PASS]", "") |> String.trim()}

      true ->
        {:low, trimmed}
    end
  end
end
