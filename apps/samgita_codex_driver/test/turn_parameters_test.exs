defmodule SamgitaCodexDriver.TurnParametersTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup {TurnFixture, :setup}

  test "additional context preserves untrusted and application provider roles", context do
    pid = start(context)
    thread = thread(context, pid)
    input = [%{"type" => "text", "text" => "Inspect the synthetic context"}]

    turn =
      start_turn(pid, thread, input, %{
        "additionalContext" => %{
          "browser_info" => %{"kind" => "untrusted", "value" => "synthetic tab"},
          "automation_info" => %{"kind" => "application", "value" => "synthetic run"}
        }
      })

    events = finish_turn(pid, thread, turn)
    [request] = ModelFixture.requests(context.fixture)

    assert Enum.any?(request["input"], fn item ->
             item["role"] == "user" and
               %{
                 "type" => "input_text",
                 "text" => "<external_browser_info>synthetic tab</external_browser_info>"
               } in Map.get(item, "content", [])
           end)

    assert Enum.any?(request["input"], fn item ->
             item["role"] == "developer" and
               %{
                 "type" => "input_text",
                 "text" => "<automation_info>synthetic run</automation_info>"
               } in Map.get(item, "content", [])
           end)

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{
               "type" => "userMessage",
               "content" => [%{"type" => "text", "text" => "Inspect the synthetic context"}]
             }
           } = notification(events, "item/completed", &(&1["item"]["type"] == "userMessage"))
  end

  test "experimental turn fields reject disabled negotiation before provider dispatch", context do
    pid = start(context, experimental: false)
    thread = thread(context, pid)

    for {field, value} <- [
          {"additionalContext", %{"source" => %{"kind" => "untrusted", "value" => "local"}}},
          {"responsesapiClientMetadata", %{"source" => "synthetic"}}
        ] do
      error =
        upstream_error(
          pid,
          "turn/start",
          %{
            "threadId" => thread,
            "input" => [%{"type" => "text", "text" => "Rejected experimental input"}],
            field => value
          },
          validation: :wire
        )

      assert error["code"] == -32_600
      assert error["message"] == "turn/start.#{field} requires experimentalApi capability"
    end

    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
  end

  test "provider turn metadata preserves causal IDs and filters reserved client keys", context do
    pid = start(context)
    thread = thread(context, pid)

    turn =
      start_turn(pid, thread, [%{"type" => "text", "text" => "Synthetic causal turn"}], %{
        "turnTrigger" => "goal",
        "parentTurnId" => "synthetic-parent",
        "rootTurnId" => "synthetic-root",
        "responsesapiClientMetadata" => %{
          "source" => "synthetic-composer",
          "workspace_kind" => "synthetic-project",
          "thread_id" => "spoofed-thread",
          "turn_id" => "spoofed-turn",
          "parent_turn_id" => "spoofed-parent",
          "root_turn_id" => "spoofed-root",
          "turn_trigger" => "spoofed-trigger"
        }
      })

    events = finish_turn(pid, thread, turn)

    for method <- ["turn/started", "turn/completed"] do
      assert %{
               "threadId" => ^thread,
               "turn" => %{"id" => ^turn, "rootTurnId" => "synthetic-root"}
             } = notification(events, method, &(&1["turn"]["id"] == turn))
    end

    [request] = ModelFixture.requests(context.fixture)
    client_metadata = request["client_metadata"]
    metadata = JSON.decode!(client_metadata["x-codex-turn-metadata"])

    assert %{
             "thread_id" => ^thread,
             "turn_id" => ^turn,
             "parent_turn_id" => "synthetic-parent",
             "root_turn_id" => "synthetic-root",
             "turn_trigger" => "goal",
             "source" => "synthetic-composer",
             "workspace_kind" => "synthetic-project"
           } = metadata

    refute Map.has_key?(client_metadata, "source")
    refute Map.has_key?(client_metadata, "workspace_kind")

    next_turn = start_turn(pid, thread, [%{"type" => "text", "text" => "Direct user turn"}])
    next_events = finish_turn(pid, thread, next_turn)

    assert %{"turn" => %{"id" => ^next_turn, "rootTurnId" => ^next_turn}} =
             notification(next_events, "turn/completed", &(&1["turn"]["id"] == next_turn))

    [_, next_request] = ModelFixture.requests(context.fixture)
    next_metadata = JSON.decode!(next_request["client_metadata"]["x-codex-turn-metadata"])
    assert next_metadata["root_turn_id"] == next_turn
    refute Map.has_key?(next_metadata, "parent_turn_id")
  end

  test "per-turn service tier does not replace the sticky tier and null clears sticky tier",
       context do
    pid = start(context)
    thread = thread(context, pid)

    # Pinned ModelInfo accepts flex even when mock-model has no advertised tiers.
    for extra <- [
          %{"serviceTier" => "flex"},
          %{"serviceTierForTurn" => "default"},
          %{},
          %{"serviceTierForTurn" => nil},
          %{"serviceTier" => nil},
          %{}
        ] do
      turn =
        start_turn(pid, thread, [%{"type" => "text", "text" => "Synthetic tier turn"}], extra)

      finish_turn(pid, thread, turn)
    end

    assert [sticky, overridden, inherited, null_inherited, cleared, still_cleared] =
             ModelFixture.requests(context.fixture)

    assert sticky["service_tier"] == "flex"
    refute Map.has_key?(overridden, "service_tier")
    assert inherited["service_tier"] == "flex"
    assert null_inherited["service_tier"] == "flex"
    refute Map.has_key?(cleared, "service_tier")
    refute Map.has_key?(still_cleared, "service_tier")
  end

  test "output schema reaches provider text format for only its requested turn", context do
    pid = start(context)
    thread = thread(context, pid)

    schema = %{
      "type" => "object",
      "properties" => %{"answer" => %{"type" => "string"}},
      "required" => ["answer"],
      "additionalProperties" => false
    }

    turn =
      start_turn(pid, thread, [%{"type" => "text", "text" => "Synthetic structured request"}], %{
        "outputSchema" => schema
      })

    finish_turn(pid, thread, turn)

    next_turn =
      start_turn(pid, thread, [%{"type" => "text", "text" => "Synthetic plain request"}])

    finish_turn(pid, thread, next_turn)

    [structured, plain] = ModelFixture.requests(context.fixture)

    assert structured["text"]["format"] == %{
             "name" => "codex_output_schema",
             "type" => "json_schema",
             "strict" => true,
             "schema" => schema
           }

    refute Map.has_key?(plain["text"] || %{}, "format")
  end

  test "tool output rejects nonempty input and an empty name without starting a turn", context do
    pid = start(context)
    thread = thread(context, pid)

    error =
      upstream_error(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "Conflicting synthetic input"}],
        "toolOutput" => %{"name" => "synthetic_tool", "output" => "synthetic output"}
      })

    assert error["code"] == -32_600
    assert error["message"] == "`toolOutput` cannot be combined with nonempty `input`"

    error =
      upstream_error(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [],
        "toolOutput" => %{"name" => "", "output" => "synthetic output"}
      })

    assert error["code"] == -32_600
    assert error["message"] == "`toolOutput.name` must not be empty"
    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")

    turn = start_turn(pid, thread, [%{"type" => "text", "text" => "Valid recovery input"}])
    finish_turn(pid, thread, turn)
    assert [_request] = ModelFixture.requests(context.fixture)
  end
end
