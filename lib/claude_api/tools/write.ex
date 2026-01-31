defmodule ClaudeAgent.Tools.Write do
  @moduledoc """
  Write files to the filesystem.
  """

  @doc """
  Writes content to a file, creating directories if needed.

  ## Examples

      iex> ClaudeAgent.Tools.Write.execute(%{
      ...>   "file_path" => "/tmp/test.txt",
      ...>   "content" => "Hello, world!"
      ...> })
      {:ok, "File written: /tmp/test.txt"}
  """
  @spec execute(map()) :: {:ok, String.t()} | {:error, term()}
  def execute(%{"file_path" => path, "content" => content}) do
    # Ensure directory exists
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, content) do
      {:ok, "File written: #{path}"}
    else
      {:error, reason} ->
        {:error, "Failed to write file: #{inspect(reason)}"}
    end
  end
end
