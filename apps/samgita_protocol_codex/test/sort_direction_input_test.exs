defmodule SamgitaProtocolCodex.SortDirectionInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @forms [
    {%{"asc" => nil}, ~s({"asc":null})},
    {%{"asc" => %{}}, ~s({"asc":{}})},
    {%{"desc" => nil}, ~s({"desc":null})},
    {%{"desc" => %{}}, ~s({"desc":{}})}
  ]
  @routes [
    {"thread/list", "ThreadListParams", ["sortDirection"], %{}, ~s({"sortDirection":DIRECTION})},
    {"thread/turns/list", "ThreadTurnsListParams", ["sortDirection"],
     %{"threadId" => "owned-thread"}, ~s({"sortDirection":DIRECTION,"threadId":"owned-thread"})},
    {"thread/items/list", "ThreadItemsListParams", ["sortDirection"],
     %{"threadId" => "owned-thread"}, ~s({"sortDirection":DIRECTION,"threadId":"owned-thread"})},
    {"thread/resume", "ThreadResumeParams", ["initialTurnsPage", "sortDirection"],
     %{"threadId" => "owned-thread", "initialTurnsPage" => %{}},
     ~s({"initialTurnsPage":{"sortDirection":DIRECTION},"threadId":"owned-thread"})},
    {"project/list", "ProjectListParams", ["sortDirection"], %{"sortKey" => "position"},
     ~s({"sortDirection":DIRECTION,"sortKey":"position"})},
    {"thread/search", "ThreadSearchParams", ["sortDirection"],
     %{"searchTerm" => "Owned direction"},
     ~s({"searchTerm":"Owned direction","sortDirection":DIRECTION})}
  ]
  @standard ~w(thread/list thread/turns/list thread/items/list)

  test "four native direction objects preserve original maps and literal bytes on all six paths" do
    for {method, _owner, path, base, template} <- @routes,
        {object, literal} <- @forms,
        opts <- profiles(method) do
      params = put_in(base, path, object)
      params_bytes = String.replace(template, "DIRECTION", literal)
      bytes = ~s({"id":"owned-direction-unit","method":"#{method}","params":#{params_bytes}})
      wire = %{"id" => "owned-direction-unit", "method" => method, "params" => params}

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request(method, params, opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw exports keep exact string schema and full versus stable input graphs" do
    expected_full =
      @routes
      |> Enum.map(fn {method, _owner, path, _base, _template} -> {method, path} end)
      |> Enum.sort()

    for profile <- ["stable", "experimental"] do
      document = read(profile, "ClientRequest.json")

      expected =
        if profile == "stable",
          do: Enum.filter(expected_full, &(elem(&1, 0) in @standard)),
          else: expected_full

      assert direction_paths(document) === expected

      assert document["definitions"]["SortDirection"] === %{
               "enum" => ["asc", "desc"],
               "type" => "string"
             }

      routes =
        if profile == "stable",
          do: Enum.filter(@routes, &(elem(&1, 0) in @standard)),
          else: @routes

      for {method, owner, path, base, _template} <- routes do
        standalone = read(profile, "v2/#{owner}.json")

        assert standalone["definitions"]["SortDirection"] ===
                 document["definitions"]["SortDirection"]

        field = field_at(document["definitions"][owner], path, document)

        assert Map.fetch!(field, "anyOf") === [
                 %{"$ref" => "#/definitions/SortDirection"},
                 %{"type" => "null"}
               ]

        assert field_at(standalone, path, standalone) === field

        for {object, _literal} <- @forms do
          params = put_in(base, path, object)
          wire = %{"id" => "owned-direction-export", "method" => method, "params" => params}
          assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

          assert {:error, %Error{code: :schema_violation}} =
                   Validator.validate(standalone, params)
        end
      end
    end
  end

  test "canonical strings null and omission preserve each method and enclosing-page gate" do
    for {method, _owner, path, base, _template} <- @routes do
      params = [base | Enum.map([nil, "asc", "desc"], &put_in(base, path, &1))]

      for value <- params do
        assert :ok = Schema.validate_request(method, value, experimental: true)

        if method in @standard do
          assert :ok = Schema.validate_request(method, value)
        else
          assert {:error, %Error{code: :experimental_api_required}} =
                   Schema.validate_request(method, value)
        end

        wire = %{"id" => "owned-direction-canonical", "method" => method, "params" => value}
        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end

      if method not in @standard do
        for {object, _literal} <- @forms do
          assert {:error, %Error{code: :experimental_api_required}} =
                   Schema.validate_request(method, put_in(base, path, object))
        end
      end
    end

    # A present initialTurnsPage stays active even when nested direction is
    # absent/null. Outer null and omission leave that Option field inactive.
    for params <- [
          %{"threadId" => "owned-thread"},
          %{"threadId" => "owned-thread", "initialTurnsPage" => nil}
        ] do
      assert :ok = Schema.validate_request("thread/resume", params)
    end
  end

  test "direction unit objects require one known key and null or empty-map payload" do
    invalid = [
      %{},
      %{"unknown" => nil},
      %{"Asc" => nil},
      %{"asc" => nil, "desc" => nil},
      %{"asc" => nil, "extra" => true},
      %{"asc" => %{"extra" => nil}},
      %{"desc" => []},
      %{"asc" => 7},
      %{"desc" => ""},
      %{"asc" => false},
      "unknown",
      false,
      []
    ]

    for {method, _owner, path, base, _template} <- @routes,
        value <- invalid,
        opts <- profiles(method) do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, put_in(base, path, value), opts)
    end
  end

  test "direction correction composes without loosening required or enclosing fields" do
    for {object, _literal} <- @forms do
      for {method, _owner, path, base, _template} <- @routes,
          opts <- profiles(method) do
        params = put_in(base, path, object)

        invalid =
          case method do
            "thread/list" ->
              [%{"limit" => false}, %{"cwd" => false}, %{"archived" => "false"}]

            "thread/search" ->
              [%{"searchTerm" => false}, %{"limit" => false}, %{"archived" => "false"}]

            "project/list" ->
              [%{"limit" => false}, %{"sortKey" => "unknown"}]

            "thread/resume" ->
              [
                %{"threadId" => false},
                %{"excludeTurns" => "true"},
                %{"initialTurnsPage" => 7},
                %{"initialTurnsPage" => %{"sortDirection" => object, "limit" => false}}
              ]

            _ ->
              [%{"threadId" => false}, %{"limit" => false}]
          end

        for extra <- invalid do
          assert {:error, %Error{code: :schema_violation}} =
                   Schema.validate_request(method, Map.merge(params, extra), opts)
        end

        required = if method == "thread/search", do: "searchTerm", else: "threadId"

        if method in ["thread/turns/list", "thread/items/list", "thread/resume", "thread/search"] do
          assert {:error, %Error{code: :schema_violation}} =
                   Schema.validate_request(method, Map.delete(params, required), opts)
        end
      end

      for method <- ["thread/turns/list", "thread/items/list"] do
        params = %{"threadId" => "owned-thread", "sortDirection" => object, "limit" => 100}
        assert :ok = Schema.validate_request(method, params)
      end

      assert :ok =
               Schema.validate_request("thread/list", %{
                 "sortKey" => %{"created_at" => nil},
                 "sortDirection" => object
               })

      assert :ok =
               Schema.validate_request(
                 "thread/search",
                 %{
                   "searchTerm" => "Owned direction",
                   "sortKey" => %{"created_at" => %{}},
                   "sortDirection" => object
                 },
                 experimental: true
               )

      assert :ok =
               Schema.validate_request(
                 "thread/resume",
                 %{
                   "threadId" => "owned-thread",
                   "excludeTurns" => true,
                   "initialTurnsPage" => %{
                     "sortDirection" => object,
                     "itemsView" => "full",
                     "limit" => 100
                   }
                 },
                 experimental: true
               )

      # sortDirection-requires-sortKey is a native handler constraint, not an
      # exported schema constraint; do not invent a local schema rejection.
      assert :ok =
               Schema.validate_request("project/list", %{"sortDirection" => object},
                 experimental: true
               )
    end
  end

  defp profiles(method),
    do: if(method in @standard, do: [[], [experimental: true]], else: [[experimental: true]])

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

  defp field_at(%{"anyOf" => variants}, path, document),
    do: field_at(Enum.find(variants, &Map.has_key?(&1, "$ref")), path, document)

  defp field_at(node, [field | rest], document),
    do: field_at(node["properties"][field], rest, document)

  defp direction_paths(document) do
    paths =
      for branch <- document["oneOf"],
          path <- reference_paths(branch["properties"]["params"], [], MapSet.new(), document),
          method <- branch["properties"]["method"]["enum"],
          do: {method, path}

    Enum.sort(paths)
  end

  defp reference_paths(%{"$ref" => "#/definitions/SortDirection"}, path, _seen, _document),
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
