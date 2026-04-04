defmodule SamgitaProvider.Provider do
  @moduledoc """
  Behaviour for LLM CLI provider implementations.

  The single required callback is `query/2`, which performs a stateless
  one-shot prompt/response exchange.

  Six optional callbacks extend the behaviour with session lifecycle
  management, streaming, introspection, and health-checking:

  - `start_session/2` — open a stateful multi-turn session
  - `send_message/2` — send a message within an existing session
  - `stream_message/3` — send a message and stream tokens to a subscriber pid
  - `close_session/1` — release session resources
  - `capabilities/0` — describe provider feature support and limits
  - `health_check/0` — assert the provider is reachable and operational

  Providers that do not implement an optional callback will raise
  `UndefinedFunctionError` if it is called; callers should guard with
  `function_exported?/3` when capabilities vary across providers.
  """

  @callback query(prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}

  @callback start_session(system_prompt :: String.t(), opts :: keyword()) ::
              {:ok, SamgitaProvider.Session.t()} | {:error, term()}

  @callback send_message(session :: SamgitaProvider.Session.t(), message :: String.t()) ::
              {:ok, String.t(), SamgitaProvider.Session.t()} | {:error, term()}

  @callback stream_message(
              session :: SamgitaProvider.Session.t(),
              message :: String.t(),
              subscriber :: pid()
            ) ::
              {:ok, reference(), SamgitaProvider.Session.t()} | {:error, term()}

  @callback close_session(session :: SamgitaProvider.Session.t()) :: :ok

  @callback capabilities() :: %{
              supports_streaming: boolean(),
              supports_tools: boolean(),
              supports_multi_turn: boolean(),
              max_context_tokens: pos_integer(),
              available_models: [String.t()]
            }

  @callback health_check() :: :ok | {:error, term()}

  @optional_callbacks [
    start_session: 2,
    send_message: 2,
    stream_message: 3,
    close_session: 1,
    capabilities: 0,
    health_check: 0
  ]
end
