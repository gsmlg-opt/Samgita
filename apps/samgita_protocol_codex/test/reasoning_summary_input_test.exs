defmodule SamgitaProtocolCodex.ReasoningSummaryInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @methods ["thread/settings/update", "turn/start", "turn/settings/update"]
  @values ~w(auto concise detailed none)
  @objects for value <- @values, payload <- [nil, %{}], do: %{value => payload}

  test "native summary unit objects retain their original values on all three request paths" do
    for method <- @methods, summary <- @objects do
      params = params(method, summary)
      wire = %{"id" => "owned-summary-object", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)

      assert :ok = Schema.validate_request(method, params, experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "canonical exports remain string-only and canonical null and omission inputs remain valid" do
    document = @export |> File.read!() |> JSON.decode!()
    assert document["definitions"]["ReasoningSummary"]["oneOf"] |> length() == 2

    for method <- @methods, summary <- @objects do
      wire = %{
        "id" => "owned-summary-export",
        "method" => method,
        "params" => params(method, summary)
      }

      assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
    end

    for method <- @methods, summary <- [nil | @values] do
      assert :ok = Schema.validate_request(method, params(method, summary), experimental: true)

      assert :ok =
               Schema.validate_request(method, Map.delete(params(method, summary), "summary"),
                 experimental: true
               )
    end
  end

  test "unit summary inputs require one known key and null or empty-map payload" do
    for method <- @methods,
        summary <- [
          %{},
          %{"unknown" => nil},
          %{"auto" => nil, "none" => nil},
          %{"concise" => nil, "extra" => true},
          %{"none" => %{"extra" => nil}},
          %{"detailed" => []},
          %{"auto" => 7},
          %{"concise" => ""},
          %{"none" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, summary), experimental: true)
    end
  end

  test "summary correction preserves enclosing identifiers and experimental method negotiation" do
    for method <- @methods, summary <- @objects do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, Map.delete(params(method, summary), "threadId"),
                 experimental: true
               )

      if method == "turn/start" do
        assert :ok = Schema.validate_request(method, params(method, summary))
      else
        assert {:error, %Error{code: :experimental_api_required}} =
                 Schema.validate_request(method, params(method, summary))
      end
    end

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request(
               "turn/settings/update",
               Map.delete(params("turn/settings/update", %{"auto" => nil}), "turnId"),
               experimental: true
             )
  end

  test "summary corrections compose with both existing mode input corrections" do
    for method <- ["thread/settings/update", "turn/start"], summary <- @objects do
      params =
        Map.merge(params(method, summary), %{
          "multiAgentMode" => %{"none" => %{}},
          "collaborationMode" => %{
            "mode" => %{"code" => nil},
            "settings" => %{"model" => "mock-model"}
          }
        })

      assert :ok = Schema.validate_request(method, params, experimental: true)
    end
  end

  defp params(method, summary) do
    base = %{"threadId" => "owned-thread", "summary" => summary}

    case method do
      "thread/settings/update" -> base
      "turn/start" -> Map.put(base, "input", [])
      "turn/settings/update" -> Map.put(base, "turnId", "owned-turn")
    end
  end
end
