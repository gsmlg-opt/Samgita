defmodule StandaloneCodex.OrdinaryWorkflowsTest do
  use ExUnit.Case, async: false

  alias StandaloneCodex.Workflows

  @moduletag timeout: 60_000

  test "independent native tool, text, interruption, recovery and owned cleanup" do
    binary = System.get_env("CODEX_BINARY")
    script = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    assert is_binary(binary) and File.regular?(binary), "BLOCKED_ENV: CODEX_BINARY required"

    assert is_binary(script) and File.regular?(script),
           "BLOCKED_ENV: CODEX_MODEL_FIXTURE_SCRIPT required"

    root =
      Path.join(
        System.tmp_dir!(),
        "standalone-ordinary-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)
    report = Workflows.run(binary, root, script)
    assert Workflows.cleaned_up?(report)
    assert_completed(report.completed)
    assert_recovery(report.completed)
    assert_interrupted(report.interrupted)

    assert :code.which(Samgita.Repo) == :non_existing
    assert :code.which(Phoenix.Endpoint) == :non_existing
    assert :code.which(Ecto.Repo) == :non_existing

    refute Enum.any?(Application.started_applications(), fn {app, _, _} ->
             app in [:samgita, :samgita_web, :ecto, :phoenix]
           end)

    # Preserve the disposable evidence if a behavioral or cleanup assertion fails.
    File.rm_rf!(root)
  end

  defp assert_completed(workflow) do
    thread = workflow.thread
    turn = workflow.turn
    assert is_binary(thread) and is_binary(turn)
    assert workflow.operations.create.response["result"]["thread"]["id"] == thread
    assert workflow.operations.submit.response["result"]["turn"]["id"] == turn
    assert workflow.operations.submit.request["params"]["threadId"] == thread

    assert [tool] = Enum.filter(workflow.events, &(&1.kind == :server_request))
    assert tool == workflow.tool
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == 1

    assert tool.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert workflow.tool_result == %{
             "success" => true,
             "contentItems" => [%{"type" => "inputText", "text" => "Synthetic lookup completed"}]
           }

    deltas = notification_params(workflow.events, "item/agentMessage/delta")
    assert deltas != []
    assert Enum.map_join(deltas, & &1["delta"]) == workflow.expected_answer
    assert Enum.all?(deltas, &(&1["threadId"] == thread and &1["turnId"] == turn))
    assert [message_id] = deltas |> Enum.map(& &1["itemId"]) |> Enum.uniq()

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             notification_params(workflow.events, "turn/completed")

    assert [%{"id" => ^turn, "status" => "completed"} = history_turn] =
             workflow.history.response["result"]["thread"]["turns"]

    assert [dynamic] = Enum.filter(history_turn["items"], &(&1["type"] == "dynamicToolCall"))
    assert dynamic["id"] == "fixture-call-1"
    assert dynamic["tool"] == "fixture_lookup"
    assert dynamic["arguments"] == %{"key" => "synthetic"}
    assert dynamic["status"] == "completed"
    assert dynamic["success"] == true
    assert dynamic["contentItems"] == workflow.tool_result["contentItems"]
    assert [message] = Enum.filter(history_turn["items"], &(&1["type"] == "agentMessage"))
    assert message["id"] == message_id
    assert message["text"] == workflow.expected_answer

    completed_items = notification_params(workflow.events, "item/completed")

    for item <- [dynamic, message] do
      assert [completion] = Enum.filter(completed_items, &(&1["item"]["id"] == item["id"]))
      assert completion["threadId"] == thread
      assert completion["turnId"] == turn
      assert completion["item"] == item
      assert is_integer(completion["completedAtMs"])
    end

    assert [first, continuation] = workflow.provider_before_recovery
    refute Enum.any?(first["input"], &(&1["type"] == "function_call_output"))
    assert [call] = Enum.filter(continuation["input"], &(&1["type"] == "function_call"))
    assert call["call_id"] == tool.wire["params"]["callId"]
    assert call["name"] == "fixture_lookup"
    assert JSON.decode!(call["arguments"]) == %{"key" => "synthetic"}

    assert [%{"call_id" => "fixture-call-1", "output" => "Synthetic lookup completed"}] =
             Enum.filter(continuation["input"], &(&1["type"] == "function_call_output"))
  end

  defp assert_recovery(workflow) do
    recovery = workflow.recovery
    assert %{generation: 1, pending: 0, uncertain: 0, gap: nil} = recovery.before

    assert %{generation: 2, pending: 0, uncertain: 0, phase: :ready, gap: gap} = recovery.after
    assert gap.reason == :explicit_reconnect and gap.generation == 1
    assert recovery.before.instance_id == recovery.after.instance_id
    assert %{"result" => %{}} = recovery.initialize
    assert [warm, cold] = workflow.native_pids
    assert is_integer(warm) and is_integer(cold) and warm != cold

    original = workflow.history.response["result"]["thread"]

    for operation <- [recovery.cold_read, recovery.resume, recovery.history] do
      assert operation.request["params"]["threadId"] == workflow.thread
      assert operation.response["result"]["thread"]["id"] == workflow.thread
    end

    for operation <- [recovery.cold_read, recovery.history] do
      restored = operation.response["result"]["thread"]
      assert restored["turns"] == original["turns"]
      assert restored["path"] == original["path"]
    end

    assert workflow.provider_after_recovery == workflow.provider_before_recovery
    assert length(workflow.provider_after_recovery) == 2
    assert notification_params(recovery.events, "turn/started") == []
    assert notification_params(recovery.events, "turn/completed") == []
    refute Enum.any?(recovery.events, &(&1.kind == :server_request))
  end

  defp assert_interrupted(workflow) do
    thread = workflow.thread
    turn = workflow.turn
    assert [tool] = Enum.filter(workflow.events, &(&1.kind == :server_request))
    assert tool == workflow.tool
    assert tool.wire["params"]["threadId"] == thread
    assert tool.wire["params"]["turnId"] == turn
    assert tool.wire["params"]["callId"] == "fixture-call-1"
    assert workflow.interrupt.request["method"] == "turn/interrupt"
    assert workflow.interrupt.request["params"] == %{"threadId" => thread, "turnId" => turn}
    assert workflow.interrupt.response["result"] == %{}
    assert workflow.interrupt.response["id"] == workflow.interrupt.request["id"]

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "interrupted"}}] =
             notification_params(workflow.events, "turn/completed")

    assert [%{"id" => ^turn, "status" => "interrupted"}] =
             workflow.history.response["result"]["thread"]["turns"]

    assert [_first] = workflow.provider_requests
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = workflow.status
    assert workflow.interaction_outcomes == []

    refute Enum.any?(notification_params(workflow.events, "item/completed"), fn params ->
             params["item"]["type"] == "agentMessage"
           end)
  end

  defp notification_params(events, method) do
    for event <- events,
        event.kind == :notification and event.wire["method"] == method,
        do: event.wire["params"]
  end
end
