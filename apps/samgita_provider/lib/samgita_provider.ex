defmodule SamgitaProvider do
  @moduledoc """
  Provider abstraction for LLM CLI tools.

  Wraps CLI tools (starting with Claude Code CLI) behind a unified `query/2` interface.
  Follows the Constitution's CLI-first principle: Samgita does NOT call LLM APIs directly.

  ## Configuration

      # config/config.exs
      config :samgita_provider, provider: SamgitaProvider.ClaudeCode

      # config/test.exs
      config :samgita_provider, provider: :mock
  """

  @doc """
  Send a prompt to the configured provider and return the response.

  ## Options

    * `:model` - Model name (default: "sonnet")
    * `:max_turns` - Maximum tool-use turns (default: 10)
    * `:system_prompt` - System prompt for the conversation

  ## Examples

      iex> SamgitaProvider.query("What is 2 + 2?")
      {:ok, "4"}

      iex> SamgitaProvider.query("Hello", system_prompt: "You are helpful")
      {:ok, "Hi there!"}
  """
  @spec query(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def query(prompt, opts \\ []) do
    case provider() do
      :mock -> {:ok, "mock response"}
      module -> module.query(prompt, opts)
    end
  end

  @doc "Returns the configured provider module or `:mock`."
  def provider do
    Application.get_env(:samgita_provider, :provider, SamgitaProvider.ClaudeCode)
  end
end
