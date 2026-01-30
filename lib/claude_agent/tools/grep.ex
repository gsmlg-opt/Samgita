defmodule ClaudeAgent.Tools.Grep do
  @moduledoc """
  Search for patterns in files using regex.
  """

  @doc """
  Searches for a pattern in files.

  ## Examples

      iex> ClaudeAgent.Tools.Grep.execute(%{"pattern" => "defmodule"})
      {:ok, "lib/samgita.ex\\nlib/samgita/application.ex\\n..."}

      iex> ClaudeAgent.Tools.Grep.execute(%{
      ...>   "pattern" => "def\\s+\\w+",
      ...>   "glob" => "*.ex",
      ...>   "output_mode" => "content",
      ...>   "context" => 2
      ...> })
      {:ok, "lib/file.ex:10: def function_name do\\n..."}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"pattern" => pattern} = input) do
    path = Map.get(input, "path", ".")
    glob_pattern = Map.get(input, "glob")
    output_mode = Map.get(input, "output_mode", "files_with_matches")
    context = Map.get(input, "context", 0)

    files = get_files(path, glob_pattern)
    regex = Regex.compile!(pattern)

    case output_mode do
      "files_with_matches" ->
        search_files_with_matches(files, regex)

      "content" ->
        search_content(files, regex, context)

      "count" ->
        search_count(files, regex)

      _ ->
        {:error, "Invalid output_mode: #{output_mode}"}
    end
  rescue
    e in Regex.CompileError ->
      {:error, "Invalid regex pattern: #{e.message}"}

    e ->
      {:error, "Grep failed: #{Exception.message(e)}"}
  end

  defp get_files(path, nil) when is_binary(path) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "**/*"))
      |> Enum.filter(&File.regular?/1)
    else
      [path]
    end
  end

  defp get_files(path, glob_pattern) when is_binary(glob_pattern) do
    base = if File.dir?(path), do: path, else: Path.dirname(path)
    Path.wildcard(Path.join(base, glob_pattern))
    |> Enum.filter(&File.regular?/1)
  end

  defp search_files_with_matches(files, regex) do
    matches =
      files
      |> Enum.filter(fn file ->
        case File.read(file) do
          {:ok, content} -> Regex.match?(regex, content)
          {:error, _} -> false
        end
      end)
      |> Enum.join("\n")

    {:ok, matches}
  end

  defp search_content(files, regex, context) do
    results =
      files
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, content} ->
            lines = String.split(content, "\n")

            lines
            |> Enum.with_index(1)
            |> Enum.filter(fn {line, _} -> Regex.match?(regex, line) end)
            |> Enum.flat_map(fn {_line, line_num} ->
              get_context_lines(lines, line_num, context)
              |> Enum.map(fn {line, num} ->
                "#{file}:#{num}: #{line}"
              end)
            end)

          {:error, _} ->
            []
        end
      end)
      |> Enum.join("\n")

    {:ok, results}
  end

  defp search_count(files, regex) do
    counts =
      files
      |> Enum.map(fn file ->
        case File.read(file) do
          {:ok, content} ->
            count = length(Regex.scan(regex, content))
            "#{file}: #{count}"

          {:error, _} ->
            "#{file}: 0"
        end
      end)
      |> Enum.join("\n")

    {:ok, counts}
  end

  defp get_context_lines(lines, line_num, context) do
    start_idx = max(0, line_num - context - 1)
    end_idx = min(length(lines) - 1, line_num + context - 1)

    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.with_index(start_idx + 1)
  end
end
