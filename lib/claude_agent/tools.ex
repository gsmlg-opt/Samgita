defmodule ClaudeAgent.Tools do
  @moduledoc """
  Tool registry and execution for Claude Agent.

  Provides Claude Code-like tools including:
  - File operations (Read, Write, Edit, Glob, Grep)
  - Bash command execution
  - Git operations
  - LSP integration (future)
  - MCP tools (future)
  """

  @doc """
  Returns all available tools in Claude API format.
  """
  @spec all() :: list(map())
  def all do
    [
      read_tool(),
      write_tool(),
      edit_tool(),
      bash_tool(),
      glob_tool(),
      grep_tool()
    ]
  end

  @doc """
  Execute a tool by name with the given input.
  """
  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def execute("read_file", input), do: ClaudeAgent.Tools.Read.execute(input)
  def execute("write_file", input), do: ClaudeAgent.Tools.Write.execute(input)
  def execute("edit_file", input), do: ClaudeAgent.Tools.Edit.execute(input)
  def execute("bash", input), do: ClaudeAgent.Tools.Bash.execute(input)
  def execute("glob", input), do: ClaudeAgent.Tools.Glob.execute(input)
  def execute("grep", input), do: ClaudeAgent.Tools.Grep.execute(input)
  def execute(name, _input), do: {:error, "Unknown tool: #{name}"}

  # Tool definitions

  defp read_tool do
    %{
      name: "read_file",
      description: """
      Reads a file from the filesystem and returns its contents.
      Supports line offset and limit for large files.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          file_path: %{
            type: "string",
            description: "Absolute path to the file to read"
          },
          offset: %{
            type: "integer",
            description: "Line number to start reading from (optional)"
          },
          limit: %{
            type: "integer",
            description: "Number of lines to read (optional)"
          }
        },
        required: ["file_path"]
      }
    }
  end

  defp write_tool do
    %{
      name: "write_file",
      description: """
      Writes content to a file, creating it if it doesn't exist.
      Will overwrite existing files.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          file_path: %{
            type: "string",
            description: "Absolute path to the file to write"
          },
          content: %{
            type: "string",
            description: "Content to write to the file"
          }
        },
        required: ["file_path", "content"]
      }
    }
  end

  defp edit_tool do
    %{
      name: "edit_file",
      description: """
      Performs exact string replacement in a file.
      The old_string must match exactly including whitespace.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          file_path: %{
            type: "string",
            description: "Absolute path to the file to edit"
          },
          old_string: %{
            type: "string",
            description: "Exact string to replace"
          },
          new_string: %{
            type: "string",
            description: "Replacement string"
          },
          replace_all: %{
            type: "boolean",
            description: "Replace all occurrences (default: false)"
          }
        },
        required: ["file_path", "old_string", "new_string"]
      }
    }
  end

  defp bash_tool do
    %{
      name: "bash",
      description: """
      Executes a bash command and returns the output.
      Use for git operations, npm/mix commands, etc.
      Timeout defaults to 120 seconds.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          command: %{
            type: "string",
            description: "The bash command to execute"
          },
          timeout: %{
            type: "integer",
            description: "Timeout in milliseconds (max 600000)"
          }
        },
        required: ["command"]
      }
    }
  end

  defp glob_tool do
    %{
      name: "glob",
      description: """
      Find files matching a glob pattern.
      Returns file paths sorted by modification time.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          pattern: %{
            type: "string",
            description: "Glob pattern (e.g., '**/*.ex', 'lib/**/*.exs')"
          },
          path: %{
            type: "string",
            description: "Directory to search in (optional, defaults to cwd)"
          }
        },
        required: ["pattern"]
      }
    }
  end

  defp grep_tool do
    %{
      name: "grep",
      description: """
      Search for pattern in files using regex.
      Supports multiple output modes and context lines.
      """,
      input_schema: %{
        type: "object",
        properties: %{
          pattern: %{
            type: "string",
            description: "Regular expression pattern to search for"
          },
          path: %{
            type: "string",
            description: "File or directory to search in (optional)"
          },
          glob: %{
            type: "string",
            description: "Glob pattern to filter files (e.g., '*.ex')"
          },
          output_mode: %{
            type: "string",
            enum: ["content", "files_with_matches", "count"],
            description: "Output mode (default: files_with_matches)"
          },
          context: %{
            type: "integer",
            description: "Lines of context before and after matches"
          }
        },
        required: ["pattern"]
      }
    }
  end
end
