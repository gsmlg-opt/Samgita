defmodule SamgitaProtocolCodex.WireTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolCodex.{Failure, Wire}

  test "native envelopes retain complete extensions, structures, null and missing fields" do
    for envelope <- [
          %{
            "id" => 0,
            "method" => "future/method",
            "params" => %{"content" => [%{"image" => "x", "structured" => nil}]},
            "future" => true
          },
          %{"id" => "0", "result" => %{"opaque" => [1, 1.5, nil, false], "missing" => %{}}},
          %{"method" => "unknown/event", "emittedAtMs" => 123, "params" => nil},
          %{
            "id" => -1,
            "error" => %{
              "code" => -32602,
              "message" => "private detail",
              "data" => %{"opaque" => "secret"}
            }
          }
        ] do
      assert {:ok, encoded} = Wire.encode(envelope)
      assert {:ok, ^envelope} = Wire.decode(encoded)
    end

    assert {:ok, omitted} = Wire.decode(~s({"id":1,"method":"config/read"}))
    refute Map.has_key?(omitted, "params")
  end

  test "message direction is shape-based; request IDs retain integer/string distinction" do
    assert Wire.classify(%{"id" => 1, "method" => "method"}) == :request
    assert Wire.classify(%{"method" => "event"}) == :notification
    assert Wire.classify(%{"id" => "1", "result" => nil}) == :response
    assert Wire.classify(%{"id" => 1, "error" => %{"code" => 1, "message" => "x"}}) == :error

    for message <- [
          nil,
          [],
          %{},
          %{"id" => nil, "result" => nil},
          %{"id" => 1.0, "method" => "x"},
          %{"id" => 9_223_372_036_854_775_808, "method" => "x"},
          %{"id" => 1, "result" => nil, "error" => %{}},
          %{"method" => "x", "result" => nil},
          %{"id" => 1, "error" => %{"code" => "1", "message" => "x"}}
        ] do
      assert Wire.classify(message) == :invalid
      assert {:error, %Failure{}} = Wire.encode(message)
    end
  end

  test "native trace context validates known fields and preserves future additions" do
    for trace <- [
          nil,
          %{},
          %{"traceparent" => nil},
          %{"traceparent" => "00-synthetic", "tracestate" => "fixture", "future" => [nil]}
        ] do
      request = %{"id" => "trace", "method" => "thread/list", "trace" => trace}
      assert {:ok, binary} = Wire.encode(request)
      assert {:ok, ^request} = Wire.decode(binary)
    end

    for trace <- [1, [], %{"traceparent" => 1}, %{"tracestate" => false}] do
      assert {:error, %Failure{code: :invalid_envelope}} =
               Wire.encode(%{"id" => 1, "method" => "thread/list", "trace" => trace})
    end
  end

  test "reject unsafe JSON values without revealing them" do
    assert {:error, %Failure{code: :invalid_json}} = Wire.validate_value([1 | 2])

    for value <- [
          %{atom: "secret"},
          %{"secret" => self()},
          %{"secret" => {1, 2}},
          %{"secret" => Date.utc_today()},
          %{"secret" => <<255>>}
        ] do
      assert {:error, failure} = Wire.encode(%{"id" => 1, "method" => "x", "params" => value})
      refute inspect(failure) =~ "secret"
    end
  end

  test "decode rejects duplicate keys, invalid frames and oversized/deep documents" do
    for binary <- [
          "[]",
          "null",
          "{}{}",
          ~s({"id":1,"id":2,"result":null}),
          ~s({"id":1,"result":{"x":1,"x":2}}),
          <<255>>,
          ~s({"id":1,)
        ] do
      assert {:error, %Failure{}} = Wire.decode(binary)
    end

    assert {:error, %Failure{code: :invalid_json}} = Wire.decode(~s({"method":"x"}) <> <<11>>)
    assert {:error, %Failure{code: :invalid_json}} = Wire.decode(~s({"method":"x"}) <> "\u00a0")

    assert {:error, %Failure{code: :message_too_large}} =
             Wire.decode(~s({"method":"x"}), max_bytes: 2)

    assert {:error, %Failure{code: :message_too_deep}} =
             Wire.decode(~s({"method":"x","params":[[[1]]]}), max_depth: 1)

    assert {:error, %Failure{code: :message_too_deep}} =
             Wire.encode(%{"method" => "x", "params" => [[1]]}, max_depth: 1)

    assert {:ok, _} = Wire.decode(~s( {"method":"x","params":"[\\\"{"}  ))
  end
end
