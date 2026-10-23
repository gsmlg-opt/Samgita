defmodule SamgitaProtocolCodex.Schema.Validator do
  @moduledoc false
  alias SamgitaProtocolCodex.Failure

  @keywords ~w($schema $id $comment $ref title description default definitions $defs type enum anyOf oneOf allOf properties required additionalProperties items minimum maximum exclusiveMinimum exclusiveMaximum minLength maxLength minItems maxItems uniqueItems multipleOf format pattern const)
  @metadata ~w($schema $id $comment title description default definitions $defs)
  @formats ~w(int64 int32 uint64 uint32 uint16 uint double)

  def validate(schema, value, root \\ nil) do
    with :ok <- vocabulary(root || schema), do: check(schema, value, root || schema, [], 0)
  end

  defp vocabulary(schema) when is_boolean(schema), do: :ok

  defp vocabulary(schema) when is_map(schema) do
    Enum.reduce_while(schema, :ok, fn {key, value}, :ok ->
      cond do
        key not in @keywords ->
          {:halt, failure(:unsupported_schema_keyword, [], key)}

        key == "format" and value not in @formats ->
          {:halt, failure(:unsupported_schema_format, [], value)}

        key in ["properties", "definitions", "$defs"] ->
          next(Enum.reduce_while(value, :ok, fn {_, child}, :ok -> next(vocabulary(child)) end))

        key in ["anyOf", "oneOf", "allOf"] ->
          next(every(value, &vocabulary/1))

        key in ["items", "additionalProperties"] and (is_map(value) or is_boolean(value)) ->
          next(vocabulary(value))

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp vocabulary(_), do: failure(:invalid_schema, [], "schema")

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
           {:error, %Failure{code: code}} -> code != :schema_violation
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
    valid =
      case format do
        "int64" ->
          is_integer(value) and value >= -9_223_372_036_854_775_808 and
            value <= 9_223_372_036_854_775_807

        "int32" ->
          is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647

        "uint64" ->
          is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615

        "uint" ->
          is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615

        "uint32" ->
          is_integer(value) and value >= 0 and value <= 4_294_967_295

        "uint16" ->
          is_integer(value) and value >= 0 and value <= 65_535

        "double" ->
          true
      end

    if valid, do: :ok, else: violation(path, "format")
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

      lookup =
        cond do
          is_map(node) ->
            Map.fetch(node, key)

          is_list(node) ->
            case Integer.parse(key) do
              {index, ""} when index >= 0 -> Enum.fetch(node, index)
              _ -> :error
            end

          true ->
            :error
        end

      case lookup do
        {:ok, child} -> {:cont, {:ok, child}}
        :error -> {:halt, failure(:invalid_schema_reference, [], "$ref")}
      end
    end)
  end

  def resolve(_, _), do: failure(:unsupported_schema_reference, [], "$ref")

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
    do: {:error, Failure.new(code, %{"path" => path, "keyword" => keyword})}
end
