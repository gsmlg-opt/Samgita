defmodule SamgitaProtocolCodex.IntegerFormatTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema}

  test "uint8 output values retain the full unsigned byte range and integer type" do
    schema = %{"type" => "integer", "format" => "uint8"}

    for value <- [0, 1, 255], do: assert(:ok = Schema.validate(schema, value))

    for value <- [-1, 256, 1.5, "1", false, nil] do
      assert {:error, %Error{code: :schema_violation}} = Schema.validate(schema, value)
    end
  end
end
