defmodule SamgitaProtocolCodex.TurnItemsViewInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @forms [
    {%{"notLoaded" => nil}, ~s({"notLoaded":null})},
    {%{"notLoaded" => %{}}, ~s({"notLoaded":{}})},
    {%{"summary" => nil}, ~s({"summary":null})},
    {%{"summary" => %{}}, ~s({"summary":{}})},
    {%{"full" => nil}, ~s({"full":null})},
    {%{"full" => %{}}, ~s({"full":{}})}
  ]
  @routes [
    {"thread/turns/list", "ThreadTurnsListParams", ["itemsView"], %{"threadId" => "owned-thread"},
     ~s({"itemsView":VIEW,"threadId":"owned-thread"})},
    {"thread/resume", "ThreadResumeParams", ["initialTurnsPage", "itemsView"],
     %{"threadId" => "owned-thread", "initialTurnsPage" => %{}},
     ~s({"initialTurnsPage":{"itemsView":VIEW},"threadId":"owned-thread"})}
  ]
  @canonical %{
    "oneOf" => [
      %{
        "description" =>
          "`items` was not loaded for this turn. The field is intentionally empty.",
        "enum" => ["notLoaded"],
        "type" => "string"
      },
      %{
        "description" => "`items` contains only a display summary for this turn.",
        "enum" => ["summary"],
        "type" => "string"
      },
      %{
        "description" =>
          "`items` contains every ThreadItem available from persisted app-server history for this turn.",
        "enum" => ["full"],
        "type" => "string"
      }
    ]
  }
  @field %{
    "anyOf" => [%{"$ref" => "#/definitions/TurnItemsView"}, %{"type" => "null"}],
    "description" =>
      "How much item detail to include for each returned turn; defaults to summary."
  }

  test "six native view objects preserve original maps and literal bytes on both exact paths" do
    for {method, _owner, path, base, template} <- @routes,
        {object, literal} <- @forms,
        opts <- profiles(method) do
      params = put_in(base, path, object)
      params_bytes = String.replace(template, "VIEW", literal)
      bytes = ~s({"id":"owned-items-view-unit","method":"#{method}","params":#{params_bytes}})
      wire = %{"id" => "owned-items-view-unit", "method" => method, "params" => params}

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request(method, params, opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw exports retain all described canonical branches and exact stable and full input paths" do
    full_paths = [
      {"thread/resume", ["initialTurnsPage", "itemsView"]},
      {"thread/turns/list", ["itemsView"]}
    ]

    for profile <- ["stable", "experimental"] do
      document = read(profile, "ClientRequest.json")

      expected =
        if profile == "stable", do: [{"thread/turns/list", ["itemsView"]}], else: full_paths

      assert view_paths(document) === expected
      assert document["definitions"]["TurnItemsView"] === @canonical

      routes = if profile == "stable", do: Enum.take(@routes, 1), else: @routes

      for {method, owner, path, base, _template} <- routes do
        standalone = read(profile, "v2/#{owner}.json")
        assert standalone["definitions"]["TurnItemsView"] === @canonical
        assert field_at(document["definitions"][owner], path, document) === @field
        assert field_at(standalone, path, standalone) === @field

        for {object, _literal} <- @forms do
          params = put_in(base, path, object)
          wire = %{"id" => "owned-items-view-export", "method" => method, "params" => params}
          assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

          assert {:error, %Error{code: :schema_violation}} =
                   Validator.validate(standalone, params)
        end
      end

      refute File.exists?(
               Path.join([@root, profile, "v2/ThreadResumeInitialTurnsPageParams.json"])
             )
    end

    stable = read("stable", "ClientRequest.json")
    assert Map.has_key?(stable["definitions"], "ThreadResumeInitialTurnsPageParams")

    refute Map.has_key?(
             stable["definitions"]["ThreadResumeParams"]["properties"],
             "initialTurnsPage"
           )
  end

  test "canonical strings null and omission preserve the active enclosing-page gate" do
    for {method, _owner, path, base, _template} <- @routes,
        params <- [
          base | Enum.map([nil, "notLoaded", "summary", "full"], &put_in(base, path, &1))
        ] do
      assert :ok = Schema.validate_request(method, params, experimental: true)

      if method == "thread/turns/list" do
        assert :ok = Schema.validate_request(method, params)
      else
        assert {:error, %Error{code: :experimental_api_required}} =
                 Schema.validate_request(method, params)
      end

      wire = %{"id" => "owned-items-view-canonical", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end

    for {object, _literal} <- @forms do
      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("thread/resume", %{
                 "threadId" => "owned-thread",
                 "initialTurnsPage" => %{"itemsView" => object}
               })
    end

    # These outer Option values deactivate the page. An inner null or omitted
    # view leaves a present page active. The request defaults to Summary, not
    # the enum/output default Full; runtime defaults are a native oracle.
    for params <- [
          %{"threadId" => "owned-thread"},
          %{"threadId" => "owned-thread", "initialTurnsPage" => nil}
        ] do
      assert :ok = Schema.validate_request("thread/resume", params)
    end
  end

  test "view unit objects require exactly one known key and null or empty-map payload" do
    invalid_payloads =
      for view <- ["notLoaded", "summary", "full"],
          payload <- [%{"extra" => nil}, [], 7, "", false],
          do: %{view => payload}

    invalid =
      [
        %{},
        %{"unknown" => nil},
        %{"NotLoaded" => nil},
        %{"Summary" => %{}},
        %{"notLoaded" => nil, "summary" => nil},
        %{"full" => nil, "extra" => true},
        "unknown",
        false,
        []
      ] ++ invalid_payloads

    for {method, _owner, path, base, _template} <- @routes,
        value <- invalid,
        opts <- profiles(method) do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, put_in(base, path, value), opts)
    end
  end

  test "view correction composes with direction inputs without loosening enclosing constraints" do
    directions =
      [%{}, %{"sortDirection" => nil}, %{"sortDirection" => "asc"}, %{"sortDirection" => "desc"}] ++
        for(
          key <- ["asc", "desc"],
          payload <- [nil, %{}],
          do: %{"sortDirection" => %{key => payload}}
        )

    for {method, _owner, path, base, _template} <- @routes,
        {object, _literal} <- @forms,
        opts <- profiles(method) do
      params = put_in(base, path, object)

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, Map.delete(params, "threadId"), opts)

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, Map.put(params, "threadId", false), opts)

      invalid =
        if method == "thread/resume" do
          [
            Map.put(params, "excludeTurns", "true"),
            Map.put(params, "initialTurnsPage", 7),
            put_in(params, ["initialTurnsPage", "limit"], false),
            put_in(params, ["initialTurnsPage", "limit"], -1),
            put_in(params, ["initialTurnsPage", "sortDirection"], "unknown")
          ]
        else
          [
            Map.put(params, "limit", false),
            Map.put(params, "limit", -1),
            Map.put(params, "sortDirection", "unknown")
          ]
        end

      for bad <- invalid do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(method, bad, opts)
      end

      for direction <- directions do
        composed =
          if method == "thread/resume" do
            params
            |> Map.put("excludeTurns", true)
            |> Map.update!("initialTurnsPage", &Map.merge(&1, Map.put(direction, "limit", 100)))
          else
            Map.merge(params, Map.put(direction, "limit", 100))
          end

        assert :ok = Schema.validate_request(method, composed, opts)
        wire = %{"id" => "owned-items-view-composed", "method" => method, "params" => composed}
        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end
    end
  end

  defp profiles("thread/turns/list"), do: [[], [experimental: true]]
  defp profiles("thread/resume"), do: [[experimental: true]]

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

  defp view_paths(document) do
    paths =
      for branch <- document["oneOf"],
          path <- reference_paths(branch["properties"]["params"], [], MapSet.new(), document),
          method <- branch["properties"]["method"]["enum"],
          do: {method, path}

    Enum.sort(paths)
  end

  defp reference_paths(%{"$ref" => "#/definitions/TurnItemsView"}, path, _seen, _document),
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
