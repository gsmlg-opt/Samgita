defmodule ClaudeAgent.Tools.Bash do
  @moduledoc """
  Execute bash commands.
  """

  @default_timeout 120_000
  @max_timeout 600_000

  @doc """
  Executes a bash command and returns the output.

  ## Examples

      iex> ClaudeAgent.Tools.Bash.execute(%{"command" => "echo 'hello'"})
      {:ok, "hello\\n"}

      iex> ClaudeAgent.Tools.Bash.execute(%{
      ...>   "command" => "sleep 5 && echo done",
      ...>   "timeout" => 10000
      ...> })
      {:ok, "done\\n"}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"command" => command} = input) do
    timeout = min(Map.get(input, "timeout", @default_timeout), @max_timeout)

    # Run command with timeout
    task =
      Task.async(fn ->
        case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, exit_code} -> {:error, {:exit_code, exit_code, output}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, output}} ->
        {:ok, output}

      {:ok, {:error, {:exit_code, code, output}}} ->
        {:error, "Command exited with code #{code}:\n#{output}"}

      nil ->
        {:error, "Command timed out after #{timeout}ms"}
    end
  rescue
    e ->
      {:error, "Failed to execute command: #{Exception.message(e)}"}
  end
end
