defmodule Samgita.Quality.SeverityBlocking do
  @moduledoc """
  Quality Gate 6: Severity Blocking.

  Aggregates all findings from previous gates and applies severity-based
  blocking rules:
  - CRITICAL: Always blocks
  - HIGH: Always blocks
  - MEDIUM: Blocks (configurable)
  - LOW: Warning only
  - COSMETIC: Informational

  This gate runs after all other gates and provides the final verdict.
  """

  alias Samgita.Quality.Gate

  @blocking_severities [:critical, :high, :medium]

  @doc """
  Evaluate severity blocking across all gate results.

  Returns a Gate.result() that summarizes blocking findings.
  """
  @spec evaluate([Gate.result()]) :: Gate.result()
  def evaluate(gate_results) do
    start = System.monotonic_time(:millisecond)

    all_findings =
      gate_results
      |> Enum.flat_map(fn r -> r.findings end)

    blocking =
      Enum.filter(all_findings, fn f ->
        f.severity in @blocking_severities
      end)

    summary_findings =
      if blocking != [] do
        by_severity = Enum.group_by(blocking, & &1.severity)

        summary =
          @blocking_severities
          |> Enum.map(fn sev ->
            count = length(Map.get(by_severity, sev, []))
            if count > 0, do: "#{count} #{sev}", else: nil
          end)
          |> Enum.filter(& &1)
          |> Enum.join(", ")

        [
          %{
            gate: 6,
            severity: :high,
            message:
              "Severity blocking: #{summary} finding(s) across #{length(gate_results)} gates",
            file: nil,
            line: nil
          }
        ]
      else
        []
      end

    verdict =
      if blocking != [], do: :fail, else: :pass

    %{
      gate: 6,
      name: "Severity Blocking",
      verdict: verdict,
      findings: summary_findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  @doc "Returns the list of severities that cause blocking."
  def blocking_severities, do: @blocking_severities
end
