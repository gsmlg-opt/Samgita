defmodule SamgitaProtocolCodex.TimelineSchemaTest do
  use ExUnit.Case, async: true

  alias SamgitaProtocolCodex.{Error, Schema}
  alias SamgitaProtocolCodex.Schema.Validator

  @export Path.expand(
            "../priv/upstream/0.163.0/experimental/v2/ThreadTimelineListResponse.json",
            __DIR__
          )

  test "native timeline turn boundaries follow pinned serde naming without rewriting values" do
    result = page([started(), completed()])
    original_bytes = JSON.encode!(result)

    assert :ok = Schema.validate_result(:server_response, "thread/timeline/list", result)
    assert JSON.encode!(result) == original_bytes

    assert :ok =
             Schema.validate_result(
               :server_response,
               "thread/timeline/list",
               page([
                 Map.put(started(), "startedAt", nil),
                 Map.merge(completed(), %{
                   "startedAt" => nil,
                   "completedAt" => nil,
                   "durationMs" => nil
                 })
               ])
             )
  end

  test "the official JSON exporter mismatch remains preserved and independently observable" do
    document = @export |> File.read!() |> JSON.decode!()
    native = page([started(), completed()])

    assert {:error, %Error{code: :schema_violation}} = Validator.validate(document, native)

    exported =
      for entry <- native["data"] do
        Map.new(entry, fn {key, value} ->
          {Map.get(
             %{
               "turnId" => "turn_id",
               "startedAt" => "started_at",
               "completedAt" => "completed_at",
               "durationMs" => "duration_ms"
             },
             key,
             key
           ), value}
        end)
      end

    assert :ok = Validator.validate(document, page(exported))

    assert {:error, %Error{code: :schema_violation}} =
             Schema.validate_result(:server_response, "thread/timeline/list", page(exported))
  end

  test "native names retain required identities, integer bounds, nullable times and union validation" do
    invalid = [
      Map.delete(started(), "turnId"),
      Map.put(started(), "turnId", nil),
      Map.put(started(), "startedAt", "100"),
      Map.put(started(), "startedAt", 9_223_372_036_854_775_808),
      Map.put(completed(), "completedAt", false),
      Map.put(completed(), "durationMs", 1.5),
      Map.put(completed(), "status", "invented"),
      Map.put(completed(), "error", %{}),
      Map.put(completed(), "type", "unknown")
    ]

    for entry <- invalid do
      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_result(:server_response, "thread/timeline/list", page([entry]))
    end

    # Opaque additions remain lossless, just as in other upstream output schemas.
    assert :ok =
             Schema.validate_result(
               :server_response,
               "thread/timeline/list",
               page([
                 Map.put(started(), "future", %{"opaque" => [nil, "λ"]})
               ])
             )
  end

  defp started,
    do: %{
      "type" => "turnStarted",
      "position" => 1,
      "turnId" => "synthetic-turn",
      "startedAt" => 100
    }

  defp completed,
    do: %{
      "type" => "turnCompleted",
      "position" => 3,
      "turnId" => "synthetic-turn",
      "status" => "completed",
      "error" => nil,
      "startedAt" => 100,
      "completedAt" => 101,
      "durationMs" => 42
    }

  defp page(data),
    do: %{"data" => data, "nextCursor" => nil, "activeRealtimeSessionAtPageStart" => nil}
end
