defmodule SamgitaProtocol.Codec do
  @moduledoc "One validated JSON object per message. No transport framing or lifecycle is implied."
  alias SamgitaProtocol.{Error, Schema}
  @max_bytes 1_048_576

  def encode(message, opts \\ []) do
    with {:ok, _} <- Schema.validate(message) do
      binary = JSON.encode!(message)

      if byte_size(binary) <= Keyword.get(opts, :max_frame_bytes, @max_bytes),
        do: {:ok, binary},
        else: {:error, Error.new("invalid_message")}
    end
  end

  def decode(binary, opts \\ [])

  def decode(binary, opts) when is_binary(binary) do
    if byte_size(binary) > Keyword.get(opts, :max_frame_bytes, @max_bytes) do
      {:error, Error.new("invalid_message")}
    else
      case JSON.decode(binary) do
        {:ok, message} -> Schema.validate(message)
        {:error, _} -> {:error, Error.new("parse_error")}
      end
    end
  end

  def decode(_, _), do: {:error, Error.new("invalid_message")}
end
