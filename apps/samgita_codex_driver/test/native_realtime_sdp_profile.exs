defmodule SamgitaCodexDriver.NativeRealtimeSdpProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_realtime_sdp
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_realtime_sdp_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @offer "v=owned-synthetic-offer\r\n"
  @answer "v=owned-synthetic-answer\r\n"
  @call_id "rtc_owned_synthetic"
  @text "Synthetic realtime client text"
  @transcript "Synthetic realtime peer transcript"
  @initial [%{"role" => "developer", "text" => "Synthetic realtime initial context"}]

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-realtime-sdp-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      scenario: tags.scenario,
      version: tags.realtime_version,
      kind: tags.transport_kind
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert events(ctx, "native_closed") != []
      end

      if File.exists?(Path.join(root, "journal.json")) and events(ctx, "fixture_error") != [] do
        IO.puts(:stderr, "Owned realtime failure evidence retained: #{root}")
      else
        File.rm_rf!(root)
      end
    end)

    ctx
  end

  for {scenario, version, kind} <- [
        {"websocket-v1", "v1", "websocket"},
        {"websocket-v3", "v3", "websocket"},
        {"webrtc-v1", "v1", "webrtc"},
        {"webrtc-v3", "v3", "webrtc"},
        {"existing-v1", "v1", "existing"},
        {"existing-v3", "v3", "existing"},
        {"webrtc-default", "v1", "webrtc"},
        {"existing-default", "v1", "existing"}
      ] do
    @tag scenario: scenario, realtime_version: version, transport_kind: kind
    test "stock native #{scenario} starts exchanges dependency events and stops", ctx do
      exercise(ctx)
    end
  end

  for {scenario, version} <- [
        {"websocket-v1-ingress", "v1"},
        {"websocket-v3-controls", "v3"},
        {"websocket-v3-utf8", "v3"}
      ] do
    @tag scenario: scenario, realtime_version: version, transport_kind: "websocket"
    test "stock native #{scenario} exchanges distinct audio startup or UTF8 controls", ctx do
      exercise_extension(ctx)
    end
  end

  defp exercise_extension(ctx) do
    pid = start(ctx)

    assert File.read!(Path.join(ctx.root, "codex/config.toml")) =~
             "experimental_realtime_ws_backend_prompt = \"\""

    thread =
      call(pid, "thread/start", %{"cwd" => Path.join(ctx.root, "workspace")})["thread"]["id"]

    assert is_binary(thread)
    assert call(pid, "thread/realtime/start", extension_start_params(ctx, thread)) == %{}
    started = collect(pid, &(notices(&1, "thread/realtime/started") != []))
    wait(fn -> length(events(ctx, "peer_ready")) == 1 end)

    expected =
      Enum.reduce(extension_steps(ctx, thread), [], fn {method, params, frames}, previous ->
        assert call(pid, method, params) == %{}
        expected = previous ++ frames
        wait(fn -> length(events(ctx, "extension_frame")) == length(expected) end)
        assert extension_frames(ctx) == expected
        expected
      end)

    exchanged =
      collect(pid, fn current ->
        notices(current, "thread/realtime/transcript/done") != [] and
          (ctx.version != "v1" or notices(current, "thread/realtime/outputAudio/delta") != [])
      end)

    wait(fn -> length(events(ctx, "peer_exchange")) == 1 end)
    assert call(pid, "thread/realtime/stop", %{"threadId" => thread}) == %{}
    closed = collect(pid, &(notices(&1, "thread/realtime/closed") != []), [], 500, true)
    assert extension_frames(ctx) == expected
    assert_extension_notices(ctx, thread, started ++ exchanged ++ closed)
    assert_dependency(ctx)
    finish(ctx, pid)
  end

  defp extension_start_params(ctx, thread) do
    params = %{
      "threadId" => thread,
      "transport" => %{"type" => "websocket"},
      "version" => ctx.version,
      "outputModality" => "audio",
      "includeStartupContext" => false,
      "prompt" => "Owned realtime controls prompt",
      "voice" => "cove",
      "realtimeSessionId" => extension_session_id(ctx)
    }

    if ctx.scenario == "websocket-v3-controls" do
      Map.merge(params, %{
        "delegationAckFiller" => false,
        "initialItems" => [
          %{"role" => "user", "text" => "Owned initial user"},
          %{"role" => "assistant", "text" => "Owned initial assistant"}
        ]
      })
    else
      params
    end
  end

  defp extension_session_id(ctx) do
    "websocket-" <> suffix = ctx.scenario
    "owned-" <> suffix
  end

  defp extension_steps(%{scenario: "websocket-v1-ingress"}, thread) do
    audio =
      {"thread/realtime/appendAudio",
       %{
         "threadId" => thread,
         "audio" => %{
           "data" => "AQACAA==",
           "sampleRate" => 24_000,
           "numChannels" => 1,
           "samplesPerChannel" => 2,
           "itemId" => "owned-v1-input"
         }
       }, [%{"type" => "input_audio_buffer.append", "audio" => "AQACAA=="}]}

    text =
      for {role, type, value} <- [
            {"assistant", "output_text", "Owned V1 assistant text"},
            {"developer", "input_text", "Owned V1 developer text"}
          ] do
        {"thread/realtime/appendText", %{"threadId" => thread, "role" => role, "text" => value},
         [
           %{
             "type" => "conversation.item.create",
             "item" => %{
               "type" => "message",
               "role" => role,
               "content" => [%{"type" => type, "text" => value}]
             }
           }
         ]}
      end

    [audio | text]
  end

  defp extension_steps(%{scenario: "websocket-v3-controls"}, thread) do
    [
      {"thread/realtime/appendAudio",
       %{
         "threadId" => thread,
         "audio" => %{
           "data" => "BQAGAA==",
           "sampleRate" => 24_000,
           "numChannels" => 1,
           "samplesPerChannel" => 2,
           "itemId" => "owned-v3-input"
         }
       }, [%{"type" => "input_audio.append", "audio" => "BQAGAA=="}]}
    ]
  end

  defp extension_steps(%{scenario: "websocket-v3-utf8"}, thread) do
    text = String.duplicate("a", 499) <> "λ" <> String.duplicate("b", 499)
    chunks = [String.duplicate("a", 499), "λ" <> String.duplicate("b", 498), "b"]
    assert byte_size(text) == 1_000
    assert Enum.map(chunks, &byte_size/1) == [499, 500, 1]
    assert Enum.join(chunks) == text

    frames =
      for chunk <- chunks do
        %{
          "type" => "session.context.append",
          "content" => [%{"type" => "input_text", "text" => chunk}]
        }
      end

    [
      {"thread/realtime/appendText",
       %{"threadId" => thread, "role" => "assistant", "text" => text}, frames}
    ]
  end

  defp extension_frames(ctx) do
    events(ctx, "native_frame")
    |> Enum.map(& &1["message"])
    |> Enum.reject(&(&1["type"] in ["session.update", "session.close"]))
  end

  defp assert_extension_notices(ctx, thread, received) do
    assert notices(received, "thread/realtime/started") == [
             %{
               "threadId" => thread,
               "realtimeSessionId" => extension_session_id(ctx),
               "version" => ctx.version
             }
           ]

    assert notices(received, "thread/realtime/sdp") == []

    assert notices(received, "thread/realtime/closed") == [
             %{"threadId" => thread, "reason" => "requested"}
           ]

    {role, transcript} =
      case ctx.scenario do
        "websocket-v1-ingress" -> {"assistant", "Owned V1 assistant reply"}
        "websocket-v3-controls" -> {"user", "Owned V3 ingress transcript"}
        "websocket-v3-utf8" -> {"assistant", "Owned V3 assistant reply λ"}
      end

    assert notices(received, "thread/realtime/transcript/delta") == [
             %{"threadId" => thread, "role" => role, "delta" => transcript}
           ]

    assert notices(received, "thread/realtime/transcript/done") == [
             %{"threadId" => thread, "role" => role, "text" => transcript}
           ]

    expected_audio =
      if ctx.version == "v1" do
        [
          %{
            "threadId" => thread,
            "audio" => %{
              "data" => "AwAEAA==",
              "sampleRate" => 24_000,
              "numChannels" => 1,
              "samplesPerChannel" => 2,
              "itemId" => nil
            }
          }
        ]
      else
        []
      end

    assert notices(received, "thread/realtime/outputAudio/delta") == expected_audio
  end

  defp exercise(ctx) do
    pid = start(ctx)

    thread =
      call(pid, "thread/start", %{"cwd" => Path.join(ctx.root, "workspace")})["thread"]["id"]

    assert is_binary(thread)
    assert call(pid, "thread/realtime/start", start_params(ctx, thread)) == %{}

    received =
      collect(pid, fn received ->
        notices(received, "thread/realtime/started") != [] and
          (ctx.kind != "webrtc" or notices(received, "thread/realtime/sdp") != [])
      end)

    assert notices(received, "thread/realtime/started") == [
             %{
               "threadId" => thread,
               "realtimeSessionId" => "owned-realtime-" <> ctx.scenario,
               "version" => ctx.version
             }
           ]

    if ctx.kind == "webrtc" do
      assert notices(received, "thread/realtime/sdp") == [
               %{"threadId" => thread, "sdp" => @answer}
             ]

      methods = Enum.map(received, & &1.wire["method"])

      assert Enum.find_index(methods, &(&1 == "thread/realtime/started")) <
               Enum.find_index(methods, &(&1 == "thread/realtime/sdp"))
    else
      assert notices(received, "thread/realtime/sdp") == []
    end

    wait(fn -> length(events(ctx, "peer_ready")) == 1 end)

    assert call(pid, "thread/realtime/appendText", %{
             "threadId" => thread,
             "role" => "user",
             "text" => @text
           }) == %{}

    exchanged =
      collect(pid, fn current ->
        notices(current, "thread/realtime/transcript/done") != [] and
          notices(current, "thread/realtime/outputAudio/delta") != []
      end)

    assert notices(exchanged, "thread/realtime/transcript/delta") == [
             %{
               "threadId" => thread,
               "role" => "user",
               "delta" => @transcript
             }
           ]

    assert notices(exchanged, "thread/realtime/transcript/done") == [
             %{
               "threadId" => thread,
               "role" => "user",
               "text" => @transcript
             }
           ]

    assert notices(exchanged, "thread/realtime/outputAudio/delta") == [
             %{
               "threadId" => thread,
               "audio" => %{
                 "data" => "AAAAAA==",
                 "sampleRate" => 24_000,
                 "numChannels" => 1,
                 "samplesPerChannel" => nil,
                 "itemId" => nil
               }
             }
           ]

    assert call(pid, "thread/realtime/stop", %{"threadId" => thread}) == %{}
    closed = collect(pid, &(notices(&1, "thread/realtime/closed") != []), [], 500, true)

    assert notices(closed, "thread/realtime/closed") == [
             %{"threadId" => thread, "reason" => "requested"}
           ]

    assert notices(received ++ exchanged ++ closed, "thread/realtime/sdp") ==
             if(ctx.kind == "webrtc", do: [%{"threadId" => thread, "sdp" => @answer}], else: [])

    assert_dependency(ctx)
    finish(ctx, pid)
  end

  defp assert_dependency(ctx) do
    assert length(events(ctx, "sideband_joined")) == 1

    assert [%{"path" => path, "authorization_verified" => true, "host_verified" => true}] =
             events(ctx, "sideband_joined") |> Enum.map(&Map.delete(&1, "event"))

    assert path == expected_ws_path(ctx)
    calls = events(ctx, "call_created")
    assert length(calls) == if(ctx.kind == "webrtc", do: 1, else: 0)

    if ctx.kind == "webrtc" do
      assert [
               %{
                 "offer" => @offer,
                 "authorization_verified" => true,
                 "host_verified" => true,
                 "path" => call_path,
                 "session" => session
               }
             ] = Enum.map(calls, &Map.delete(&1, "event"))

      assert call_path ==
               if(ctx.version == "v3",
                 do: "/v1/live",
                 else: "/v1/realtime/calls?intent=quicksilver&architecture=avas"
               )

      assert session["model"] == "owned-synthetic-realtime"
      refute Map.has_key?(session, "id")
      assert session["instructions"] == "Synthetic SDP prompt"
      assert session["audio"]["output"]["voice"] == "cove"
    end

    updates =
      events(ctx, "native_frame") |> Enum.filter(&(&1["message"]["type"] == "session.update"))

    assert length(updates) ==
             if(
               ctx.kind == "websocket" or
                 (ctx.kind == "webrtc" and ctx.version == "v1"),
               do: 1,
               else: 0
             )

    assert length(events(ctx, "peer_exchange")) == 1
  end

  defp start_params(ctx, thread) do
    transport =
      case ctx.kind do
        "websocket" -> %{"type" => "websocket"}
        "webrtc" -> %{"type" => "webrtc", "sdp" => @offer}
        "existing" -> %{"type" => "existingCall", "callId" => @call_id}
      end

    params = %{
      "threadId" => thread,
      "transport" => transport,
      "outputModality" => "audio",
      "includeStartupContext" => false,
      "realtimeSessionId" => "owned-realtime-" <> ctx.scenario
    }

    params =
      if String.ends_with?(ctx.scenario, "-default"),
        do: params,
        else: Map.put(params, "version", ctx.version)

    params = if ctx.kind == "existing", do: params, else: Map.put(params, "voice", "cove")

    if ctx.kind != "existing" and ctx.version == "v3",
      do: Map.put(params, "initialItems", @initial),
      else: params
  end

  defp expected_ws_path(ctx) do
    case {ctx.kind, ctx.version} do
      {"websocket", "v1"} -> "/v1/realtime?intent=quicksilver&model=owned-synthetic-realtime"
      {"websocket", "v3"} -> "/v1/live?model=owned-synthetic-realtime"
      {_, "v1"} -> "/v1/realtime?intent=quicksilver&call_id=" <> @call_id
      {_, "v3"} -> "/v1/live/" <> @call_id
    end
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               "-I",
               @script,
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--scenario",
               ctx.scenario
             ],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_realtime_sdp", "version" => "1"}, %{
               "experimentalApi" => true
             })

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} =
             Session.request_native(pid, %{
               "id" => "owned-realtime-#{System.unique_integer([:positive])}",
               "method" => method,
               "params" => params
             })

    result
  end

  defp collect(pid, predicate, received \\ [], remaining \\ 500, allow_closed \\ false)

  defp collect(_pid, _predicate, _received, 0, _allow_closed),
    do: flunk("Owned realtime notification deadline")

  defp collect(pid, predicate, received, remaining, allow_closed) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current

    for event <- current do
      refute event.kind == :server_request

      refute event.wire["method"] in ["turn/started", "thread/realtime/error", "error"],
             "Unexpected owned realtime event: #{inspect(event.wire)}"

      unless allow_closed, do: refute(event.wire["method"] == "thread/realtime/closed")
    end

    if predicate.(received),
      do: received,
      else:
        (
          Process.sleep(10)
          collect(pid, predicate, received, remaining - 1, allow_closed)
        )
  end

  defp finish(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert :ok = Session.close(pid)
    wait(fn -> events(ctx, "native_closed") != [] end)
    assert events(ctx, "fixture_error") == []
    # Stopping may drop the socket without a close frame; both paths must finish.
    assert length(events(ctx, "ws_worker_closed")) == 1
  end

  defp notices(received, method),
    do: for(event <- received, event.wire["method"] == method, do: event.wire["params"])

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned realtime observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.(),
      do: value,
      else:
        (
          Process.sleep(10)
          wait(predicate, remaining - 1)
        )
  end
end
