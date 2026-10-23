defmodule SamgitaProtocolCodex.Schema.Validator do
  @moduledoc false
  alias SamgitaProtocolCodex.Error

  @keywords ~w($schema $id $comment $ref title description default definitions $defs type enum anyOf oneOf allOf properties required additionalProperties items minimum maximum exclusiveMinimum exclusiveMaximum minLength maxLength minItems maxItems uniqueItems multipleOf format pattern const)
  @metadata ~w($schema $id $comment title description default definitions $defs)
  @formats ~w(int64 int32 uint64 uint32 uint16 uint double)
  @integer_ranges %{
    "int64" => -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
    "int32" => -2_147_483_648..2_147_483_647,
    "uint64" => 0..18_446_744_073_709_551_615,
    "uint" => 0..18_446_744_073_709_551_615,
    "uint32" => 0..4_294_967_295,
    "uint16" => 0..65_535
  }

  def validate(schema, value, root \\ nil) do
    with :ok <- vocabulary(root || schema), do: check(schema, value, root || schema, [], 0)
  end

  defp vocabulary(schema) when is_boolean(schema), do: :ok

  defp vocabulary(schema) when is_map(schema) do
    every(schema, fn {key, value} -> vocabulary_entry(key, value) end)
  end

  defp vocabulary(_), do: failure(:invalid_schema, [], "schema")

  defp vocabulary_entry(key, _) when key not in @keywords,
    do: failure(:unsupported_schema_keyword, [], key)

  defp vocabulary_entry("format", value) when value not in @formats,
    do: failure(:unsupported_schema_format, [], value)

  defp vocabulary_entry(key, value) when key in ["properties", "definitions", "$defs"],
    do: every(value, fn {_, child} -> vocabulary(child) end)

  defp vocabulary_entry(key, value) when key in ["anyOf", "oneOf", "allOf"],
    do: every(value, &vocabulary/1)

  defp vocabulary_entry(key, value)
       when key in ["items", "additionalProperties"] and (is_map(value) or is_boolean(value)),
       do: vocabulary(value)

  defp vocabulary_entry(_, _), do: :ok

  defp check(_, _, _, path, depth) when depth > 256,
    do: failure(:schema_recursion_limit, path, "depth")

  defp check(true, _, _, _, _), do: :ok
  defp check(false, _, _, path, _), do: failure(:schema_violation, path, "false")

  defp check(%{"$ref" => reference}, value, root, path, depth) do
    with {:ok, target} <- resolve(root, reference),
         do: check(target, value, root, path, depth + 1)
  end

  defp check(schema, value, root, path, depth) do
    Enum.reduce_while(schema, :ok, fn {keyword, constraint}, :ok ->
      if keyword in @metadata,
        do: {:cont, :ok},
        else: next(assertion(keyword, constraint, schema, value, root, path, depth))
    end)
  end

  defp assertion("type", types, _, value, _, path, _) do
    if Enum.any?(List.wrap(types), &type?(&1, value)), do: :ok, else: violation(path, "type")
  end

  defp assertion("enum", values, _, value, _, path, _) do
    if Enum.any?(values, &equal?(&1, value)), do: :ok, else: violation(path, "enum")
  end

  defp assertion("const", expected, _, value, _, path, _) do
    if equal?(expected, value), do: :ok, else: violation(path, "const")
  end

  defp assertion(key, choices, _, value, root, path, depth)
       when key in ["anyOf", "oneOf", "allOf"] do
    results = Enum.map(choices, &check(&1, value, root, path, depth + 1))
    count = Enum.count(results, &(&1 == :ok))

    valid =
      case key do
        "anyOf" -> count > 0
        "oneOf" -> count == 1
        "allOf" -> count == length(choices)
      end

    case Enum.find(results, fn
           {:error, %Error{code: code}} -> code != :schema_violation
           _ -> false
         end) do
      nil -> if valid, do: :ok, else: violation(path, key)
      error -> error
    end
  end

  defp assertion("required", names, _, value, _, path, _) when is_map(value) do
    if Enum.all?(names, &Map.has_key?(value, &1)), do: :ok, else: violation(path, "required")
  end

  defp assertion("properties", properties, _, value, root, path, depth) when is_map(value) do
    every(properties, fn {name, child} ->
      if Map.has_key?(value, name),
        do: check(child, value[name], root, path ++ [name], depth + 1),
        else: :ok
    end)
  end

  defp assertion("additionalProperties", extra, schema, value, root, path, depth)
       when is_map(value) do
    value
    |> Map.drop(Map.keys(Map.get(schema, "properties", %{})))
    |> every(fn {name, child} -> check(extra, child, root, path ++ [name], depth + 1) end)
  end

  defp assertion("items", child, _, value, root, path, depth) when is_list(value) do
    value
    |> Enum.with_index()
    |> every(fn {element, index} ->
      check(child, element, root, path ++ [Integer.to_string(index)], depth + 1)
    end)
  end

  defp assertion("format", format, _, value, _, path, _) when is_number(value) do
    if valid_format?(format, value), do: :ok, else: violation(path, "format")
  end

  defp assertion(key, bound, _, value, _, path, _)
       when key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"] and
              is_number(value) do
    valid =
      case key do
        "minimum" -> value >= bound
        "maximum" -> value <= bound
        "exclusiveMinimum" -> value > bound
        "exclusiveMaximum" -> value < bound
        "multipleOf" -> bound > 0 and value / bound == trunc(value / bound)
      end

    if valid, do: :ok, else: violation(path, key)
  end

  defp assertion(key, bound, _, value, _, path, _)
       when key in ["minLength", "maxLength"] and is_binary(value) do
    length = value |> String.codepoints() |> length()

    if (key == "minLength" and length >= bound) or (key == "maxLength" and length <= bound),
      do: :ok,
      else: violation(path, key)
  end

  defp assertion("pattern", pattern, _, value, _, path, _) when is_binary(value) do
    case Regex.compile(pattern, "u") do
      {:ok, regex} -> if Regex.match?(regex, value), do: :ok, else: violation(path, "pattern")
      {:error, _} -> failure(:invalid_schema, path, "pattern")
    end
  end

  defp assertion(key, bound, _, value, _, path, _)
       when key in ["minItems", "maxItems"] and is_list(value) do
    if (key == "minItems" and length(value) >= bound) or
         (key == "maxItems" and length(value) <= bound),
       do: :ok,
       else: violation(path, key)
  end

  defp assertion("uniqueItems", true, _, value, _, path, _) when is_list(value) do
    if unique?(value), do: :ok, else: violation(path, "uniqueItems")
  end

  defp assertion(_, _, _, _, _, _, _), do: :ok

  def resolve(root, "#"), do: {:ok, root}

  def resolve(root, "#/" <> pointer) do
    pointer
    |> URI.decode()
    |> String.split("/")
    |> Enum.reduce_while({:ok, root}, fn token, {:ok, node} ->
      key = token |> String.replace("~1", "/") |> String.replace("~0", "~")

      case lookup(node, key) do
        {:ok, child} -> {:cont, {:ok, child}}
        :error -> {:halt, failure(:invalid_schema_reference, [], "$ref")}
      end
    end)
  end

  def resolve(_, _), do: failure(:unsupported_schema_reference, [], "$ref")

  defp lookup(node, key) when is_map(node), do: Map.fetch(node, key)

  defp lookup(node, key) when is_list(node) do
    case Integer.parse(key) do
      {index, ""} when index >= 0 -> Enum.fetch(node, index)
      _ -> :error
    end
  end

  defp lookup(_, _), do: :error
  defp valid_format?("double", _), do: true
  defp valid_format?(format, value), do: is_integer(value) and value in @integer_ranges[format]

  defp type?("object", value), do: is_map(value) and not is_struct(value)
  defp type?("array", value), do: is_list(value)
  defp type?("string", value), do: is_binary(value)
  defp type?("integer", value), do: is_integer(value)
  defp type?("number", value), do: is_number(value)
  defp type?("boolean", value), do: is_boolean(value)
  defp type?("null", value), do: is_nil(value)
  defp type?(_, _), do: false
  defp equal?(left, right), do: left == right
  defp unique?([]), do: true
  defp unique?([first | rest]), do: not Enum.any?(rest, &equal?(first, &1)) and unique?(rest)

  defp every(values, fun),
    do: Enum.reduce_while(values, :ok, fn value, :ok -> next(fun.(value)) end)

  defp next(:ok), do: {:cont, :ok}
  defp next(error), do: {:halt, error}
  defp violation(path, keyword), do: failure(:schema_violation, path, keyword)

  defp failure(code, path, keyword),
    do: {:error, Error.new(code, %{"path" => path, "keyword" => keyword})}
end
