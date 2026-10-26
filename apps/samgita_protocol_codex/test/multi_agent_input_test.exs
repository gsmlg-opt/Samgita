defmodule SamgitaProtocolCodex.MultiAgentInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @methods ["thread/start", "thread/settings/update", "turn/start"]
  @unit_objects for name <- ~w(none explicitRequestOnly proactive),
                    payload <- [nil, %{}],
                    do: %{name => payload}

  test "native none input retains its exact wire value on all deprecated request fields" do
    for method <- @methods,
        value <- ["none", "explicitRequestOnly", "proactive", %{"custom" => ""} | @unit_objects] do
      params = params(method, value)
      wire = %{"id" => "owned-none-input", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)

      assert :ok = Schema.validate_request(method, params, experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "official exports remain unchanged while native none input is accepted" do
    document = @export |> File.read!() |> JSON.decode!()
    assert document["definitions"]["MultiAgentMode"]["oneOf"] |> length() == 2

    for method <- @methods, value <- ["none" | @unit_objects] do
      wire = %{"id" => "owned-none-export", "method" => method, "params" => params(method, value)}

      assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
      assert :ok = Schema.validate_request(method, wire["params"], experimental: true)
    end
  end

  test "none input does not broaden the existing mode union or enclosing request constraints" do
    for method <- @methods,
        value <- ["NONE", "invented-mode", false, 3, [], %{"custom" => 7}] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, value), experimental: true)
    end

    for method <- ["thread/settings/update", "turn/start"] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, Map.delete(params(method), "threadId"),
                 experimental: true
               )
    end
  end

  test "tagged unit objects require one known variant with null or empty-map payload" do
    for method <- @methods,
        value <- [
          %{},
          %{"none" => 7},
          %{"none" => false},
          %{"none" => %{"extra" => nil}},
          %{"none" => nil, "proactive" => nil},
          %{"none" => nil, "extra" => true},
          %{"proactive" => ""},
          %{"explicitRequestOnly" => []},
          %{"custom" => nil},
          %{"unknown" => nil}
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, value), experimental: true)
    end
  end

  test "none input retains experimental field negotiation" do
    for method <- @methods, value <- ["none" | @unit_objects] do
      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request(method, params(method, value))
    end
  end

  defp params(method, value \\ "none") do
    base = %{"multiAgentMode" => value}

    case method do
      "thread/start" -> base
      "thread/settings/update" -> Map.put(base, "threadId", "owned-thread")
      "turn/start" -> Map.merge(base, %{"threadId" => "owned-thread", "input" => []})
    end
  end
end
