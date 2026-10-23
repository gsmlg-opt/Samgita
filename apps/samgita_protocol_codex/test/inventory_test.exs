defmodule SamgitaProtocolCodex.InventoryTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocolCodex.Schema
  alias SamgitaProtocolCodex.Schema.Validator

  @fixture Path.expand("fixtures/native/contracts.json", __DIR__)
  @root Path.expand("../priv/upstream/0.163.0", __DIR__)

  test "every advertised request, response and notification has a valid synthetic example" do
    corpus = @fixture |> File.read!() |> JSON.decode!()
    assert corpus["evidence_kind"] == "synthetic-schema-only"
    assert length(corpus["messages"]) == 460

    directions = %{
      "client_request" => :client_request,
      "server_request" => :server_request,
      "server_notification" => :server_notification,
      "client_notification" => :client_notification,
      "server_response" => :server_response,
      "client_response" => :client_response
    }

    for row <- corpus["messages"] do
      value = row["value"]
      direction = directions[row["direction"]]
      opts = [experimental: true, params_present: is_map(value) and Map.has_key?(value, "params")]

      result =
        case direction do
          direction when direction in [:client_request, :server_request] ->
            Schema.validate_request(
              row["method"],
              value["params"],
              Keyword.put(opts, :direction, direction)
            )

          direction when direction in [:client_notification, :server_notification] ->
            Schema.validate_notification(direction, row["method"], value["params"], opts)

          direction ->
            Schema.validate_result(direction, row["method"], value, experimental: true)
        end

      assert result == :ok, row["id"] <> " " <> inspect(result)
    end
  end

  @tag timeout: 120_000
  test "every inventoried field and union/enum alternative is interpreted against pinned schemas" do
    corpus = @fixture |> File.read!() |> JSON.decode!()
    assert length(corpus["contracts"]) == 6621

    documents =
      [Path.join(@root, "experimental/**/*.json"), Path.join(@root, "supplemental/**/*.json")]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Map.new(fn path ->
        name = path |> Path.relative_to(@root) |> String.replace_prefix("experimental/", "")
        {name, path |> File.read!() |> JSON.decode!()}
      end)

    for row <- corpus["contracts"] do
      document = documents[row["schema"]]
      assert {:ok, schema} = Validator.resolve(document, "#" <> row["pointer"])
      result = Validator.validate(schema, row["value"], document)
      assert result == :ok == row["valid"], row["id"] <> " " <> inspect(result)
    end
  end
end
