defmodule SamgitaCodexDriver.NativeRealtimeLifecycleProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_realtime_fixture.py", __DIR__)
  @v1 ~w(juniper maple spruce ember vale breeze arbor sol cove)
  @v2 ~w(alloy ash ballad coral echo sage shimmer verse marin cedar)
  @v3 @v1 ++
        ~w(aube bubbie haetsal hanul himari leher miko neer porto rindo rio rivage selva sonna tinta viola)

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    try do
      TurnFixture.setup(tags)
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  test "builtin voice lists require neither authentication nor a loaded thread or backend", ctx do
    remove_auth(ctx)
    pid = start(ctx)

    assert call(pid, "thread/realtime/listVoices", %{}) == %{
             "voices" => %{
               "v1" => @v1,
               "v2" => @v2,
               "v3" => @v3,
               "defaultV1" => "cove",
               "defaultV2" => "marin"
             }
           }

    assert call(pid, "thread/loaded/list", %{})["data"] == []
    barrier(ctx)
    assert handshakes(ctx) == []
    assert_idle(ctx, pid)
  end

  test "V2 startup preserves URL model auth voice modality and prompt precedence", ctx do
    pid = start(ctx)

    settings = [
      {%{}, "synthetic-configured-realtime", "marin", "audio",
       "Synthetic configured prompt\n\nSynthetic startup context"},
      {%{
         "prompt" => "Synthetic request overridden by configuration",
         "includeStartupContext" => false
       }, "synthetic-configured-realtime", "marin", "audio", "Synthetic configured prompt"},
      {%{
         "model" => "synthetic-request-model",
         "voice" => "cedar",
         "outputModality" => "text",
         "prompt" => "Synthetic explicit prompt",
         "includeStartupContext" => false,
         "transport" => %{"type" => "websocket"}
       }, "synthetic-request-model", "cedar", "text", "Synthetic explicit prompt"},
      {%{"prompt" => nil, "includeStartupContext" => false}, "synthetic-configured-realtime",
       "marin", "audio", ""}
    ]

    for {{options, model, voice, modality, prompt}, index} <- Enum.with_index(settings, 1) do
      thread_options =
        if index <= 2,
          do: %{},
          else: %{"config" => %{"experimental_realtime_ws_backend_prompt" => ""}}

      thread = TurnFixture.thread(ctx, pid, thread_options)
      session_id = "synthetic-start-#{index}"
      begin_realtime(pid, thread, Map.put(options, "realtimeSessionId", session_id))
      events = wait_event(pid, "thread/realtime/started")

      assert notification(events, "thread/realtime/started") == %{
               "threadId" => thread,
               "realtimeSessionId" => session_id,
               "version" => "v2"
             }

      update = wait_frame(ctx, index, "session.update")["session"]
      handshake = Enum.at(handshakes(ctx), index - 1)
      assert handshake["path"] == "/v1/realtime?model=#{model}"
      assert handshake["authorization"] == "Bearer SYNTHETIC_REALTIME_ONLY"
      assert update["type"] == "realtime"
      assert update["instructions"] == prompt
      assert update["output_modalities"] == [modality]
      assert update["audio"]["input"]["format"] == %{"type" => "audio/pcm", "rate" => 24_000}
      assert update["audio"]["output"]["voice"] == voice
      assert update["audio"]["output"]["format"] == %{"type" => "audio/pcm", "rate" => 24_000}
      stop(pid, thread)
    end

    assert_idle(ctx, pid)
  end

  test "explicit V1 and V2 voices reach the captured native session update", ctx do
    selections =
      for {version, voices} <- [
            {"v1", ~w(juniper maple spruce ember vale breeze arbor sol)},
            {"v2", ~w(alloy ash ballad coral echo sage shimmer verse marin)}
          ],
          voice <- voices,
          do: {version, %{"voice" => voice}, voice}

    assert_realtime_voice_selections(ctx, selections)
  end

  test "V3 exclusive voices and omitted or null defaults reach native session updates", ctx do
    selections =
      Enum.map(
        ~w(aube bubbie haetsal hanul himari leher miko neer porto rindo rio rivage selva sonna tinta viola),
        &{"v3", %{"voice" => &1}, &1}
      ) ++ [{"v3", %{}, "cove"}, {"v3", %{"voice" => nil}, "cove"}]

    assert_realtime_voice_selections(ctx, selections)
  end

  test "audio text and speech append translate native frames and correlated backend notifications",
       ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid)
    begin_realtime(pid, thread)
    wait_event(pid, "thread/realtime/started")
    wait_frame(ctx, 1, "session.update")

    assert call(pid, "thread/realtime/appendAudio", %{
             "threadId" => thread,
             "audio" => %{
               "data" => "BQYH",
               "sampleRate" => 24_000,
               "numChannels" => 1,
               "samplesPerChannel" => 3,
               "itemId" => "synthetic-input"
             }
           }) == %{}

    for {role, text} <- [
          {"user", "synthetic user"},
          {"assistant", "synthetic assistant"},
          {"developer", "synthetic developer"}
        ] do
      assert call(pid, "thread/realtime/appendText", %{
               "threadId" => thread,
               "role" => role,
               "text" => text
             }) == %{}
    end

    assert call(pid, "thread/realtime/appendSpeech", %{
             "threadId" => thread,
             "text" => "synthetic speech"
           }) == %{}

    wait_frame(ctx, 1, "response.create")
    await(fn -> Enum.count(frames(ctx, 1), &(&1["type"] == "conversation.item.create")) == 4 end)
    wait_frame(ctx, 1, "input_audio_buffer.append")
    messages = frames(ctx, 1)

    assert Enum.any?(
             messages,
             &(&1 == %{"type" => "input_audio_buffer.append", "audio" => "BQYH"})
           )

    for {role, type, text} <- [
          {"user", "input_text", "[USER] synthetic user"},
          {"assistant", "output_text", "synthetic assistant"},
          {"developer", "input_text", "synthetic developer"},
          {"user", "input_text", "[BACKEND] synthetic speech"}
        ] do
      assert Enum.any?(messages, fn message ->
               message["type"] == "conversation.item.create" and
                 message["item"]["role"] == role and
                 message["item"]["content"] == [%{"type" => type, "text" => text}]
             end)
    end

    raw_item = %{"id" => "synthetic-peer-item", "type" => "message", "role" => "user"}

    control(ctx, "emit", 1, [
      %{"type" => "conversation.item.input_audio_transcription.delta", "delta" => "heard "},
      %{
        "type" => "conversation.item.input_audio_transcription.completed",
        "transcript" => "heard final"
      },
      %{
        "type" => "response.output_audio.delta",
        "delta" => "AAAAAA==",
        "sample_rate" => 16_000,
        "channels" => 2,
        "samples_per_channel" => 2,
        "item_id" => "synthetic-audio"
      },
      %{"type" => "conversation.item.added", "item" => raw_item}
    ])

    events = wait_event(pid, "thread/realtime/itemAdded")

    assert notification(events, "thread/realtime/transcript/delta") == %{
             "threadId" => thread,
             "role" => "user",
             "delta" => "heard "
           }

    assert notification(events, "thread/realtime/transcript/done") == %{
             "threadId" => thread,
             "role" => "user",
             "text" => "heard final"
           }

    assert notification(events, "thread/realtime/outputAudio/delta") == %{
             "threadId" => thread,
             "audio" => %{
               "data" => "AAAAAA==",
               "sampleRate" => 16_000,
               "numChannels" => 2,
               "samplesPerChannel" => 2,
               "itemId" => "synthetic-audio"
             }
           }

    assert notification(events, "thread/realtime/itemAdded") == %{
             "threadId" => thread,
             "item" => raw_item
           }

    stop(pid, thread)
    assert_idle(ctx, pid)
  end

  test "typed transcript items retain delta facts across stop cold timeline read and resume",
       ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})

    begin_realtime(pid, thread, %{
      "outputModality" => "text",
      "realtimeSessionId" => "synthetic-history"
    })

    started = wait_event(pid, "thread/realtime/started")

    control(ctx, "emit", 1, [
      %{"type" => "response.output_text.delta", "delta" => "hello "},
      %{"type" => "response.output_text.delta", "delta" => "world"},
      %{"type" => "response.output_text.done", "text" => "a different final revision"}
    ])

    transcript = wait_event(pid, "thread/realtime/transcript/done")

    assert notification(transcript, "thread/realtime/transcript/done")["text"] ==
             "a different final revision"

    closing = stop(pid, thread)
    events = started ++ transcript ++ closing
    completed = items(events, "thread/realtime/item/completed")

    assert Enum.map(completed, & &1["type"]) == [
             "realtimeSessionStarted",
             "transcriptSegment",
             "realtimeSessionClosed"
           ]

    [session_item, segment, closed_item] = completed
    assert segment["role"] == "assistant"
    assert segment["text"] == "hello world"
    assert closed_item["outcome"] == "ended"

    for item <- completed do
      assert item["id"] =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      assert item["realtimeSessionId"] == "synthetic-history"
    end

    assert length(Enum.uniq_by(completed, & &1["id"])) == 3
    assert Enum.any?(items(events, "thread/realtime/item/started"), &(&1 == session_item))
    deltas = Enum.filter(events, &(&1.wire["method"] == "thread/realtime/item/transcript/delta"))
    assert Enum.map(deltas, & &1.wire["params"]["delta"]) == ["hello ", "world"]
    assert Enum.all?(deltas, &(&1.wire["params"]["itemId"] == segment["id"]))
    assert timeline(pid, thread) == completed
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert call(cold, "thread/read", %{"threadId" => thread})["thread"]["id"] == thread
    assert timeline(cold, thread) == completed
    assert call(cold, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert timeline(cold, thread) == completed
    assert length(handshakes(ctx)) == 1
    assert_idle(ctx, cold)
  end

  test "user delta facts and failed closure survive a distinct cold native timeline read", ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    session_id = "synthetic-user-failed-history"

    begin_realtime(pid, thread, %{
      "outputModality" => "text",
      "realtimeSessionId" => session_id,
      "flushTranscriptTailOnSessionEnd" => false
    })

    started = wait_event(pid, "thread/realtime/started")
    wait_frame(ctx, 1, "session.update")

    control(ctx, "emit", 1, [
      %{"type" => "conversation.item.input_audio_transcription.delta", "delta" => "owned user "},
      %{"type" => "conversation.item.input_audio_transcription.delta", "delta" => "delta λ"},
      %{
        "type" => "conversation.item.input_audio_transcription.completed",
        "transcript" => "owned final revision differs"
      }
    ])

    transcript = wait_event(pid, "thread/realtime/transcript/done")

    assert notification(transcript, "thread/realtime/transcript/done") == %{
             "threadId" => thread,
             "role" => "user",
             "text" => "owned final revision differs"
           }

    control(ctx, "emit", 1, [
      %{"type" => "error", "error" => %{"message" => "Owned failed-history fault"}}
    ])

    failed = wait_event(pid, "thread/realtime/closed")

    assert notification(failed, "thread/realtime/error") == %{
             "threadId" => thread,
             "message" => "Owned failed-history fault"
           }

    assert notification(failed, "thread/realtime/closed") == %{
             "threadId" => thread,
             "reason" => "error"
           }

    events = wait_realtime_items(pid, 3, started ++ transcript ++ failed)

    expected =
      assert_realtime_facts(events, thread, session_id, [
        %{"type" => "realtimeSessionStarted"},
        %{"type" => "transcriptSegment", "role" => "user", "text" => "owned user delta λ"},
        %{"type" => "realtimeSessionClosed", "outcome" => "failed"}
      ])

    [_, segment, _] = expected

    assert for(
             event <- events,
             event.wire["method"] == "thread/realtime/item/transcript/delta",
             do: event.wire["params"]
           ) == [
             %{"threadId" => thread, "itemId" => segment["id"], "delta" => "owned user "},
             %{"threadId" => thread, "itemId" => segment["id"], "delta" => "delta λ"}
           ]

    warm = assert_complete_realtime_timeline(pid, thread, expected)

    await(fn ->
      Enum.any?(journal(ctx), &(&1["event"] == "peer_closed" and &1["connection"] == 1))
    end)

    assert_realtime_idle(ctx, pid)
    cold = restart_realtime_native(ctx, pid)
    assert call(cold, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) == warm
    assert_complete_realtime_timeline(cold, thread, expected)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    barrier(ctx)
    assert length(handshakes(ctx)) == 1
    assert File.ls!(ctx.fixture.workspace) == []
    assert_realtime_idle(ctx, cold)
  end

  test "active timeline pages report the session at each opening boundary and retain cold cursors",
       ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    session_id = "synthetic-active-page-history"

    begin_realtime(pid, thread, %{
      "outputModality" => "text",
      "realtimeSessionId" => session_id,
      "flushTranscriptTailOnSessionEnd" => false
    })

    started = wait_event(pid, "thread/realtime/started")
    wait_frame(ctx, 1, "session.update")

    active_events =
      Enum.reduce(
        Enum.with_index(["owned first segment", "owned second segment"], 1),
        started,
        fn {text, index}, events ->
          control(ctx, "emit", 1, [
            %{"type" => "response.output_text.delta", "delta" => text},
            %{"type" => "response.output_text.done", "text" => text}
          ])

          batch = wait_event(pid, "thread/realtime/transcript/done")
          assert notification(batch, "thread/realtime/transcript/done")["text"] == text
          wait_realtime_items(pid, index + 1, events ++ batch)
        end
      )

    expected =
      assert_realtime_facts(active_events, thread, session_id, [
        %{"type" => "realtimeSessionStarted"},
        %{"type" => "transcriptSegment", "role" => "assistant", "text" => "owned first segment"},
        %{"type" => "transcriptSegment", "role" => "assistant", "text" => "owned second segment"}
      ])

    full = assert_complete_realtime_timeline(pid, thread, expected)
    [start_entry, first_entry, second_entry] = full["data"]
    newest = call(pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 1})
    assert newest["data"] == [second_entry]
    assert newest["activeRealtimeSessionAtPageStart"] == session_id
    first_cursor = newest["nextCursor"]
    assert is_binary(first_cursor) and byte_size(first_cursor) > 0
    middle_query = %{"threadId" => thread, "limit" => 1, "cursor" => first_cursor}
    middle = call(pid, "thread/timeline/list", middle_query)
    assert middle["data"] == [first_entry]
    assert middle["activeRealtimeSessionAtPageStart"] == session_id
    second_cursor = middle["nextCursor"]
    assert is_binary(second_cursor) and byte_size(second_cursor) > 0
    refute first_cursor == second_cursor
    oldest_query = %{"threadId" => thread, "limit" => 1, "cursor" => second_cursor}
    oldest = call(pid, "thread/timeline/list", oldest_query)

    assert oldest == %{
             "data" => [start_entry],
             "activeRealtimeSessionAtPageStart" => nil,
             "nextCursor" => nil
           }

    closing = stop(pid, thread)
    completed_events = wait_realtime_items(pid, 4, active_events ++ closing)

    all_expected =
      assert_realtime_facts(completed_events, thread, session_id, [
        %{"type" => "realtimeSessionStarted"},
        %{"type" => "transcriptSegment", "role" => "assistant", "text" => "owned first segment"},
        %{"type" => "transcriptSegment", "role" => "assistant", "text" => "owned second segment"},
        %{"type" => "realtimeSessionClosed", "outcome" => "ended"}
      ])

    assert Enum.take(all_expected, 3) == expected
    closed_full = assert_complete_realtime_timeline(pid, thread, all_expected)
    assert Enum.take(closed_full["data"], 3) == full["data"]
    closed_page = call(pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 1})
    assert closed_page["data"] == [List.last(closed_full["data"])]
    assert closed_page["activeRealtimeSessionAtPageStart"] == session_id
    closed_cursor = closed_page["nextCursor"]
    assert is_binary(closed_cursor) and byte_size(closed_cursor) > 0
    newest_query = %{"threadId" => thread, "limit" => 1, "cursor" => closed_cursor}
    assert call(pid, "thread/timeline/list", newest_query) == newest

    await(fn ->
      Enum.any?(journal(ctx), &(&1["event"] == "peer_closed" and &1["connection"] == 1))
    end)

    assert_realtime_idle(ctx, pid)
    cold = restart_realtime_native(ctx, pid)

    for {query, snapshot} <- [
          {%{"threadId" => thread, "limit" => 100}, closed_full},
          {%{"threadId" => thread, "limit" => 1}, closed_page},
          {newest_query, newest},
          {middle_query, middle},
          {oldest_query, oldest}
        ] do
      assert call(cold, "thread/timeline/list", query) == snapshot
    end

    assert call(cold, "thread/loaded/list", %{})["data"] == []
    barrier(ctx)
    assert length(handshakes(ctx)) == 1
    assert File.ls!(ctx.fixture.workspace) == []
    assert_realtime_idle(ctx, cold)
  end

  test "opt-in terminal transcript records complete ordinary history without inference", ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    session_id = "synthetic-explicit-tail-history"

    begin_realtime(pid, thread, %{
      "outputModality" => "text",
      "realtimeSessionId" => session_id,
      "flushTranscriptTailOnSessionEnd" => true
    })

    started = wait_event(pid, "thread/realtime/started")
    wait_frame(ctx, 1, "session.update")

    control(ctx, "emit", 1, [
      %{
        "type" => "conversation.item.input_audio_transcription.delta",
        "delta" => "owned delta λ"
      },
      %{
        "type" => "conversation.item.input_audio_transcription.completed",
        "transcript" => "owned tail <final>& λ"
      }
    ])

    transcript = wait_event(pid, "thread/realtime/transcript/done")

    assert notification(transcript, "thread/realtime/transcript/done") == %{
             "threadId" => thread,
             "role" => "user",
             "text" => "owned tail <final>& λ"
           }

    before_stop = System.system_time(:second)
    closing = stop(pid, thread)
    after_stop = System.system_time(:second)
    events = started ++ transcript ++ closing
    realtime = items(events, "thread/realtime/item/completed")
    assert [session_fact, segment, close_fact] = realtime

    assert session_fact == %{
             "id" => session_fact["id"],
             "realtimeSessionId" => session_id,
             "type" => "realtimeSessionStarted"
           }

    assert segment == %{
             "id" => segment["id"],
             "realtimeSessionId" => session_id,
             "type" => "transcriptSegment",
             "role" => "user",
             "text" => "owned delta λ"
           }

    assert close_fact == %{
             "id" => close_fact["id"],
             "realtimeSessionId" => session_id,
             "type" => "realtimeSessionClosed",
             "outcome" => "ended"
           }

    expected_text =
      "<realtime_delegation>\n" <>
        "  <source>transcript_tail_flush</source>\n" <>
        "  <input>The user just ended their realtime session. Here is the remaining handoff/transcript tail. " <>
        "You probably do not have to do anything; acknowledge the handoff unless the transcript itself asks for something.</input>\n" <>
        "  <transcript_delta>user: owned tail &lt;final&gt;&amp; λ</transcript_delta>\n" <>
        "</realtime_delegation>"

    warm = call(pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})

    assert %{
             "data" => [start_row, segment_row, turn_start, user_row, _turn_end, close_row],
             "nextCursor" => nil,
             "activeRealtimeSessionAtPageStart" => nil
           } = warm

    turn_id = turn_start["turnId"]
    user_id = user_row["item"]["id"]
    timestamp = turn_start["startedAt"]
    assert is_integer(timestamp) and timestamp >= before_stop and timestamp <= after_stop

    ids = Enum.map(realtime, & &1["id"]) ++ [turn_id, user_id]
    assert length(Enum.uniq(ids)) == 5

    for id <- ids do
      assert id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    expected_user = %{
      "id" => user_id,
      "clientId" => nil,
      "type" => "userMessage",
      "content" => [%{"type" => "text", "text" => expected_text, "text_elements" => []}]
    }

    expected_rows = [
      %{"type" => "realtime", "item" => session_fact},
      %{"type" => "realtime", "item" => segment},
      %{"type" => "turnStarted", "turnId" => turn_id, "startedAt" => timestamp},
      %{"type" => "item", "turnId" => turn_id, "item" => expected_user},
      %{
        "type" => "turnCompleted",
        "turnId" => turn_id,
        "status" => "completed",
        "error" => nil,
        "startedAt" => timestamp,
        "completedAt" => timestamp,
        "durationMs" => 0
      },
      %{"type" => "realtime", "item" => close_fact}
    ]

    for {actual, expected} <- Enum.zip(warm["data"], expected_rows) do
      assert Map.delete(actual, "position") == expected
      assert is_integer(actual["position"]) and actual["position"] >= 0
    end

    positions = Enum.map(warm["data"], & &1["position"])
    assert positions == Enum.sort(positions)
    assert start_row["item"] == session_fact and segment_row["item"] == segment
    assert close_row["item"] == close_fact

    # A recording-only turn is durable history, never a newly advertised running task.
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ])
           )

    assert_idle(ctx, pid)
    assert %{interactions: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    instance = Session.status(pid).instance_id
    native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1
    cold = start(ctx)
    assert Session.status(cold).instance_id != instance
    %{connection: cold_connection} = :sys.get_state(cold)
    assert cold_connection.port != connection.port
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert call(cold, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) == warm
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    barrier(ctx)
    assert length(handshakes(ctx)) == 1
    assert File.ls!(ctx.fixture.workspace) == []
    assert_idle(ctx, cold)
    assert %{interactions: 0, gap: nil} = Session.status(cold)
    assert Session.uncertain_operations(cold) == []
  end

  test "replacement closes the prior identity and requested stop leaves subsequent startup usable",
       ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid)
    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-old"})
    wait_event(pid, "thread/realtime/started")
    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-new"})
    events = wait_event(pid, "thread/realtime/started")

    assert notification(events, "thread/realtime/closed") == %{
             "threadId" => thread,
             "reason" => "requested"
           }

    assert notification(events, "thread/realtime/started")["realtimeSessionId"] == "synthetic-new"

    assert Enum.any?(items(events, "thread/realtime/item/completed"), fn item ->
             item["type"] == "realtimeSessionClosed" and
               item["realtimeSessionId"] == "synthetic-old" and item["outcome"] == "ended"
           end)

    stop(pid, thread)
    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-after-stop"})

    assert notification(wait_event(pid, "thread/realtime/started"), "thread/realtime/started")[
             "realtimeSessionId"
           ] == "synthetic-after-stop"

    wait_frame(ctx, 3, "session.update")
    stop(pid, thread)
    assert length(handshakes(ctx)) == 3
    assert_idle(ctx, pid)
  end

  test "peer errors and transport closure retain native outcomes and require explicit restart",
       ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid)
    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-fault"})
    wait_event(pid, "thread/realtime/started")

    control(ctx, "emit", 1, [
      %{"type" => "error", "error" => %{"message" => "Synthetic realtime fault"}}
    ])

    failed = wait_event(pid, "thread/realtime/closed")

    assert notification(failed, "thread/realtime/error") == %{
             "threadId" => thread,
             "message" => "Synthetic realtime fault"
           }

    assert notification(failed, "thread/realtime/closed")["reason"] == "error"

    assert Enum.any?(
             items(failed, "thread/realtime/item/completed"),
             &(&1["type"] == "realtimeSessionClosed" and &1["outcome"] == "failed")
           )

    assert length(handshakes(ctx)) == 1
    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-transport"})
    wait_event(pid, "thread/realtime/started")
    control(ctx, "close", 2)
    disconnected = wait_event(pid, "thread/realtime/closed")
    assert notification(disconnected, "thread/realtime/closed")["reason"] == "transport_closed"

    assert Enum.any?(
             items(disconnected, "thread/realtime/item/completed"),
             &(&1["type"] == "realtimeSessionClosed" and &1["outcome"] == "ended")
           )

    begin_realtime(pid, thread, %{"realtimeSessionId" => "synthetic-recovered"})
    wait_event(pid, "thread/realtime/started")
    wait_frame(ctx, 3, "session.update")
    stop(pid, thread)
    outcomes = timeline(pid, thread) |> Enum.filter(&(&1["type"] == "realtimeSessionClosed"))
    assert Enum.map(outcomes, & &1["outcome"]) == ["failed", "ended", "ended"]
    assert_idle(ctx, pid)
  end

  test "preparation rejects missing auth and incompatible settings asynchronously before connection",
       ctx do
    remove_auth(ctx)
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid)

    failures = [
      {%{}, "realtime conversation requires API key auth"},
      {%{"voice" => "cove"},
       "realtime voice `cove` is not supported for v2; supported voices: " <> Enum.join(@v2, ", ")},
      {%{"version" => "v1", "outputModality" => "text"},
       "text realtime output modality requires realtime v2"},
      {%{"initialItems" => [%{"role" => "user", "text" => "synthetic initial"}]},
       "initial realtime items require realtime v3"}
    ]

    for {options, message} <- failures do
      begin_realtime(pid, thread, options)
      events = wait_event(pid, "thread/realtime/error")

      assert notification(events, "thread/realtime/error") == %{
               "threadId" => thread,
               "message" => message
             }

      refute notification(events, "thread/realtime/started")
    end

    barrier(ctx)
    assert handshakes(ctx) == []
    assert_idle(ctx, pid)
  end

  test "native experimental malformed-field and existing-call gates retain direct RPC errors",
       ctx do
    methods = [
      {"thread/realtime/listVoices", %{}},
      {"thread/realtime/start", %{"threadId" => "absent", "outputModality" => "audio"}},
      {"thread/realtime/appendAudio",
       %{
         "threadId" => "absent",
         "audio" => %{"data" => "AA==", "sampleRate" => 24_000, "numChannels" => 1}
       }},
      {"thread/realtime/appendText", %{"threadId" => "absent", "text" => "synthetic"}},
      {"thread/realtime/appendSpeech", %{"threadId" => "absent", "text" => "synthetic"}},
      {"thread/realtime/stop", %{"threadId" => "absent"}}
    ]

    for negotiation <- [:absent, false] do
      pid = start(ctx, negotiation)

      for {method, params} <- methods do
        error = upstream_error(pid, method, params)
        assert error["code"] == -32_600
        assert error["message"] =~ "experimentalApi"
      end

      assert_idle(ctx, pid)
      assert :ok = Session.close(pid)
    end

    pid = start(ctx)

    for {method, params} <- [
          {"thread/realtime/start", %{"threadId" => "absent"}},
          {"thread/realtime/start", %{"threadId" => "absent", "outputModality" => "video"}},
          {"thread/realtime/start",
           %{"threadId" => "absent", "outputModality" => "audio", "voice" => "unknown-synthetic"}},
          {"thread/realtime/start",
           %{"threadId" => "absent", "outputModality" => "audio", "version" => "v4"}},
          {"thread/realtime/appendAudio",
           %{
             "threadId" => "absent",
             "audio" => %{"data" => "AA==", "sampleRate" => -1, "numChannels" => 1}
           }},
          {"thread/realtime/appendText", %{"threadId" => "absent", "text" => 42}},
          {"thread/realtime/appendSpeech", %{"threadId" => "absent"}},
          {"thread/realtime/stop", %{}}
        ] do
      assert upstream_error(pid, method, params)["code"] == -32_600
    end

    for {option, value} <- [
          {"includeStartupContext", true},
          {"prompt", nil},
          {"initialItems", [%{"role" => "user", "text" => "synthetic"}]},
          {"model", "synthetic"},
          {"voice", "marin"},
          {"delegationAckFiller", true}
        ] do
      params = %{
        "threadId" => "not-a-loaded-thread",
        "outputModality" => "audio",
        "transport" => %{"type" => "existingCall", "callId" => "synthetic-call"},
        option => value
      }

      error = upstream_error(pid, "thread/realtime/start", params)
      assert error["code"] == -32_600
      assert error["message"] == "existingCall transport does not support #{option}"
    end

    barrier(ctx)
    assert handshakes(ctx) == []
    assert_idle(ctx, pid)
  end

  defp assert_realtime_voice_selections(ctx, selections) do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    pid = start(ctx)

    for {{version, voice_options, expected_voice}, index} <- Enum.with_index(selections, 1) do
      thread = TurnFixture.thread(ctx, pid)
      session_id = "synthetic-voice-#{version}-#{index}"

      options =
        Map.merge(voice_options, %{
          "version" => version,
          "realtimeSessionId" => session_id,
          "transport" => %{"type" => "websocket"}
        })

      begin_realtime(pid, thread, options)
      events = wait_event(pid, "thread/realtime/started")

      assert notification(events, "thread/realtime/started") == %{
               "threadId" => thread,
               "realtimeSessionId" => session_id,
               "version" => version
             }

      update = wait_frame(ctx, index, "session.update")["session"]
      handshake = Enum.at(handshakes(ctx), index - 1)

      expected_path =
        case version do
          "v1" -> "/v1/realtime?intent=quicksilver&model=synthetic-configured-realtime"
          "v2" -> "/v1/realtime?model=synthetic-configured-realtime"
          "v3" -> "/v1/live?model=synthetic-configured-realtime"
        end

      assert handshake["connection"] == index
      assert handshake["path"] == expected_path
      assert handshake["authorization"] == "Bearer SYNTHETIC_REALTIME_ONLY"
      assert handshake["headers"]["x-session-id"] == session_id
      assert update["audio"]["output"]["voice"] == expected_voice

      case version do
        "v1" ->
          assert update["type"] == "quicksilver"

        "v2" ->
          assert update["type"] == "realtime"
          assert update["output_modalities"] == ["audio"]

        "v3" ->
          assert update["delegation"] == %{"type" => "client"}
          refute Map.has_key?(update, "type")
      end

      closed = stop(pid, thread)

      await(fn ->
        Enum.any?(journal(ctx), &(&1["event"] == "peer_closed" and &1["connection"] == index))
      end)

      barrier(ctx)
      assert {:ok, trailing} = Session.drain(pid)
      all_events = events ++ closed ++ trailing
      refute notification(all_events, "thread/realtime/error")
      refute Enum.any?(all_events, &(&1.kind == :server_request))

      assert Enum.filter(frames(ctx, index), &(&1["type"] == "session.update")) == [
               %{"type" => "session.update", "session" => update}
             ]

      assert length(handshakes(ctx)) == index
      assert_idle(ctx, pid)
    end

    assert Enum.map(handshakes(ctx), & &1["connection"]) == Enum.to_list(1..length(selections))
  end

  defp start(ctx, negotiation \\ true) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_realtime_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp call(pid, method, params), do: TurnFixture.call(pid, method, params)

  defp upstream_error(pid, method, params),
    do: TurnFixture.upstream_error(pid, method, params, validation: :wire)

  defp notification(events, method), do: TurnFixture.notification(events, method)

  defp begin_realtime(pid, thread, options \\ %{}) do
    assert call(
             pid,
             "thread/realtime/start",
             Map.merge(%{"threadId" => thread, "outputModality" => "audio"}, options)
           ) == %{}
  end

  defp stop(pid, thread) do
    assert call(pid, "thread/realtime/stop", %{"threadId" => thread}) == %{}
    events = wait_event(pid, "thread/realtime/closed")

    assert notification(events, "thread/realtime/closed") == %{
             "threadId" => thread,
             "reason" => "requested"
           }

    events
  end

  defp items(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]["item"]
  end

  defp timeline(pid, thread) do
    for entry <-
          call(pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})["data"],
        entry["type"] == "realtime",
        do: entry["item"]
  end

  defp assert_realtime_facts(events, thread, session_id, contents) do
    completed = items(events, "thread/realtime/item/completed")
    assert length(completed) == length(contents)
    assert length(Enum.uniq_by(completed, & &1["id"])) == length(contents)

    expected =
      for {actual, content} <- Enum.zip(completed, contents) do
        assert actual["id"] =~
                 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

        fact = Map.merge(content, %{"id" => actual["id"], "realtimeSessionId" => session_id})
        assert actual == fact
        fact
      end

    assert for(
             event <- events,
             event.wire["method"] == "thread/realtime/item/completed",
             do: event.wire["params"]
           ) ==
             Enum.map(expected, &%{"threadId" => thread, "item" => &1})

    refute Enum.any?(events, &(&1.kind == :server_request))
    expected
  end

  defp assert_complete_realtime_timeline(pid, thread, expected) do
    page = call(pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})

    assert Map.keys(page) |> Enum.sort() == [
             "activeRealtimeSessionAtPageStart",
             "data",
             "nextCursor"
           ]

    assert page["activeRealtimeSessionAtPageStart"] == nil
    assert page["nextCursor"] == nil
    assert Enum.map(page["data"], & &1["item"]) == expected

    for entry <- page["data"] do
      assert Map.keys(entry) |> Enum.sort() == ["item", "position", "type"]
      assert entry["type"] == "realtime"
      assert is_integer(entry["position"]) and entry["position"] >= 0
    end

    positions = Enum.map(page["data"], & &1["position"])
    assert positions == Enum.sort(Enum.uniq(positions))
    page
  end

  defp wait_realtime_items(pid, count, events, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch

    if length(items(events, "thread/realtime/item/completed")) >= count do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "Realtime canonical item deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected realtime event gap")
      after
        20 -> :ok
      end

      wait_realtime_items(pid, count, events, deadline)
    end
  end

  defp restart_realtime_native(ctx, pid) do
    instance = Session.status(pid).instance_id
    native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1
    cold = start(ctx)
    assert Session.status(cold).instance_id != instance
    %{connection: cold_connection} = :sys.get_state(cold)
    assert cold_connection.port != connection.port
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    cold
  end

  defp assert_realtime_idle(ctx, pid) do
    assert_idle(ctx, pid)
    assert %{interactions: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp remove_auth(ctx) do
    path = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      path,
      String.replace(
        File.read!(path),
        "experimental_bearer_token = \"SYNTHETIC_REALTIME_ONLY\"\n",
        ""
      )
    )
  end

  defp journal(ctx),
    do: ctx.root |> Path.join("realtime-journal.json") |> File.read!() |> JSON.decode!()

  defp handshakes(ctx), do: Enum.filter(journal(ctx), &(&1["event"] == "handshake"))

  defp frames(ctx, connection) do
    for event <- journal(ctx),
        event["event"] == "native_frame" and event["connection"] == connection,
        do: event["message"]
  end

  defp wait_frame(ctx, connection, type) do
    await(fn -> Enum.find(frames(ctx, connection), &(&1["type"] == type)) end)
  end

  defp barrier(ctx), do: control(ctx, "barrier", nil)

  defp control(ctx, action, connection, events \\ []) do
    id = System.unique_integer([:positive])

    assert {:ok, _} =
             Stdio.send(
               ctx.fixture.transport,
               JSON.encode!(%{
                 "id" => id,
                 "action" => action,
                 "connection" => connection,
                 "events" => events
               })
             )

    await(fn ->
      Enum.find(journal(ctx), &(&1["event"] == "control_completed" and &1["id"] == id))
    end)
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [nil, false] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Realtime peer positive-evidence deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp wait_event(pid, method, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch

    if notification(events, method) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Realtime native #{method} deadline: #{inspect(events)}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected realtime event gap")
      after
        20 -> :ok
      end

      wait_event(pid, method, events, deadline)
    end
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    assert ModelFixture.requests(ctx.fixture) == []
  end
end
