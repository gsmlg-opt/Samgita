defmodule SamgitaCodexDriver.NativeActiveTurnSettingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/active_turn_settings_fixture.py", __DIR__)
  @model_a "step-settings-a"
  @model_b "step-settings-b"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Synthetic lookup that waits for an explicit test response",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-turn-settings-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario] || "active")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    %{binary: binary, root: root, fixture: fixture}
  end

  test "current-turn settings reach the next capture without changing the first capture or future turn",
       context do
    {pid, thread, turn, tool, events} = active(context)
    assert_applied(pid, patch(thread, turn))
    # Omission leaves the published settings intact; neither update starts work.
    assert_applied(pid, target(thread, turn))
    assert_pending(context, pid)
    finish_active(context, pid, thread, turn, tool, events)
    finish_future(pid, thread)

    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    assert_initial(first)
    assert_changed(continued, "priority")
    assert_initial(future)
  end

  test "null tier clears while null model effort and summary preserve the published values",
       context do
    {pid, thread, turn, tool, events} = active(context)
    assert_applied(pid, patch(thread, turn))

    assert_applied(
      pid,
      Map.merge(target(thread, turn), %{
        "model" => nil,
        "effort" => nil,
        "summary" => nil,
        "serviceTier" => nil
      })
    )

    assert_pending(context, pid)
    finish_active(context, pid, thread, turn, tool, events)
    finish_future(pid, thread)

    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    assert_initial(first)
    assert_changed(continued, :absent)
    assert_initial(future)
  end

  test "advertised custom effort reaches the next capture without changing future defaults",
       context do
    {pid, thread, turn, tool, events} = active(context)
    assert_applied(pid, Map.put(patch(thread, turn), "effort", "fixture-effort"))
    assert_pending(context, pid)
    finish_active(context, pid, thread, turn, tool, events)
    finish_future(pid, thread)

    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    assert_initial(first)
    assert continued["model"] == @model_b

    assert continued["reasoning"] == %{
             "effort" => "fixture-effort",
             "summary" => "detailed"
           }

    assert continued["service_tier"] == "priority"
    assert_initial(future)
  end

  test "idle completed and mismatched targets cannot start work or consume the pending native tool",
       context do
    pid = start(context)
    thread = settings_thread(context, pid)

    assert %{"status" => "targetUnavailable"} =
             call(pid, "turn/settings/update", patch(thread, "never-started"))

    assert [] = ModelFixture.requests(context.fixture)
    {turn, tool, events} = begin_active(context, pid, thread)

    assert %{"status" => "targetUnavailable"} =
             call(pid, "turn/settings/update", patch(thread, "wrong-turn"))

    assert_pending(context, pid)
    assert_applied(pid, patch(thread, turn))
    finish_active(context, pid, thread, turn, tool, events)
    before = ModelFixture.requests(context.fixture)

    assert %{"status" => "targetUnavailable"} =
             call(pid, "turn/settings/update", patch(thread, turn))

    assert ModelFixture.requests(context.fixture) == before
    finish_future(pid, thread)
    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    assert_initial(first)
    assert_changed(continued, "priority")
    assert_initial(future)
  end

  test "native unknown-field and malformed patches preserve the pending tool and both settings owners",
       context do
    {pid, thread, turn, tool, events} = active(context)
    params = patch(thread, turn)

    for field <- ["personality", "permissions", "cwd", "collaborationMode", "scope"] do
      error =
        upstream_error(pid, "turn/settings/update", Map.put(params, field, "unsupported"),
          validation: :wire
        )

      assert error["code"] == -32_600
      assert error["message"] =~ "unknown field"
      assert error["message"] =~ field
      assert_pending(context, pid)
    end

    for invalid <- [
          Map.delete(params, "turnId"),
          Map.put(params, "turnId", nil),
          Map.put(params, "threadId", 17),
          Map.put(params, "model", 17),
          Map.put(params, "effort", 17),
          Map.put(params, "effort", ""),
          Map.put(params, "summary", "unsupported"),
          Map.put(params, "serviceTier", 17)
        ] do
      error = upstream_error(pid, "turn/settings/update", invalid, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert_pending(context, pid)
    end

    finish_active(context, pid, thread, turn, tool, events)
    finish_future(pid, thread)
    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    Enum.each([first, continued, future], &assert_initial/1)
  end

  @tag scenario: "feature_disabled"
  test "disabled step switching rejects publication without consuming an existing tool",
       context do
    {pid, thread, turn, tool, events} = active(context)

    assert upstream_error(pid, "turn/settings/update", patch(thread, turn)) == %{
             "code" => -32_600,
             "message" => "turn settings updates require the step_model_switching feature"
           }

    assert_pending(context, pid)
    finish_active(context, pid, thread, turn, tool, events)
    finish_future(pid, thread)
    assert [first, continued, future] = ModelFixture.requests(context.fixture)
    Enum.each([first, continued, future], &assert_initial/1)
  end

  @tag scenario: "assistant"
  test "stable-only negotiation rejects the experimental method locally and on the native wire",
       context do
    pid = start(context, experimental: false)
    thread = thread(context, pid, %{"model" => @model_a})
    params = patch(thread, "never-started")

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(pid, "turn/settings/update", params)

    assert upstream_error(pid, "turn/settings/update", params, validation: :wire) == %{
             "code" => -32_600,
             "message" => "turn/settings/update requires experimentalApi capability"
           }

    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
    finish_future(pid, thread)
    assert [request] = ModelFixture.requests(context.fixture)
    assert_initial(request)
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp active(context) do
    pid = start(context)
    thread = settings_thread(context, pid)
    {turn, tool, events} = begin_active(context, pid, thread)
    {pid, thread, turn, tool, events}
  end

  defp settings_thread(context, pid),
    do: thread(context, pid, %{"model" => @model_a, "dynamicTools" => [@lookup]})

  defp begin_active(context, pid, thread) do
    turn = start_turn(pid, thread, text("Initial synthetic settings input"))
    {tool, events} = await_tool(pid, [], System.monotonic_time(:millisecond) + 10_000)
    assert_tool(pid, thread, turn, tool)
    assert_pending(context, pid)
    assert [first] = ModelFixture.requests(context.fixture)
    assert_initial(first)
    {turn, tool, events}
  end

  defp await_tool(pid, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    refute notification(events, "turn/completed")
    requests = Enum.filter(events, &(&1.kind == :server_request))

    case requests do
      [tool] ->
        {tool, events}

      [] ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {:codex_driver, ^pid, :events_available} -> await_tool(pid, events, deadline)
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap awaiting settings tool")
        after
          remaining -> flunk("Real Codex did not request the fixed settings tool")
        end

      _ ->
        flunk("Unexpected additional native interaction")
    end
  end

  defp assert_tool(pid, thread, turn, tool) do
    assert tool.kind == :server_request
    assert tool.wire["method"] == "item/tool/call"
    assert is_integer(tool.wire["id"]) or is_binary(tool.wire["id"])
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp assert_pending(context, pid) do
    assert [_] = ModelFixture.requests(context.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp finish_active(context, pid, thread, turn, tool, events) do
    # Only this exact native request receives this fixed response. Never approve
    # arbitrary requests, and re-check all association/argument fields at reply time.
    assert_tool(pid, thread, turn, tool)
    assert_pending(context, pid)

    assert :ok =
             Session.respond(pid, tool.handle, {
               :ok,
               %{
                 "contentItems" => [
                   %{"type" => "inputText", "text" => "Synthetic lookup completed"}
                 ],
                 "success" => true
               }
             })

    events = events ++ finish_turn(pid, thread, turn)

    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == thread
      assert params["turn"]["id"] == turn
    end

    assert [_, continued] = ModelFixture.requests(context.fixture)

    assert [output] =
             Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

    assert output["call_id"] == "fixture-call-1"
    assert output["output"] == "Synthetic lookup completed"
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp finish_future(pid, thread) do
    turn = start_turn(pid, thread, text("Future turn must use the original settings"))
    finish_turn(pid, thread, turn)
  end

  defp target(thread, turn), do: %{"threadId" => thread, "turnId" => turn}

  defp patch(thread, turn),
    do:
      Map.merge(target(thread, turn), %{
        "model" => @model_b,
        "effort" => "high",
        "summary" => "detailed",
        "serviceTier" => "priority"
      })

  defp assert_applied(pid, params),
    do: assert(call(pid, "turn/settings/update", params) == %{"status" => "applied"})

  defp assert_initial(request) do
    assert request["model"] == @model_a
    assert request["reasoning"] == %{"effort" => "low", "summary" => "concise"}
    refute Map.has_key?(request, "service_tier")
  end

  defp assert_changed(request, tier) do
    assert request["model"] == @model_b
    assert request["reasoning"] == %{"effort" => "high", "summary" => "detailed"}

    if tier == :absent,
      do: refute(Map.has_key?(request, "service_tier")),
      else: assert(request["service_tier"] == tier)
  end

  defp text(value), do: [%{"type" => "text", "text" => value}]
end
