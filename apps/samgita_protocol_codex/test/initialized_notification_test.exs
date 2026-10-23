defmodule SamgitaProtocolCodex.InitializedNotificationTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}

  for experimental <- [false, true] do
    @tag experimental: experimental
    test "initialized preserves optional params and additions, experimental=#{experimental}",
         context do
      profile = if context.experimental, do: "experimental", else: "stable"

      schema =
        Path.expand("../priv/upstream/0.163.0/#{profile}/ClientNotification.json", __DIR__)
        |> File.read!()
        |> JSON.decode!()

      canonical = %{"method" => "initialized"}

      variants =
        [canonical] ++
          Enum.map(
            [
              nil,
              %{},
              [],
              "Synthetic scalar",
              42,
              false,
              %{"nested" => [nil, %{"text" => "é🙂"}]}
            ],
            &Map.put(canonical, "params", &1)
          )

      for original <- variants,
          additions <- [%{}, %{"future" => %{"nested" => [nil, true, "é🙂"]}}] do
        wire = Map.merge(original, additions)

        assert :ok = Schema.validate(schema, wire)

        assert :ok =
                 Schema.validate_notification(:client_notification, "initialized", wire["params"],
                   experimental: context.experimental,
                   params_present: Map.has_key?(wire, "params")
                 )

        assert Wire.classify(wire) == :notification
        assert {:ok, encoded} = Wire.encode(wire)
        assert {:ok, ^wire} = Wire.decode(encoded)
      end

      for wire <- [%{}, %{"method" => nil}, %{"method" => 42}, %{"method" => "Initialized"}] do
        assert {:error, %Error{code: :schema_violation}} = Schema.validate(schema, wire)
      end
    end
  end
end
