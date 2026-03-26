defmodule Samgita.Quality.GateTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.Gate

  describe "gate definitions" do
    test "all 10 gates are defined" do
      assert map_size(Gate.all()) == 10
    end

    test "each gate has a name" do
      for id <- 1..10 do
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

  describe "all/0" do
    test "returns map with all gate IDs as keys" do
      gates = Gate.all()

      assert Map.has_key?(gates, 1)
      assert Map.has_key?(gates, 9)
    end

    test "each gate has name and blocking fields" do
      gates = Gate.all()

      Enum.each(gates, fn {_id, gate} ->
        assert Map.has_key?(gate, :name)
        assert Map.has_key?(gate, :blocking)
        assert is_binary(gate.name)
        assert is_boolean(gate.blocking)
      end)
    end
  end

  describe "get/1" do
    test "returns gate definition for valid IDs" do
      assert Gate.get(1) == %{name: "Input Guardrails", blocking: true}
      assert Gate.get(2) == %{name: "Static Analysis", blocking: true}
      assert Gate.get(6) == %{name: "Severity Blocking", blocking: true}
      assert Gate.get(8) == %{name: "Mock Detector", blocking: false}
    end

    test "returns nil for invalid IDs" do
      assert Gate.get(0) == nil
      assert Gate.get(11) == nil
      assert Gate.get(999) == nil
    end

    test "handles nil input" do
      assert Gate.get(nil) == nil
    end
  end

  describe "name/1" do
    test "returns all correct gate names" do
      assert Gate.name(1) == "Input Guardrails"
      assert Gate.name(2) == "Static Analysis"
      assert Gate.name(3) == "Blind Review"
      assert Gate.name(4) == "Anti-Sycophancy"
      assert Gate.name(5) == "Output Guardrails"
      assert Gate.name(6) == "Severity Blocking"
      assert Gate.name(7) == "Test Coverage"
      assert Gate.name(8) == "Mock Detector"
      assert Gate.name(9) == "Test Mutation Detector"
      assert Gate.name(10) == "Completion Council"
    end

    test "returns default name for invalid IDs" do
      assert Gate.name(0) == "Unknown Gate 0"
      assert Gate.name(11) == "Unknown Gate 11"
    end

    test "handles nil input" do
      assert Gate.name(nil) == "Unknown Gate "
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

    test "handles empty results list" do
      assert {:pass, []} = Gate.aggregate([])
    end

    test "ignores warn and skip verdicts" do
      results = [
        %{gate: 1, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 2, verdict: :warn, findings: [], duration_ms: 20},
        %{gate: 3, verdict: :skip, findings: [], duration_ms: 30}
      ]

      assert {:pass, ^results} = Gate.aggregate(results)
    end

    test "fails when multiple blocking gates fail" do
      results = [
        %{gate: 1, verdict: :fail, findings: [], duration_ms: 10},
        %{gate: 2, verdict: :fail, findings: [], duration_ms: 20},
        %{gate: 3, verdict: :fail, findings: [], duration_ms: 30}
      ]

      assert {:fail, ^results} = Gate.aggregate(results)
    end

    test "passes when all blocking gates pass with non-blocking failures" do
      results = [
        %{gate: 1, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 2, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 3, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 4, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 5, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 6, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 7, verdict: :pass, findings: [], duration_ms: 10},
        %{gate: 8, verdict: :fail, findings: [], duration_ms: 10},
        %{gate: 9, verdict: :fail, findings: [], duration_ms: 10}
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
      findings = [
        %{severity: :medium, message: "Missing validation", gate: 3, file: nil, line: nil}
      ]

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

    test "returns true when any finding is blocking" do
      findings = [
        %{severity: :low, message: "Low warning", gate: 2, file: "test.ex", line: 10},
        %{severity: :cosmetic, message: "Cosmetic", gate: 2, file: "test.ex", line: 11},
        %{severity: :critical, message: "Critical", gate: 2, file: "test.ex", line: 12}
      ]

      assert Gate.has_blocking_findings?(findings)
    end

    test "returns false when all findings are non-blocking" do
      findings = [
        %{severity: :low, message: "Low warning", gate: 2, file: "test.ex", line: 10},
        %{severity: :cosmetic, message: "Cosmetic", gate: 2, file: "test.ex", line: 11}
      ]

      refute Gate.has_blocking_findings?(findings)
    end
  end
end
