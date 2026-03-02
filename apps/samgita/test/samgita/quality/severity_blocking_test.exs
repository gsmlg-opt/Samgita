defmodule Samgita.Quality.SeverityBlockingTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.SeverityBlocking

  describe "evaluate/1" do
    test "passes when no findings" do
      results = [
        %{gate: 1, name: "Gate 1", verdict: :pass, findings: [], duration_ms: 0},
        %{gate: 2, name: "Gate 2", verdict: :pass, findings: [], duration_ms: 0}
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.gate == 6
      assert result.name == "Severity Blocking"
      assert result.verdict == :pass
      assert result.findings == []
    end

    test "fails when critical findings exist" do
      results = [
        %{
          gate: 3,
          name: "Review",
          verdict: :fail,
          findings: [
            %{gate: 3, severity: :critical, message: "SQL injection", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :fail
      assert Enum.any?(result.findings, &String.contains?(&1.message, "1 critical"))
    end

    test "fails when high severity findings exist" do
      results = [
        %{
          gate: 5,
          name: "Output",
          verdict: :fail,
          findings: [
            %{gate: 5, severity: :high, message: "Dangerous op", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :fail
    end

    test "fails when medium severity findings exist" do
      results = [
        %{
          gate: 2,
          name: "Static",
          verdict: :fail,
          findings: [
            %{gate: 2, severity: :medium, message: "Warning", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :fail
    end

    test "passes when only low severity findings" do
      results = [
        %{
          gate: 8,
          name: "Mock",
          verdict: :pass,
          findings: [
            %{gate: 8, severity: :low, message: "Minor issue", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :pass
    end

    test "passes when only cosmetic findings" do
      results = [
        %{
          gate: 9,
          name: "Mutation",
          verdict: :pass,
          findings: [
            %{gate: 9, severity: :cosmetic, message: "Style nit", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :pass
    end

    test "aggregates across multiple gates" do
      results = [
        %{
          gate: 1,
          name: "Input",
          verdict: :pass,
          findings: [],
          duration_ms: 0
        },
        %{
          gate: 2,
          name: "Static",
          verdict: :fail,
          findings: [
            %{gate: 2, severity: :medium, message: "Warn 1", file: nil, line: nil},
            %{gate: 2, severity: :medium, message: "Warn 2", file: nil, line: nil}
          ],
          duration_ms: 0
        },
        %{
          gate: 3,
          name: "Review",
          verdict: :fail,
          findings: [
            %{gate: 3, severity: :critical, message: "Critical bug", file: nil, line: nil}
          ],
          duration_ms: 0
        }
      ]

      result = SeverityBlocking.evaluate(results)
      assert result.verdict == :fail
      assert Enum.any?(result.findings, &String.contains?(&1.message, "1 critical"))
      assert Enum.any?(result.findings, &String.contains?(&1.message, "2 medium"))
    end

    test "includes duration_ms" do
      result = SeverityBlocking.evaluate([])
      assert is_integer(result.duration_ms)
    end
  end

  describe "blocking_severities/0" do
    test "returns critical, high, medium" do
      assert :critical in SeverityBlocking.blocking_severities()
      assert :high in SeverityBlocking.blocking_severities()
      assert :medium in SeverityBlocking.blocking_severities()
      refute :low in SeverityBlocking.blocking_severities()
      refute :cosmetic in SeverityBlocking.blocking_severities()
    end
  end
end
