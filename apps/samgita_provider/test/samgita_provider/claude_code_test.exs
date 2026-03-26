defmodule SamgitaProvider.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias SamgitaProvider.ClaudeCode

  describe "build_args/2" do
    test "includes required CLI flags" do
      args = ClaudeCode.build_args("test prompt", [])
      assert "--print" in args
      assert "--output-format" in args
      assert "json" in args
      assert "--dangerously-skip-permissions" in args
      assert "--no-session-persistence" in args
    end

    test "prompt is the last argument" do
      args = ClaudeCode.build_args("my prompt", [])
      assert List.last(args) == "my prompt"
    end

    test "defaults to sonnet model" do
      args = ClaudeCode.build_args("test", [])
      model_idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_idx + 1) == "sonnet"
    end

    test "respects model option as atom" do
      args = ClaudeCode.build_args("test", model: :opus)
      model_idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_idx + 1) == "opus"
    end

    test "respects model option as string" do
      args = ClaudeCode.build_args("test", model: "haiku")
      model_idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_idx + 1) == "haiku"
    end

    test "uses custom system prompt when provided" do
      args = ClaudeCode.build_args("test", system_prompt: "Be concise")
      sp_idx = Enum.find_index(args, &(&1 == "--system-prompt"))
      assert Enum.at(args, sp_idx + 1) == "Be concise"
    end

    test "uses default system prompt when none provided" do
      args = ClaudeCode.build_args("test", [])
      sp_idx = Enum.find_index(args, &(&1 == "--system-prompt"))
      default_sp = Enum.at(args, sp_idx + 1)
      assert is_binary(default_sp)
      assert String.length(default_sp) > 0
    end

    test "includes --max-turns flag when max_turns: 5 is given" do
      args = ClaudeCode.build_args("test prompt", max_turns: 5)
      mt_idx = Enum.find_index(args, &(&1 == "--max-turns"))
      assert mt_idx != nil
      assert Enum.at(args, mt_idx + 1) == "5"
      assert mt_idx < Enum.find_index(args, &(&1 == "test prompt"))
    end

    test "does not include --max-turns when no max_turns option is given" do
      args = ClaudeCode.build_args("test prompt", [])
      refute "--max-turns" in args
    end

    test "does not include --max-turns when max_turns: 0 is given" do
      args = ClaudeCode.build_args("test prompt", max_turns: 0)
      refute "--max-turns" in args
    end
  end

  describe "parse_json_output/1" do
    test "parses successful result with is_error false" do
      json = Jason.encode!(%{"result" => "Hello from Claude", "is_error" => false})
      assert {:ok, "Hello from Claude"} = ClaudeCode.parse_json_output(json)
    end

    test "parses error result with is_error true" do
      json = Jason.encode!(%{"result" => "Something failed", "is_error" => true})
      assert {:error, "Something failed"} = ClaudeCode.parse_json_output(json)
    end

    test "parses result without is_error field" do
      json = Jason.encode!(%{"result" => "Plain result"})
      assert {:ok, "Plain result"} = ClaudeCode.parse_json_output(json)
    end

    test "classifies error when JSON parsing fails on rate limit text" do
      assert {:error, :rate_limit} = ClaudeCode.parse_json_output("Error: rate limit exceeded")
    end

    test "classifies error when JSON parsing fails on overloaded text" do
      assert {:error, :overloaded} = ClaudeCode.parse_json_output("Error: overloaded")
    end

    test "returns trimmed string error for unrecognized plain text" do
      assert {:error, "unexpected failure"} =
               ClaudeCode.parse_json_output("  unexpected failure  ")
    end
  end

  describe "classify_error/2" do
    test "returns :rate_limit for rate limit messages" do
      assert {:error, :rate_limit} = ClaudeCode.classify_error("rate limit exceeded", 429)
    end

    test "returns :rate_limit for rate_limit messages" do
      assert {:error, :rate_limit} = ClaudeCode.classify_error("error: rate_limit", 1)
    end

    test "returns :overloaded for overloaded messages" do
      assert {:error, :overloaded} = ClaudeCode.classify_error("API is overloaded", 503)
    end

    test "returns :claude_not_found for not found messages" do
      assert {:error, :claude_not_found} = ClaudeCode.classify_error("command not found", 127)
    end

    test "returns :claude_not_found for ENOENT messages" do
      assert {:error, :claude_not_found} = ClaudeCode.classify_error("ENOENT: no such file", 1)
    end

    test "returns trimmed string for unrecognized errors" do
      assert {:error, "some other error"} = ClaudeCode.classify_error("  some other error  ", 1)
    end

    test "uses default exit_code when not provided" do
      assert {:error, :overloaded} = ClaudeCode.classify_error("overloaded")
    end
  end

  describe "query/2 with fake claude command" do
    setup do
      # Write a shell script that simulates claude JSON output
      script_path =
        Path.join(System.tmp_dir!(), "fake_claude_#{System.unique_integer([:positive])}.sh")

      File.write!(script_path, """
      #!/bin/sh
      echo '{"result":"mock response from fake claude","is_error":false}'
      """)

      File.chmod!(script_path, 0o755)
      on_exit(fn -> File.rm(script_path) end)
      %{script_path: script_path}
    end

    test "returns ok with result when command succeeds", %{script_path: script_path} do
      # Temporarily override the claude_command for this test
      original = Application.get_env(:samgita_provider, :claude_command, "claude")
      Application.put_env(:samgita_provider, :claude_command, script_path)

      try do
        assert {:ok, "mock response from fake claude"} = ClaudeCode.query("test prompt")
      after
        Application.put_env(:samgita_provider, :claude_command, original)
      end
    end

    test "handles timeout", %{script_path: _script_path} do
      # Create a script that sleeps longer than the timeout
      sleep_script =
        Path.join(System.tmp_dir!(), "slow_claude_#{System.unique_integer([:positive])}.sh")

      File.write!(sleep_script, "#!/bin/sh\nsleep 10\n")
      File.chmod!(sleep_script, 0o755)
      on_exit(fn -> File.rm(sleep_script) end)

      original = Application.get_env(:samgita_provider, :claude_command, "claude")
      Application.put_env(:samgita_provider, :claude_command, sleep_script)

      try do
        assert {:error, :timeout} = ClaudeCode.query("test prompt", timeout: 100)
      after
        Application.put_env(:samgita_provider, :claude_command, original)
      end
    end

    test "returns :claude_not_found when command does not exist" do
      original = Application.get_env(:samgita_provider, :claude_command, "claude")
      Application.put_env(:samgita_provider, :claude_command, "/nonexistent/claude_binary")

      try do
        assert {:error, :claude_not_found} = ClaudeCode.query("test prompt")
      after
        Application.put_env(:samgita_provider, :claude_command, original)
      end
    end
  end
end
