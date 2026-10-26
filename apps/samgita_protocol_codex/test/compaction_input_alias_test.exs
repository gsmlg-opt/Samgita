defmodule SamgitaProtocolCodex.CompactionInputAliasTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @tags ["compaction", "compaction_summary"]

  test "native compaction input alias keeps the exact original tag and optional metadata" do
    for tag <- @tags,
        additions <- [
          %{},
          %{"id" => nil, "internal_chat_message_metadata_passthrough" => nil},
          %{
            "id" => "owned-checkpoint-λ",
            "internal_chat_message_metadata_passthrough" => %{"turn_id" => "owned-turn"},
            "future" => %{"opaque" => [nil, "λ"]}
          }
        ] do
      item = Map.merge(checkpoint(tag), additions)
      wire = %{"id" => "alias-input", "method" => "thread/resume", "params" => params(item)}
      bytes = JSON.encode!(wire)

      assert :ok = Schema.validate_request("thread/resume", wire["params"], experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "the official export remains canonical while the native input alias is accepted" do
    document = @export |> File.read!() |> JSON.decode!()

    native = %{
      "id" => "alias-export",
      "method" => "thread/resume",
      "params" => params(checkpoint())
    }

    canonical = put_in(native, ["params", "history"], [checkpoint("compaction")])

    assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, native)
    assert :ok = Validator.validate(document, canonical)
    assert :ok = Schema.validate_request("thread/resume", native["params"], experimental: true)
  end

  test "alias branch retains required data, field types and experimental presence" do
    for tag <- @tags do
      item = checkpoint(tag)

      assert {:error,
              %Error{
                code: :experimental_api_required,
                details: %{"path" => ["params", "history"]}
              }} = Schema.validate_request("thread/resume", params(item))

      for invalid <- [
            Map.delete(item, "encrypted_content"),
            Map.put(item, "encrypted_content", nil),
            Map.put(item, "encrypted_content", 7),
            Map.put(item, "id", false),
            Map.put(item, "internal_chat_message_metadata_passthrough", []),
            Map.put(item, "internal_chat_message_metadata_passthrough", %{"turn_id" => 7}),
            Map.put(item, "type", "invented")
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request("thread/resume", params(invalid), experimental: true)
      end
    end
  end

  test "the alias does not broaden unrelated input unions" do
    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_request(
               "turn/start",
               %{"threadId" => "owned-thread", "input" => [checkpoint()]},
               experimental: true
             )
  end

  defp checkpoint(tag \\ "compaction_summary"),
    do: %{"type" => tag, "encrypted_content" => "SYNTHETIC_OPAQUE_CHECKPOINT"}

  defp params(item), do: %{"threadId" => "owned-source", "history" => [item]}
end
