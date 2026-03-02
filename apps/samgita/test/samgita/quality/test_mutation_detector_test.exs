defmodule Samgita.Quality.TestMutationDetectorTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.TestMutationDetector

  describe "scan/2" do
    test "returns pass for nonexistent path" do
      result = TestMutationDetector.scan("/nonexistent/path")
      assert result.gate == 9
      assert result.name == "Test Mutation Detector"
      assert result.verdict == :pass
      assert result.findings == []
    end

    test "includes duration_ms" do
      result = TestMutationDetector.scan("/nonexistent")
      assert is_integer(result.duration_ms)
    end
  end

  describe "analyze_test_file/1" do
    test "detects catch-all rescue blocks" do
      content = """
      defmodule CatchAllTest do
        use ExUnit.Case
        test "catches everything" do
          try do
            raise "boom"
          rescue
            _ -> :ok
          end
        end
      end
      """

      file = write_temp_file(content)
      findings = TestMutationDetector.analyze_test_file(file)
      assert Enum.any?(findings, &String.contains?(&1.message, "catch-all rescue"))
    after
      cleanup_temp()
    end

    test "detects empty test blocks" do
      content = """
      defmodule EmptyTest do
        use ExUnit.Case
        test "empty" do
        end
      end
      """

      file = write_temp_file(content)
      findings = TestMutationDetector.analyze_test_file(file)
      assert Enum.any?(findings, &String.contains?(&1.message, "empty test block"))
    after
      cleanup_temp()
    end

    test "passes well-written test file" do
      content = """
      defmodule GoodTest do
        use ExUnit.Case
        alias MyApp.Users

        test "creates a user" do
          assert {:ok, %{name: "Alice"}} = Users.create(%{name: "Alice"})
        end

        test "validates required fields" do
          assert {:error, changeset} = Users.create(%{})
          assert changeset.errors[:name]
        end
      end
      """

      file = write_temp_file(content)
      findings = TestMutationDetector.analyze_test_file(file)
      assert findings == []
    after
      cleanup_temp()
    end
  end

  defp write_temp_file(content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "mutation_detector_test_#{:rand.uniform(99999)}_test.exs"
      )

    File.write!(path, content)
    path
  end

  defp cleanup_temp do
    Path.wildcard(Path.join(System.tmp_dir!(), "mutation_detector_test_*"))
    |> Enum.each(&File.rm/1)
  end
end
