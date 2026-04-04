defmodule SamgitaProvider do
  @moduledoc """
  Provider abstraction for LLM CLI tools.

  Wraps CLI tools (starting with Claude Code CLI) behind a unified `query/2` interface
  and optional session lifecycle functions for multi-turn conversations.

  Follows the Constitution's CLI-first principle: Samgita does NOT call LLM APIs directly.

  ## Configuration

      # Use Claude Code provider (default)
      config :samgita_provider, provider: SamgitaProvider.ClaudeCode

      # Use Codex provider
      config :samgita_provider, provider: SamgitaProvider.Codex

      # Use mock provider for tests (Mox-based)
      config :samgita_provider, provider: SamgitaProvider.MockProvider
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
    get_provider().query(prompt, opts)
  end

  @doc """
  Open a stateful multi-turn session with the configured provider.

  If the provider does not implement `start_session/2`, a
  `SamgitaProvider.Session` struct is created locally as a fallback.

  ## Options

    * `:model` - Model name (default: "sonnet")
    * Any additional provider-specific options
  """
  @spec start_session(String.t(), keyword()) ::
          {:ok, SamgitaProvider.Session.t()} | {:error, term()}
  def start_session(system_prompt, opts \\ []) do
    provider = get_provider()

    if function_exported?(provider, :start_session, 2) do
      provider.start_session(system_prompt, opts)
    else
      {:ok, SamgitaProvider.Session.new(provider, system_prompt, opts)}
    end
  end

  @doc """
  Send a message within an existing session.

  If the provider does not implement `send_message/2`, falls back to
  `query/2` using the session's system prompt and model as options.
  """
  @spec send_message(SamgitaProvider.Session.t(), String.t()) ::
          {:ok, String.t(), SamgitaProvider.Session.t()} | {:error, term()}
  def send_message(session, message) do
    provider = session.provider

    if function_exported?(provider, :send_message, 2) do
      provider.send_message(session, message)
    else
      opts = [system_prompt: session.system_prompt, model: session.model] ++ (session.opts || [])

      case provider.query(message, opts) do
        {:ok, response} ->
          updated = session |> SamgitaProvider.Session.increment_message_count()
          {:ok, response, updated}

        error ->
          error
      end
    end
  end

  @doc """
  Send a message and stream tokens to a subscriber pid.

  If the provider does not implement `stream_message/3`, falls back to
  `send_message/2` and delivers the full response as a single chunk via
  `{:stream_chunk, ref, response}` followed by `{:stream_done, ref}`.
  """
  @spec stream_message(SamgitaProvider.Session.t(), String.t(), pid()) ::
          {:ok, reference(), SamgitaProvider.Session.t()} | {:error, term()}
  def stream_message(session, message, subscriber) do
    provider = session.provider

    if function_exported?(provider, :stream_message, 3) do
      provider.stream_message(session, message, subscriber)
    else
      case send_message(session, message) do
        {:ok, response, updated_session} ->
          ref = make_ref()
          send(subscriber, {:stream_chunk, ref, response})
          send(subscriber, {:stream_done, ref})
          {:ok, ref, updated_session}

        error ->
          error
      end
    end
  end

  @doc """
  Release session resources.

  If the provider does not implement `close_session/1`, returns `:ok`.
  """
  @spec close_session(SamgitaProvider.Session.t()) :: :ok
  def close_session(session) do
    provider = session.provider

    if function_exported?(provider, :close_session, 1) do
      provider.close_session(session)
    else
      :ok
    end
  end

  @doc """
  Describe the configured provider's feature support and limits.

  If the provider does not implement `capabilities/0`, returns a default
  capabilities map with streaming and tools disabled.
  """
  @spec capabilities() :: map()
  def capabilities do
    provider = get_provider()

    if function_exported?(provider, :capabilities, 0) do
      provider.capabilities()
    else
      %{
        supports_streaming: false,
        supports_tools: false,
        supports_multi_turn: false,
        max_context_tokens: 200_000,
        available_models: ["sonnet"]
      }
    end
  end

  @doc """
  Assert the configured provider is reachable and operational.

  If the provider does not implement `health_check/0`, returns `:ok`.
  """
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    provider = get_provider()

    if function_exported?(provider, :health_check, 0) do
      provider.health_check()
    else
      :ok
    end
  end

  @doc "Returns the configured provider module."
  def provider do
    get_provider()
  end

  defp get_provider do
    Application.get_env(:samgita_provider, :provider, SamgitaProvider.ClaudeCode)
  end
end
