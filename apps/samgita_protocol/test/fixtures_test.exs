defmodule SamgitaProtocol.FixturesTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Codec, Schema}
  alias SamgitaProtocol.Schema.Document

  test "versioned valid fixtures round trip and correlated results satisfy their request" do
    for path <- Path.wildcard(Path.join(__DIR__, "fixtures/v1/*.json")) do
      assert {:ok, message} = Codec.decode(File.read!(path)), path
      assert {:ok, json} = Codec.encode(message)
      assert {:ok, ^message} = Codec.decode(json)

      if String.ends_with?(path, ".response.json") do
        request =
          path
          |> String.replace(".response.json", ".request.json")
          |> File.read!()
          |> JSON.decode!()

        assert :ok = Schema.validate_reply(request, message)
      end
    end
  end

  test "invalid fixtures return their named typed error" do
    for path <- Path.wildcard(Path.join(__DIR__, "fixtures/invalid/*.json")) do
      assert {:error, error} = Codec.decode(File.read!(path))
      assert error.code == Path.basename(path, ".json")
    end
  end

  test "published JSON schema is generated from the executable versioned definitions" do
    path = Path.join(__DIR__, "../priv/schemas/1.0/protocol.schema.json")
    assert JSON.decode!(File.read!(path)) == Document.build()
  end
end
