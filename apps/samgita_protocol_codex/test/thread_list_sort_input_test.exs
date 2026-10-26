defmodule SamgitaProtocolCodex.ThreadListSortInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @values ~w(created_at updated_at recency_at section_position)
  @profiles [[], [experimental: true]]
  @forms [
    {%{"created_at" => nil}, ~s({"created_at":null})},
    {%{"created_at" => %{}}, ~s({"created_at":{}})},
    {%{"updated_at" => nil}, ~s({"updated_at":null})},
    {%{"updated_at" => %{}}, ~s({"updated_at":{}})},
    {%{"recency_at" => nil}, ~s({"recency_at":null})},
    {%{"recency_at" => %{}}, ~s({"recency_at":{}})},
    {%{"section_position" => nil}, ~s({"section_position":null})},
    {%{"section_position" => %{}}, ~s({"section_position":{}})}
  ]

  test "native list-sort objects preserve complete caller maps and literal bytes" do
    for {object, literal} <- @forms, opts <- @profiles do
      bytes =
        ~s({"id":"owned-list-sort-unit","method":"thread/list","params":{"sortKey":#{literal}}})

      wire = %{
        "id" => "owned-list-sort-unit",
        "method" => "thread/list",
        "params" => %{"sortKey" => object}
      }

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request("thread/list", wire["params"], opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "both official profiles retain the singleton graph and reject unit objects" do
    for profile <- ["stable", "experimental"] do
      document =
        Path.join([@root, profile, "ClientRequest.json"]) |> File.read!() |> JSON.decode!()

      standalone =
        Path.join([@root, profile, "v2", "ThreadListParams.json"])
        |> File.read!()
        |> JSON.decode!()

      assert document["definitions"]["ThreadSortKey"] === %{
               "enum" => @values,
               "type" => "string"
             }

      assert standalone["definitions"]["ThreadSortKey"] ===
               document["definitions"]["ThreadSortKey"]

      assert document["definitions"]["ThreadListParams"]["properties"]["sortKey"] ===
               %{
                 "anyOf" => [%{"$ref" => "#/definitions/ThreadSortKey"}, %{"type" => "null"}],
                 "description" => "Optional sort key; defaults to created_at."
               }

      assert request_methods(document, "ThreadSortKey") === ["thread/list"]

      assert standalone["properties"]["sortKey"] ===
               document["definitions"]["ThreadListParams"]["properties"]["sortKey"]

      for {object, _literal} <- @forms do
        wire = %{
          "id" => "owned-list-sort-export",
          "method" => "thread/list",
          "params" => %{"sortKey" => object}
        }

        assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

        assert {:error, %Error{code: :schema_violation}} =
                 Validator.validate(standalone, wire["params"])
      end
    end
  end

  test "standard canonical strings outer null and omission need no experimental gate" do
    for opts <- @profiles do
      for value <- [nil | @values] do
        params = %{"sortKey" => value}
        assert :ok = Schema.validate_request("thread/list", params, opts)

        wire = %{
          "id" => "owned-list-sort-canonical",
          "method" => "thread/list",
          "params" => params
        }

        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end

      assert :ok = Schema.validate_request("thread/list", %{}, opts)
    end
  end

  test "unit inputs require exactly one known key and null or empty-map payload" do
    for opts <- @profiles,
        value <- [
          %{},
          %{"unknown" => nil},
          %{"CreatedAt" => nil},
          %{"created_at" => nil, "updated_at" => nil},
          %{"section_position" => nil, "extra" => true},
          %{"created_at" => %{"extra" => nil}},
          %{"updated_at" => []},
          %{"recency_at" => 7},
          %{"section_position" => ""},
          %{"updated_at" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/list", %{"sortKey" => value}, opts)
    end
  end

  test "list-sort correction preserves enclosing constraints and ordinary field composition" do
    for {object, _literal} <- @forms do
      base = %{"sortKey" => object}

      for opts <- @profiles,
          invalid <- [%{"cwd" => false}, %{"limit" => false}, %{"archived" => "false"}] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("thread/list", Map.merge(base, invalid), opts)
      end

      params =
        Map.merge(base, %{
          "sectionId" => "owned-section",
          "sortDirection" => "asc",
          "useStateDbOnly" => true,
          "limit" => 100,
          "modelProviders" => ["fixture"]
        })

      for opts <- @profiles do
        assert :ok = Schema.validate_request("thread/list", params, opts)
      end

      wire = %{
        "id" => "owned-list-sort-composition",
        "method" => "thread/list",
        "params" => params
      }

      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  defp request_methods(document, target) do
    for branch <- document["oneOf"],
        target in references([branch["properties"]["params"]], MapSet.new(), document),
        method <- branch["properties"]["method"]["enum"],
        do: method
  end

  defp references([], seen, _document), do: seen

  defp references([value | rest], seen, document) when is_map(value) do
    reference = String.replace_prefix(Map.get(value, "$ref", ""), "#/definitions/", "")

    if reference != "" and not MapSet.member?(seen, reference) do
      references(
        [document["definitions"][reference] | Map.values(value) ++ rest],
        MapSet.put(seen, reference),
        document
      )
    else
      references(Map.values(value) ++ rest, seen, document)
    end
  end

  defp references([value | rest], seen, document) when is_list(value),
    do: references(value ++ rest, seen, document)

  defp references([_value | rest], seen, document), do: references(rest, seen, document)
end
