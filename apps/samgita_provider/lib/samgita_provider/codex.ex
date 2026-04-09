defmodule SamgitaProvider.Codex do
  @moduledoc """
  OpenAI Codex CLI provider implementation.

  Invokes the `codex` CLI via `System.cmd/3` in full-auto mode
  with plain-text output. Model selection is mapped to reasoning
  effort levels via the `CODEX_MODEL_REASONING_EFFORT` env var.
  """

  @behaviour SamgitaProvider.Provider

  require Logger

  @default_timeout 300_000

  @impl true
  def query(prompt, opts \\ []) do
    command = Application.get_env(:samgita_provider, :codex_command, "codex")
    args = build_args(prompt, opts)
    model = to_string(opts[:model] || "sonnet")
    timeout = opts[:timeout] || @default_timeout
    working_dir = opts[:working_directory]

    Logger.debug("Codex CLI: #{command} #{Enum.join(args, " ")}")

    cmd_opts = build_cmd_opts(model, working_dir)
    task = Task.async(fn -> execute_codex_command(command, args, cmd_opts) end)
    await_task_result(task, timeout)
  end

  defp build_cmd_opts(model, working_dir) do
    [stderr_to_stdout: true, env: cmd_env(model)]
    |> maybe_add_cd(working_dir)
  end

  defp execute_codex_command(command, args, cmd_opts) do
    case System.cmd(command, args, cmd_opts) do
      {output, 0} ->
        handle_success_output(output)

      {output, exit_code} ->
        handle_error_output(output, exit_code)
    end
  rescue
    e in ErlangError ->
      handle_erlang_error(e)
  end

  defp handle_success_output(output) do
    text = String.trim(output)

    if text == "" do
      {:error, :empty_response}
    else
      {:ok, text}
    end
  end

  defp handle_error_output(output, exit_code) do
    Logger.error("Codex CLI exited with code #{exit_code}: #{String.slice(output, 0, 500)}")

    classify_error(output, exit_code)
  end

  defp handle_erlang_error(e) do
    case e do
      %ErlangError{original: :enoent} ->
        {:error, :codex_not_found}

      _ ->
        Logger.error("Codex CLI error: #{inspect(e)}")
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
    args = ["exec", "--full-auto"]

    args =
      case opts[:working_directory] do
        nil -> args
        dir -> args ++ ["--writable-root", dir]
      end

    # Codex doesn't support --system-prompt, so prepend it to the prompt
    effective_prompt =
      case opts[:system_prompt] do
        nil -> prompt
        sp -> "#{sp}\n\n#{prompt}"
      end

    args ++ [effective_prompt]
  end

  @doc false
  def effort_for_model(model) do
    case to_string(model) do
      "opus" -> "xhigh"
      "haiku" -> "low"
      _ -> "high"
    end
  end

  defp cmd_env(model) do
    [{"CODEX_MODEL_REASONING_EFFORT", effort_for_model(model)}]
  end

  defp maybe_add_cd(opts, nil), do: opts
  defp maybe_add_cd(opts, dir), do: Keyword.put(opts, :cd, dir)

  defp classify_error(output, _exit_code) do
    cond do
      String.contains?(output, "rate limit") or String.contains?(output, "rate_limit") ->
        {:error, :rate_limit}

      String.contains?(output, "overloaded") ->
        {:error, :overloaded}

      String.contains?(output, "not found") or String.contains?(output, "ENOENT") ->
        {:error, :codex_not_found}

      true ->
        {:error, String.trim(output)}
    end
  end
end
