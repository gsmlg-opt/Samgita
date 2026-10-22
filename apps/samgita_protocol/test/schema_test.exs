defmodule SamgitaProtocol.SchemaTest do
  use ExUnit.Case, async: true
  alias SamgitaProtocol.{Capabilities, Codec, Error, Event, Schema}

  import SamgitaProtocol.TestFixtures

  test "event redelivery preserves identity, time and causal metadata" do
    original = event()
    assert {:ok, redelivery} = Event.retry(original, "delivery-2")
    assert redelivery == Map.put(original, "delivery_attempt_id", "delivery-2")
    assert {:error, %Error{code: "invalid_params"}} = Event.retry(original, "delivery-1")
  end

  test "event delivery round trips without creating an execution session" do
    message = request("project/event.receive", %{"event" => event()}, %{"command_id" => "cmd-1"})
    assert {:ok, json} = Codec.encode(message)
    assert {:ok, ^message} = Codec.decode(json)
    refute Map.has_key?(message["params"], "thread_id")
  end

  test "unsupported versions, fields, methods and malformed JSON fail explicitly" do
    m = request("thread/read", %{"thread_id" => "thread-1"})

    for bad <- [
          Map.put(m, "schema_version", "9.0"),
          Map.put(m, "unknown", true),
          Map.put(m, "id", nil),
          Map.put(m, "method", "run/arbitrary"),
          put_in(m, ["params", "thread_id"], 12)
        ] do
      assert {:error, %Error{}} = Schema.validate(bad)
    end

    assert {:error, %Error{code: "parse_error"}} = Codec.decode("{broken")
    assert {:error, %Error{code: "invalid_message"}} = Codec.decode("[]")

    assert {:error, %Error{code: "invalid_message"}} =
             Codec.decode(String.duplicate("x", 20), max_frame_bytes: 10)
  end

  test "non-JSON Elixir values produce typed errors rather than escaping the codec" do
    for value <- [%URI{scheme: "secret"}, self(), %{"nested" => %URI{}}] do
      assert {:error, %Error{code: "invalid_message"}} = Codec.encode(value)
    end

    assert {:error, %Error{code: "invalid_params"}} = Event.validate(%URI{})
  end

  test "state-changing operations need command identity and scoped task references" do
    m =
      request("turn/start", %{
        "thread_id" => "thread-1",
        "input" => [%{"type" => "text", "text" => "hi"}]
      })

    assert {:error, %Error{code: "invalid_message"}} = Schema.validate(m)
    assert {:ok, _} = Schema.validate(Map.put(m, "command_id", "cmd-1"))
    assert {:error, %Error{}} = Schema.validate(Map.put(m, "task_ref", "task-alone"))
  end

  test "typed errors exclude arbitrary messages and negotiation rejects required omissions" do
    error = Error.new("unsupported_capability", %{"capability" => "approvals.v1"})
    assert {:ok, ^error} = error |> Error.to_map() |> Error.from_map()

    assert {:error, %Error{code: "unsupported_capability"}} =
             Capabilities.negotiate(["project_events.v1"], ["sessions.v1"], ["sessions.v1"])

    assert {:ok, ["sessions.v1"]} =
             Capabilities.negotiate(["sessions.v1"], ["sessions.v1", "streaming.v1"], [])
  end

  test "processing completion does not imply authoritative project acceptance" do
    assert :ok =
             Schema.validate_result("project/event.report", %{
               "event_id" => "evt-1",
               "decision_id" => "d-1",
               "report_status" => "recorded",
               "management_acceptance" => "not_requested"
             })

    assert {:error, %Error{}} =
             Schema.validate_result("project/event.report", %{
               "event_id" => "evt-1",
               "status" => "completed"
             })
  end
end
