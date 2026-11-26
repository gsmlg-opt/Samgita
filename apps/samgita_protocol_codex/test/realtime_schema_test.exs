defmodule SamgitaProtocolCodex.RealtimeSchemaTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema}
  alias SamgitaProtocolCodex.Schema.Validator

  @methods ["thread/realtime/item/started", "thread/realtime/item/completed"]
  @export Path.expand("../priv/upstream/current/experimental/ServerNotification.json", __DIR__)

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
      assert :ok = validate_history(item)
      assert JSON.encode!(item) == before
    end
  end

  test "official export disagreement remains observable without changing original JSON" do
    document = @export |> File.read!() |> JSON.decode!()

    for native <- [
          promoted(),
          Map.merge(
            %{"id" => "realtime-item", "realtimeSessionId" => "session"},
            accepted("start")
          ),
          Map.merge(%{"id" => "realtime-item", "realtimeSessionId" => "session"}, saved("chunk"))
        ] do
      exported =
        Map.new(native, fn {key, value} ->
          {Map.get(
             %{
               "turnId" => "turn_id",
               "itemId" => "item_id",
               "handoffId" => "handoff_id",
               "sourceEventIds" => "source_event_ids",
               "inputItemId" => "input_item_id"
             },
             key,
             key
           ), value}
        end)

      for method <- @methods do
        assert {:error, %Error{code: :schema_violation}} =
                 Validator.validate(document, %{"method" => method, "params" => params(native)})

        assert :ok =
                 Validator.validate(document, %{"method" => method, "params" => params(exported)})

        assert :ok = validate_notification(method, native)
        assert {:error, %Error{code: :schema_violation}} = validate_notification(method, exported)
      end

      assert {:error, %Error{code: :schema_violation}} = validate_timeline(exported)
      assert {:error, %Error{code: :schema_violation}} = validate_history(exported)
    end
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
          %{
            "type" => "frame",
            "channels" => %{"voice_transcript" => %{"role" => "user", "text" => "λ"}}
          },
          %{"type" => "transcriptSegment", "role" => "assistant", "text" => "λ"},
          %{"type" => "realtimeSessionClosed", "outcome" => "ended"},
          accepted("start"),
          accepted("steer"),
          saved("chunk"),
          saved("sessionEnd")
        ] do
      item = Map.merge(%{"id" => "realtime-item", "realtimeSessionId" => "session"}, content)
      for method <- @methods, do: assert(:ok = validate_notification(method, item))
      assert :ok = validate_timeline(item)
      assert :ok = validate_history(item)
    end

    assert {:error, %Error{code: :experimental_api_required}} =
             Schema.validate_notification(:server_notification, hd(@methods), params(promoted()))
  end

  test "observation time preserves the optional nullable integer output contract" do
    for item <- [
          promoted(),
          Map.put(promoted(), "observedAtMs", nil),
          Map.put(promoted(), "observedAtMs", -9_223_372_036_854_775_808),
          Map.put(promoted(), "observedAtMs", 9_223_372_036_854_775_807)
        ] do
      original = JSON.encode!(item)
      for method <- @methods, do: assert(:ok = validate_notification(method, item))
      assert :ok = validate_timeline(item)
      assert :ok = validate_history(item)
      assert JSON.encode!(item) == original
    end

    for value <- ["1", 1.5, false, -9_223_372_036_854_775_809, 9_223_372_036_854_775_808] do
      assert_invalid(Map.put(promoted(), "observedAtMs", value))
    end
  end

  test "frame and saved input variants retain required fields and enum constraints" do
    for content <- [
          %{"type" => "frame", "channels" => %{}},
          %{
            "type" => "frame",
            "channels" => %{"voiceTranscript" => %{"role" => "user", "text" => "λ"}}
          },
          %{
            "type" => "frame",
            "channels" => %{"voice_transcript" => %{"role" => "unknown", "text" => "λ"}}
          },
          Map.delete(accepted("start"), "handoffId"),
          Map.delete(accepted("start"), "inputItemId"),
          Map.put(accepted("start"), "sourceEventIds", [1]),
          accepted("unknown"),
          Map.put(saved("chunk"), "input", false),
          Map.delete(saved("chunk"), "sourceEventIds"),
          saved("unknown")
        ] do
      assert_invalid(
        Map.merge(%{"id" => "realtime-item", "realtimeSessionId" => "session"}, content)
      )
    end
  end

  defp accepted(mode),
    do: %{
      "type" => "turnInputAccepted",
      "handoffId" => "handoff",
      "turnId" => "turn",
      "mode" => mode,
      "sourceEventIds" => ["source"],
      "inputItemId" => "input-item",
      "input" => "λ"
    }

  defp saved(reason),
    do: %{
      "type" => "sessionInputSaved",
      "reason" => reason,
      "sourceEventIds" => ["source"],
      "inputItemId" => "input-item",
      "input" => "λ"
    }

  defp assert_invalid(item) do
    for method <- @methods do
      assert {:error, %Error{code: :schema_violation}} = validate_notification(method, item)
    end

    assert {:error, %Error{code: :schema_violation}} = validate_timeline(item)
    assert {:error, %Error{code: :schema_violation}} = validate_history(item)
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

  defp validate_history(item),
    do:
      Schema.validate_result(:server_response, "thread/realtime/list", %{
        "data" => [%{"position" => 1, "item" => item}],
        "nextCursor" => nil,
        "coverage" => "ready",
        "projectedThroughItemIndex" => 2,
        "snapshotEnd" => 2
      })
end
