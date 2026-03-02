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

    Logger.debug("Codex CLI: #{command} #{Enum.join(args, " ")}")

    try do
      case System.cmd(command, args,
             stderr_to_stdout: true,
             timeout: timeout,
             env: cmd_env(model)
           ) do
        {output, 0} ->
          text = String.trim(output)

          if text == "" do
            {:error, :empty_response}
          else
            {:ok, text}
          end

        {output, exit_code} ->
          Logger.error("Codex CLI exited with code #{exit_code}: #{String.slice(output, 0, 500)}")
          classify_error(output, exit_code)
      end
    rescue
      e in ErlangError ->
        case e do
          %ErlangError{original: :enoent} ->
            {:error, :codex_not_found}

          _ ->
            Logger.error("Codex CLI error: #{inspect(e)}")
            {:error, Exception.message(e)}
        end
    end
  end

  @doc false
  def build_args(prompt, _opts) do
    ["exec", "--full-auto", prompt]
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
