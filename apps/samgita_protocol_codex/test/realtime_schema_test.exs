defmodule SamgitaProtocolCodex.RealtimeSchemaTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema}
  alias SamgitaProtocolCodex.Schema.Validator

  @methods ["thread/realtime/item/started", "thread/realtime/item/completed"]
  @export Path.expand("../priv/upstream/0.163.0/experimental/ServerNotification.json", __DIR__)

  test "timeline accepts an embedded native promoted realtime item" do
    assert :ok = validate_timeline(promoted())
  end

  test "promoted native realtime items validate losslessly in notifications and timeline" do
    for presentation <- [
          %{"type" => "wholeItem"},
          %{"type" => "inlineMarkdown"},
          %{"type" => "inlineVisualization", "index" => 2}
        ] do
      item = promoted(presentation)
      before = JSON.encode!(item)

      for method <- @methods do
        assert :ok = validate_notification(method, item)
      end

      assert :ok = validate_timeline(item)
      assert JSON.encode!(item) == before
    end
  end

  test "official export disagreement remains observable without changing original JSON" do
    document = @export |> File.read!() |> JSON.decode!()
    native = promoted()

    exported =
      native
      |> Map.delete("turnId")
      |> Map.delete("itemId")
      |> Map.merge(%{"turn_id" => "turn", "item_id" => "agent-item"})

    for method <- @methods do
      assert {:error, %Error{code: :schema_violation}} =
               Validator.validate(document, %{"method" => method, "params" => params(native)})

      assert :ok =
               Validator.validate(document, %{"method" => method, "params" => params(exported)})

      assert {:error, %Error{code: :schema_violation}} = validate_notification(method, exported)
    end

    assert {:error, %Error{code: :schema_violation}} = validate_timeline(exported)
  end

  test "required identities and presentation constraints survive the naming correction" do
    for item <- [
          Map.delete(promoted(), "turnId"),
          Map.delete(promoted(), "itemId"),
          Map.put(promoted(), "turnId", nil),
          Map.put(promoted(), "itemId", 1),
          promoted(%{"type" => "invented"}),
          promoted(%{"type" => "inlineVisualization", "index" => -1}),
          promoted(%{"type" => "inlineVisualization", "index" => 4_294_967_296}),
          promoted(%{"type" => "inlineVisualization", "index" => 1.5})
        ] do
      for method <- @methods do
        assert {:error, %Error{code: :schema_violation}} = validate_notification(method, item)
      end

      assert {:error, %Error{code: :schema_violation}} = validate_timeline(item)
    end
  end

  test "other realtime variants and notification capability gates remain intact" do
    for content <- [
          %{"type" => "realtimeSessionStarted"},
          %{"type" => "transcriptSegment", "role" => "assistant", "text" => "λ"},
          %{"type" => "realtimeSessionClosed", "outcome" => "ended"}
        ] do
      item = Map.merge(%{"id" => "realtime-item", "realtimeSessionId" => "session"}, content)
      for method <- @methods, do: assert(:ok = validate_notification(method, item))
      assert :ok = validate_timeline(item)
    end

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_notification(:server_notification, hd(@methods), params(promoted()))
  end

  defp promoted(presentation \\ %{"type" => "wholeItem"}),
    do: %{
      "id" => "realtime-item",
      "realtimeSessionId" => "session",
      "type" => "bemItemPromoted",
      "turnId" => "turn",
      "itemId" => "agent-item",
      "presentation" => presentation
    }

  defp params(item), do: %{"threadId" => "thread", "item" => item}

  defp validate_notification(method, item),
    do:
      Schema.validate_notification(:server_notification, method, params(item), experimental: true)

  defp validate_timeline(item),
    do:
      Schema.validate_result(:server_response, "thread/timeline/list", %{
        "data" => [%{"type" => "realtime", "position" => 1, "item" => item}],
        "nextCursor" => nil,
        "activeRealtimeSessionAtPageStart" => nil
      })
end
