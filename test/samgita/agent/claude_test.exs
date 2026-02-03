defmodule Samgita.Agent.ClaudeTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.Claude

  @moduletag :integration

  setup do
    # Ensure test file doesn't exist
    test_file = "/tmp/claude_test_#{:rand.uniform(10000)}.txt"
    File.rm(test_file)

    on_exit(fn ->
      File.rm(test_file)
    end)

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

      # Give it a moment for the file to be created
      Process.sleep(500)

      # Check if file exists
      if File.exists?(test_file) do
        content = File.read!(test_file)
        IO.puts("✅ File created successfully!")
        IO.puts("Content: #{content}")
        assert String.contains?(content, "Hello from Claude")
      else
        IO.puts("❌ File was NOT created")
        IO.puts("Test file path: #{test_file}")
        flunk("File was not created")
      end
    end

    @tag timeout: 60_000
    test "can read a file", %{test_file: test_file} do
      # First create a file
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
