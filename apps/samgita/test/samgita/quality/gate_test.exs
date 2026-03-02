defmodule Samgita.Quality.GateTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.Gate

  describe "gate definitions" do
    test "all 9 gates are defined" do
      assert map_size(Gate.all()) == 9
    end

    test "each gate has a name" do
      for id <- 1..9 do
        assert is_binary(Gate.name(id))
        refute Gate.name(id) =~ "Unknown"
      end
    end

    test "gates 1-7 are blocking" do
      for id <- 1..7 do
        assert Gate.blocking?(id), "Gate #{id} should be blocking"
      end
    end

    test "gates 8-9 are non-blocking" do
      for id <- 8..9 do
        refute Gate.blocking?(id), "Gate #{id} should be non-blocking"
      end
    end

    test "unknown gate returns nil" do
      assert Gate.get(99) == nil
      assert Gate.name(99) == "Unknown Gate 99"
      refute Gate.blocking?(99)
    end
  end

  describe "aggregate/1" do
    test "passes when all gates pass" do
      results = [
        %{gate: 1, verdict: :pass, findings: [], name: "Input Guardrails", duration_ms: 10},
        %{gate: 2, verdict: :pass, findings: [], name: "Static Analysis", duration_ms: 20}
      ]

      assert {:pass, ^results} = Gate.aggregate(results)
    end

    test "fails when a blocking gate fails" do
      results = [
        %{gate: 1, verdict: :pass, findings: [], name: "Input Guardrails", duration_ms: 10},
        %{
          gate: 3,
          verdict: :fail,
          findings: [%{severity: :high}],
          name: "Blind Review",
          duration_ms: 30
        }
      ]

      assert {:fail, ^results} = Gate.aggregate(results)
    end

    test "passes when non-blocking gate fails" do
      results = [
        %{gate: 1, verdict: :pass, findings: [], name: "Input Guardrails", duration_ms: 10},
        %{
          gate: 8,
          verdict: :fail,
          findings: [%{severity: :low}],
          name: "Mock Detector",
          duration_ms: 15
        }
      ]

      assert {:pass, ^results} = Gate.aggregate(results)
    end
  end

  describe "has_blocking_findings?/1" do
    test "returns true for critical findings" do
      findings = [%{severity: :critical, message: "SQL injection", gate: 3, file: nil, line: nil}]
      assert Gate.has_blocking_findings?(findings)
    end

    test "returns true for high findings" do
      findings = [%{severity: :high, message: "XSS vulnerability", gate: 3, file: nil, line: nil}]
      assert Gate.has_blocking_findings?(findings)
    end

    test "returns true for medium findings" do
      findings = [%{severity: :medium, message: "Missing validation", gate: 3, file: nil, line: nil}]
      assert Gate.has_blocking_findings?(findings)
    end

    test "returns false for low findings only" do
      findings = [%{severity: :low, message: "Style issue", gate: 3, file: nil, line: nil}]
      refute Gate.has_blocking_findings?(findings)
    end

    test "returns false for cosmetic findings only" do
      findings = [%{severity: :cosmetic, message: "Naming", gate: 3, file: nil, line: nil}]
      refute Gate.has_blocking_findings?(findings)
    end

    test "returns false for empty findings" do
      refute Gate.has_blocking_findings?([])
    end
  end
end
