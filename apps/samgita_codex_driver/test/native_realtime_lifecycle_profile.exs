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

  defp start(ctx, negotiation \\ true) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: ["app-server", "--listen", "stdio://"],
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
