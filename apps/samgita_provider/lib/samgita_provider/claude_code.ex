defmodule SamgitaProvider.ClaudeCode do
  @moduledoc """
  Claude Code CLI provider implementation.

  Invokes the `claude` CLI directly via `System.cmd/3` in print mode
  with JSON output, bypassing permissions for autonomous operation.
  """

  @behaviour SamgitaProvider.Provider

  require Logger

  @default_timeout 300_000

  @impl true
  def query(prompt, opts \\ []) do
    command = Application.get_env(:samgita_provider, :claude_command, "claude")
    args = build_args(prompt, opts)
    timeout = opts[:timeout] || @default_timeout

    Logger.debug("Claude CLI: #{command} #{Enum.join(args, " ")}")

    cmd_opts = build_cmd_opts(opts[:working_directory])
    task = Task.async(fn -> execute_claude_command(command, args, cmd_opts) end)
    await_task_result(task, timeout)
  end

  defp build_cmd_opts(working_dir) do
    [stderr_to_stdout: true, env: cmd_env()]
    |> maybe_add_cd(working_dir)
  end

  defp execute_claude_command(command, args, cmd_opts) do
    case System.cmd(command, args, cmd_opts) do
      {output, 0} ->
        parse_json_output(output)

      {output, exit_code} ->
        handle_error_output(output, exit_code)
    end
  rescue
    e in ErlangError ->
      handle_erlang_error(e)
  end

  defp handle_error_output(output, exit_code) do
    Logger.error("Claude CLI exited with code #{exit_code}: #{String.slice(output, 0, 500)}")

    classify_error(output, exit_code)
  end

  defp handle_erlang_error(e) do
    case e do
      %ErlangError{original: :enoent} ->
        {:error, :claude_not_found}

      _ ->
        Logger.error("Claude CLI error: #{inspect(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp await_task_result(task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc false
  def build_args(prompt, opts) do
    model = to_string(opts[:model] || "sonnet")

    system_prompt =
      opts[:system_prompt] ||
        "You are a helpful AI assistant with access to file operations and shell commands."

    args = [
      "--print",
      "--output-format",
      "json",
      "--model",
      model,
      "--dangerously-skip-permissions",
      "--system-prompt",
      system_prompt,
      "--no-session-persistence"
    ]

    args = maybe_add_max_turns(args, opts[:max_turns])

    # Append prompt as the positional argument
    args ++ [prompt]
  end

  defp cmd_env do
    # Pass through relevant env vars; don't override what's already set
    []
  end

  @doc false
  def parse_json_output(output) do
    case Jason.decode(output) do
      {:ok, %{"result" => result, "is_error" => false}} ->
        {:ok, result}

      {:ok, %{"result" => result, "is_error" => true}} ->
        {:error, result}

      {:ok, %{"result" => result}} ->
        {:ok, result}

      {:error, _} ->
        # If JSON parsing fails, the output might be plain text (e.g. an error message)
        classify_error(output, 1)
    end
  end

  defp maybe_add_cd(opts, nil), do: opts
  defp maybe_add_cd(opts, dir), do: Keyword.put(opts, :cd, dir)

  defp maybe_add_max_turns(args, nil), do: args

  defp maybe_add_max_turns(args, max_turns) when is_integer(max_turns) and max_turns > 0 do
    args ++ ["--max-turns", to_string(max_turns)]
  end

  defp maybe_add_max_turns(args, _invalid), do: args

  @doc false
  def classify_error(output, _exit_code \\ 1) do
    cond do
      String.contains?(output, "rate limit") or String.contains?(output, "rate_limit") ->
        {:error, :rate_limit}

      String.contains?(output, "overloaded") ->
        {:error, :overloaded}

      String.contains?(output, "not found") or String.contains?(output, "ENOENT") ->
        {:error, :claude_not_found}

      true ->
        {:error, String.trim(output)}
    end
  end
end
