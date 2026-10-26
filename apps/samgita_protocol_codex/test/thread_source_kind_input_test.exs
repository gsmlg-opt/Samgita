defmodule SamgitaProtocolCodex.ThreadSourceKindInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @kinds ~w(cli vscode exec appServer subAgent subAgentReview subAgentCompact subAgentThreadSpawn subAgentOther unknown)
  @forms [
    {%{"cli" => nil}, ~s({"cli":null})},
    {%{"cli" => %{}}, ~s({"cli":{}})},
    {%{"vscode" => nil}, ~s({"vscode":null})},
    {%{"vscode" => %{}}, ~s({"vscode":{}})},
    {%{"exec" => nil}, ~s({"exec":null})},
    {%{"exec" => %{}}, ~s({"exec":{}})},
    {%{"appServer" => nil}, ~s({"appServer":null})},
    {%{"appServer" => %{}}, ~s({"appServer":{}})},
    {%{"subAgent" => nil}, ~s({"subAgent":null})},
    {%{"subAgent" => %{}}, ~s({"subAgent":{}})},
    {%{"subAgentReview" => nil}, ~s({"subAgentReview":null})},
    {%{"subAgentReview" => %{}}, ~s({"subAgentReview":{}})},
    {%{"subAgentCompact" => nil}, ~s({"subAgentCompact":null})},
    {%{"subAgentCompact" => %{}}, ~s({"subAgentCompact":{}})},
    {%{"subAgentThreadSpawn" => nil}, ~s({"subAgentThreadSpawn":null})},
    {%{"subAgentThreadSpawn" => %{}}, ~s({"subAgentThreadSpawn":{}})},
    {%{"subAgentOther" => nil}, ~s({"subAgentOther":null})},
    {%{"subAgentOther" => %{}}, ~s({"subAgentOther":{}})},
    {%{"unknown" => nil}, ~s({"unknown":null})},
    {%{"unknown" => %{}}, ~s({"unknown":{}})}
  ]
  @field %{
    "description" =>
      "Optional source filter; when set, only sessions from these source kinds are returned. When omitted or empty, defaults to interactive sources.",
    "items" => %{"$ref" => "#/definitions/ThreadSourceKind"},
    "type" => ["array", "null"]
  }

  test "twenty source-kind objects preserve literal singleton arrays and original caller maps" do
    for method <- ["thread/list", "thread/search"],
        {object, literal} <- @forms,
        opts <- profiles(method) do
      params = params(method, [object])

      params_bytes =
        if method == "thread/list",
          do: ~s({"sourceKinds":[#{literal}]}),
          else: ~s({"searchTerm":"Owned source input","sourceKinds":[#{literal}]})

      bytes = ~s({"id":"owned-source-kind-unit","method":"#{method}","params":#{params_bytes}})
      wire = %{"id" => "owned-source-kind-unit", "method" => method, "params" => params}
      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request(method, params, opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "raw exports keep all canonical variants and exact stable and full array reachability" do
    for profile <- ["stable", "experimental"] do
      document = read(profile, "ClientRequest.json")
      expected = [{"thread/list", ["sourceKinds", "[]"]}]

      expected =
        if profile == "stable",
          do: expected,
          else: expected ++ [{"thread/search", ["sourceKinds", "[]"]}]

      assert source_paths(document) === expected

      assert document["definitions"]["ThreadSourceKind"] === %{
               "enum" => @kinds,
               "type" => "string"
             }

      methods =
        if profile == "stable", do: ["thread/list"], else: ["thread/list", "thread/search"]

      for method <- methods do
        owner = if method == "thread/list", do: "ThreadListParams", else: "ThreadSearchParams"
        standalone = read(profile, "v2/#{owner}.json")

        assert standalone["definitions"]["ThreadSourceKind"] === %{
                 "enum" => @kinds,
                 "type" => "string"
               }

        assert document["definitions"][owner]["properties"]["sourceKinds"] === @field
        assert standalone["properties"]["sourceKinds"] === @field

        for {object, _literal} <- @forms do
          params = params(method, [object])
          wire = %{"id" => "owned-source-kind-export", "method" => method, "params" => params}
          assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

          assert {:error, %Error{code: :schema_violation}} =
                   Validator.validate(standalone, params)
        end
      end

      refute File.exists?(Path.join([@root, profile, "v2/ThreadSourceKind.json"]))
    end

    stable = read("stable", "ClientRequest.json")
    refute Map.has_key?(stable["definitions"], "ThreadSearchParams")
    refute File.exists?(Path.join([@root, "stable", "v2/ThreadSearchParams.json"]))
  end

  test "canonical arrays outer null omission and empty arrays retain the actual method gate" do
    for method <- ["thread/list", "thread/search"] do
      values = [
        base(method),
        params(method, nil),
        params(method, []) | Enum.map(@kinds, &params(method, [&1]))
      ]

      for params <- values do
        assert :ok = Schema.validate_request(method, params, experimental: true)

        if method == "thread/list" do
          assert :ok = Schema.validate_request(method, params)
        else
          assert {:error, %Error{code: :experimental_api_required}} =
                   Schema.validate_request(method, params)
        end

        wire = %{"id" => "owned-source-kind-canonical", "method" => method, "params" => params}
        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end
    end

    for {object, _literal} <- @forms do
      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("thread/search", params("thread/search", [object]))
    end

    # Validation preserves outer null, absence and empty arrays; it does not
    # insert or equate native defaults. Interactive defaults also include custom
    # atlas/chatgpt sessions. List's relation-filter+None exception remains
    # native-owned and is not qualified by these schema checks.
  end

  test "array elements require exactly one correctly renamed unit key and null or empty-map payload" do
    bad_payloads =
      for key <- @kinds, payload <- [%{"extra" => nil}, [], true, 7, ""], do: %{key => payload}

    bad_elements =
      [
        nil,
        %{},
        %{"future" => nil},
        %{"vsCode" => nil},
        %{"vs_code" => %{}},
        %{"VSCode" => nil},
        %{"AppServer" => nil},
        %{"subagent" => nil},
        %{"vscode" => nil, "unknown" => nil},
        %{"vscode" => nil, "extra" => true},
        "vsCode",
        "future",
        false,
        []
      ] ++ bad_payloads

    for method <- ["thread/list", "thread/search"], opts <- profiles(method) do
      for value <- bad_elements do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(method, params(method, [value]), opts)
      end

      for value <- ["vscode", %{"vscode" => nil}, false, 7] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(method, params(method, value), opts)
      end
    end
  end

  test "source objects preserve mixed-array order and compose without loosening enclosing constraints" do
    for method <- ["thread/list", "thread/search"],
        {object, _literal} <- @forms,
        opts <- profiles(method) do
      params =
        params(method, ["unknown", object, "vscode", object])
        |> Map.merge(%{
          "sortKey" => %{"created_at" => nil},
          "sortDirection" => %{"asc" => %{}},
          "limit" => 100,
          "cursor" => nil
        })

      assert :ok = Schema.validate_request(method, params, opts)
      wire = %{"id" => "owned-source-kind-composed", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)

      assert JSON.decode!(bytes)["params"]["sourceKinds"] === [
               "unknown",
               object,
               "vscode",
               object
             ]

      invalid = [
        nil,
        [],
        Map.put(params, "limit", false),
        Map.put(params, "limit", -1),
        Map.put(params, "cursor", false),
        Map.put(params, "archived", "false"),
        Map.put(params, "sortKey", "future"),
        Map.put(params, "sortDirection", "future")
      ]

      invalid =
        if method == "thread/list",
          do:
            invalid ++
              [Map.put(params, "useStateDbOnly", nil), Map.put(params, "useStateDbOnly", "true")],
          else:
            invalid ++ [Map.delete(params, "searchTerm"), Map.put(params, "searchTerm", false)]

      for value <- invalid do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(method, value, opts)
      end
    end
  end

  defp base("thread/list"), do: %{}
  defp base("thread/search"), do: %{"searchTerm" => "Owned source input"}
  defp params(method, kinds), do: Map.put(base(method), "sourceKinds", kinds)
  defp profiles("thread/list"), do: [[], [experimental: true]]
  defp profiles("thread/search"), do: [[experimental: true]]

  defp read(profile, file),
    do: Path.join([@root, profile, file]) |> File.read!() |> JSON.decode!()

  defp source_paths(document) do
    paths =
      for branch <- document["oneOf"],
          path <- reference_paths(branch["properties"]["params"], [], MapSet.new(), document),
          method <- branch["properties"]["method"]["enum"],
          do: {method, path}

    Enum.sort(paths)
  end

  defp reference_paths(%{"$ref" => "#/definitions/ThreadSourceKind"}, path, _seen, _document),
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
