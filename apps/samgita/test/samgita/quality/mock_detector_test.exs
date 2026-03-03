defmodule Samgita.Quality.MockDetectorTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.MockDetector

  setup do
    # Create temp directory for test fixtures
    tmp_dir = Path.join(System.tmp_dir!(), "mock_detector_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

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

    test "scans test directory and aggregates findings", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test")
      File.mkdir_p!(test_dir)

      # Create a bad test file
      bad_file = Path.join(test_dir, "bad_test.exs")

      File.write!(bad_file, """
      defmodule BadTest do
        use ExUnit.Case

        test "bad" do
          assert true
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
          user = User.create(%{name: "Dave"})
          assert user.name == "Dave"
        end
      end
      """)

      result = MockDetector.scan(tmp_dir)

      assert result.gate == 8
      assert result.name == "Mock Detector"
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
          result = Calculator.add(1, 2)
          assert result == 3
        end
      end
      """)

      result = MockDetector.scan(tmp_dir)

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles missing test directory gracefully", %{tmp_dir: tmp_dir} do
      result = MockDetector.scan(tmp_dir)

      assert result.gate == 8
      assert result.name == "Mock Detector"
      assert result.verdict == :pass
      assert result.findings == []
    end

    test "scans nested test directories", %{tmp_dir: tmp_dir} do
      test_dir = Path.join(tmp_dir, "test")
      nested_dir = Path.join([test_dir, "integration", "auth"])
      File.mkdir_p!(nested_dir)

      nested_file = Path.join(nested_dir, "login_test.exs")

      File.write!(nested_file, """
      defmodule LoginTest do
        test "no assertions" do
          :ok
        end
      end
      """)

      result = MockDetector.scan(tmp_dir)

      # Should find the nested test file with issues
      assert Enum.any?(result.findings, &(&1.file == "login_test.exs"))
    end
  end

  describe "analyze_test_file/2" do
    test "detects file with no assertions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "no_assertions_test.exs")

      File.write!(file_path, """
      defmodule NoAssertTest do
        use ExUnit.Case
        test "does nothing" do
          _x = 1 + 1
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 8
      assert finding.severity == :medium
      assert finding.message == "Test file has no assertions"
      assert finding.file == "no_assertions_test.exs"
    end

    test "detects file with only hardcoded assertions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "hardcoded_test.exs")

      File.write!(file_path, """
      defmodule HardcodedTest do
        use ExUnit.Case
        alias MyApp.Foo
        test "always true" do
          assert true
        end
        test "always equal" do
          assert 1 == 1
        end
        test "string comparison" do
          assert "foo" == "foo"
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 8
      assert finding.severity == :medium

      assert finding.message ==
               "All assertions are on hardcoded values (3 assertions)"

      assert finding.file == "hardcoded_test.exs"
    end

    test "detects file that doesn't import source modules", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "no_imports_test.exs")

      File.write!(file_path, """
      defmodule NoImportsTest do
        use ExUnit

        test "has assertions but no module references" do
          assert 2 + 2 == 4
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      assert length(findings) == 1
      assert [finding] = findings
      assert finding.gate == 8
      assert finding.severity == :low
      assert finding.message == "Test file doesn't reference any source modules"
      assert finding.file == "no_imports_test.exs"
    end

    test "passes file with assertions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "good_test.exs")

      File.write!(file_path, """
      defmodule GoodTest do
        use ExUnit.Case
        alias MyApp.Foo
        test "checks something" do
          assert Foo.bar() == :ok
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)
      assert findings == []
    end

    test "returns no findings for file with real assertions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "valid_test.exs")

      File.write!(file_path, """
      defmodule ValidTest do
        use ExUnit.Case
        alias MyApp.User

        test "validates user" do
          user = User.create(%{name: "Alice"})
          assert user.name == "Alice"
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      assert findings == []
    end

    test "skips test helper files", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "test_helper.exs")

      File.write!(file_path, """
      ExUnit.start()
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for missing source references since it's a helper
      assert findings == [] or
               not Enum.any?(
                 findings,
                 &(&1.message == "Test file doesn't reference any source modules")
               )
    end

    test "skips support files", %{tmp_dir: tmp_dir} do
      support_dir = Path.join(tmp_dir, "support")
      File.mkdir_p!(support_dir)
      file_path = Path.join(support_dir, "data_case.exs")

      File.write!(file_path, """
      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for missing source references since it's in support
      assert findings == [] or
               not Enum.any?(
                 findings,
                 &(&1.message == "Test file doesn't reference any source modules")
               )
    end

    test "detects multiple issues in same file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "multiple_issues_test.exs")

      File.write!(file_path, """
      defmodule MultipleIssuesTest do
        test "bad test" do
          assert true
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should have both hardcoded assertion and no source reference issues
      assert length(findings) == 2
      messages = Enum.map(findings, & &1.message)

      assert "All assertions are on hardcoded values (1 assertions)" in messages
      assert "Test file doesn't reference any source modules" in messages
    end

    test "handles file read errors gracefully", %{tmp_dir: tmp_dir} do
      non_existent = Path.join(tmp_dir, "does_not_exist.exs")

      findings = MockDetector.analyze_test_file(non_existent, tmp_dir)

      assert findings == []
    end

    test "detects refute as valid assertion", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "refute_test.exs")

      File.write!(file_path, """
      defmodule RefuteTest do
        use ExUnit.Case
        alias MyApp.User

        test "validates user" do
          refute User.invalid?(%{name: "Alice"})
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for no assertions
      assert not Enum.any?(findings, &(&1.message == "Test file has no assertions"))
    end

    test "detects expect as valid assertion (for mocks)", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "expect_test.exs")

      File.write!(file_path, """
      defmodule ExpectTest do
        use ExUnit.Case
        import Mox

        test "calls mock" do
          expect(MyMock, :call, fn -> :ok end)
          MyMock.call()
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for no assertions
      assert not Enum.any?(findings, &(&1.message == "Test file has no assertions"))
    end

    test "accepts file with import statement", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "import_test.exs")

      File.write!(file_path, """
      defmodule ImportTest do
        use ExUnit.Case
        import MyApp.TestHelpers

        test "uses helper" do
          result = create_user()
          assert result.id
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for no source references
      assert not Enum.any?(
               findings,
               &(&1.message == "Test file doesn't reference any source modules")
             )
    end

    test "accepts file with direct module calls", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "module_call_test.exs")

      File.write!(file_path, """
      defmodule ModuleCallTest do
        use ExUnit.Case

        test "calls module directly" do
          result = MyApp.User.create(%{name: "Bob"})
          assert result.name == "Bob"
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for no source references
      assert not Enum.any?(
               findings,
               &(&1.message == "Test file doesn't reference any source modules")
             )
    end

    test "mixed hardcoded and real assertions returns no findings", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "mixed_test.exs")

      File.write!(file_path, """
      defmodule MixedTest do
        use ExUnit.Case
        alias MyApp.User

        test "has both types" do
          assert true
          user = User.create(%{name: "Charlie"})
          assert user.name == "Charlie"
        end
      end
      """)

      findings = MockDetector.analyze_test_file(file_path, tmp_dir)

      # Should not flag for hardcoded assertions since there are also real ones
      assert not Enum.any?(findings, &String.contains?(&1.message, "hardcoded values"))
    end
  end
end
