defmodule Samgita.Quality.TestMutationDetectorTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.TestMutationDetector

  setup do
    # Create temp directory for test fixtures
    tmp_dir =
      Path.join(System.tmp_dir!(), "test_mutation_detector_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

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

    test "scans test directory and aggregates findings", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test")
      File.mkdir_p!(test_dir)

      # Create a file with issues
      bad_file = Path.join(test_dir, "bad_test.exs")

      File.write!(bad_file, """
      defmodule BadTest do
        use ExUnit.Case

        test "empty" do
        end

        test "catch-all" do
          try do
            raise "error"
          rescue
            _ -> :ok
          end
        end
      end
      """)

      # Create a good test file
      good_file = Path.join(test_dir, "good_test.exs")

      File.write!(good_file, """
      defmodule GoodTest do
        use ExUnit.Case
        alias MyApp.User

        test "good" do
          assert {:ok, %{name: name}} = User.create(%{name: "Eve"})
          assert name == "Eve"
        end
      end
      """)

      result = TestMutationDetector.scan(tmp_dir)

      assert result.gate == 9
      assert result.name == "Test Mutation Detector"
      assert is_integer(result.duration_ms)

      # Should have findings from bad_test.exs
      assert length(result.findings) >= 1
      assert Enum.any?(result.findings, &(&1.file == "bad_test.exs"))
    end

    test "returns pass verdict when no blocking findings", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test")
      File.mkdir_p!(test_dir)

      good_file = Path.join(test_dir, "perfect_test.exs")

      File.write!(good_file, """
      defmodule PerfectTest do
        use ExUnit.Case
        alias MyApp.Calculator

        test "adds numbers" do
          assert {:ok, result} = Calculator.add(1, 2)
          assert result == 3
        end

        test "handles errors properly" do
          assert {:error, :invalid} = Calculator.add(nil, nil)
        end
      end
      """)

      result = TestMutationDetector.scan(tmp_dir)

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles missing test directory gracefully", %{tmp_dir: tmp_dir} do
      result = TestMutationDetector.scan(tmp_dir)

      assert result.gate == 9
      assert result.name == "Test Mutation Detector"
      assert result.verdict == :pass
      assert result.findings == []
    end

    test "scans nested test directories", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test")
      nested_dir = Path.join([test_dir, "unit", "services"])
      File.mkdir_p!(nested_dir)

      nested_file = Path.join(nested_dir, "user_service_test.exs")

      File.write!(nested_file, """
      defmodule UserServiceTest do
        use ExUnit.Case

        test "empty" do
        end
      end
      """)

      result = TestMutationDetector.scan(tmp_dir)

      # Should find the nested test file
      assert Enum.any?(result.findings, &(&1.file == "user_service_test.exs"))
    end
  end

  describe "analyze_test_file/1" do
    test "detects catch-all rescue blocks", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "catch_all_test.exs")

      File.write!(file_path, """
      defmodule CatchAllTest do
        use ExUnit.Case
        test "catches everything" do
          try do
            raise "boom"
          rescue
            _ -> :ok
          end
        end

        test "another catch-all" do
          try do
            raise "error"
          rescue
            _ -> assert true
          end
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 9
      assert finding.severity == :low
      assert finding.message == "2 catch-all rescue block(s) that silently pass"
      assert finding.file == "catch_all_test.exs"
    end

    test "detects catch-all with nil return", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "nil_rescue_test.exs")

      File.write!(file_path, """
      defmodule NilRescueTest do
        use ExUnit.Case

        test "returns nil on error" do
          try do
            raise "error"
          rescue
            _ -> nil
          end
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert length(findings) == 1
      assert [finding] = findings
      assert String.contains?(finding.message, "catch-all rescue block")
    end

    test "detects broad pattern matches", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "broad_pattern_test.exs")

      File.write!(file_path, """
      defmodule BroadPatternTest do
        use ExUnit.Case

        test "broad match 1" do
          assert {:ok, _} = some_function()
        end

        test "broad match 2" do
          assert {:ok, _} = another_function()
        end

        test "broad match 3" do
          assert {:ok, _} = yet_another()
        end

        test "broad match 4" do
          assert {:ok, _} = more_functions()
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 9
      assert finding.severity == :low

      assert finding.message ==
               "4 broad {:ok, _} pattern matches without value inspection"

      assert finding.file == "broad_pattern_test.exs"
    end

    test "does not flag broad patterns if specific matches exist", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "mixed_pattern_test.exs")

      File.write!(file_path, """
      defmodule MixedPatternTest do
        use ExUnit.Case

        test "broad match" do
          assert {:ok, _} = some_function()
        end

        test "specific match" do
          assert {:ok, %{field: value}} = another_function()
          assert value == "expected"
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      # Should not flag because there's at least one specific match
      assert not Enum.any?(findings, &String.contains?(&1.message, "broad {:ok, _}"))
    end

    test "does not flag if only 3 or fewer broad matches", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "few_broad_test.exs")

      File.write!(file_path, """
      defmodule FewBroadTest do
        use ExUnit.Case

        test "broad 1" do
          assert {:ok, _} = f1()
        end

        test "broad 2" do
          assert {:ok, _} = f2()
        end

        test "broad 3" do
          assert {:ok, _} = f3()
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      # Should not flag with only 3 broad matches (threshold is > 3)
      assert not Enum.any?(findings, &String.contains?(&1.message, "broad {:ok, _}"))
    end

    test "detects empty test blocks", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "empty_test.exs")

      File.write!(file_path, """
      defmodule EmptyTest do
        use ExUnit.Case
        test "empty" do
        end

        test "another empty" do
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 9
      assert finding.severity == :medium
      assert finding.message == "2 empty test block(s) with no assertions"
      assert finding.file == "empty_test.exs"
    end

    test "empty test with whitespace is detected", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "whitespace_test.exs")

      File.write!(file_path, """
      defmodule WhitespaceTest do
        use ExUnit.Case

        test "just whitespace" do

        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert length(findings) == 1
      assert [finding] = findings
      assert String.contains?(finding.message, "empty test block")
    end

    test "passes well-written test file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "good_test.exs")

      File.write!(file_path, """
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
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)
      assert findings == []
    end

    test "returns no findings for valid test patterns", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "valid_test.exs")

      File.write!(file_path, """
      defmodule ValidTest do
        use ExUnit.Case
        alias MyApp.User

        test "creates user with validation" do
          try do
            user = User.create(%{name: "Alice"})
            assert {:ok, %{id: id, name: name}} = user
            assert is_integer(id)
            assert name == "Alice"
          rescue
            ArgumentError -> flunk("Unexpected error")
          end
        end

        test "handles error case" do
          assert {:error, %{reason: "invalid"}} = User.create(%{})
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert findings == []
    end

    test "detects multiple issues in same file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "multiple_issues_test.exs")

      File.write!(file_path, """
      defmodule MultipleIssuesTest do
        use ExUnit.Case

        test "empty" do
        end

        test "catch-all" do
          try do
            raise "error"
          rescue
            _ -> :ok
          end
        end

        test "broad 1" do
          assert {:ok, _} = f1()
        end

        test "broad 2" do
          assert {:ok, _} = f2()
        end

        test "broad 3" do
          assert {:ok, _} = f3()
        end

        test "broad 4" do
          assert {:ok, _} = f4()
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      # Should detect empty test, catch-all, and broad patterns
      assert length(findings) == 3
      messages = Enum.map(findings, & &1.message)

      assert Enum.any?(messages, &String.contains?(&1, "empty test block"))
      assert Enum.any?(messages, &String.contains?(&1, "catch-all rescue"))
      assert Enum.any?(messages, &String.contains?(&1, "broad {:ok, _}"))
    end

    test "handles file read errors gracefully", %{tmp_dir: tmp_dir} do
      non_existent = Path.join(tmp_dir, "does_not_exist.exs")

      findings = TestMutationDetector.analyze_test_file(non_existent)

      assert findings == []
    end

    test "specific rescue patterns are not flagged", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "specific_rescue_test.exs")

      File.write!(file_path, """
      defmodule SpecificRescueTest do
        use ExUnit.Case

        test "catches specific error" do
          try do
            raise ArgumentError
          rescue
            ArgumentError -> assert true
            RuntimeError -> flunk("Wrong error")
          end
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      # Should not flag specific rescue clauses
      assert not Enum.any?(findings, &String.contains?(&1.message, "catch-all rescue"))
    end

    test "non-empty test blocks are not flagged", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "non_empty_test.exs")

      File.write!(file_path, """
      defmodule NonEmptyTest do
        use ExUnit.Case

        test "has assertion" do
          assert 1 + 1 == 2
        end

        test "has multiple lines" do
          x = 1
          y = 2
          assert x + y == 3
        end
      end
      """)

      findings = TestMutationDetector.analyze_test_file(file_path)

      assert not Enum.any?(findings, &String.contains?(&1.message, "empty test block"))
    end
  end
end
