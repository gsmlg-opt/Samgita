defmodule ClaudeAPI.Tools.Read do
  @moduledoc """
  Read files from the filesystem.
  """

  @doc """
  Reads a file and returns its contents with line numbers.

  ## Examples

      iex> ClaudeAPI.Tools.Read.execute(%{"file_path" => "/tmp/test.txt"})
      {:ok, "     1→line one\\n     2→line two"}

      iex> ClaudeAPI.Tools.Read.execute(%{
      ...>   "file_path" => "/tmp/test.txt",
      ...>   "offset" => 10,
      ...>   "limit" => 5
      ...> })
      {:ok, "    10→line ten\\n    11→line eleven\\n..."}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"file_path" => path} = input) do
    offset = Map.get(input, "offset", 0)
    limit = Map.get(input, "limit")

    with {:ok, content} <- File.read(path) do
      lines = String.split(content, "\n")

      formatted_lines =
        lines
        |> Enum.with_index(1)
        |> maybe_slice(offset, limit)
        |> Enum.map(fn {line, number} ->
          # Format like Claude Code: right-aligned line number + tab + content
          "#{String.pad_leading(Integer.to_string(number), 6)}→#{line}"
        end)
        |> Enum.join("\n")

      {:ok, formatted_lines}
    else
      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp maybe_slice(lines, 0, nil), do: lines

  defp maybe_slice(lines, offset, nil) when offset > 0 do
    Enum.drop(lines, offset)
  end

  defp maybe_slice(lines, 0, limit) when is_integer(limit) do
    Enum.take(lines, limit)
  end

  defp maybe_slice(lines, offset, limit) when is_integer(limit) do
    lines
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end
end
