defmodule SamgitaProtocolCodex.ThreadStartSourceInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @root Path.expand("../priv/upstream/0.163.0", __DIR__)
  @values ~w(startup clear)
  @profiles [[], [experimental: true]]
  @forms [
    {%{"startup" => nil}, ~s({"startup":null})},
    {%{"startup" => %{}}, ~s({"startup":{}})},
    {%{"clear" => nil}, ~s({"clear":null})},
    {%{"clear" => %{}}, ~s({"clear":{}})}
  ]

  test "native start-source objects preserve complete caller maps and literal bytes" do
    for {object, literal} <- @forms, opts <- @profiles do
      bytes =
        ~s({"id":"owned-source-unit","method":"thread/start","params":{"sessionStartSource":#{literal}}})

      wire = %{
        "id" => "owned-source-unit",
        "method" => "thread/start",
        "params" => %{"sessionStartSource" => object}
      }

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request("thread/start", wire["params"], opts)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "both official profiles retain the singleton graph and reject unit objects" do
    for profile <- ["stable", "experimental"] do
      document =
        Path.join([@root, profile, "ClientRequest.json"]) |> File.read!() |> JSON.decode!()

      assert document["definitions"]["ThreadStartSource"] === %{
               "enum" => @values,
               "type" => "string"
             }

      assert document["definitions"]["ThreadStartParams"]["properties"]["sessionStartSource"] ===
               %{"anyOf" => [%{"$ref" => "#/definitions/ThreadStartSource"}, %{"type" => "null"}]}

      assert request_methods(document, "ThreadStartSource") === ["thread/start"]

      for {object, _literal} <- @forms do
        wire = %{
          "id" => "owned-source-export",
          "method" => "thread/start",
          "params" => %{"sessionStartSource" => object}
        }

        assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
      end
    end
  end

  test "standard canonical strings outer null and omission need no experimental gate" do
    for opts <- @profiles do
      for value <- [nil | @values] do
        params = %{"sessionStartSource" => value}
        assert :ok = Schema.validate_request("thread/start", params, opts)

        wire = %{"id" => "owned-source-canonical", "method" => "thread/start", "params" => params}
        bytes = JSON.encode!(wire)
        assert {:ok, ^bytes} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(bytes)
      end

      assert :ok = Schema.validate_request("thread/start", %{}, opts)
    end
  end

  test "unit inputs require exactly one known key and null or empty-map payload" do
    for opts <- @profiles,
        value <- [
          %{},
          %{"unknown" => nil},
          %{"Startup" => nil},
          %{"startup" => nil, "clear" => nil},
          %{"startup" => nil, "extra" => true},
          %{"clear" => %{"extra" => nil}},
          %{"startup" => []},
          %{"clear" => 7},
          %{"startup" => ""},
          %{"clear" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", %{"sessionStartSource" => value}, opts)
    end
  end

  test "start-source correction preserves enclosing constraints and composes with existing inputs" do
    for {object, _literal} <- @forms do
      base = %{"sessionStartSource" => object}

      for opts <- @profiles,
          invalid <- [%{"model" => false}, %{"cwd" => []}, %{"ephemeral" => "false"}] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("thread/start", Map.merge(base, invalid), opts)
      end

      params =
        Map.merge(base, %{
          "historyMode" => %{"legacy" => %{}},
          "multiAgentMode" => %{"none" => %{}},
          "personality" => %{"none" => nil},
          "dynamicTools" => [
            %{"name" => "lookup", "description" => "Owned fixture", "inputSchema" => %{}}
          ]
        })

      assert :ok = Schema.validate_request("thread/start", params, experimental: true)
      wire = %{"id" => "owned-source-composition", "method" => "thread/start", "params" => params}
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
