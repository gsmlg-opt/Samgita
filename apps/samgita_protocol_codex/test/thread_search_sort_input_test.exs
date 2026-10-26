defmodule SamgitaProtocolCodex.ThreadSearchSortInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @values ~w(created_at updated_at recency_at)
  @forms [
    {%{"created_at" => nil}, ~s({"created_at":null})},
    {%{"created_at" => %{}}, ~s({"created_at":{}})},
    {%{"updated_at" => nil}, ~s({"updated_at":null})},
    {%{"updated_at" => %{}}, ~s({"updated_at":{}})},
    {%{"recency_at" => nil}, ~s({"recency_at":null})},
    {%{"recency_at" => %{}}, ~s({"recency_at":{}})}
  ]

  test "native search sort objects preserve complete caller maps and literal bytes" do
    for {object, literal} <- @forms do
      bytes =
        ~s({"id":"owned-search-unit","method":"thread/search","params":{"searchTerm":"Owned search","sortKey":#{literal}}})

      wire = %{
        "id" => "owned-search-unit",
        "method" => "thread/search",
        "params" => %{"searchTerm" => "Owned search", "sortKey" => object}
      }

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request("thread/search", wire["params"], experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw official contracts retain string sorts and only the full request graph reaches them" do
    full =
      Path.join([@root, "experimental", "ClientRequest.json"]) |> File.read!() |> JSON.decode!()

    stable = Path.join([@root, "stable", "ClientRequest.json"]) |> File.read!() |> JSON.decode!()

    standalone =
      Path.join([@root, "experimental", "v2", "ThreadSearchParams.json"])
      |> File.read!()
      |> JSON.decode!()

    for document <- [full, stable, standalone] do
      assert document["definitions"]["ThreadSearchSortKey"] === %{
               "enum" => @values,
               "type" => "string"
             }
    end

    expected_field = %{
      "anyOf" => [%{"$ref" => "#/definitions/ThreadSearchSortKey"}, %{"type" => "null"}],
      "description" => "Optional sort key; defaults to created_at."
    }

    assert full["definitions"]["ThreadSearchParams"]["properties"]["sortKey"] === expected_field
    assert standalone["properties"]["sortKey"] === expected_field
    assert request_methods(full, "ThreadSearchSortKey") === ["thread/search"]
    assert request_methods(stable, "ThreadSearchSortKey") === []
    refute Map.has_key?(stable["definitions"], "ThreadSearchParams")

    for {object, _literal} <- @forms do
      params = %{"searchTerm" => "Owned search", "sortKey" => object}
      wire = %{"id" => "owned-search-export", "method" => "thread/search", "params" => params}
      assert {:error, %Error{code: :schema_violation}} = Validator.validate(full, wire)
      assert {:error, %Error{code: :schema_violation}} = Validator.validate(standalone, params)
    end
  end

  test "canonical strings outer null and omission preserve the experimental method gate" do
    for value <- [nil | @values] do
      params = %{"searchTerm" => "Owned search", "sortKey" => value}
      assert :ok = Schema.validate_request("thread/search", params, experimental: true)

      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("thread/search", params)

      wire = %{"id" => "owned-search-canonical", "method" => "thread/search", "params" => params}
      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end

    params = %{"searchTerm" => "Owned search"}
    assert :ok = Schema.validate_request("thread/search", params, experimental: true)

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_request("thread/search", params)

    for {object, _literal} <- @forms do
      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("thread/search", Map.put(params, "sortKey", object))
    end
  end

  test "search sort objects require one known key and null or empty-map payload" do
    for value <- [
          %{},
          %{"unknown" => nil},
          %{"CreatedAt" => nil},
          %{"created_at" => nil, "updated_at" => nil},
          %{"recency_at" => nil, "extra" => true},
          %{"created_at" => %{"extra" => nil}},
          %{"updated_at" => []},
          %{"recency_at" => 7},
          %{"created_at" => ""},
          %{"updated_at" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(
                 "thread/search",
                 %{"searchTerm" => "Owned search", "sortKey" => value},
                 experimental: true
               )
    end
  end

  test "sort correction retains required query and enclosing field constraints" do
    for {object, _literal} <- @forms do
      params = %{"searchTerm" => "Owned search", "sortKey" => object}

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/search", Map.delete(params, "searchTerm"),
                 experimental: true
               )

      for invalid <- [
            %{"searchTerm" => false},
            %{"limit" => false},
            %{"archived" => "false"},
            %{"sortDirection" => "unknown"}
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("thread/search", Map.merge(params, invalid),
                   experimental: true
                 )
      end
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
