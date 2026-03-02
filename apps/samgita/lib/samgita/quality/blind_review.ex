defmodule Samgita.Quality.BlindReview do
  @moduledoc """
  Blind review system (Quality Gate 3).

  Spawns 3 parallel independent reviewers that cannot see each other's findings:
  - review-code: SOLID principles, patterns, maintainability
  - review-business: Requirements coverage, edge cases, UX
  - review-security: OWASP Top 10, vulnerabilities

  If all 3 unanimously approve, triggers Anti-Sycophancy gate (Gate 4)
  with a Devil's Advocate reviewer.
  """

  require Logger

  alias Samgita.Agent.Claude
  alias Samgita.Quality.Gate

  @reviewers [
    %{
      agent_type: "review-code",
      focus: "Code quality: SOLID principles, design patterns, maintainability, readability"
    },
    %{
      agent_type: "review-business",
      focus: "Business logic: Requirements coverage, edge cases, user experience, completeness"
    },
    %{
      agent_type: "review-security",
      focus:
        "Security: OWASP Top 10, injection vulnerabilities, authentication, authorization, data exposure"
    }
  ]

  @doc """
  Run a blind review on the given code changes.

  Returns aggregated findings from all reviewers.
  """
  @spec review(String.t(), keyword()) :: {:ok, Gate.result()} | {:error, term()}
  def review(diff, opts \\ []) do
    project_context = opts[:project_context] || ""
    start_time = System.monotonic_time(:millisecond)

    # Run all reviewers in parallel (blind — they can't see each other)
    tasks =
      Enum.map(@reviewers, fn reviewer ->
        Task.async(fn ->
          run_reviewer(reviewer, diff, project_context)
        end)
      end)

    # Collect results with timeout
    timeout = opts[:timeout] || 120_000
    results = Task.yield_many(tasks, timeout)

    findings =
      results
      |> Enum.zip(@reviewers)
      |> Enum.flat_map(fn {{_task, result}, reviewer} ->
        case result do
          {:ok, {:ok, reviewer_findings}} ->
            reviewer_findings

          {:ok, {:error, reason}} ->
            Logger.warning("[BlindReview] #{reviewer.agent_type} failed: #{inspect(reason)}")

            [
              %{
                gate: 3,
                severity: :low,
                message: "Reviewer #{reviewer.agent_type} failed: #{inspect(reason)}",
                file: nil,
                line: nil
              }
            ]

          {:exit, reason} ->
            Logger.error("[BlindReview] #{reviewer.agent_type} crashed: #{inspect(reason)}")

            [
              %{
                gate: 3,
                severity: :low,
                message: "Reviewer #{reviewer.agent_type} crashed",
                file: nil,
                line: nil
              }
            ]

          nil ->
            Logger.warning("[BlindReview] #{reviewer.agent_type} timed out")

            [
              %{
                gate: 3,
                severity: :low,
                message: "Reviewer #{reviewer.agent_type} timed out",
                file: nil,
                line: nil
              }
            ]
        end
      end)

    duration = System.monotonic_time(:millisecond) - start_time

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    result = %{
      gate: 3,
      name: "Blind Review",
      verdict: verdict,
      findings: findings,
      duration_ms: duration
    }

    # Check for unanimous approval → trigger anti-sycophancy
    if verdict == :pass and unanimous_approval?(findings) do
      Logger.info("[BlindReview] Unanimous approval detected, would trigger anti-sycophancy gate")
    end

    {:ok, result}
  end

  @doc "Returns the list of reviewer configurations."
  def reviewers, do: @reviewers

  ## Internal

  defp run_reviewer(reviewer, diff, project_context) do
    prompt = build_review_prompt(reviewer, diff, project_context)

    case Claude.chat(prompt, model: :sonnet) do
      {:ok, response} ->
        findings = parse_review_response(response, reviewer.agent_type)
        {:ok, findings}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_review_prompt(reviewer, diff, project_context) do
    """
    You are a #{reviewer.agent_type} performing a blind code review.
    You CANNOT see other reviewers' findings. Review independently.

    ## Your Focus Area
    #{reviewer.focus}

    ## Project Context
    #{project_context}

    ## Code Changes (diff)
    ```
    #{diff}
    ```

    ## Review Instructions

    Review the code changes above. For each issue found, output in this format:

    FINDING: [SEVERITY] description
    FILE: path/to/file (or "N/A" if not file-specific)
    LINE: line_number (or 0 if not line-specific)

    Severity levels: CRITICAL, HIGH, MEDIUM, LOW, COSMETIC

    If the code looks good with no issues, output:
    FINDING: [PASS] No issues found in #{reviewer.focus |> String.split(":") |> List.first()}

    Be thorough but fair. Only flag real issues, not style preferences.
    """
  end

  defp parse_review_response(response, agent_type) do
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
      parse_finding_block(lines, agent_type)
    end)
  end

  defp parse_finding_block([], _agent_type), do: []

  defp parse_finding_block(lines, agent_type) do
    finding_line = Enum.find(lines, &String.contains?(&1, "FINDING:"))

    if finding_line do
      {severity, message} = parse_finding_line(finding_line)

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
            gate: 3,
            severity: severity,
            message: "[#{agent_type}] #{message}",
            file: file,
            line: line_num
          }
        ]
      end
    else
      []
    end
  end

  defp parse_finding_line(line) do
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

  defp unanimous_approval?(findings) do
    # Unanimous if no findings of severity higher than cosmetic
    not Enum.any?(findings, fn f ->
      f.severity in [:critical, :high, :medium, :low]
    end)
  end
end
