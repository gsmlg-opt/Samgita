defmodule Samgita.Agent.Claude do
  @moduledoc """
  Claude integration using ClaudeAgentSDK with full tool support.
  Provides read_file, write_file, edit_file, bash, glob, and grep tools.
  """

  require Logger

  @max_backoff_ms 3_600_000

  def chat(prompt, opts \\ []) do
    model = to_string(opts[:model] || "sonnet")

    # Build options with tools enabled and permissions bypassed
    sdk_opts = %ClaudeAgentSDK.Options{
      model: model,
      max_turns: 10,
      permission_mode: :bypass_permissions,
      system_prompt: "You are a helpful AI assistant with access to file operations and shell commands."
    }

    try do
      # Execute query and collect all assistant responses
      response =
        ClaudeAgentSDK.query(prompt, sdk_opts, nil)
        |> Enum.reduce("", fn msg, acc ->
          case msg.type do
            :assistant ->
              text = ClaudeAgentSDK.ContentExtractor.extract_text(msg)
              # Unescape newlines for proper formatting
              unescaped = String.replace(text || "", "\\n", "\n")
              acc <> unescaped

            _ ->
              acc
          end
        end)
        |> String.trim()

      {:ok, response}
    rescue
      e ->
        Logger.error("Claude SDK error: #{inspect(e)}")
        handle_error(Exception.message(e))
    end
  end

  def backoff_ms(attempt) do
    min((60_000 * :math.pow(2, attempt)) |> round(), @max_backoff_ms)
  end

  defp handle_error(message) do
    cond do
      String.contains?(message, "rate limit") or String.contains?(message, "rate_limit") ->
        {:error, :rate_limit}

      String.contains?(message, "overloaded") ->
        {:error, :overloaded}

      true ->
        {:error, message}
    end
  end
end
