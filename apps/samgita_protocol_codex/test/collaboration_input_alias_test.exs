defmodule SamgitaProtocolCodex.CollaborationInputAliasTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand("../priv/upstream/0.163.0/experimental/ClientRequest.json", __DIR__)
  @aliases ~w(code pair_programming execute custom)
  @methods ["turn/start", "thread/settings/update"]

  test "native mode input aliases retain caller values and nullable settings" do
    for method <- @methods,
        mode <- ["plan", "default" | @aliases],
        extra <- [
          %{},
          %{"reasoning_effort" => nil, "developer_instructions" => nil},
          %{"reasoning_effort" => "custom-effort", "developer_instructions" => "Owned λ🙂"}
        ] do
      params = params(method, mode, extra)
      wire = %{"id" => "owned-mode-input", "method" => method, "params" => params}
      bytes = JSON.encode!(wire)

      assert :ok = Schema.validate_request(method, params, experimental: true)
      assert {:ok, ^bytes} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(bytes)
    end
  end

  test "official exports remain canonical while native input aliases are accepted" do
    document = @export |> File.read!() |> JSON.decode!()
    assert document["definitions"]["ModeKind"]["enum"] == ["plan", "default"]

    for method <- @methods, mode <- @aliases do
      wire = %{"id" => "owned-mode-export", "method" => method, "params" => params(method, mode)}

      assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, wire)
      assert :ok = Schema.validate_request(method, wire["params"], experimental: true)
    end
  end

  test "mode aliases preserve required fields and reject unknown or invalid types" do
    for method <- @methods do
      valid = params(method, "code")

      for invalid <- [
            put_in(valid, ["collaborationMode", "mode"], "invented-mode"),
            put_in(valid, ["collaborationMode", "mode"], nil),
            put_in(valid, ["collaborationMode", "mode"], 7),
            put_in(valid, ["collaborationMode", "settings"], %{}),
            put_in(valid, ["collaborationMode", "settings", "model"], false),
            put_in(valid, ["collaborationMode", "settings", "developer_instructions"], [])
          ] do
        assert {:error, %Error{code: :schema_violation}} =
                 Schema.validate_request(method, invalid, experimental: true)
      end
    end
  end

  test "aliases retain collaboration field experimental negotiation" do
    for method <- @methods, mode <- ["default" | @aliases] do
      assert {:error, %Error{code: :experimental_api_required}} =
               Schema.validate_request(method, params(method, mode))
    end
  end

  defp params(method, mode, extra \\ %{}) do
    base = %{
      "threadId" => "owned-thread",
      "collaborationMode" => %{
        "mode" => mode,
        "settings" => Map.merge(%{"model" => "mock-model"}, extra)
      }
    }

    if method == "turn/start", do: Map.put(base, "input", []), else: base
  end
end
