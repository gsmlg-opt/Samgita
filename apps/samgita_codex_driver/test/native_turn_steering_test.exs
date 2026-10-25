defmodule SamgitaCodexDriver.NativeTurnSteeringTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @max_chars 1_048_576
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

  setup {TurnFixture, :setup}

  for experimental <- [false, true] do
    @tag experimental: experimental
    test "idle steer cannot start inference and validates preconditions, experimental=#{experimental}",
         context do
      pid = start(context, experimental: context.experimental)
      thread = thread(context, pid)

      params = %{
        "threadId" => thread,
        "expectedTurnId" => "absent-turn",
        "input" => [text("Idle steer")]
      }

      assert upstream_error(pid, "turn/steer", params) == %{
               "code" => -32_600,
               "message" => "no active turn to steer"
             }

      assert upstream_error(pid, "turn/steer", Map.put(params, "expectedTurnId", "")) == %{
               "code" => -32_600,
               "message" => "expectedTurnId must not be empty"
             }

      for value <- [Map.delete(params, "expectedTurnId"), Map.put(params, "expectedTurnId", nil)] do
        error = upstream_error(pid, "turn/steer", value, validation: :wire)
        assert error["code"] == -32_600
        assert error["message"] =~ "Invalid request"
      end

      if !context.experimental do
        for {field, value} <- [
              {"additionalContext",
               %{"browser_info" => %{"kind" => "untrusted", "value" => "Rejected context"}}},
              {"responsesapiClientMetadata", %{"source" => "rejected-steer"}}
            ] do
          error =
            upstream_error(pid, "turn/steer", Map.put(params, field, value), validation: :wire)

          assert error == %{
                   "code" => -32_600,
                   "message" => "turn/steer.#{field} requires experimentalApi capability"
                 }
        end
      end

      assert [] = ModelFixture.requests(context.fixture)
      assert {:ok, events} = Session.drain(pid)
      refute notification(events, "turn/started")

      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)

      turn = start_turn(pid, thread, [text("Valid turn after rejected idle steering")])
      finish_turn(pid, thread, turn)
      assert [_request] = ModelFixture.requests(context.fixture)

      assert [%{"id" => ^turn, "status" => "completed"}] =
               call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
                 "thread"
               ]["turns"]
    end
  end

  test "native search projects the pending dynamic-tool turn as active and cold history as notLoaded",
       context do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(context.binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    {context, pid, thread, turn, tool, events} = active_turn(context)
    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(context.fixture.bin, "rg"))
    config = Path.join(context.fixture.codex_home, "config.toml")
    config_bytes = File.read!(config)
    marker = "Initial synthetic input"
    active = %{"type" => "active", "activeFlags" => []}

    assert [active_change] =
             Enum.filter(events, fn event ->
               event.wire["method"] == "thread/status/changed" and
                 event.wire["params"] == %{"threadId" => thread, "status" => active}
             end)

    assert active_change.kind == :notification
    # Ignore setup notifications preceding the actual active transition.
    events = Enum.drop_while(events, &(&1 != active_change))
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    refute notification(events, "turn/completed")
    assert [initial_request] = ModelFixture.requests(context.fixture)
    assert provider_text?(initial_request, marker)
    refute Enum.any?(initial_request["input"], &(&1["type"] == "function_call_output"))

    # Assert actual saved history and rollout bytes before rg searches them.
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert saved["status"] == active
    assert [%{"id" => ^turn, "status" => "inProgress", "error" => nil}] = saved["turns"]
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(context.root) <> "/")
    assert File.lstat!(path).type == :regular
    assert File.read!(path) =~ marker

    assert_search = fn current_pid, status ->
      response = call(current_pid, "thread/search", %{"searchTerm" => marker, "limit" => 100})
      assert Map.fetch!(response, "nextCursor") == nil
      assert [row] = Map.fetch!(response, "data")
      assert Map.fetch!(row, "snippet") == marker
      projection = Map.fetch!(row, "thread")

      for field <- ["id", "path", "sessionId", "cwd", "modelProvider", "ephemeral"] do
        assert Map.fetch!(projection, field) == Map.fetch!(saved, field)
      end

      assert projection["id"] == thread
      assert projection["sessionId"] == thread
      assert Map.fetch!(projection, "status") == status
      assert Map.fetch!(projection, "turns") == []
    end

    for _ <- 1..2 do
      assert_search.(pid, active)

      observed =
        call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

      assert observed["status"] == active
      assert [%{"id" => ^turn, "status" => "inProgress", "error" => nil}] = observed["turns"]
      assert ModelFixture.requests(context.fixture) == [initial_request]
      assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
    end

    assert {:ok, passive_events} = Session.drain(pid)
    refute Enum.any?(passive_events, &(&1.kind == :server_request))
    lifecycle = ["thread/status/changed", "turn/started", "turn/completed", "error"]
    refute Enum.any?(passive_events, &(&1.wire["method"] in lifecycle))

    # The original generation-bound handle is answered exactly once, explicitly.
    events = finish_active(pid, thread, turn, tool, events ++ passive_events)
    assert_single_turn(events, thread, turn)
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    refute notification(events, "error")

    assert Enum.map(Enum.filter(events, &(&1.wire["method"] in lifecycle)), fn event ->
             assert event.kind == :notification
             event.wire["method"]
           end) == [
             "thread/status/changed",
             "turn/started",
             "thread/status/changed",
             "turn/completed"
           ]

    assert Enum.map(
             Enum.filter(events, &(&1.wire["method"] == "thread/status/changed")),
             & &1.wire["params"]
           ) == [
             %{"threadId" => thread, "status" => active},
             %{"threadId" => thread, "status" => %{"type" => "idle"}}
           ]

    assert [^initial_request, continuation] = ModelFixture.requests(context.fixture)
    assert [call_item] = Enum.filter(continuation["input"], &(&1["type"] == "function_call"))
    assert call_item["call_id"] == "fixture-call-1"
    assert call_item["name"] == "fixture_lookup"
    assert JSON.decode!(call_item["arguments"]) == %{"key" => "synthetic"}

    assert [%{"call_id" => "fixture-call-1", "output" => "Synthetic lookup completed"}] =
             Enum.filter(continuation["input"], &(&1["type"] == "function_call_output"))

    completed =
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert completed["status"] == %{"type" => "idle"}

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil} = completed_turn] =
             completed["turns"]

    items = Map.fetch!(completed_turn, "items")
    assert Enum.map(items, & &1["type"]) == ["userMessage", "dynamicToolCall", "agentMessage"]
    assert Enum.at(items, 0)["content"] == [text(marker) |> Map.put("text_elements", [])]

    dynamic = Enum.at(items, 1)
    assert dynamic["id"] == "fixture-call-1"
    assert dynamic["tool"] == "fixture_lookup"
    assert dynamic["arguments"] == %{"key" => "synthetic"}
    assert dynamic["status"] == "completed"

    assert dynamic["contentItems"] == [
             %{"type" => "inputText", "text" => "Synthetic lookup completed"}
           ]

    assert dynamic["success"] == true
    assert Enum.at(items, 2)["text"] == "Deterministic local fixture answer"

    for item <- items do
      assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => ^item} =
               notification(events, "item/completed", &(&1["item"]["id"] == item["id"]))
    end

    assert_search.(pid, %{"type" => "idle"})
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)

    cold = start(context)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_search.(cold, %{"type" => "notLoaded"})

    restored =
      call(cold, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert restored["status"] == %{"type" => "notLoaded"}
    assert restored["turns"] == [completed_turn]
    assert_search.(cold, %{"type" => "notLoaded"})
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert ModelFixture.requests(context.fixture) == [initial_request, continuation]
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(cold)
    assert Session.uncertain_operations(cold) == []
    assert {:ok, cold_events} = Session.drain(cold)
    refute Enum.any?(cold_events, &(&1.kind == :server_request or &1.wire["method"] in lifecycle))
    assert File.read!(config) == config_bytes
    assert :ok = Session.close(cold)
  end

  test "text steering keeps the active turn and merges accepted context and metadata into its next request",
       context do
    {context, pid, thread, turn, tool, events} = active_turn(context)

    assert %{"turnId" => ^turn} =
             call(pid, "turn/steer", %{
               "threadId" => thread,
               "expectedTurnId" => turn,
               "clientUserMessageId" => "synthetic-steer-client-id",
               "input" => [text("Accepted steering é🙂")],
               "additionalContext" => %{
                 "browser_info" => %{"kind" => "untrusted", "value" => "accepted synthetic tab"},
                 "automation_info" => %{
                   "kind" => "application",
                   "value" => "accepted synthetic run"
                 }
               },
               "responsesapiClientMetadata" => %{
                 "source" => "synthetic-steer",
                 "turn_id" => "spoofed-turn"
               }
             })

    events = finish_active(pid, thread, turn, tool, events)
    assert_single_turn(events, thread, turn)

    for method <- ["item/started", "item/completed"] do
      assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"content" => content}} =
               notification(
                 events,
                 method,
                 &(&1["item"]["clientId"] == "synthetic-steer-client-id")
               )

      assert content == [
               %{"type" => "text", "text" => "Accepted steering é🙂", "text_elements" => []}
             ]
    end

    assert [first, second] = ModelFixture.requests(context.fixture)
    refute provider_text?(first, "Accepted steering é🙂")
    assert provider_text?(second, "Accepted steering é🙂")

    assert provider_text?(
             second,
             "<external_browser_info>accepted synthetic tab</external_browser_info>",
             "user"
           )

    assert provider_text?(
             second,
             "<automation_info>accepted synthetic run</automation_info>",
             "developer"
           )

    assert %{"thread_id" => ^thread, "turn_id" => ^turn, "source" => "synthetic-steer"} =
             JSON.decode!(second["client_metadata"]["x-codex-turn-metadata"])

    history = persisted_history(context, pid, thread, turn)
    assert Enum.any?(history, &(&1["clientId"] == "synthetic-steer-client-id"))
  end

  test "active steer rejections preserve the pending tool and do not merge rejected content",
       context do
    {context, pid, thread, turn, tool, events} = active_turn(context)

    base = %{
      "threadId" => thread,
      "expectedTurnId" => turn,
      "input" => [text("Rejected steering marker")]
    }

    assert upstream_error(pid, "turn/steer", Map.put(base, "expectedTurnId", "wrong-turn")) == %{
             "code" => -32_600,
             "message" => "expected active turn id `wrong-turn` but found `#{turn}`"
           }

    assert upstream_error(
             pid,
             "turn/steer",
             Map.merge(base, %{
               "input" => [],
               "additionalContext" => %{
                 "browser_info" => %{"kind" => "untrusted", "value" => "Rejected context marker"}
               },
               "responsesapiClientMetadata" => %{"source" => "rejected-metadata-marker"}
             })
           ) == %{"code" => -32_600, "message" => "input must not be empty"}

    oversized = String.duplicate("x", @max_chars + 1)

    assert upstream_error(pid, "turn/steer", Map.put(base, "input", [text(oversized)])) == %{
             "code" => -32_602,
             "message" => "Input exceeds the maximum length of #{@max_chars} characters.",
             "data" => %{
               "input_error_code" => "input_too_large",
               "max_chars" => @max_chars,
               "actual_chars" => @max_chars + 1
             }
           }

    assert length(ModelFixture.requests(context.fixture)) == 1

    assert %{"turnId" => ^turn} =
             call(pid, "turn/steer", Map.put(base, "input", [text("Accepted after rejection")]))

    events = finish_active(pid, thread, turn, tool, events)
    assert_single_turn(events, thread, turn)
    assert [_, second] = ModelFixture.requests(context.fixture)
    assert provider_text?(second, "Accepted after rejection")

    for marker <- [
          "Rejected steering marker",
          "Rejected context marker",
          "rejected-metadata-marker"
        ] do
      refute JSON.encode!(second) =~ marker
    end

    history = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    refute JSON.encode!(history) =~ "Rejected steering marker"
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "standalone retained tool output steers the pending turn and persists its item identity",
       context do
    {context, pid, thread, turn, tool, events} = active_turn(context)

    output = %{
      "name" => "synthetic_steered_text",
      "namespace" => "synthetic_namespace",
      "output" => "Steered standalone output é🙂",
      "retain" => true
    }

    assert start_turn(pid, thread, [], %{"toolOutput" => output}) == turn
    events = finish_active(pid, thread, turn, tool, events)
    assert_single_turn(events, thread, turn)
    item = assert_output(events, thread, turn, output)
    assert [first, second] = ModelFixture.requests(context.fixture)
    refute Enum.any?(first["input"], &(&1["name"] == output["name"]))
    assert_provider_output(second, item, output["output"])
    assert item in persisted_history(context, pid, thread, turn)
  end

  for audio <- [false, true] do
    @tag audio: audio
    test "structured output steering preserves encrypted and image content with audio support=#{audio}",
         context do
      modalities = if context.audio, do: ["text", "image", "audio"], else: ["text", "image"]

      {context, pid, thread, turn, tool, events} =
        active_turn(context, %{
          "input_modalities" => modalities,
          "supports_image_detail_original" => true
        })

      content = [
        %{"type" => "input_text", "text" => "Structured steering é🙂"},
        %{
          "type" => "input_image",
          "file_id" => "synthetic-steering-file",
          "detail" => "original"
        },
        %{"type" => "input_audio", "audio_url" => "data:audio/wav;base64,c3ludGhldGlj"},
        %{"type" => "encrypted_content", "encrypted_content" => "synthetic-opaque-ciphertext"}
      ]

      output = %{"name" => "synthetic_steered_media", "output" => content, "retain" => false}
      assert start_turn(pid, thread, [], %{"toolOutput" => output}) == turn
      events = finish_active(pid, thread, turn, tool, events)
      assert_single_turn(events, thread, turn)
      item = assert_output(events, thread, turn, output)
      assert [_, second] = ModelFixture.requests(context.fixture)

      expected =
        if context.audio,
          do: content,
          else:
            List.replace_at(content, 2, %{
              "type" => "input_text",
              "text" => "audio content omitted because you do not support audio input"
            })

      assert_provider_output(second, item, expected)
      assert item in persisted_history(context, pid, thread, turn)
    end
  end

  defp active_turn(context, model \\ %{}) do
    fixture = ModelFixture.start(Path.join(context.root, "active"), "dynamic_tool")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    context = %{context | fixture: fixture}
    if model != %{}, do: configure_model(context, model)
    pid = start(context)
    thread = thread(context, pid, %{"dynamicTools" => [@lookup]})
    turn = start_turn(pid, thread, [text("Initial synthetic input")])
    {tool, events} = await_tool(pid, [], System.monotonic_time(:millisecond) + 10_000)

    assert %{
             "method" => "item/tool/call",
             "params" => %{
               "threadId" => ^thread,
               "turnId" => ^turn,
               "callId" => "fixture-call-1",
               "tool" => "fixture_lookup",
               "arguments" => %{"key" => "synthetic"}
             }
           } = tool.wire

    assert [_] = ModelFixture.requests(fixture)
    {context, pid, thread, turn, tool, events}
  end

  defp await_tool(pid, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    case Enum.find(events, &(&1.kind == :server_request)) do
      nil ->
        refute notification(events, "turn/completed")
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {:codex_driver, ^pid, :events_available} ->
            await_tool(pid, events, deadline)

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected gap while awaiting synthetic tool")
        after
          remaining -> flunk("Real Codex did not request the synthetic dynamic tool")
        end

      tool ->
        {tool, events}
    end
  end

  defp finish_active(pid, thread, turn, tool, events) do
    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok,
                %{
                  "contentItems" => [
                    %{"type" => "inputText", "text" => "Synthetic lookup completed"}
                  ],
                  "success" => true
                }}
             )

    events ++ finish_turn(pid, thread, turn)
  end

  defp assert_single_turn(events, thread, turn) do
    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == thread
      assert params["turn"]["id"] == turn
    end
  end

  defp assert_output(events, thread, turn, output) do
    completed = notification(events, "item/completed", &(&1["item"]["name"] == output["name"]))
    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"id" => id}} = completed

    expected = %{
      "type" => "functionCallOutput",
      "id" => id,
      "name" => output["name"],
      "namespace" => output["namespace"],
      "output" => output["output"]
    }

    assert completed["item"] == expected

    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => ^expected} =
             notification(events, "item/started", &(&1["item"]["id"] == id))

    expected
  end

  defp assert_provider_output(request, item, output) do
    assert [captured] =
             Enum.filter(
               request["input"],
               &(&1["type"] == "function_call_output" and &1["name"] == item["name"])
             )

    expected = %{
      "type" => "function_call_output",
      "id" => item["id"],
      "name" => item["name"],
      "output" => output
    }

    expected =
      if item["namespace"], do: Map.put(expected, "namespace", item["namespace"]), else: expected

    assert captured == expected
  end

  defp persisted_history(context, pid, thread, turn) do
    read = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = read["thread"]["turns"]
    requests = ModelFixture.requests(context.fixture)
    assert :ok = Session.close(pid)
    resumed = start(context)
    assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    read = call(resumed, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert [%{"id" => ^turn, "items" => ^items}] = read["thread"]["turns"]
    assert ModelFixture.requests(context.fixture) == requests
    items
  end

  defp provider_text?(request, text, role \\ "user") do
    Enum.any?(
      request["input"],
      &(&1["role"] == role and
          %{"type" => "input_text", "text" => text} in Map.get(&1, "content", []))
    )
  end

  defp text(value), do: %{"type" => "text", "text" => value}
end
