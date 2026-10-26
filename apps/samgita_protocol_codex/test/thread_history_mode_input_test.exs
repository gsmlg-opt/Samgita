defmodule SamgitaProtocolCodex.ThreadHistoryModeInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @values ~w(legacy paginated)
  @forms [
    {%{"legacy" => nil}, ~s({"legacy":null})},
    {%{"legacy" => %{}}, ~s({"legacy":{}})},
    {%{"paginated" => nil}, ~s({"paginated":null})},
    {%{"paginated" => %{}}, ~s({"paginated":{}})}
  ]

  test "native history-mode objects preserve complete caller maps and literal bytes" do
    for {object, literal} <- @forms do
      bytes =
        ~s({"id":"owned-history-unit","method":"thread/start","params":{"historyMode":#{literal}}})

      wire = %{
        "id" => "owned-history-unit",
        "method" => "thread/start",
        "params" => %{"historyMode" => object}
      }

      assert JSON.decode!(bytes) === wire
      assert :ok = Schema.validate_request("thread/start", wire["params"], experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "official exports remain string-only and canonical null and omission inputs remain valid" do
    document = @export |> File.read!() |> JSON.decode!()

    assert document["definitions"]["ThreadHistoryMode"] === %{
             "enum" => @values,
             "type" => "string"
           }

    assert request_methods(document, "ThreadHistoryMode") === ["thread/start"]

    for {object, _literal} <- @forms do
      wire = %{
        "id" => "owned-history-export",
        "method" => "thread/start",
        "params" => %{"historyMode" => object}
      }

      assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
    end

    for value <- [nil | @values] do
      assert :ok =
               Schema.validate_request("thread/start", %{"historyMode" => value},
                 experimental: true
               )
    end

    assert :ok = Schema.validate_request("thread/start", %{}, experimental: true)
    assert :ok = Schema.validate_request("thread/start", %{})
  end

  test "history-mode objects require one known key and a null or empty-map payload" do
    for value <- [
          %{},
          %{"unknown" => nil},
          %{"legacy" => nil, "paginated" => nil},
          %{"legacy" => nil, "extra" => true},
          %{"paginated" => %{"extra" => nil}},
          %{"legacy" => []},
          %{"paginated" => 7},
          %{"legacy" => ""},
          %{"paginated" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", %{"historyMode" => value},
                 experimental: true
               )
    end
  end

  test "correction preserves the actual field gate and enclosing field constraints" do
    for {object, _literal} <- @forms do
      params = %{"historyMode" => object}

      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request("thread/start", params)

      for invalid <- [%{"model" => false}, %{"cwd" => []}, %{"ephemeral" => "false"}] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("thread/start", Map.merge(params, invalid),
                   experimental: true
                 )
      end
    end
  end

  test "history-mode objects compose with every other thread-start input correction" do
    for {object, _literal} <- @forms do
      params = %{
        "historyMode" => object,
        "multiAgentMode" => %{"none" => %{}},
        "personality" => %{"none" => nil},
        "dynamicTools" => [
          %{"name" => "lookup", "description" => "Owned fixture", "inputSchema" => %{}}
        ]
      }

      assert :ok = Schema.validate_request("thread/start", params, experimental: true)

      wire = %{
        "id" => "owned-history-composition",
        "method" => "thread/start",
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
