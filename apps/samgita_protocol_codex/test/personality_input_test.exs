defmodule SamgitaProtocolCodex.PersonalityInputTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @methods ["thread/start", "thread/resume", "thread/settings/update", "turn/start"]
  @values ~w(none friendly pragmatic)
  @objects for value <- @values, payload <- [nil, %{}], do: %{value => payload}

  test "native personality unit objects preserve complete caller maps on the four input paths" do
    for method <- @methods, personality <- @objects do
      params = params(method, personality)
      wire = %{"id" => "owned-personality-object", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)
      assert :ok = Schema.validate_request(method, params, experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "canonical export strings and outer null or omission retain their original contracts" do
    document = @export |> File.read!() |> JSON.decode!()
    assert document["definitions"]["Personality"]["enum"] === @values

    for method <- @methods, personality <- @objects do
      wire = %{
        "id" => "owned-personality-export",
        "method" => method,
        "params" => params(method, personality)
      }

      assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
    end

    for method <- @methods, personality <- [nil | @values] do
      assert :ok =
               Schema.validate_request(method, params(method, personality), experimental: true)

      assert :ok =
               Schema.validate_request(
                 method,
                 Map.delete(params(method, personality), "personality"),
                 experimental: true
               )
    end
  end

  test "unit personality inputs require one known key and a null or empty-map payload" do
    for method <- @methods,
        personality <- [
          %{},
          %{"unknown" => nil},
          %{"none" => nil, "friendly" => nil},
          %{"friendly" => nil, "extra" => true},
          %{"pragmatic" => %{"extra" => nil}},
          %{"none" => []},
          %{"friendly" => 7},
          %{"pragmatic" => ""},
          %{"none" => false},
          "unknown",
          false,
          []
        ] do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_request(method, params(method, personality), experimental: true)
    end
  end

  test "correction preserves required identifiers and each method's experimental status" do
    for method <- @methods, personality <- @objects do
      if method != "thread/start" do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(
                   method,
                   Map.delete(params(method, personality), "threadId"),
                   experimental: true
                 )
      end

      if method == "thread/settings/update" do
        assert {:error, %Error{code: :experimental_api_required}} =
                 Schema.validate_request(method, params(method, personality))
      else
        assert :ok = Schema.validate_request(method, params(method, personality))
      end
    end
  end

  test "personality corrections compose with existing input corrections on every overlapping route" do
    for method <- @methods, personality <- @objects do
      params = params(method, personality)

      params =
        case method do
          "thread/start" ->
            Map.merge(params, %{
              "multiAgentMode" => %{"none" => %{}},
              "dynamicTools" => [
                %{"name" => "lookup", "description" => "Owned fixture", "inputSchema" => %{}}
              ]
            })

          "thread/resume" ->
            Map.put(params, "history", [
              %{"type" => "compaction_summary", "encrypted_content" => "OWNED_CHECKPOINT"}
            ])

          _ ->
            Map.merge(params, %{
              "summary" => %{"none" => %{}},
              "multiAgentMode" => %{"none" => nil},
              "collaborationMode" => %{
                "mode" => %{"code" => %{}},
                "settings" => %{"model" => "mock-model"}
              }
            })
        end

      assert :ok = Schema.validate_request(method, params, experimental: true)
    end
  end

  defp params(method, personality) do
    base = %{"personality" => personality}

    case method do
      "thread/start" -> base
      "turn/start" -> Map.merge(base, %{"threadId" => "owned-thread", "input" => []})
      _ -> Map.put(base, "threadId", "owned-thread")
    end
  end
end
