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
    command = claude_command()
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
    json_str = extract_json(output)

    case Jason.decode(json_str) do
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

  # stderr warnings (e.g. "Warning: no stdin data received") may be
  # prepended to stdout when using stderr_to_stdout. Strip non-JSON
  # prefix so we can parse the actual JSON payload.
  defp extract_json(output) do
    case :binary.match(output, <<"{">>) do
      {pos, _} when pos > 0 -> binary_part(output, pos, byte_size(output) - pos)
      _ -> output
    end
  end

  defp maybe_add_cd(opts, nil), do: opts
  defp maybe_add_cd(opts, dir), do: Keyword.put(opts, :cd, dir)

  defp maybe_add_max_turns(args, nil), do: args

  defp maybe_add_max_turns(args, max_turns) when is_integer(max_turns) and max_turns > 0 do
    args ++ ["--max-turns", to_string(max_turns)]
  end

  defp maybe_add_max_turns(args, _invalid), do: args

  @impl true
  def start_session(system_prompt, opts \\ []) do
    session_id = generate_session_id()

    session = SamgitaProvider.Session.new(__MODULE__, system_prompt, opts)
    session = %{session | id: session_id, state: %{session_id: session_id}}

    {:ok, session}
  end

  @impl true
  def send_message(%SamgitaProvider.Session{} = session, message) do
    command = claude_command()
    session_id = session.state.session_id
    is_resume = session.message_count > 0

    args =
      build_session_args(message, session.model, session.system_prompt, session_id, is_resume)

    args = maybe_add_max_turns(args, Keyword.get(session.opts || [], :max_turns))

    cmd_opts = build_cmd_opts(Keyword.get(session.opts || [], :working_directory))

    Logger.debug("Claude CLI session #{session_id}: #{command} #{Enum.join(args, " ")}")

    task = Task.async(fn -> execute_claude_command(command, args, cmd_opts) end)

    case await_task_result(task, @default_timeout) do
      {:ok, result} ->
        updated = SamgitaProvider.Session.increment_message_count(session)
        {:ok, result, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def close_session(%SamgitaProvider.Session{} = _session) do
    # Claude CLI sessions are file-based; no explicit cleanup needed
    :ok
  end

  @impl true
  def capabilities do
    %{
      supports_streaming: false,
      supports_tools: true,
      supports_multi_turn: true,
      max_context_tokens: 200_000,
      available_models: ["opus", "sonnet", "haiku"]
    }
  end

  @impl true
  def health_check do
    case System.cmd(claude_command(), ["--version"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> {:error, output}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc false
  def build_session_args(prompt, model, system_prompt, session_id, is_resume) do
    args = [
      "--print",
      "--output-format",
      "json",
      "--model",
      to_string(model),
      "--session-id",
      session_id,
      "--dangerously-skip-permissions"
    ]

    args = if is_resume, do: args ++ ["--resume"], else: args

    args =
      if !is_resume and system_prompt,
        do: args ++ ["--system-prompt", system_prompt],
        else: args

    # Prompt is always last
    args ++ [prompt]
  end

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

  defp claude_command do
    Application.get_env(:samgita_provider, :claude_command, "claude")
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
