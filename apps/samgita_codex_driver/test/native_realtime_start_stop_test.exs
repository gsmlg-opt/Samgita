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
  @script_sha "738e607671c129efc35e26a2d5304eef7cd9d9d0d60df74d23e8d19c91941315"
  @session "owned-v432-realtime-session"
  @model "owned-v432-realtime-model"
  @prompt "Owned local realtime start"
  @item_started "thread/realtime/item/started"
  @item_completed "thread/realtime/item/completed"
  @started "thread/realtime/started"
  @closed "thread/realtime/closed"
  @selected [@item_started, @item_completed, @started, @closed]
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

  setup do
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
      capture: capture
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
    selected = Enum.filter(events, &(&1.wire["method"] in @selected))
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
    originals =
      for frame <- capture(profile),
          frame.direction == :in,
          frame.wire["method"] in @selected,
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

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ~w(error warning turn/started turn/completed item/started item/completed thread/realtime/error thread/realtime/item/transcriptDelta)
           end)
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
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [@script, "--root", profile.root],
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
    %{transport: transport, identity: identity}
  end

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
