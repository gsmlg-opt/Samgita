defmodule SamgitaProtocolCodex.DynamicToolInputSemanticsTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)

  test "native legacy declarations retain absent, null and boolean input fields losslessly" do
    variants = [
      %{},
      %{"namespace" => nil, "deferLoading" => nil, "exposeToContext" => nil},
      %{"namespace" => "catalog", "exposeToContext" => true},
      %{"namespace" => "catalog", "exposeToContext" => false},
      %{"namespace" => "catalog", "deferLoading" => nil, "exposeToContext" => false},
      %{"namespace" => "catalog", "deferLoading" => false, "exposeToContext" => false},
      %{"namespace" => "catalog", "deferLoading" => true, "exposeToContext" => true}
    ]

    for flags <- variants do
      tools = [Map.merge(legacy(), flags)]
      wire = %{"id" => "legacy-input", "method" => "thread/start", "params" => params(tools)}
      original = JSON.encode!(wire)

      assert :ok = Schema.validate_request("thread/start", wire["params"], experimental: true)
      assert {:ok, ^original} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(original)
    end
  end

  test "legacy groups, unnamespaced tools and opaque extra fields remain native input" do
    tools = [
      Map.merge(legacy(), %{"namespace" => "catalog", "future" => [nil, %{"opaque" => "λ"}]}),
      Map.put(legacy(), "name", "top_level"),
      Map.merge(legacy(), %{"namespace" => "catalog", "name" => "second"}),
      Map.put(legacy(), "tools", [%{"type" => "function"}])
    ]

    assert :ok = Schema.validate_request("thread/start", params(tools), experimental: true)
  end

  test "the unchanged official export still exposes its canonical-only mismatch" do
    document = @export |> File.read!() |> JSON.decode!()
    wire = %{"id" => "export-oracle", "method" => "thread/start", "params" => params([legacy()])}

    assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)

    assert :ok = Schema.validate_request("thread/start", wire["params"], experimental: true)
  end

  test "canonical functions and namespaces keep the original tagged contracts" do
    function = canonical()
    namespace = namespace([function])

    assert :ok =
             Schema.validate_request("thread/start", params([function, namespace]),
               experimental: true
             )

    for invalid <- [
          Map.put(function, "deferLoading", nil),
          Map.put(function, "type", "invented"),
          Map.put(namespace, "tools", [%{"type" => "namespace"}]),
          Map.delete(function, "inputSchema")
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", params([invalid]), experimental: true)
    end
  end

  test "legacy declarations and empty arrays retain experimental field-presence negotiation" do
    for tools <- [[legacy()], []] do
      assert {:error,
              %Error{
                code: :experimental_api_required,
                details: %{"path" => ["params", "dynamicTools"]}
              }} = Schema.validate_request("thread/start", params(tools))
    end

    assert :ok = Schema.validate_request("thread/start", %{})
    assert :ok = Schema.validate_request("thread/start", params(nil))
    assert :ok = Schema.validate_request("thread/start", params([]), experimental: true)
  end

  test "list-level canonical and legacy signatures cannot be mixed, even in nested tools" do
    mixed = [
      [canonical(), legacy()],
      [Map.put(canonical(), "namespace", nil)],
      [Map.put(canonical(), "exposeToContext", false)],
      [namespace([legacy()])],
      [namespace([Map.put(canonical(), "namespace", nil)])],
      [namespace([Map.put(canonical(), "exposeToContext", nil)])]
    ]

    for tools <- mixed do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", params(tools), experimental: true)
    end
  end

  test "legacy required fields and nullable primitive types remain validated" do
    malformed = [
      nil,
      false,
      "function",
      1,
      [],
      %{},
      Map.delete(legacy(), "name"),
      Map.delete(legacy(), "description"),
      Map.delete(legacy(), "inputSchema"),
      Map.put(legacy(), "name", nil),
      Map.put(legacy(), "description", 7),
      Map.put(legacy(), "namespace", false),
      Map.put(legacy(), "deferLoading", "false"),
      Map.put(legacy(), "exposeToContext", 0)
    ]

    for invalid <- malformed do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", params([invalid]), experimental: true)
    end

    for input_schema <- [nil, true, false, "opaque", 7, [], %{}] do
      assert :ok =
               Schema.validate_request(
                 "thread/start",
                 params([Map.put(legacy(), "inputSchema", input_schema)]),
                 experimental: true
               )
    end

    for tools <- [%{}, "invalid", 7, false] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request("thread/start", params(tools), experimental: true)
    end
  end

  defp legacy,
    do: %{"name" => "lookup", "description" => "Synthetic lookup λ", "inputSchema" => %{}}

  defp canonical, do: Map.put(legacy(), "type", "function")

  defp namespace(tools),
    do: %{"type" => "namespace", "name" => "catalog", "description" => "", "tools" => tools}

  defp params(tools), do: %{"dynamicTools" => tools}
end
