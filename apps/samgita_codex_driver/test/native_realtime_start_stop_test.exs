defmodule SamgitaCodexDriver.NativeRealtimeStartStopTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_realtime_fixture.py", __DIR__)
  @script_sha "594d4527735a17683cd1f96d6b2a9c6f65df6bf16a65d99dff1b0dba5e14ee84"
  @session "owned-v432-realtime-session"
  @model "owned-v432-realtime-model"
  @prompt "Owned local realtime start"
  @item_started "thread/realtime/item/started"
  @item_completed "thread/realtime/item/completed"
  @started "thread/realtime/started"
  @closed "thread/realtime/closed"
  @realtime_error "thread/realtime/error"
  @service_error_session "owned-v438-realtime-session"
  @service_error_message "Owned local realtime service unavailable λ"
  @item_added "thread/realtime/itemAdded"
  @audio_delta "thread/realtime/outputAudio/delta"
  @item_audio_session "owned-item-audio-realtime-session"
  @backend_item %{
    "id" => "owned-item-audio-backend-item",
    "type" => "message",
    "role" => "user",
    "content" => [%{"type" => "input_text", "text" => "Owned inert realtime item λ"}]
  }
  @audio_base64 "AADoAxj8/38="
  @item_audio_backend [
    %{"type" => "conversation.item.added", "item" => @backend_item},
    %{
      "type" => "response.output_audio.delta",
      "delta" => @audio_base64,
      "sample_rate" => 16_000,
      "channels" => 2,
      "samples_per_channel" => 2,
      "item_id" => "owned-item-audio-output-item"
    }
  ]
  @service_error_backend %{
    "type" => "error",
    "error" => %{
      "type" => "server_error",
      "code" => "server_error",
      "message" => @service_error_message,
      "param" => nil
    }
  }
  @selected [@item_started, @item_completed, @started, @closed]
  @item_delta "thread/realtime/item/transcript/delta"
  @flat_delta "thread/realtime/transcript/delta"
  @flat_done "thread/realtime/transcript/done"
  @transcript_methods [@item_delta, @flat_delta, @flat_done]
  @transcript_session "owned-v435-realtime-session"
  @delta_one "Owned realtime λ "
  @delta_two "draft."
  @streamed_text "Owned realtime λ draft."
  @done_text "Owned realtime λ revised final."
  @transcript_backend [
    %{"type" => "response.output_text.delta", "delta" => @delta_one},
    %{"type" => "response.output_text.delta", "delta" => @delta_two},
    %{"type" => "response.output_text.done", "text" => @done_text}
  ]
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  @peer_ack %{
    "type" => "session.updated",
    "session" => %{
      "id" => "owned-v432-peer-session",
      "instructions" => @prompt
    }
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next.capture, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded, index: ledger.count + 1}

        {:ok,
         %{count: ledger.count + 1, bytes: ledger.bytes + size, records: [entry | ledger.records]}}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-realtime-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      workspace: Path.join(root, "workspace"),
      capture: capture,
      scenario: Map.get(tags, :realtime_scenario, "start-stop")
    }

    peer = start_peer(profile)
    frozen = frozen_files(profile)
    session = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    %{profile: profile, peer: peer, session: session, frozen: frozen}
  end

  test "native ordinary realtime start and requested stop persist exact timeline facts without inference",
       ctx do
    profile = ctx.profile
    pid = ctx.session.pid
    active_deadline = now() + 20_000

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(thread)

    params = %{
      "threadId" => thread,
      "outputModality" => "text",
      "version" => "v2",
      "transport" => %{"type" => "websocket"},
      "realtimeSessionId" => @session,
      "includeStartupContext" => false,
      "flushTranscriptTailOnSessionEnd" => false,
      "clientManagedHandoffs" => true,
      "prompt" => @prompt
    }

    lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/start", params) === %{}

    [start_request] =
      Enum.filter(
        capture(profile),
        &(&1.direction == :out and
            &1.wire["method"] == "thread/realtime/start")
      )

    assert :ok = Schema.validate(schema("ClientRequest.json"), start_request.wire, max_depth: 32)

    events =
      collect(profile, pid, [], min(active_deadline, now() + 5_000), fn events ->
        Enum.any?(events, &(&1.wire["method"] == @started)) and
          length(notices(events, @item_completed)) == 1 and peer_ready?(profile)
      end)

    started_upper = System.system_time(:millisecond)
    [first] = notices(events, @item_completed)
    first_id = Map.fetch!(first.wire["params"]["item"], "id")
    assert_uuid(first_id)

    started_item = %{
      "id" => first_id,
      "realtimeSessionId" => @session,
      "type" => "realtimeSessionStarted"
    }

    first_expected = [
      {@item_started, %{"threadId" => thread, "item" => started_item}},
      {@item_completed, %{"threadId" => thread, "item" => started_item}},
      {@started, %{"threadId" => thread, "realtimeSessionId" => @session, "version" => "v2"}}
    ]

    assert_selected(profile, events, first_expected, lower, started_upper)
    assert_peer(profile, 1)

    stop_lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/stop", %{"threadId" => thread}) === %{}

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        Enum.any?(events, &(&1.wire["method"] == @closed))
      end)

    stopped_upper = System.system_time(:millisecond)
    [^first, last] = notices(events, @item_completed)
    last_id = Map.fetch!(last.wire["params"]["item"], "id")
    assert_uuid(last_id)
    refute last_id === first_id

    closed_item = %{
      "id" => last_id,
      "realtimeSessionId" => @session,
      "type" => "realtimeSessionClosed",
      "outcome" => "ended"
    }

    last_expected = [
      {@item_started, %{"threadId" => thread, "item" => closed_item}},
      {@item_completed, %{"threadId" => thread, "item" => closed_item}},
      {@closed, %{"threadId" => thread, "reason" => "requested"}}
    ]

    selected = Enum.filter(events, &(&1.wire["method"] in @selected))
    assert length(selected) === 6
    assert_selected(profile, Enum.take(selected, 3), first_expected, lower, started_upper)
    assert_selected(profile, Enum.drop(selected, 3), last_expected, stop_lower, stopped_upper)
    originals = assert_originals(profile, selected)

    # A native store read is a persistence barrier, not a silence-based absence check.
    saved =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"
    assert File.regular?(saved["path"])
    timeline = call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})
    assert_timeline(timeline, started_item, closed_item)

    assert call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) ===
             timeline

    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert Enum.filter(events, &(&1.wire["method"] in @selected)) === selected
    await_peer_closed(profile, min(active_deadline, now() + 5_000))
    peer_state = assert_peer(profile, 0)
    peer_bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert_ready(profile, pid)
    assert_inputs(ctx)
    assert now() <= active_deadline

    outgoing = for frame <- capture(profile), frame.direction == :out, do: frame.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/realtime/start thread/realtime/stop thread/read thread/timeline/list thread/timeline/list)

    close_native(pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.peer.transport, ctx.peer.identity)
    assert_inputs(ctx)
    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert read_peer(profile) === peer_state

    assert JSON.decode!(File.read!(Path.join(profile.root, "peer-closed.json"))) ===
             %{
               "activeSockets" => 0,
               "handlerThreads" => 0,
               "threadAlive" => false,
               "serverClosed" => true
             }

    assert assert_originals(profile, selected) === originals
  end

  @tag realtime_scenario: "transcript"
  test "native transcript retains streamed text when flat completion revises the final text",
       ctx do
    profile = ctx.profile
    pid = ctx.session.pid
    active_deadline = now() + 20_000

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(thread)

    params = %{
      "threadId" => thread,
      "outputModality" => "text",
      "version" => "v2",
      "transport" => %{"type" => "websocket"},
      "realtimeSessionId" => @transcript_session,
      "includeStartupContext" => false,
      "flushTranscriptTailOnSessionEnd" => false,
      "clientManagedHandoffs" => true,
      "prompt" => @prompt
    }

    lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/start", params) === %{}

    [start_request] =
      Enum.filter(
        capture(profile),
        &(&1.direction == :out and
            &1.wire["method"] == "thread/realtime/start")
      )

    assert :ok = Schema.validate(schema("ClientRequest.json"), start_request.wire, max_depth: 32)

    events =
      collect(profile, pid, [], min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @item_started)) == 1 and
          length(notices(events, @item_completed)) == 1 and
          length(notices(events, @started)) == 1 and peer_ready?(profile)
      end)

    started_upper = System.system_time(:millisecond)
    [first_start] = notices(events, @item_started)
    a = Map.fetch!(first_start.wire["params"]["item"], "id")
    assert_uuid(a)

    first_item = %{
      "id" => a,
      "realtimeSessionId" => @transcript_session,
      "type" => "realtimeSessionStarted"
    }

    first_expected = [
      {@item_started, %{"threadId" => thread, "item" => first_item}},
      {@item_completed, %{"threadId" => thread, "item" => first_item}},
      {@started,
       %{"threadId" => thread, "realtimeSessionId" => @transcript_session, "version" => "v2"}}
    ]

    assert_selected(profile, events, first_expected, lower, started_upper)
    assert_peer(profile, 1)

    first_originals =
      assert_originals(
        profile,
        Enum.filter(events, &(&1.wire["method"] in selected_methods(profile)))
      )

    release_boundary = length(capture(profile))

    # Release genuine backend data only after both native and peer readiness.
    transcript_lower = System.system_time(:millisecond)
    release_transcript(ctx.peer.port, min(active_deadline, now() + 5_000))

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @flat_done)) == 1 and
          length(notices(events, @item_completed)) == 2 and
          read_peer(profile)["sent"] == [@peer_ack | @transcript_backend]
      end)

    transcript_upper = System.system_time(:millisecond)
    [^first_start, transcript_start] = notices(events, @item_started)
    t = Map.fetch!(transcript_start.wire["params"]["item"], "id")
    assert_uuid(t)
    refute t === a

    empty_transcript = %{
      "id" => t,
      "realtimeSessionId" => @transcript_session,
      "type" => "transcriptSegment",
      "role" => "assistant",
      "text" => ""
    }

    transcript = %{
      "id" => t,
      "realtimeSessionId" => @transcript_session,
      "type" => "transcriptSegment",
      "role" => "assistant",
      "text" => @streamed_text
    }

    transcript_expected = [
      {@item_started, %{"threadId" => thread, "item" => empty_transcript}},
      {@item_delta, %{"threadId" => thread, "itemId" => t, "delta" => @delta_one}},
      {@flat_delta, %{"threadId" => thread, "role" => "assistant", "delta" => @delta_one}},
      {@item_delta, %{"threadId" => thread, "itemId" => t, "delta" => @delta_two}},
      {@flat_delta, %{"threadId" => thread, "role" => "assistant", "delta" => @delta_two}},
      {@item_completed, %{"threadId" => thread, "item" => transcript}},
      {@flat_done, %{"threadId" => thread, "role" => "assistant", "text" => @done_text}}
    ]

    methods = selected_methods(profile)
    selected = Enum.filter(events, &(&1.wire["method"] in methods))
    assert length(selected) === 10
    assert_selected(profile, Enum.take(selected, 3), first_expected, lower, started_upper)

    assert_selected(
      profile,
      Enum.drop(selected, 3),
      transcript_expected,
      transcript_lower,
      transcript_upper
    )

    assert_transcript_peer(profile, 1)

    stop_lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/stop", %{"threadId" => thread}) === %{}

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @closed)) == 1
      end)

    stopped_upper = System.system_time(:millisecond)
    [^first_start, ^transcript_start, last_start] = notices(events, @item_started)
    b = Map.fetch!(last_start.wire["params"]["item"], "id")
    assert_uuid(b)
    assert length(Enum.uniq([a, t, b])) === 3

    last_item = %{
      "id" => b,
      "realtimeSessionId" => @transcript_session,
      "type" => "realtimeSessionClosed",
      "outcome" => "ended"
    }

    last_expected = [
      {@item_started, %{"threadId" => thread, "item" => last_item}},
      {@item_completed, %{"threadId" => thread, "item" => last_item}},
      {@closed, %{"threadId" => thread, "reason" => "requested"}}
    ]

    selected = Enum.filter(events, &(&1.wire["method"] in methods))
    assert length(selected) === 13
    assert_selected(profile, Enum.take(selected, 3), first_expected, lower, started_upper)

    assert_selected(
      profile,
      Enum.slice(selected, 3, 7),
      transcript_expected,
      transcript_lower,
      transcript_upper
    )

    assert_selected(profile, Enum.drop(selected, 10), last_expected, stop_lower, stopped_upper)
    originals = assert_originals(profile, selected)
    assert Enum.take(originals, 3) === first_originals
    assert_transcript_delta_payloads(originals, thread, t)
    assert_release_order(profile, originals, release_boundary)

    saved =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"
    assert File.regular?(saved["path"])

    rollout =
      assert_transcript_rollout(
        profile,
        saved["path"],
        [
          %{
            "id" => a,
            "realtime_session_id" => @transcript_session,
            "type" => "realtime_session_started"
          },
          %{
            "id" => t,
            "realtime_session_id" => @transcript_session,
            "type" => "transcript_segment",
            "role" => "assistant",
            "text" => @streamed_text
          },
          %{
            "id" => b,
            "realtime_session_id" => @transcript_session,
            "type" => "realtime_session_closed",
            "outcome" => "ended"
          }
        ],
        [
          {lower, started_upper},
          {transcript_lower, transcript_upper},
          {stop_lower, stopped_upper}
        ]
      )

    expected_timeline = %{
      "data" =>
        Enum.zip_with(rollout.ordinals, [first_item, transcript, last_item], fn ordinal, item ->
          %{"type" => "realtime", "position" => ordinal, "item" => item}
        end),
      "nextCursor" => nil,
      "activeRealtimeSessionAtPageStart" => nil
    }

    timeline = call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})
    assert_transcript_timeline(timeline, [first_item, transcript, last_item])
    assert timeline === expected_timeline
    assert_original_timeline_responses(profile, thread, expected_timeline, 1)
    refute Enum.any?(timeline["data"], &(get_in(&1, ["item", "text"]) in ["", @done_text]))

    assert call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) ===
             timeline

    assert_original_timeline_responses(profile, thread, expected_timeline, 2)
    assert_rollout_snapshot(rollout)

    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert Enum.filter(events, &(&1.wire["method"] in methods)) === selected
    await_peer_closed(profile, min(active_deadline, now() + 5_000))
    peer_state = assert_transcript_peer(profile, 0)
    peer_bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert_inputs(ctx)
    assert_ready(profile, pid)
    assert now() <= active_deadline
    outgoing = for frame <- capture(profile), frame.direction == :out, do: frame.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/realtime/start thread/realtime/stop thread/read thread/timeline/list thread/timeline/list)

    close_native(pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.peer.transport, ctx.peer.identity)
    assert_inputs(ctx)
    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert read_peer(profile) === peer_state

    assert JSON.decode!(File.read!(Path.join(profile.root, "peer-closed.json"))) === %{
             "activeSockets" => 0,
             "handlerThreads" => 0,
             "threadAlive" => false,
             "serverClosed" => true
           }

    assert assert_originals(profile, selected) === originals
    assert_rollout_snapshot(rollout)
  end

  @tag realtime_scenario: "item-audio"
  test "native itemAdded and PCM output preserve literal payloads without adding history items",
       ctx do
    profile = ctx.profile
    pid = ctx.session.pid
    active_deadline = now() + 20_000

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(thread)
    lower = System.system_time(:millisecond)

    assert call(profile, pid, "thread/realtime/start", %{
             "threadId" => thread,
             "outputModality" => "audio",
             "version" => "v2",
             "transport" => %{"type" => "websocket"},
             "realtimeSessionId" => @item_audio_session,
             "includeStartupContext" => false,
             "flushTranscriptTailOnSessionEnd" => false,
             "clientManagedHandoffs" => true,
             "prompt" => @prompt
           }) === %{}

    events =
      collect(profile, pid, [], min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @item_started)) == 1 and
          length(notices(events, @item_completed)) == 1 and
          length(notices(events, @started)) == 1 and peer_ready?(profile)
      end)

    started_upper = System.system_time(:millisecond)
    [first] = notices(events, @item_completed)
    a = Map.fetch!(first.wire["params"]["item"], "id")
    assert_uuid(a)

    first_item = %{
      "id" => a,
      "realtimeSessionId" => @item_audio_session,
      "type" => "realtimeSessionStarted"
    }

    first_expected = [
      {@item_started, %{"threadId" => thread, "item" => first_item}},
      {@item_completed, %{"threadId" => thread, "item" => first_item}},
      {@started,
       %{"threadId" => thread, "realtimeSessionId" => @item_audio_session, "version" => "v2"}}
    ]

    assert_selected(profile, events, first_expected, lower, started_upper)
    assert_item_audio_peer(profile, 1, false)

    first_originals =
      assert_originals(
        profile,
        Enum.filter(events, &(&1.wire["method"] in selected_methods(profile)))
      )

    release_boundary = length(capture(profile))
    payload_lower = System.system_time(:millisecond)
    release_item_audio(ctx.peer.port, min(active_deadline, now() + 5_000))

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @item_added)) == 1 and
          length(notices(events, @audio_delta)) == 1 and
          read_peer(profile)["sent"] == [@peer_ack | @item_audio_backend]
      end)

    payload_upper = System.system_time(:millisecond)

    audio = %{
      "data" => @audio_base64,
      "sampleRate" => 16_000,
      "numChannels" => 2,
      "samplesPerChannel" => 2,
      "itemId" => "owned-item-audio-output-item"
    }

    middle_expected = [
      {@item_added, %{"threadId" => thread, "item" => @backend_item}},
      {@audio_delta, %{"threadId" => thread, "audio" => audio}}
    ]

    [audio_event] = notices(events, @audio_delta)
    assert audio_event.wire["params"]["audio"] === audio
    pcm = Base.decode64!(audio_event.wire["params"]["audio"]["data"])
    assert pcm === <<0, 0, 232, 3, 24, 252, 255, 127>>
    assert for(<<sample::little-signed-16 <- pcm>>, do: sample) === [0, 1000, -1000, 32_767]
    assert byte_size(pcm) === audio["samplesPerChannel"] * audio["numChannels"] * 2

    stop_lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/stop", %{"threadId" => thread}) === %{}

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @closed)) == 1
      end)

    stopped_upper = System.system_time(:millisecond)
    [^first, last] = notices(events, @item_completed)
    b = Map.fetch!(last.wire["params"]["item"], "id")
    assert_uuid(b)
    refute b === a

    last_item = %{
      "id" => b,
      "realtimeSessionId" => @item_audio_session,
      "type" => "realtimeSessionClosed",
      "outcome" => "ended"
    }

    last_expected = [
      {@item_started, %{"threadId" => thread, "item" => last_item}},
      {@item_completed, %{"threadId" => thread, "item" => last_item}},
      {@closed, %{"threadId" => thread, "reason" => "requested"}}
    ]

    methods = selected_methods(profile)
    selected = Enum.filter(events, &(&1.wire["method"] in methods))
    assert length(selected) === 8
    assert_selected(profile, Enum.take(selected, 3), first_expected, lower, started_upper)

    assert_selected(
      profile,
      Enum.slice(selected, 3, 2),
      middle_expected,
      payload_lower,
      payload_upper
    )

    assert_selected(profile, Enum.drop(selected, 5), last_expected, stop_lower, stopped_upper)
    originals = assert_originals(profile, selected)
    assert Enum.take(originals, 3) === first_originals
    assert_item_audio_release(profile, originals, release_boundary)

    # The public read is a persistence barrier. These two transport observations
    # have no history effects in the pinned realtime-history observer.
    saved =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"

    rollout =
      assert_item_audio_rollout(profile, saved["path"], [
        {%{
           "id" => a,
           "realtime_session_id" => @item_audio_session,
           "type" => "realtime_session_started"
         }, {lower, started_upper}},
        {%{
           "id" => b,
           "realtime_session_id" => @item_audio_session,
           "type" => "realtime_session_closed",
           "outcome" => "ended"
         }, {stop_lower, stopped_upper}}
      ])

    timeline = call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})
    assert_timeline(timeline, first_item, last_item)
    assert Enum.map(timeline["data"], & &1["position"]) === rollout.ordinals

    assert call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) ===
             timeline

    assert_original_timeline_responses(profile, thread, timeline, 2)
    assert_rollout_snapshot(rollout)

    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert Enum.filter(events, &(&1.wire["method"] in methods)) === selected
    await_peer_closed(profile, min(active_deadline, now() + 5_000))
    peer_state = assert_item_audio_peer(profile, 0, true)
    peer_bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert_ready(profile, pid)
    assert_inputs(ctx)
    assert now() <= active_deadline
    outgoing = for frame <- capture(profile), frame.direction == :out, do: frame.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/realtime/start thread/realtime/stop thread/read thread/timeline/list thread/timeline/list)

    close_native(pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.peer.transport, ctx.peer.identity)
    assert_inputs(ctx)
    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert read_peer(profile) === peer_state

    assert JSON.decode!(File.read!(Path.join(profile.root, "peer-closed.json"))) === %{
             "activeSockets" => 0,
             "handlerThreads" => 0,
             "threadAlive" => false,
             "serverClosed" => true
           }

    assert assert_originals(profile, selected) === originals
    assert_rollout_snapshot(rollout)
  end

  @tag realtime_scenario: "service-error"
  test "native backend service error closes once and retains failed facts across a cold read",
       ctx do
    pid = ctx.session.pid
    active_deadline = now() + 20_000

    thread =
      call(ctx.profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(thread)
    profile = Map.put(ctx.profile, :service_error_thread, thread)

    params = %{
      "threadId" => thread,
      "outputModality" => "text",
      "version" => "v2",
      "transport" => %{"type" => "websocket"},
      "realtimeSessionId" => @service_error_session,
      "includeStartupContext" => false,
      "flushTranscriptTailOnSessionEnd" => false,
      "clientManagedHandoffs" => true,
      "prompt" => @prompt
    }

    lower = System.system_time(:millisecond)
    assert call(profile, pid, "thread/realtime/start", params) === %{}

    [start_request] =
      Enum.filter(
        capture(profile),
        &(&1.direction == :out and &1.wire["method"] == "thread/realtime/start")
      )

    assert :ok = Schema.validate(schema("ClientRequest.json"), start_request.wire, max_depth: 32)

    events =
      collect(profile, pid, [], min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @item_started)) == 1 and
          length(notices(events, @item_completed)) == 1 and
          length(notices(events, @started)) == 1 and peer_ready?(profile)
      end)

    started_upper = System.system_time(:millisecond)
    [first_start] = notices(events, @item_started)
    a = Map.fetch!(first_start.wire["params"]["item"], "id")
    assert_uuid(a)

    first_item = %{
      "id" => a,
      "realtimeSessionId" => @service_error_session,
      "type" => "realtimeSessionStarted"
    }

    first_expected = [
      {@item_started, %{"threadId" => thread, "item" => first_item}},
      {@item_completed, %{"threadId" => thread, "item" => first_item}},
      {@started,
       %{"threadId" => thread, "realtimeSessionId" => @service_error_session, "version" => "v2"}}
    ]

    assert_selected(profile, events, first_expected, lower, started_upper)
    assert_peer(profile, 1)

    first_originals =
      assert_originals(
        profile,
        Enum.filter(events, &(&1.wire["method"] in selected_methods(profile)))
      )

    release_boundary = length(capture(profile))
    failure_lower = System.system_time(:millisecond)
    release_service_error(ctx.peer.port, min(active_deadline, now() + 5_000))

    events =
      collect(profile, pid, events, min(active_deadline, now() + 5_000), fn events ->
        length(notices(events, @realtime_error)) == 1 and
          length(notices(events, @item_started)) == 2 and
          length(notices(events, @item_completed)) == 2 and
          length(notices(events, @closed)) == 1 and
          read_peer(profile)["sent"] == [@peer_ack, @service_error_backend]
      end)

    failure_upper = System.system_time(:millisecond)
    [^first_start, failed_start] = notices(events, @item_started)
    b = Map.fetch!(failed_start.wire["params"]["item"], "id")
    assert_uuid(b)
    refute b === a

    failed_item = %{
      "id" => b,
      "realtimeSessionId" => @service_error_session,
      "type" => "realtimeSessionClosed",
      "outcome" => "failed"
    }

    failed_expected = [
      {@realtime_error, %{"threadId" => thread, "message" => @service_error_message}},
      {@item_started, %{"threadId" => thread, "item" => failed_item}},
      {@item_completed, %{"threadId" => thread, "item" => failed_item}},
      {@closed, %{"threadId" => thread, "reason" => "error"}}
    ]

    methods = selected_methods(profile)
    selected = Enum.filter(events, &(&1.wire["method"] in methods))
    assert length(selected) === 7
    assert_selected(profile, Enum.take(selected, 3), first_expected, lower, started_upper)

    assert_selected(
      profile,
      Enum.drop(selected, 3),
      failed_expected,
      failure_lower,
      failure_upper
    )

    originals = assert_originals(profile, selected)
    assert Enum.take(originals, 3) === first_originals
    assert_service_error_release(profile, originals, release_boundary)

    saved =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"
    assert File.regular?(saved["path"])
    timeline = call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100})
    assert_timeline(timeline, first_item, failed_item)

    assert call(profile, pid, "thread/timeline/list", %{"threadId" => thread, "limit" => 100}) ===
             timeline

    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert Enum.filter(events, &(&1.wire["method"] in methods)) === selected
    await_peer_closed(profile, min(active_deadline, now() + 5_000))
    peer_state = assert_service_error_peer(profile)
    peer_bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert_ready(profile, pid)
    assert_inputs(ctx)

    outgoing = for frame <- capture(profile), frame.direction == :out, do: frame.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/realtime/start thread/read thread/timeline/list thread/timeline/list)

    warm_native = :atomics.get(ctx.session.identity, 1)
    close_native(pid, ctx.session.connection, ctx.session.identity)
    original_capture = Agent.get(profile.capture, & &1)

    # A cold native instance has its own bounded ledger; original ingress stays immutable.
    cold_capture =
      start_supervised!(
        Supervisor.child_spec(
          {Agent, fn -> %{count: 0, bytes: 0, records: []} end},
          id: :service_error_cold_capture
        )
      )

    cold_profile = %{profile | capture: cold_capture}
    cold = start_native(cold_profile)
    cold_profile = Map.put(cold_profile, :generation, Session.status(cold.pid).generation)
    refute :atomics.get(cold.identity, 1) === warm_native

    assert call(cold_profile, cold.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    cold_saved =
      call(cold_profile, cold.pid, "thread/read", %{
        "threadId" => thread,
        "includeTurns" => false
      })["thread"]

    assert cold_saved["id"] === thread and cold_saved["historyMode"] === "paginated"
    assert cold_saved["path"] === saved["path"]

    for _read <- 1..2 do
      page =
        call(cold_profile, cold.pid, "thread/timeline/list", %{
          "threadId" => thread,
          "limit" => 100
        })

      assert page === timeline
      assert_timeline(page, first_item, failed_item)
    end

    assert {:ok, cold_events} = Session.drain(cold.pid, 128)
    assert_events(cold_profile, cold_events)
    refute Enum.any?(cold_events, &String.starts_with?(&1.wire["method"], "thread/realtime/"))
    assert assert_originals(cold_profile, []) === []
    assert_ready(cold_profile, cold.pid)
    assert now() <= active_deadline

    cold_outgoing =
      for frame <- capture(cold_profile), frame.direction == :out, do: frame.wire["method"]

    assert cold_outgoing ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/read thread/timeline/list thread/timeline/list)

    close_native(cold.pid, cold.connection, cold.identity)
    close_transport(ctx.peer.transport, ctx.peer.identity)
    assert_inputs(ctx)
    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert read_peer(profile) === peer_state
    assert Agent.get(profile.capture, & &1) === original_capture
    assert assert_originals(profile, selected) === originals

    assert JSON.decode!(File.read!(Path.join(profile.root, "peer-closed.json"))) === %{
             "activeSockets" => 0,
             "handlerThreads" => 0,
             "threadAlive" => false,
             "serverClosed" => true
           }
  end

  defp assert_item_audio_release(profile, originals, release_boundary) do
    frames = capture(profile)

    [start] =
      Enum.filter(
        frames,
        &(&1.direction == :out and &1.wire["method"] == "thread/realtime/start")
      )

    [response] = Enum.filter(frames, &(&1.direction == :in and &1.wire["id"] == start.wire["id"]))

    [stop] =
      Enum.filter(frames, &(&1.direction == :out and &1.wire["method"] == "thread/realtime/stop"))

    assert :ok = Schema.validate(schema("ClientRequest.json"), start.wire, max_depth: 32)
    assert response.wire === %{"id" => start.wire["id"], "result" => %{}}
    assert start.index < response.index and response.index <= release_boundary
    assert Enum.all?(Enum.take(originals, 3), &(&1.index <= release_boundary))

    assert Enum.all?(
             Enum.slice(originals, 3, 2),
             &(&1.index > release_boundary and &1.index < stop.index)
           )

    assert Enum.all?(Enum.drop(originals, 5), &(&1.index > stop.index))
  end

  defp release_item_audio(port, deadline) do
    remaining = deadline - now()
    assert remaining > 0

    assert {:ok, socket} =
             :gen_tcp.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, send_timeout: remaining, send_timeout_close: true],
               remaining
             )

    try do
      request =
        "POST /fixture/item-audio HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

      assert byte_size(request) <= 8192
      assert :ok = :gen_tcp.send(socket, request)
      response = control_response(socket, <<>>, deadline)
      assert byte_size(request) + byte_size(response) <= 8192

      assert response ===
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 17\r\nConnection: close\r\n\r\n{\"released\":true}"
    after
      assert :ok = :gen_tcp.close(socket)
    end
  end

  defp assert_item_audio_peer(profile, active, released) do
    state = read_peer(profile)
    assert state["paths"] === ["/v1/realtime?model=#{@model}"]
    assert [message] = state["messages"]
    assert message["type"] === "session.update"
    assert message["session"]["type"] === "realtime"
    assert message["session"]["instructions"] === @prompt
    assert message["session"]["output_modalities"] === ["audio"]

    assert state["sent"] ===
             if(released, do: [@peer_ack | @item_audio_backend], else: [@peer_ack])

    assert state["requestCount"] === if(released, do: 2, else: 1)

    assert state["controls"] ===
             if(released,
               do: [%{"method" => "POST", "path" => "/fixture/item-audio", "bodyBytes" => 0}],
               else: []
             )

    assert state["activeConnections"] === active
    assert state["responsesRequests"] === 0 and state["otherHttp"] === []
    assert state["errors"] === []

    assert is_integer(state["frameCount"]) and state["frameCount"] >= if(released, do: 4, else: 2) and
             state["frameCount"] <= 32

    state
  end

  defp assert_item_audio_rollout(profile, path, expected) do
    assert is_binary(path)
    path = Path.expand(path)
    assert String.starts_with?(path, Path.join(profile.root, "codex") <> "/")
    assert File.regular?(path)
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) > 0 and byte_size(bytes) <= 1_048_576
    assert String.ends_with?(bytes, "\n")
    lines = bytes |> binary_part(0, byte_size(bytes) - 1) |> String.split("\n")
    assert length(lines) <= 2_048
    records = Enum.map(lines, &JSON.decode!/1)
    realtime = Enum.filter(records, &(&1["type"] == "realtime_item"))
    assert length(realtime) === 2
    assert Enum.map(realtime, & &1["payload"]) === Enum.map(expected, &elem(&1, 0))

    for {record, {_payload, bracket}} <- Enum.zip(realtime, expected),
        do: assert_rollout_record(record, bracket)

    assert [a, b] = ordinals = Enum.map(realtime, &Map.fetch!(&1, "ordinal"))
    assert is_integer(a) and is_integer(b) and 0 <= a and a < b
    %{path: path, bytes: bytes, sha256: hash(bytes), ordinals: ordinals}
  end

  defp assert_service_error_release(profile, originals, release_boundary) do
    frames = capture(profile)

    [start] =
      Enum.filter(
        frames,
        &(&1.direction == :out and &1.wire["method"] == "thread/realtime/start")
      )

    [response] = Enum.filter(frames, &(&1.direction == :in and &1.wire["id"] == start.wire["id"]))
    assert start.index < response.index and response.index <= release_boundary
    assert Enum.all?(Enum.take(originals, 3), &(&1.index <= release_boundary))
    assert Enum.all?(Enum.drop(originals, 3), &(&1.index > release_boundary))
  end

  defp release_service_error(port, deadline) do
    remaining = deadline - now()
    assert remaining > 0

    assert {:ok, socket} =
             :gen_tcp.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, send_timeout: remaining, send_timeout_close: true],
               remaining
             )

    try do
      request =
        "POST /fixture/service-error HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

      assert byte_size(request) <= 8192
      assert :ok = :gen_tcp.send(socket, request)
      response = control_response(socket, <<>>, deadline)
      assert byte_size(request) + byte_size(response) <= 8192

      assert response ===
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 17\r\nConnection: close\r\n\r\n{\"released\":true}"
    after
      assert :ok = :gen_tcp.close(socket)
    end
  end

  defp assert_service_error_peer(profile) do
    state = read_peer(profile)
    assert state["paths"] === ["/v1/realtime?model=#{@model}"]
    assert [message] = state["messages"]
    assert message["type"] === "session.update"
    assert message["session"]["type"] === "realtime"
    assert message["session"]["instructions"] === @prompt
    assert message["session"]["output_modalities"] === ["text"]
    assert state["sent"] === [@peer_ack, @service_error_backend]
    assert state["requestCount"] === 2

    assert state["controls"] === [
             %{"method" => "POST", "path" => "/fixture/service-error", "bodyBytes" => 0}
           ]

    assert state["activeConnections"] === 0
    assert state["responsesRequests"] === 0 and state["otherHttp"] === []
    assert state["errors"] === []

    assert is_integer(state["frameCount"]) and state["frameCount"] >= 3 and
             state["frameCount"] <= 32

    state
  end

  defp assert_transcript_rollout(profile, path, expected_payloads, brackets) do
    assert is_binary(path)
    path = Path.expand(path)
    assert String.starts_with?(path, Path.join(profile.root, "codex") <> "/")
    assert File.regular?(path)
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) > 0 and byte_size(bytes) <= 1_048_576
    assert String.ends_with?(bytes, "\n")
    lines = bytes |> binary_part(0, byte_size(bytes) - 1) |> String.split("\n")
    assert length(lines) <= 2_048
    records = Enum.map(lines, &JSON.decode!/1)
    realtime = Enum.filter(records, &(&1["type"] == "realtime_item"))
    assert length(realtime) === 3
    assert Enum.map(realtime, & &1["payload"]) === expected_payloads

    for {record, bracket} <- Enum.zip(realtime, brackets) do
      assert_rollout_record(record, bracket)
    end

    ordinals = Enum.map(realtime, &Map.fetch!(&1, "ordinal"))
    assert [a, t, b] = ordinals
    assert is_integer(a) and is_integer(t) and is_integer(b) and 0 <= a and a < t and t < b
    %{path: path, bytes: bytes, sha256: hash(bytes), ordinals: ordinals}
  end

  defp assert_rollout_record(record, {lower, upper}) do
    assert Enum.sort(Map.keys(record)) === ["ordinal", "payload", "timestamp", "type"]
    assert record["type"] === "realtime_item"
    assert {:ok, timestamp, 0} = DateTime.from_iso8601(record["timestamp"])
    millis = DateTime.to_unix(timestamp, :millisecond)
    assert millis > 0 and lower <= millis and millis <= upper
  end

  defp assert_original_timeline_responses(profile, thread, expected, count) do
    frames = capture(profile)

    requests =
      Enum.filter(
        frames,
        &(&1.direction == :out and &1.wire["method"] == "thread/timeline/list")
      )

    assert length(requests) === count
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === count

    for sent <- requests do
      id = sent.wire["id"]

      assert sent.wire === %{
               "id" => id,
               "method" => "thread/timeline/list",
               "params" => %{"threadId" => thread, "limit" => 100}
             }

      assert [^sent, received] = Enum.filter(frames, &(&1.wire["id"] == id))
      assert received.direction === :in and sent.index < received.index
      envelope = %{"id" => id, "result" => expected}
      assert received.wire === envelope
      assert JSON.decode!(received.encoded) === envelope
      assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
      assert decoded === envelope

      assert :ok =
               Schema.validate(
                 schema("v2/ThreadTimelineListResponse.json"),
                 received.wire["result"],
                 max_depth: 32
               )
    end
  end

  defp assert_rollout_snapshot(rollout) do
    assert File.stat!(rollout.path).size === byte_size(rollout.bytes)
    bytes = File.read!(rollout.path)
    assert bytes === rollout.bytes
    assert hash(bytes) === rollout.sha256
  end

  defp assert_transcript_timeline(page, items) do
    assert [first, middle, last] = Map.fetch!(page, "data")
    a = Map.fetch!(first, "position")
    t = Map.fetch!(middle, "position")
    b = Map.fetch!(last, "position")
    assert is_integer(a) and is_integer(t) and is_integer(b) and 0 <= a and a < t and t < b

    expected = %{
      "data" =>
        Enum.zip_with([a, t, b], items, fn position, item ->
          %{"type" => "realtime", "position" => position, "item" => item}
        end),
      "nextCursor" => nil,
      "activeRealtimeSessionAtPageStart" => nil
    }

    assert page === expected

    assert :ok =
             Schema.validate(schema("v2/ThreadTimelineListResponse.json"), page, max_depth: 32)
  end

  defp assert_transcript_delta_payloads(originals, thread, item) do
    deltas = Enum.filter(originals, &(&1.wire["method"] == @item_delta))
    assert length(deltas) === 2

    for {original, delta} <- Enum.zip(deltas, [@delta_one, @delta_two]) do
      expected = %{"threadId" => thread, "itemId" => item, "delta" => delta}
      assert original.wire["params"] === expected
      assert JSON.decode!(original.encoded)["params"] === expected

      assert :ok =
               Schema.validate(
                 schema("v2/ThreadRealtimeItemTranscriptDeltaNotification.json"),
                 original.wire["params"],
                 max_depth: 32
               )
    end
  end

  defp assert_release_order(profile, originals, release_boundary) do
    frames = capture(profile)

    [start] =
      Enum.filter(
        frames,
        &(&1.direction == :out and &1.wire["method"] == "thread/realtime/start")
      )

    [response] = Enum.filter(frames, &(&1.direction == :in and &1.wire["id"] == start.wire["id"]))

    [stop] =
      Enum.filter(frames, &(&1.direction == :out and &1.wire["method"] == "thread/realtime/stop"))

    assert start.index < response.index and response.index <= release_boundary
    assert Enum.all?(Enum.take(originals, 3), &(&1.index <= release_boundary))

    assert Enum.all?(
             Enum.slice(originals, 3, 7),
             &(&1.index > release_boundary and &1.index < stop.index)
           )

    assert Enum.all?(Enum.drop(originals, 10), &(&1.index > stop.index))
    # Submission ACK and terminal delivery can race; their mutual order is not prescribed.
  end

  defp release_transcript(port, deadline) do
    remaining = deadline - now()
    assert remaining > 0

    assert {:ok, socket} =
             :gen_tcp.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, send_timeout: remaining, send_timeout_close: true],
               remaining
             )

    try do
      request =
        "POST /fixture/transcript HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

      assert byte_size(request) <= 8192
      assert :ok = :gen_tcp.send(socket, request)
      response = control_response(socket, <<>>, deadline)
      assert byte_size(request) + byte_size(response) <= 8192

      assert response ===
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 17\r\nConnection: close\r\n\r\n{\"released\":true}"
    after
      assert :ok = :gen_tcp.close(socket)
    end
  end

  defp control_response(socket, bytes, deadline) do
    assert byte_size(bytes) <= 8192
    remaining = deadline - now()
    assert remaining > 0, "Owned transcript control response deadline"

    case :gen_tcp.recv(socket, 0, remaining) do
      {:ok, fresh} -> control_response(socket, bytes <> fresh, deadline)
      {:error, :closed} -> bytes
      other -> flunk("Owned transcript control response failed: #{inspect(other)}")
    end
  end

  defp assert_transcript_peer(profile, active) do
    state = read_peer(profile)
    assert state["paths"] === ["/v1/realtime?model=#{@model}"]
    assert [message] = state["messages"]
    assert message["type"] === "session.update"
    assert message["session"]["type"] === "realtime"
    assert message["session"]["instructions"] === @prompt
    assert message["session"]["output_modalities"] === ["text"]
    assert state["sent"] === [@peer_ack | @transcript_backend]
    assert state["requestCount"] === 2

    assert state["controls"] === [
             %{"method" => "POST", "path" => "/fixture/transcript", "bodyBytes" => 0}
           ]

    assert state["activeConnections"] === active
    assert state["responsesRequests"] === 0 and state["otherHttp"] === []
    assert state["errors"] === []

    assert is_integer(state["frameCount"]) and state["frameCount"] >= 5 and
             state["frameCount"] <= 32

    state
  end

  defp assert_timeline(page, started, closed) do
    assert [first, last] = Map.fetch!(page, "data")
    a = Map.fetch!(first, "position")
    b = Map.fetch!(last, "position")
    assert is_integer(a) and is_integer(b) and 0 <= a and a < b

    expected = %{
      "data" => [
        %{"type" => "realtime", "position" => a, "item" => started},
        %{"type" => "realtime", "position" => b, "item" => closed}
      ],
      "nextCursor" => nil,
      "activeRealtimeSessionAtPageStart" => nil
    }

    assert page === expected

    assert :ok =
             Schema.validate(schema("v2/ThreadTimelineListResponse.json"), page, max_depth: 32)
  end

  defp assert_selected(profile, events, prescribed, lower, upper) do
    methods = selected_methods(profile)
    selected = Enum.filter(events, &(&1.wire["method"] in methods))
    assert length(selected) === length(prescribed)

    for {event, {method, params}} <- Enum.zip(selected, prescribed) do
      emitted = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted) and lower <= emitted and emitted <= upper
      assert event.kind === :notification and event.generation === profile.generation
      assert event.wire === %{"method" => method, "params" => params, "emittedAtMs" => emitted}
      assert :ok = Schema.validate(schema("ServerNotification.json"), event.wire, max_depth: 32)
    end
  end

  defp assert_originals(profile, events) do
    methods = selected_methods(profile)

    originals =
      for frame <- capture(profile),
          frame.direction == :in,
          frame.wire["method"] in methods,
          do: frame

    assert Enum.map(originals, & &1.wire) === Enum.map(events, & &1.wire)
    indices = Enum.map(originals, & &1.index)
    assert indices === Enum.sort(Enum.uniq(indices))

    for {original, event} <- Enum.zip(originals, events) do
      assert JSON.decode!(original.encoded) === event.wire
      assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 32)
      assert decoded === event.wire
    end

    originals
  end

  defp collect(profile, pid, events, deadline, predicate) do
    assert now() < deadline, "Owned realtime notification deadline"
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert_ready(profile, pid)
    assert read_peer(profile)["errors"] === []

    if predicate.(events) do
      events
    else
      Process.sleep(10)
      collect(profile, pid, events, deadline, predicate)
    end
  end

  defp assert_events(profile, events) do
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert Enum.all?(
             events,
             &(&1.kind === :notification and &1.generation === profile.generation)
           )

    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))

    if profile.scenario == "service-error" do
      refute Enum.any?(events, fn event ->
               event.wire["method"] in ~w(error warning turn/started turn/completed item/started item/completed)
             end)

      failures = notices(events, @realtime_error)
      assert length(failures) <= 1

      for failure <- failures do
        assert failure.wire["params"] === %{
                 "threadId" => profile.service_error_thread,
                 "message" => @service_error_message
               }
      end

      refute Enum.any?(events, fn event ->
               String.starts_with?(event.wire["method"], "thread/realtime/") and
                 event.wire["method"] not in selected_methods(profile)
             end)
    else
      refute Enum.any?(events, fn event ->
               event.wire["method"] in ~w(error warning turn/started turn/completed item/started item/completed thread/realtime/error)
             end)
    end

    if profile.scenario == "start-stop" do
      refute Enum.any?(events, &(&1.wire["method"] in @transcript_methods))
    end

    if profile.scenario == "item-audio" do
      refute Enum.any?(events, fn event ->
               String.starts_with?(event.wire["method"], "thread/realtime/") and
                 event.wire["method"] not in selected_methods(profile)
             end)
    end
  end

  defp assert_peer(profile, active) do
    state = read_peer(profile)
    assert state["paths"] === ["/v1/realtime?model=#{@model}"]
    assert [message] = state["messages"]
    assert message["type"] === "session.update"
    assert message["session"]["type"] === "realtime"
    assert message["session"]["instructions"] === @prompt
    assert message["session"]["output_modalities"] === ["text"]
    assert state["sent"] === [@peer_ack]
    assert state["requestCount"] === 1
    assert state["controls"] === []
    assert state["activeConnections"] === active
    assert state["responsesRequests"] === 0 and state["otherHttp"] === []
    assert state["errors"] === []

    assert is_integer(state["frameCount"]) and state["frameCount"] >= 2 and
             state["frameCount"] <= 32

    state
  end

  defp peer_ready?(profile) do
    state = read_peer(profile)

    length(state["paths"]) == 1 and length(state["messages"]) == 1 and
      state["sent"] == [@peer_ack]
  end

  defp await_peer_closed(profile, deadline) do
    assert now() < deadline, "Owned realtime connection close deadline"
    state = read_peer(profile)
    assert state["errors"] === []

    if state["activeConnections"] != 0 do
      Process.sleep(10)
      await_peer_closed(profile, deadline)
    end
  end

  defp read_peer(profile) do
    bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert byte_size(bytes) <= 2_097_152
    JSON.decode!(bytes)
  end

  defp start_peer(profile) do
    args = [@script, "--root", profile.root]

    args =
      if profile.scenario in ["transcript", "service-error", "item-audio"],
        do: args ++ ["--scenario", profile.scenario],
        else: args

    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: args,
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 4096
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = peer_startup(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    assert hash(File.read!(profile.python)) === hash(File.read!("/proc/#{native}/exe"))
    assert %URI{scheme: "http", host: "127.0.0.1", port: port} = URI.parse(startup["url"])
    assert is_integer(port) and port > 0 and port <= 65_535
    %{transport: transport, identity: identity, port: port}
  end

  defp selected_methods(%{scenario: "transcript"}), do: @selected ++ @transcript_methods
  defp selected_methods(%{scenario: "service-error"}), do: @selected ++ [@realtime_error]
  defp selected_methods(%{scenario: "item-audio"}), do: @selected ++ [@item_added, @audio_delta]
  defp selected_methods(_profile), do: @selected

  defp peer_startup(port, buffer, deadline) do
    assert now() < deadline, "Owned realtime peer startup deadline"

    receive do
      {^port, {:data, bytes}} -> peer_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned realtime peer startup exit #{status}")
    after
      10 -> peer_startup(port, buffer, deadline)
    end
  end

  defp peer_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned realtime peer startup output")
      [_partial] -> peer_startup(port, buffer, deadline)
    end
  end

  defp start_native(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: profile.capture,
                    executable: profile.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: profile.workspace,
                    inherit_env: [],
                    env: environment(profile),
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_native(pid, connection, identity) end)
    info = %{"name" => "owned_ordinary_realtime", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      profile,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, identity: identity}
  end

  defp environment(profile) do
    %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "SAMGITA_ORDINARY_REALTIME_FIXTURE_KEY" => "owned-inert-realtime-fixture",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }
  end

  defp frozen_files(profile),
    do:
      Map.new(
        ~w(codex/config.toml codex/models.json),
        &{&1, File.read!(Path.join(profile.root, &1))}
      )

  defp assert_inputs(ctx) do
    assert frozen_files(ctx.profile) === ctx.frozen
    assert File.ls!(ctx.profile.workspace) === []
    assert hash(File.read!(@script)) === @script_sha
  end

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.index < received.index
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile),
    do:
      Agent.get(profile.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] == method))

  defp schema(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)
      |> File.read!()
      |> JSON.decode!()

  defp assert_ready(profile, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === profile.generation
    assert Session.uncertain_operations(pid) === []
  end

  defp close_native(pid, connection, identity) do
    assert :ok = StdioSessionFixture.close(pid, connection)
    close_transport(connection, identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp assert_uuid(id), do: assert(is_binary(id) and Regex.match?(@uuid, id))
  defp request_id, do: "owned-realtime-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
