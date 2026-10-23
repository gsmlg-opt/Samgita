defmodule SamgitaProtocolCodex.Schema.Gates do
  @moduledoc false
  alias SamgitaProtocolCodex.Error
  alias SamgitaProtocolCodex.Schema.Validator

  @semantics_path Path.expand(
                    "../../../priv/upstream/0.163.0/source/experimental-semantics.json",
                    __DIR__
                  )
  @external_resource @semantics_path
  @semantics @semantics_path |> File.read!() |> JSON.decode!() |> Map.fetch!("types")
  @enum_gates Enum.flat_map(@semantics, fn {type, rules} ->
                Enum.map(rules["variants"], &Map.put(&1, "schema_title", &1["variant"] <> type))
              end)

  def check(full, stable, value, full_root, stable_root) do
    walk(full, stable, value, full_root, stable_root, [], 0)
  end

  defp walk(_, _, _, _, _, path, depth) when depth > 256,
    do: {:error, Error.new(:schema_recursion_limit, %{"path" => path})}

  defp walk(%{"$ref" => reference}, stable, value, full_root, stable_root, path, depth) do
    with {:ok, target} <- Validator.resolve(full_root, reference) do
      walk(target, stable, value, full_root, stable_root, path, depth + 1)
    end
  end

  defp walk(full, %{"$ref" => reference}, value, full_root, stable_root, path, depth) do
    with {:ok, target} <- Validator.resolve(stable_root, reference) do
      walk(full, target, value, full_root, stable_root, path, depth + 1)
    end
  end

  defp walk(full, stable, value, full_root, stable_root, path, depth)
       when is_map(full) and is_map(stable) do
    with :ok <- enum_variant(full, value, path),
         :ok <- properties(full, stable, value, full_root, stable_root, path, depth),
         :ok <- alternatives(full, stable, value, full_root, stable_root, path, depth) do
      items(full, stable, value, full_root, stable_root, path, depth)
    end
  end

  defp walk(_, nil, _, _, _, path, _), do: gated(path)
  defp walk(_, _, _, _, _, _, _), do: :ok

  defp items(%{"items" => child_schema}, stable, value, full_root, stable_root, path, depth)
       when is_list(value) and is_map(child_schema) do
    value
    |> Enum.with_index()
    |> every(fn {child, index} ->
      walk(
        child_schema,
        Map.get(stable, "items", true),
        child,
        full_root,
        stable_root,
        path ++ [Integer.to_string(index)],
        depth + 1
      )
    end)
  end

  defp items(_, _, _, _, _, _, _), do: :ok

  defp properties(full, stable, value, full_root, stable_root, path, depth) when is_map(value) do
    full_properties = Map.get(full, "properties", %{})
    stable_properties = Map.get(stable, "properties", %{})

    every(full_properties, fn {name, child} ->
      cond do
        not Map.has_key?(value, name) ->
          :ok

        not Map.has_key?(stable_properties, name) ->
          field_gate(field_rule(full, full_root, name), value[name], path ++ [name])

        true ->
          walk(
            child,
            stable_properties[name],
            value[name],
            full_root,
            stable_root,
            path ++ [name],
            depth + 1
          )
      end
    end)
  end

  defp properties(_, _, _, _, _, _, _), do: :ok

  defp field_gate(nil, _, path),
    do: {:error, Error.new(:unverified_experimental_semantics, %{"path" => path})}

  defp field_gate(rule, value, path),
    do: if(active?(rule["presence"], value), do: gated(path), else: :ok)

  defp alternatives(full, stable, value, full_root, stable_root, path, depth) do
    every(["anyOf", "oneOf", "allOf"], fn keyword ->
      choices = Map.get(full, keyword, [])
      older = Map.get(stable, keyword, [])

      choices
      |> Enum.filter(&(keyword == "allOf" or candidate?(&1, value, full_root)))
      |> every(fn choice ->
        previous = Enum.find(older, &same_variant?(choice, &1))
        walk(choice, previous, value, full_root, stable_root, path, depth + 1)
      end)
    end)
  end

  defp candidate?(schema, value, root), do: Validator.validate(schema, value, root) == :ok

  defp field_rule(schema, root, name) do
    own = get_in(@semantics, [schema["title"], "fields", name])

    own ||
      Enum.find_value(Map.get(root, "definitions", %{}), fn {type, definition} ->
        if definition == schema, do: get_in(@semantics, [type, "fields", name])
      end)
  end

  defp enum_variant(schema, value, path) do
    gated? =
      Enum.any?(@enum_gates, fn rule ->
        schema["title"] == rule["schema_title"] or
          (is_binary(rule["tag"]) and is_map(value) and
             get_in(schema, ["properties", rule["tag"], "enum"]) == [rule["wire_name"]] and
             value[rule["tag"]] == rule["wire_name"])
      end)

    if gated?, do: gated(path), else: :ok
  end

  defp active?("non_null", value), do: not is_nil(value)
  defp active?("non_null_nonempty_string", value), do: value not in [nil, ""]
  defp active?("true", value), do: value == true
  defp active?("nonempty_collection", value), do: value not in [[], %{}]
  defp active?("nested", _), do: false
  defp active?("present", _), do: true

  defp same_variant?(choice, previous) when is_map(choice) and is_map(previous) do
    cond do
      choice == previous -> true
      choice["$ref"] -> choice["$ref"] == previous["$ref"]
      choice["title"] -> choice["title"] == previous["title"]
      choice["type"] -> choice["type"] == previous["type"]
      true -> false
    end
  end

  defp same_variant?(choice, previous), do: choice == previous

  defp every(values, fun),
    do:
      Enum.reduce_while(values, :ok, fn value, :ok ->
        case fun.(value) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

  defp gated(path), do: {:error, Error.new(:experimental_api_required, %{"path" => path})}
end
