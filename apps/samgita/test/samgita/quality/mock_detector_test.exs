defmodule Samgita.Quality.MockDetectorTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.MockDetector

  describe "scan/2" do
    test "returns pass for nonexistent path" do
      result = MockDetector.scan("/nonexistent/path")
      assert result.gate == 8
      assert result.name == "Mock Detector"
      assert result.verdict == :pass
      assert Enum.any?(result.findings, &String.contains?(&1.message, "not available"))
    end

    test "returns pass for nil path" do
      result = MockDetector.scan(nil)
      assert result.verdict == :pass
    end

    test "includes duration_ms" do
      result = MockDetector.scan("/nonexistent")
      assert is_integer(result.duration_ms)
    end
  end

  describe "analyze_test_file/2" do
    test "detects file with no assertions" do
      content = """
      defmodule NoAssertTest do
        use ExUnit.Case
        test "does nothing" do
          _x = 1 + 1
        end
      end
      """

      file = write_temp_file(content)
      findings = MockDetector.analyze_test_file(file, "/tmp")
      assert Enum.any?(findings, &String.contains?(&1.message, "no assertions"))
    after
      cleanup_temp()
    end

    test "passes file with assertions" do
      content = """
      defmodule GoodTest do
        use ExUnit.Case
        alias MyApp.Foo
        test "checks something" do
          assert Foo.bar() == :ok
        end
      end
      """

      file = write_temp_file(content)
      findings = MockDetector.analyze_test_file(file, "/tmp")
      assert findings == []
    after
      cleanup_temp()
    end

    test "detects only hardcoded assertions" do
      content = """
      defmodule HardcodedTest do
        use ExUnit.Case
        alias MyApp.Foo
        test "always true" do
          assert true
        end
        test "always equal" do
          assert 1 == 1
        end
      end
      """

      file = write_temp_file(content)
      findings = MockDetector.analyze_test_file(file, "/tmp")
      assert Enum.any?(findings, &String.contains?(&1.message, "hardcoded"))
    after
      cleanup_temp()
    end
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "mock_detector_test_#{:rand.uniform(99999)}_test.exs")
    File.write!(path, content)
    path
  end

  defp cleanup_temp do
    Path.wildcard(Path.join(System.tmp_dir!(), "mock_detector_test_*"))
    |> Enum.each(&File.rm/1)
  end
end
