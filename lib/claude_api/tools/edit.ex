defmodule ClaudeAPI.Tools.Edit do
  @moduledoc """
  Edit files with exact string replacement.
  """

  @doc """
  Performs exact string replacement in a file.

  ## Examples

      iex> ClaudeAPI.Tools.Edit.execute(%{
      ...>   "file_path" => "/tmp/test.txt",
      ...>   "old_string" => "old text",
      ...>   "new_string" => "new text"
      ...> })
      {:ok, "File edited: /tmp/test.txt"}

      iex> ClaudeAPI.Tools.Edit.execute(%{
      ...>   "file_path" => "/tmp/test.txt",
      ...>   "old_string" => "replace me",
      ...>   "new_string" => "replaced",
      ...>   "replace_all" => true
      ...> })
      {:ok, "File edited: /tmp/test.txt (3 replacements)"}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"file_path" => path, "old_string" => old_str, "new_string" => new_str} = input) do
    replace_all = Map.get(input, "replace_all", false)

    with {:ok, content} <- File.read(path),
         {:ok, new_content, count} <- replace_string(content, old_str, new_str, replace_all),
         :ok <- File.write(path, new_content) do
      if count > 1 do
        {:ok, "File edited: #{path} (#{count} replacements)"}
      else
        {:ok, "File edited: #{path}"}
      end
    else
      {:error, :not_found} ->
        {:error, "String not found in file: #{old_str}"}

      {:error, :multiple_matches} ->
        {:error, "Multiple matches found. Use replace_all: true or provide more context"}

      {:error, reason} ->
        {:error, "Failed to edit file: #{inspect(reason)}"}
    end
  end

  defp replace_string(content, old_str, new_str, replace_all) do
    case {String.split(content, old_str, parts: :infinity), replace_all} do
      {[_], _} ->
        # No matches
        {:error, :not_found}

      {[_, _], _} ->
        # Exactly one match
        {:ok, String.replace(content, old_str, new_str, global: false), 1}

      {parts, true} ->
        # Multiple matches, replace all
        count = length(parts) - 1
        {:ok, Enum.join(parts, new_str), count}

      {_parts, false} ->
        # Multiple matches, but replace_all is false
        {:error, :multiple_matches}
    end
  end
end
