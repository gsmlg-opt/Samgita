defmodule Samgita.Agent.Claude do
  @moduledoc """
  Claude CLI wrapper using System.cmd.
  Uses host's existing authentication.
  """

  require Logger

  @max_backoff_ms 3_600_000

  def chat(prompt, opts \\ []) do
    command = Application.get_env(:samgita, :claude_command, "claude")
    args = build_args(prompt, opts)

    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, parse_output(output)}
      {output, _} -> handle_error(output)
    end
  end

  def backoff_ms(attempt) do
    min((60_000 * :math.pow(2, attempt)) |> round(), @max_backoff_ms)
  end

  defp build_args(prompt, opts) do
    base = ["--print", "--no-input"]
    model = if m = opts[:model], do: ["--model", m], else: []
    base ++ model ++ [prompt]
  end

  defp handle_error(output) do
    cond do
      String.contains?(output, "rate limit") -> {:error, :rate_limit}
      String.contains?(output, "overloaded") -> {:error, :overloaded}
      true -> {:error, output}
    end
  end

  defp parse_output(output) do
    String.trim(output)
  end
end
