defmodule Samgita.Quality.CompletionCouncil do
  @moduledoc """
  Multi-agent voting system that determines when a PRD is "done."

  Council runs every N iterations (configurable, default: 5).
  3 council members vote independently:
  - Requirements Verifier — Are all PRD requirements met?
  - Test Auditor — Are tests comprehensive and passing?
  - Devil's Advocate — Skeptical review, find remaining issues

  Requires 2/3 votes for completion.
  If unanimous COMPLETE → spawn extra Devil's Advocate review.

  Stagnation detection: if N iterations pass with no git changes, force evaluation.
  """

  require Logger

  alias Samgita.Agent.Claude

  @council_members [
    %{
      role: :requirements_verifier,
      agent_type: "review-business",
      focus: "Verify all PRD requirements are implemented, tested, and working"
    },
    %{
      role: :test_auditor,
      agent_type: "review-code",
      focus: "Verify tests are comprehensive, meaningful, and passing"
    },
    %{
      role: :devils_advocate,
      agent_type: "review-security",
      focus: "Find remaining issues, risks, incomplete features, and quality gaps"
    }
  ]

  @type vote :: :complete | :incomplete | :abstain
  @type member_result :: %{
          role: atom(),
          vote: vote(),
          reasoning: String.t(),
          remaining_issues: [String.t()]
        }
  @type council_result :: %{
          verdict: :complete | :incomplete | :stagnated,
          votes: [member_result()],
          unanimous: boolean(),
          quorum_met: boolean()
        }

  @doc "Run the completion council evaluation."
  @spec evaluate(String.t(), String.t(), keyword()) :: {:ok, council_result()} | {:error, term()}
  def evaluate(prd_content, project_status, opts \\ []) do
    timeout = opts[:timeout] || 120_000

    # Run all council members in parallel
    tasks =
      Enum.map(@council_members, fn member ->
        Task.async(fn ->
          evaluate_member(member, prd_content, project_status)
        end)
      end)

    results = Task.yield_many(tasks, timeout)

    votes =
      results
      |> Enum.zip(@council_members)
      |> Enum.map(fn {{_task, result}, member} ->
        case result do
          {:ok, {:ok, vote_result}} ->
            vote_result

          {:ok, {:error, reason}} ->
            Logger.warning("[CompletionCouncil] #{member.role} failed: #{inspect(reason)}")

            %{
              role: member.role,
              vote: :abstain,
              reasoning: "Evaluation failed: #{inspect(reason)}",
              remaining_issues: []
            }

          {:exit, reason} ->
            Logger.error("[CompletionCouncil] #{member.role} crashed: #{inspect(reason)}")

            %{
              role: member.role,
              vote: :abstain,
              reasoning: "Evaluator crashed",
              remaining_issues: []
            }

          nil ->
            Logger.warning("[CompletionCouncil] #{member.role} timed out")

            %{
              role: member.role,
              vote: :abstain,
              reasoning: "Evaluation timed out",
              remaining_issues: []
            }
        end
      end)

    complete_votes = Enum.count(votes, fn v -> v.vote == :complete end)
    total_valid = Enum.count(votes, fn v -> v.vote != :abstain end)
    unanimous = complete_votes == total_valid and total_valid == 3

    verdict =
      cond do
        complete_votes >= 2 -> :complete
        true -> :incomplete
      end

    # Anti-sycophancy: if unanimous complete, log warning (would trigger extra review)
    if unanimous and verdict == :complete do
      Logger.info(
        "[CompletionCouncil] Unanimous completion detected — anti-sycophancy check recommended"
      )
    end

    result = %{
      verdict: verdict,
      votes: votes,
      unanimous: unanimous,
      quorum_met: complete_votes >= 2
    }

    {:ok, result}
  end

  @doc "Check for stagnation: no meaningful progress in N iterations."
  @spec check_stagnation(non_neg_integer(), non_neg_integer()) :: :ok | :stagnated
  def check_stagnation(iterations_since_change, threshold \\ 5) do
    if iterations_since_change >= threshold do
      Logger.warning(
        "[CompletionCouncil] Stagnation detected: #{iterations_since_change} iterations without changes"
      )

      :stagnated
    else
      :ok
    end
  end

  @doc "Returns council member configurations."
  def members, do: @council_members

  ## Internal

  defp evaluate_member(member, prd_content, project_status) do
    prompt = build_evaluation_prompt(member, prd_content, project_status)

    case Claude.chat(prompt, model: :sonnet) do
      {:ok, response} ->
        vote_result = parse_vote_response(response, member.role)
        {:ok, vote_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_evaluation_prompt(member, prd_content, project_status) do
    """
    You are a #{member.role} on the Completion Council.
    Your focus: #{member.focus}

    ## PRD (Product Requirements Document)
    #{prd_content}

    ## Current Project Status
    #{project_status}

    ## Instructions

    Evaluate whether this project's PRD requirements are fully met.
    Consider:
    - Are all features from the PRD implemented?
    - Are tests passing and comprehensive?
    - Are there any critical gaps or risks?

    Respond in this exact format:

    VOTE: COMPLETE or INCOMPLETE
    REASONING: Your detailed reasoning
    REMAINING:
    - Issue 1 (if any)
    - Issue 2 (if any)

    Be honest and thorough. Vote COMPLETE only if you're confident.
    """
  end

  defp parse_vote_response(response, role) do
    lines = String.split(response, "\n")

    vote =
      lines
      |> Enum.find(&String.contains?(&1, "VOTE:"))
      |> case do
        nil ->
          :abstain

        line ->
          cond do
            String.contains?(String.upcase(line), "COMPLETE") and
                not String.contains?(String.upcase(line), "INCOMPLETE") ->
              :complete

            String.contains?(String.upcase(line), "INCOMPLETE") ->
              :incomplete

            true ->
              :abstain
          end
      end

    reasoning =
      lines
      |> Enum.find(&String.contains?(&1, "REASONING:"))
      |> case do
        nil -> response
        line -> String.replace(line, "REASONING:", "") |> String.trim()
      end

    remaining =
      lines
      |> Enum.drop_while(fn line -> not String.contains?(line, "REMAINING:") end)
      |> Enum.drop(1)
      |> Enum.filter(&String.starts_with?(String.trim(&1), "-"))
      |> Enum.map(fn line ->
        line |> String.trim() |> String.replace(~r/^-\s*/, "")
      end)

    %{
      role: role,
      vote: vote,
      reasoning: reasoning,
      remaining_issues: remaining
    }
  end
end
