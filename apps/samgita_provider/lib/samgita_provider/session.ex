defmodule SamgitaProvider.Session do
  @moduledoc "Struct representing a provider session and its accumulated state."

  @type t :: %__MODULE__{
          id: binary(),
          provider: module(),
          system_prompt: String.t(),
          model: String.t(),
          opts: keyword(),
          state: any(),
          message_count: non_neg_integer(),
          total_tokens: non_neg_integer(),
          started_at: DateTime.t()
        }

  defstruct [
    :id,
    :provider,
    :system_prompt,
    :model,
    :opts,
    :state,
    :started_at,
    message_count: 0,
    total_tokens: 0
  ]

  @doc """
  Creates a new session with a generated UUID and the current UTC timestamp.

  ## Parameters

    - `provider` — the module atom of the provider implementation
    - `system_prompt` — the system prompt string for this session
    - `opts` — keyword list of additional options; `:model` (default `"sonnet"`) is extracted here

  """
  @spec new(module(), String.t(), keyword()) :: t()
  def new(provider, system_prompt, opts \\ []) do
    {model, remaining_opts} = Keyword.pop(opts, :model, "sonnet")

    %__MODULE__{
      id: generate_id(),
      provider: provider,
      system_prompt: system_prompt,
      model: model,
      opts: remaining_opts,
      state: nil,
      message_count: 0,
      total_tokens: 0,
      started_at: DateTime.utc_now()
    }
  end

  @doc "Returns the session with `message_count` incremented by 1."
  @spec increment_message_count(t()) :: t()
  def increment_message_count(%__MODULE__{} = session) do
    %{session | message_count: session.message_count + 1}
  end

  @doc "Returns the session with `total_tokens` increased by `count`."
  @spec add_tokens(t(), non_neg_integer()) :: t()
  def add_tokens(%__MODULE__{} = session, count) do
    %{session | total_tokens: session.total_tokens + count}
  end

  # Generates a random UUID v4 string using :crypto, without requiring an external library.
  # Bit layout (128 bits total): time_low(32) + time_mid(16) + version(4) + time_hi(12)
  #   + variant(2) + clock_seq(62)
  defp generate_id do
    <<a::32, b::16, _::4, c::12, _::2, d::62>> = :crypto.strong_rand_bytes(16)

    hex =
      <<a::32, b::16, 4::4, c::12, 2::2, d::62>>
      |> Base.encode16(case: :lower)

    <<p1::8-bytes, p2::4-bytes, p3::4-bytes, p4::4-bytes, p5::12-bytes>> = hex
    "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
  end
end
