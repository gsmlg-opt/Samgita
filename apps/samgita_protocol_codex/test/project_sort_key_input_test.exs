defmodule SamgitaProtocolCodex.ProjectSortKeyInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @forms [
    {%{"position" => nil}, ~s({"position":null})},
    {%{"position" => %{}}, ~s({"position":{}})},
    {%{"recencyAt" => nil}, ~s({"recencyAt":null})},
    {%{"recencyAt" => %{}}, ~s({"recencyAt":{}})}
  ]

  test "four project key objects preserve complete caller maps and literal bytes" do
    for {object, literal} <- @forms do
      params = %{"sortKey" => object}
      wire = %{"id" => "owned-project-key-unit", "method" => "project/list", "params" => params}

      bytes =
        ~s({"id":"owned-project-key-unit","method":"project/list","params":{"sortKey":#{literal}}})

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request("project/list", params, experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw exports retain string keys and the exact singleton full input graph" do
    full = read("experimental", "ClientRequest.json")
    stable = read("stable", "ClientRequest.json")
    standalone = read("experimental", "v2/ProjectListParams.json")

    for document <- [full, stable, standalone] do
      assert document["definitions"]["ProjectSortKey"] === %{
               "enum" => ["position", "recencyAt"],
               "type" => "string"
             }
    end

    expected_field = %{
      "anyOf" => [%{"$ref" => "#/definitions/ProjectSortKey"}, %{"type" => "null"}],
      "description" => "Defaults to position. Recency sorting always places empty projects last."
    }

    assert full["definitions"]["ProjectListParams"]["properties"]["sortKey"] === expected_field
    assert standalone["properties"]["sortKey"] === expected_field
    assert key_paths(full) === [{"project/list", ["sortKey"]}]
    assert key_paths(stable) === []
    refute Map.has_key?(stable["definitions"], "ProjectListParams")
    refute File.exists?(Path.join([@root, "stable", "v2/ProjectListParams.json"]))

    for {object, _literal} <- @forms do
      params = %{"sortKey" => object}
      wire = %{"id" => "owned-project-key-export", "method" => "project/list", "params" => params}
      assert {:error, %Error{code: :schema_violation}} = Validator.validate(full, wire)
      assert {:error, %Error{code: :schema_violation}} = Validator.validate(standalone, params)
    end
  end

  test "canonical keys outer null omission and object forms retain the experimental method gate" do
    params = [%{}, %{"sortKey" => nil}, %{"sortKey" => "position"}, %{"sortKey" => "recencyAt"}]

    for value <- params ++ Enum.map(@forms, fn {object, _literal} -> %{"sortKey" => object} end) do
      assert :ok = Schema.validate_request("project/list", value, experimental: true)

      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("project/list", value)

      wire = %{
        "id" => "owned-project-key-canonical",
        "method" => "project/list",
        "params" => value
      }

      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "key unit objects require one known key and null or empty-map payload" do
    for value <- [
          %{},
          %{"unknown" => nil},
          %{"Position" => nil},
          %{"recency_at" => nil},
          %{"position" => nil, "recencyAt" => nil},
          %{"position" => nil, "extra" => true},
          %{"position" => %{"extra" => nil}},
          %{"recencyAt" => []},
          %{"position" => 7},
          %{"recencyAt" => ""},
          %{"position" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("project/list", %{"sortKey" => value}, experimental: true)
    end
  end

  test "key correction composes with directions without loosening enclosing constraints" do
    for {object, _literal} <- @forms do
      base = %{"sortKey" => object}

      for direction <- [
            nil,
            "asc",
            "desc",
            %{"asc" => nil},
            %{"asc" => %{}},
            %{"desc" => nil},
            %{"desc" => %{}}
          ] do
        params = Map.merge(base, %{"sortDirection" => direction, "limit" => 100, "cursor" => nil})
        assert :ok = Schema.validate_request("project/list", params, experimental: true)

        wire = %{
          "id" => "owned-project-key-composition",
          "method" => "project/list",
          "params" => params
        }

        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end

      for invalid <- [
            %{"limit" => false},
            %{"limit" => -1},
            %{"cursor" => false},
            %{"sortDirection" => "sideways"},
            %{"sortDirection" => %{"asc" => []}}
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("project/list", Map.merge(base, invalid),
                   experimental: true
                 )
      end
    end

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request("project/list", nil, experimental: true)

    # The cross-field rule belongs to the native handler. Outer absent/null key
    # still passes the exported schema with a direction; a present object with
    # null payload is Some(ProjectSortKey), not an absent key.
    for params <- [%{"sortDirection" => "asc"}, %{"sortKey" => nil, "sortDirection" => "desc"}] do
      assert :ok = Schema.validate_request("project/list", params, experimental: true)
    end
  end

  defp read(profile, file),
    do: Path.join([@root, profile, file]) |> File.read!() |> JSON.decode!()

  defp key_paths(document) do
    paths =
      for branch <- document["oneOf"],
          path <- reference_paths(branch["properties"]["params"], [], MapSet.new(), document),
          method <- branch["properties"]["method"]["enum"],
          do: {method, path}

    Enum.sort(paths)
  end

  defp reference_paths(%{"$ref" => "#/definitions/ProjectSortKey"}, path, _seen, _document),
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

  defp reference_paths(value, path, seen, document) when is_map(value),
    do: Enum.flat_map(Map.values(value), &reference_paths(&1, path, seen, document))

  defp reference_paths(value, path, seen, document) when is_list(value),
    do: Enum.flat_map(value, &reference_paths(&1, path, seen, document))

  defp reference_paths(_value, _path, _seen, _document), do: []
end
