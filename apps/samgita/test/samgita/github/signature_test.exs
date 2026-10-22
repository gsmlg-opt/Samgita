defmodule Samgita.GitHub.SignatureTest do
  use ExUnit.Case, async: true
  alias Samgita.GitHub.Signature

  @secret "webhook-test-secret"

  test "authenticates exact raw bytes, including JSON formatting and key order" do
    raw = ~s({"action":"opened", "number":1}\n)
    signature = sign(raw)
    assert :ok = Signature.verify(raw, signature, @secret)

    for changed <- [~s({"action":"opened","number":1}), ~s({"number":1, "action":"opened"}\n)] do
      assert {:error, :invalid_signature} = Signature.verify(changed, signature, @secret)
    end

    assert {:error, :invalid_signature} = Signature.verify(raw, signature, "another-secret")
  end

  test "rejects missing, malformed and non-SHA256 signatures" do
    raw = "{}"
    valid = sign(raw)

    for invalid <- [
          nil,
          [],
          [valid],
          "",
          "sha1=" <> String.duplicate("0", 40),
          "SHA256=" <> String.duplicate("0", 64),
          valid <> "\n",
          " " <> valid,
          "sha256=" <> String.duplicate("g", 64),
          "sha256=00",
          String.duplicate("0", 64)
        ] do
      assert {:error, :invalid_signature} = Signature.verify(raw, invalid, @secret)
    end

    assert {:error, :invalid_signature} = Signature.verify(nil, valid, @secret)
    assert {:error, :invalid_signature} = Signature.verify(raw, valid, "")
  end

  test "rejects a raw body above the ingress limit" do
    raw = String.duplicate("x", 1_048_577)
    assert {:error, :invalid_signature} = Signature.verify(raw, sign(raw), @secret)
  end

  defp sign(raw),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, @secret, raw), case: :lower)
end
