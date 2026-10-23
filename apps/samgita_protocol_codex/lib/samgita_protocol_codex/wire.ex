defmodule SamgitaProtocolCodex.Wire do
  @moduledoc """
  Lossless native JSON envelopes for the pinned Codex app-server.

  Unknown string keys and values survive encoding. Missing fields stay missing;
  explicit null stays `nil`. This layer validates envelopes, not method schemas.
  No JSON value becomes an atom. Bounds default to 16 MiB and 64 nesting levels.
  """

  alias SamgitaProtocolCodex.Error

  @default_bytes 16 * 1024 * 1024
  @default_depth 64
  @min_id -9_223_372_036_854_775_808
  @max_id 9_223_372_036_854_775_807

  def encode(message, opts \\ []) do
    with :ok <- validate_value(message, opts),
         :ok <- envelope(message) do
      binary = JSON.encode!(message)

      if byte_size(binary) <= Keyword.get(opts, :max_bytes, @default_bytes),
        do: {:ok, binary},
        else: error(:message_too_large)
    end
  rescue
    _ -> error(:invalid_json)
  end

  def decode(binary, opts \\ [])

  def decode(binary, opts) when is_binary(binary) do
    with :ok <- binary_bounds(binary, opts),
         {:ok, message} <- parse(binary),
         :ok <- validate_value(message, opts),
         :ok <- envelope(message) do
      {:ok, message}
    end
  end

  def decode(_, _), do: error(:invalid_json)

  @doc "Classify a valid native envelope; malformed or ambiguous shapes are invalid."
  def classify(message) when is_map(message) and not is_struct(message) do
    method? = Map.has_key?(message, "method")
    id? = Map.has_key?(message, "id")
    result? = Map.has_key?(message, "result")
    error? = Map.has_key?(message, "error")

    classify_shape({method?, id?, result?, error?}, message)
  end

  def classify(_), do: :invalid

  defp classify_shape({true, true, false, false}, message) do
    valid =
      valid_method?(message["method"]) and valid_id?(message["id"]) and
        valid_trace?(Map.get(message, "trace"))

    if valid, do: :request, else: :invalid
  end

  defp classify_shape({true, false, false, false}, message),
    do: if(valid_method?(message["method"]), do: :notification, else: :invalid)

  defp classify_shape({false, true, true, false}, message),
    do: if(valid_id?(message["id"]), do: :response, else: :invalid)

  defp classify_shape({false, true, false, true}, message),
    do:
      if(valid_id?(message["id"]) and valid_error?(message["error"]),
        do: :error,
        else: :invalid
      )

  defp classify_shape(_, _), do: :invalid
  defp valid_method?(method), do: is_binary(method) and String.valid?(method)

  @doc false
  def validate_value(value, opts \\ []) do
    json_value(value, Keyword.get(opts, :max_depth, @default_depth))
  rescue
    _ -> error(:invalid_json)
  end

  defp envelope(message) do
    if classify(message) == :invalid, do: error(:invalid_envelope), else: :ok
  end

  defp valid_id?(id) when is_integer(id), do: id >= @min_id and id <= @max_id
  defp valid_id?(id) when is_binary(id), do: String.valid?(id)
  defp valid_id?(_), do: false

  defp valid_trace?(nil), do: true

  defp valid_trace?(trace) when is_map(trace) and not is_struct(trace) do
    Enum.all?(["traceparent", "tracestate"], fn key ->
      is_nil(trace[key]) or (is_binary(trace[key]) and String.valid?(trace[key]))
    end)
  end

  defp valid_trace?(_), do: false

  defp valid_error?(%{"code" => code, "message" => message} = error)
       when is_map(error) and not is_struct(error) do
    is_integer(code) and code >= @min_id and code <= @max_id and is_binary(message) and
      String.valid?(message)
  end

  defp valid_error?(_), do: false

  defp json_value(_, depth) when depth < 0, do: error(:message_too_deep)
  defp json_value(value, _) when value in [nil, true, false], do: :ok
  defp json_value(value, _) when is_integer(value) or is_float(value), do: :ok

  defp json_value(value, _) when is_binary(value) do
    if String.valid?(value), do: :ok, else: error(:invalid_json)
  end

  defp json_value(value, depth) when is_list(value) do
    Enum.reduce_while(value, :ok, fn element, :ok -> continue(json_value(element, depth - 1)) end)
  end

  defp json_value(value, depth) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, :ok, fn
      {key, child}, :ok when is_binary(key) ->
        case json_value(key, depth - 1) do
          :ok -> continue(json_value(child, depth - 1))
          error -> {:halt, error}
        end

      _, :ok ->
        {:halt, error(:invalid_json)}
    end)
  end

  defp json_value(_, _), do: error(:invalid_json)
  defp continue(:ok), do: {:cont, :ok}
  defp continue(error), do: {:halt, error}

  defp binary_bounds(binary, opts) do
    if byte_size(binary) > Keyword.get(opts, :max_bytes, @default_bytes),
      do: error(:message_too_large),
      else: nesting(binary, false, false, 0, Keyword.get(opts, :max_depth, @default_depth))
  end

  # Bound nesting before calling the JSON decoder, including adversarial inputs.
  defp nesting(<<>>, _, _, _, _), do: :ok
  defp nesting(_, _, _, depth, limit) when depth > limit + 1, do: error(:message_too_deep)

  defp nesting(<<_, rest::binary>>, true, true, depth, limit),
    do: nesting(rest, true, false, depth, limit)

  defp nesting(<<92, rest::binary>>, true, false, depth, limit),
    do: nesting(rest, true, true, depth, limit)

  defp nesting(<<34, rest::binary>>, quoted, false, depth, limit),
    do: nesting(rest, not quoted, false, depth, limit)

  defp nesting(<<char, rest::binary>>, false, false, depth, limit) when char in [123, 91],
    do: nesting(rest, false, false, depth + 1, limit)

  defp nesting(<<char, rest::binary>>, false, false, depth, limit) when char in [125, 93],
    do: nesting(rest, false, false, depth - 1, limit)

  defp nesting(<<_, rest::binary>>, quoted, escaped, depth, limit),
    do: nesting(rest, quoted, escaped, depth, limit)

  defp parse(binary) do
    decoders = [
      object_start: fn _ -> %{} end,
      object_push: fn key, value, object ->
        if Map.has_key?(object, key), do: raise(ArgumentError, "duplicate JSON key")
        Map.put(object, key, value)
      end,
      object_finish: fn object, accumulator -> {object, accumulator} end
    ]

    case JSON.decode(binary, nil, decoders) do
      {value, _, rest} ->
        if json_whitespace?(rest), do: {:ok, value}, else: error(:invalid_json)

      {:error, _} ->
        error(:invalid_json)
    end
  rescue
    _ -> error(:invalid_json)
  end

  defp json_whitespace?(<<>>), do: true

  defp json_whitespace?(<<char, rest::binary>>) when char in [9, 10, 13, 32],
    do: json_whitespace?(rest)

  defp json_whitespace?(_), do: false

  defp error(code), do: {:error, Error.new(code)}
end
