defmodule Samgita.Agent.ClaudeTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.Claude

  # Requires a real Claude CLI. Excluded from `mix test` by default.
  # Run with: mix test --include e2e
  @moduletag :e2e

  setup do
    test_file = "/tmp/claude_test_#{:rand.uniform(10000)}.txt"
    File.rm(test_file)
    on_exit(fn -> File.rm(test_file) end)
    {:ok, test_file: test_file}
  end

  describe "Claude with file operations" do
    @tag timeout: 60_000
    test "can write a file", %{test_file: test_file} do
      prompt = """
      Please write the text "Hello from Claude!" to the file #{test_file}.
      Use the write tool to create this file.
      """

      {:ok, response} = Claude.chat(prompt)

      IO.puts("\n=== Claude Response ===")
      IO.puts(response)
      IO.puts("======================\n")

      Process.sleep(500)

      if File.exists?(test_file) do
        content = File.read!(test_file)
        assert String.contains?(content, "Hello from Claude")
      else
        flunk("File was not created. Claude response: #{response}")
      end
    end

    @tag timeout: 60_000
    test "can read a file", %{test_file: test_file} do
      File.write!(test_file, "Test content for reading")

      prompt = """
      Please read the file #{test_file} and tell me what it contains.
      """

      {:ok, response} = Claude.chat(prompt)

      IO.puts("\n=== Claude Response ===")
      IO.puts(response)
      IO.puts("======================\n")

      assert String.contains?(response, "Test content") or
               String.contains?(response, "reading")
    end
  end
end
