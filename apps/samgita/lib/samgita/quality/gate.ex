defmodule Samgita.Quality.Gate do
  @moduledoc """
  Quality gate definitions for the 9-gate system.

  Every code change passes through quality gates before acceptance:

  1. Input Guardrails — Validate task scope, detect prompt injection
  2. Static Analysis — Linting, type checking, compilation
  3. Blind Review — 3 independent parallel reviewers
  4. Anti-Sycophancy — Devil's advocate on unanimous approval
  5. Output Guardrails — Secret detection, spec compliance
  6. Severity Blocking — Critical/High/Medium = BLOCK
  7. Test Coverage — Unit 100% pass, >80% coverage
  8. Mock Detector — Flags tests that never import source
  9. Test Mutation Detector — Detects assertion gaming
  """

  @type gate_id :: 1..9
  @type severity :: :critical | :high | :medium | :low | :cosmetic
  @type verdict :: :pass | :fail | :warn | :skip
  @type finding :: %{
          gate: gate_id(),
          severity: severity(),
          message: String.t(),
          file: String.t() | nil,
          line: non_neg_integer() | nil
        }

  @type result :: %{
          gate: gate_id(),
          name: String.t(),
          verdict: verdict(),
          findings: [finding()],
          duration_ms: non_neg_integer()
        }

  @gates %{
    1 => %{name: "Input Guardrails", blocking: true},
    2 => %{name: "Static Analysis", blocking: true},
    3 => %{name: "Blind Review", blocking: true},
    4 => %{name: "Anti-Sycophancy", blocking: true},
    5 => %{name: "Output Guardrails", blocking: true},
    6 => %{name: "Severity Blocking", blocking: true},
    7 => %{name: "Test Coverage", blocking: true},
    8 => %{name: "Mock Detector", blocking: false},
    9 => %{name: "Test Mutation Detector", blocking: false}
  }

  @doc "Returns all gate definitions."
  def all, do: @gates

  @doc "Returns a gate definition by ID."
  def get(id), do: Map.get(@gates, id)

  @doc "Returns gate name by ID."
  def name(id) do
    case get(id) do
      %{name: name} -> name
      nil -> "Unknown Gate #{id}"
    end
  end

  @doc "Returns whether a gate is blocking (fail = reject)."
  def blocking?(id) do
    case get(id) do
      %{blocking: blocking} -> blocking
      nil -> false
    end
  end

  @doc "Aggregate multiple gate results into an overall verdict."
  @spec aggregate([result()]) :: {:pass | :fail, [result()]}
  def aggregate(results) do
    failed_blocking =
      Enum.filter(results, fn r ->
        r.verdict == :fail and blocking?(r.gate)
      end)

    if failed_blocking == [] do
      {:pass, results}
    else
      {:fail, results}
    end
  end

  @doc "Check if findings contain any blocking severity issues."
  @spec has_blocking_findings?([finding()]) :: boolean()
  def has_blocking_findings?(findings) do
    Enum.any?(findings, fn f ->
      f.severity in [:critical, :high, :medium]
    end)
  end
end
