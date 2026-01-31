defmodule ClaudeAgent.Tools.Glob do
  @moduledoc """
  Find files matching glob patterns.
  """

  @doc """
  Finds files matching a glob pattern.

  ## Examples

      iex> ClaudeAgent.Tools.Glob.execute(%{"pattern" => "**/*.ex"})
      {:ok, "lib/samgita.ex\\nlib/samgita/application.ex\\n..."}

      iex> ClaudeAgent.Tools.Glob.execute(%{
      ...>   "pattern" => "*.exs",
      ...>   "path" => "test"
      ...> })
      {:ok, "test/test_helper.exs\\ntest/samgita_test.exs"}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"pattern" => pattern} = input) do
    base_path = Map.get(input, "path", ".")
    full_pattern = Path.join(base_path, pattern)

    try do
      files =
        full_pattern
        |> Path.wildcard()
        |> Enum.sort_by(&file_mtime/1, :desc)
        |> Enum.map(&Path.relative_to_cwd/1)
        |> Enum.join("\n")

      {:ok, files}
    rescue
      e ->
        {:error, "Glob failed: #{Exception.message(e)}"}
    end
  end

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> {{1970, 1, 1}, {0, 0, 0}}
    end
  end
end
