defmodule Samgita.Agent.ClaudeTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.Claude

  setup do
    original = Application.get_env(:samgita, :claude_command)
    on_exit(fn -> Application.put_env(:samgita, :claude_command, original) end)
    :ok
  end

  describe "backoff_ms/1" do
    test "returns exponential backoff values" do
      assert Claude.backoff_ms(0) == 60_000
      assert Claude.backoff_ms(1) == 120_000
      assert Claude.backoff_ms(2) == 240_000
      assert Claude.backoff_ms(3) == 480_000
    end

    test "caps at max backoff of 1 hour" do
      assert Claude.backoff_ms(10) == 3_600_000
      assert Claude.backoff_ms(20) == 3_600_000
    end
  end

  describe "chat/2" do
    test "returns ok tuple on successful command" do
      Application.put_env(:samgita, :claude_command, "echo")

      result = Claude.chat("hello world")
      assert {:ok, output} = result
      assert is_binary(output)
    end

    test "passes model option as args" do
      Application.put_env(:samgita, :claude_command, "echo")

      {:ok, output} = Claude.chat("test prompt", model: "sonnet")
      assert output =~ "--model"
      assert output =~ "sonnet"
    end

    test "returns error tuple for nonexistent command" do
      Application.put_env(:samgita, :claude_command, "nonexistent_command_12345")

      assert {:error, message} = Claude.chat("test")
      assert message =~ "Command failed"
    end

    test "returns rate_limit error for rate limit output" do
      tmp_dir = System.tmp_dir!()
      script_path = Path.join(tmp_dir, "mock_claude_rate_limit.sh")
      File.write!(script_path, "#!/bin/sh\necho 'rate limit exceeded'\nexit 1")
      File.chmod!(script_path, 0o755)

      Application.put_env(:samgita, :claude_command, script_path)

      assert {:error, :rate_limit} = Claude.chat("test")

      File.rm(script_path)
    end

    test "returns overloaded error for overloaded output" do
      tmp_dir = System.tmp_dir!()
      script_path = Path.join(tmp_dir, "mock_claude_overloaded.sh")
      File.write!(script_path, "#!/bin/sh\necho 'server overloaded'\nexit 1")
      File.chmod!(script_path, 0o755)

      Application.put_env(:samgita, :claude_command, script_path)

      assert {:error, :overloaded} = Claude.chat("test")

      File.rm(script_path)
    end

    test "returns raw error output for unknown errors" do
      tmp_dir = System.tmp_dir!()
      script_path = Path.join(tmp_dir, "mock_claude_error.sh")
      File.write!(script_path, "#!/bin/sh\necho 'some unknown error'\nexit 1")
      File.chmod!(script_path, 0o755)

      Application.put_env(:samgita, :claude_command, script_path)

      assert {:error, "some unknown error\n"} = Claude.chat("test")

      File.rm(script_path)
    end
  end
end
