defmodule SamgitaProtocolCodex.MergeStrategyInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @methods ["config/value/write", "config/batchWrite"]
  @profiles [[], [experimental: true]]
  @forms [
    {%{"replace" => nil}, ~s({"replace":null})},
    {%{"replace" => %{}}, ~s({"replace":{}})},
    {%{"upsert" => nil}, ~s({"upsert":null})},
    {%{"upsert" => %{}}, ~s({"upsert":{}})}
  ]
  @canonical %{"enum" => ["replace", "upsert"], "type" => "string"}
  @paths [
    {"config/batchWrite", ["edits", "[]", "mergeStrategy"]},
    {"config/value/write", ["mergeStrategy"]}
  ]

  test "four native strategy objects preserve maps and literal bytes on both standard paths" do
    for method <- @methods, {object, literal} <- @forms, opts <- @profiles do
      params = params(method, object)

      params_bytes =
        case method do
          "config/value/write" ->
            ~s({"keyPath":"desktop","mergeStrategy":#{literal},"value":{"appearanceTheme":"light"}})

          "config/batchWrite" ->
            ~s({"edits":[{"keyPath":"desktop","mergeStrategy":#{literal},"value":{"appearanceTheme":"light"}}]})
        end

      bytes = ~s({"id":"owned-merge-unit","method":"#{method}","params":#{params_bytes}})
      wire = %{"id" => "owned-merge-unit", "method" => method, "params" => params}
      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request(method, params, opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw exports keep the canonical string enum and exactly two stable and full input paths" do
    for profile <- ["stable", "experimental"] do
      document = read(profile, "ClientRequest.json")
      assert strategy_paths(document) === @paths
      assert document["definitions"]["MergeStrategy"] === @canonical

      for {method, owner, path} <- [
            {"config/value/write", "ConfigValueWriteParams", ["mergeStrategy"]},
            {"config/batchWrite", "ConfigBatchWriteParams", ["edits", "[]", "mergeStrategy"]}
          ] do
        standalone = read(profile, "v2/#{owner}.json")
        assert standalone["definitions"]["MergeStrategy"] === @canonical

        assert field_at(document["definitions"][owner], path, document) === %{
                 "$ref" => "#/definitions/MergeStrategy"
               }

        assert field_at(standalone, path, standalone) === %{
                 "$ref" => "#/definitions/MergeStrategy"
               }

        for {object, _literal} <- @forms do
          params = params(method, object)
          wire = %{"id" => "owned-merge-export", "method" => method, "params" => params}
          assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

          assert {:error, %Error{code: :schema_violation}} =
                   Validator.validate(standalone, params)
        end
      end

      assert document["definitions"]["ConfigValueWriteParams"]["required"] === [
               "keyPath",
               "mergeStrategy",
               "value"
             ]

      assert document["definitions"]["ConfigEdit"]["required"] === [
               "keyPath",
               "mergeStrategy",
               "value"
             ]

      assert document["definitions"]["ConfigBatchWriteParams"]["required"] === ["edits"]

      for name <- ["ConfigEdit", "MergeStrategy"] do
        refute File.exists?(Path.join([@root, profile, "v2/#{name}.json"]))
      end
    end
  end

  test "canonical strings remain standard while outer null or omitted strategy has no default" do
    for method <- @methods, strategy <- ["replace", "upsert"], opts <- @profiles do
      params = params(method, strategy)
      assert :ok = Schema.validate_request(method, params, opts)
      wire = %{"id" => "owned-merge-canonical", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end

    # A null unit payload selects a present strategy. The strategy field itself
    # is non-Option and required; unlike prior input families it has no default.
    for method <- @methods, opts <- @profiles do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, nil), opts)

      omitted =
        if method == "config/value/write",
          do: Map.delete(params(method, "replace"), "mergeStrategy"),
          else: %{"edits" => [Map.delete(edit("replace"), "mergeStrategy")]}

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, omitted, opts)

      assert :ok = Schema.validate_request("config/batchWrite", %{"edits" => []}, opts)
    end
  end

  test "unit strategy objects require exactly one known key and null or empty-map payload" do
    malformed_payloads =
      for key <- ["replace", "upsert"],
          payload <- [%{"extra" => nil}, [], 7, "", false],
          do: %{key => payload}

    malformed =
      [
        %{},
        %{"unknown" => nil},
        %{"Replace" => nil},
        %{"Upsert" => %{}},
        %{"replace" => nil, "upsert" => nil},
        %{"upsert" => nil, "extra" => true},
        "unknown",
        false,
        []
      ] ++ malformed_payloads

    for method <- @methods, value <- malformed, opts <- @profiles do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, value), opts)
    end
  end

  test "strategy correction preserves required enclosing fields array order and arbitrary JSON values" do
    for {object, _literal} <- @forms, opts <- @profiles do
      single = params("config/value/write", object)
      batch = params("config/batchWrite", object)

      invalid_single = [
        nil,
        [],
        Map.delete(single, "keyPath"),
        Map.delete(single, "value"),
        Map.put(single, "keyPath", false),
        Map.put(single, "filePath", false),
        Map.put(single, "expectedVersion", false)
      ]

      invalid_batch = [
        nil,
        [],
        %{},
        %{"edits" => nil},
        %{"edits" => %{}},
        %{"edits" => [false]},
        %{"edits" => [Map.delete(edit(object), "keyPath")]},
        %{"edits" => [Map.delete(edit(object), "value")]},
        %{"edits" => [Map.put(edit(object), "keyPath", false)]},
        %{"edits" => [edit(object), Map.delete(edit("replace"), "mergeStrategy")]},
        Map.put(batch, "filePath", false),
        Map.put(batch, "expectedVersion", false),
        Map.put(batch, "reloadUserConfig", nil),
        Map.put(batch, "reloadUserConfig", "false")
      ]

      for invalid <- invalid_single do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("config/value/write", invalid, opts)
      end

      for invalid <- invalid_batch do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("config/batchWrite", invalid, opts)
      end

      for method <- @methods,
          value <- [nil, false, 7, "literal", ["a", nil], %{"nested" => true}] do
        params =
          if method == "config/value/write" do
            single
            |> Map.put("value", value)
            |> Map.merge(%{"filePath" => nil, "expectedVersion" => nil})
          else
            %{
              "edits" => [Map.put(edit(object), "value", value), edit("replace")],
              "filePath" => nil,
              "expectedVersion" => nil,
              "reloadUserConfig" => false
            }
          end

        # value:true in the export means unconstrained JSON, including explicit
        # null. These schema checks do not claim that every value is a valid
        # native desktop configuration or that deletion/hot reload was executed.
        assert :ok = Schema.validate_request(method, params, opts)
        wire = %{"id" => "owned-merge-values", "method" => method, "params" => params}
        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end
    end
  end

  defp edit(strategy),
    do: %{
      "keyPath" => "desktop",
      "mergeStrategy" => strategy,
      "value" => %{"appearanceTheme" => "light"}
    }

  defp params("config/value/write", strategy), do: edit(strategy)
  defp params("config/batchWrite", strategy), do: %{"edits" => [edit(strategy)]}

  defp read(profile, file),
    do: Path.join([@root, profile, file]) |> File.read!() |> JSON.decode!()

  defp field_at(node, [], _document), do: node

  defp field_at(%{"$ref" => ref}, path, document),
    do:
      field_at(
        document["definitions"][String.replace_prefix(ref, "#/definitions/", "")],
        path,
        document
      )

  defp field_at(node, ["[]" | rest], document), do: field_at(node["items"], rest, document)

  defp field_at(node, [field | rest], document),
    do: field_at(node["properties"][field], rest, document)

  defp strategy_paths(document) do
    paths =
      for branch <- document["oneOf"],
          path <- reference_paths(branch["properties"]["params"], [], MapSet.new(), document),
          method <- branch["properties"]["method"]["enum"],
          do: {method, path}

    Enum.sort(paths)
  end

  defp reference_paths(%{"$ref" => "#/definitions/MergeStrategy"}, path, _seen, _document),
    do: [path]

  defp reference_paths(%{"$ref" => ref}, path, seen, document) do
    if MapSet.member?(seen, ref),
      do: [],
      else:
        reference_paths(
          document["definitions"][String.replace_prefix(ref, "#/definitions/", "")],
          path,
          MapSet.put(seen, ref),
          document
        )
  end

  defp reference_paths(%{"properties" => properties}, path, seen, document),
    do:
      Enum.flat_map(properties, fn {key, schema} ->
        reference_paths(schema, path ++ [key], seen, document)
      end)

  defp reference_paths(%{"items" => items}, path, seen, document),
    do: reference_paths(items, path ++ ["[]"], seen, document)

  defp reference_paths(value, path, seen, document) when is_map(value),
    do: Enum.flat_map(Map.values(value), &reference_paths(&1, path, seen, document))

  defp reference_paths(value, path, seen, document) when is_list(value),
    do: Enum.flat_map(value, &reference_paths(&1, path, seen, document))

  defp reference_paths(_value, _path, _seen, _document), do: []
end
