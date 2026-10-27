defmodule SamgitaCodexDriver.NativeMcpEventEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/mcp_event_stream_fixture.py", __DIR__)
  @stream_method "mcpServer/event/stream/notification"
  @subscription "owned-native-envelope-subscription"
  @arguments %{"project" => "owned", "nested" => [1, nil, "λ🙂"]}
  @data %{"value" => "λ🙂", "nested" => [1, nil, false], "marker" => "OWNED_NATIVE_EVENT"}

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
      wire = JSON.decode!(encoded)

      response? = Map.has_key?(wire, "id") and not Map.has_key?(wire, "method")

      if response? or wire["method"] === "mcpServer/event/stream/notification" do
        case record(capture, :in, encoded) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      else
        {:cont, :ok}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Only this test's ordinary RPC envelopes and original MCP stream notices
    # enter the ledger. No backend headers or startup account state are captured.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction === :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded}

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
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, child))
    input = Path.join(root, "workspace/INPUT.md")
    File.write!(input, "Owned MCP subscription input stays inert.\n")

    assert {:ok, transport} =
             Stdio.open(
               executable: python,
               args: [@script, "--root", root],
               cwd: Path.join(root, "workspace"),
               inherit_env: [],
               env: %{
                 "CODEX_HOME" => Path.join(root, "codex"),
                 "PATH" => "/usr/bin:/bin",
                 "PYTHONDONTWRITEBYTECODE" => "1"
               },
               max_message_bytes: 65_536
             )

    identity = :atomics.new(1, [])
    peer = %{transport: transport, identity: identity}
    on_exit(fn -> close_peer(peer) end)
    startup = peer_line(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    base_url = Map.fetch!(startup, "baseUrl")
    assert is_binary(base_url) and String.starts_with?(base_url, "http://127.0.0.1:")

    frozen =
      Map.new(
        [
          @script,
          __ENV__.file,
          input,
          Path.join(root, "codex/config.toml"),
          Path.join(root, "codex/models.json")
        ],
        &{&1, snapshot(&1)}
      )

    %{root: root, binary: Path.expand(binary), peer: peer, base_url: base_url, frozen: frozen}
  end

  for {label, stop_id} <- [
        {"negative integer", -504_950},
        {"positive integer", 504_950},
        {"Unicode string", "owned-stop-λ🙂"}
      ] do
    @tag stop_id: stop_id
    test "native MCP event envelopes retain #{label} stop ID through actual cancellation", ctx do
      exercise_stream(ctx)
    end
  end

  defp exercise_stream(ctx) do
    session = start_native(ctx)
    assert stream_notices(drain(session.pid)) === []

    {created, _response, _request} =
      call(session, "thread/start", %{
        "cwd" => Path.join(ctx.root, "workspace"),
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    thread_id = Map.fetch!(Map.fetch!(created, "thread"), "id")
    assert is_binary(thread_id) and byte_size(thread_id) > 0

    {named, _response, _request} =
      call(session, "thread/name/set", %{
        "threadId" => thread_id,
        "name" => "Owned empty MCP event thread λ"
      })

    assert named === %{}

    baseline = read_thread(session, thread_id)
    history = %{path: Map.fetch!(baseline, "path"), bytes: nil}
    assert is_binary(history.path) and String.starts_with?(history.path, ctx.root <> "/")
    history = %{history | bytes: snapshot(history.path)}
    assert Map.fetch!(baseline, "turns") === []
    assert stream_notices(drain(session.pid)) === []
    params = stream_params(thread_id)

    request = %{
      "id" => request_id(),
      "method" => "mcpServer/event/stream/start",
      "params" => params
    }

    lower = System.system_time(:millisecond)

    task =
      Task.async(fn -> Session.request_native(session.pid, request, timeout_ms: 5_000) end)

    opened = wait_stream(ctx.peer, &is_map(&1["stream"]), now() + 5_000)
    internal_id = Map.fetch!(opened["stream"], "requestId")
    refute internal_id === @subscription
    actual_params = Map.fetch!(opened["stream"], "params")
    assert Map.take(actual_params, ~w(name arguments)) === Map.take(params, ~w(name arguments))
    assert Map.drop(actual_params["_meta"], ["progressToken"]) === %{"source" => "owned-client"}
    assert Map.has_key?(actual_params["_meta"], "progressToken")
    assert Session.status(session.pid).pending === 1

    refute Enum.any?(capture(session), fn record ->
             record.direction === :in and record.wire["id"] === request["id"]
           end)

    assert control(ctx.peer, "active") === %{"queued" => "active"}
    active_events = await_notice(session.pid, [], now() + 5_000)
    [active] = stream_notices(active_events)

    assert {:ok, %{"id" => id, "result" => %{}} = response} = Task.await(task, 5_000)
    assert id === request["id"]
    assert response["result"] === %{}
    assert_exchange(session, request, response)
    assert_notice(session, active, internal_id, "active", lower, System.system_time(:millisecond))
    assert_activation_interval(session, request, active, response)

    lower = System.system_time(:millisecond)
    assert control(ctx.peer, "event") === %{"queued" => "event"}
    event_events = await_notice(session.pid, [], now() + 5_000)
    [event] = stream_notices(event_events)
    assert_notice(session, event, internal_id, "event", lower, System.system_time(:millisecond))
    sent = wait_stream(ctx.peer, &(length(&1["stream"]["sent"]) === 2), now() + 5_000)
    assert_peer_notifications(sent, internal_id)

    {stopped_result, _response, stop_request} =
      call(
        session,
        "mcpServer/event/stream/stop",
        %{"subscriptionId" => @subscription},
        ctx.stop_id
      )

    assert stopped_result === %{}
    assert stop_request["id"] === ctx.stop_id
    assert :ok = Schema.validate(request_schema(), stop_request, max_depth: 32)

    stopped =
      wait_stream(
        ctx.peer,
        &(&1["stream"]["peerClosed"] === true and &1["stream"]["finished"] === true),
        now() + 5_000
      )

    assert_peer_notifications(stopped, internal_id)
    assert read_thread(session, thread_id) === baseline
    assert snapshot(history.path) === history.bytes
    assert_idle(session, thread_id)
    trailing = drain(session.pid)
    assert stream_notices(trailing) === []
    close_native(session)
    selected = stream_notices(active_events ++ event_events ++ trailing)

    assert Enum.map(selected, & &1.wire["params"]["notification"]["method"]) ===
             ~w(notifications/events/active notifications/events/event)

    sequences = Enum.map(selected, & &1.sequence)
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences === Enum.sort(Enum.uniq(sequences))
    assert_originals(session, selected)
    assert_inventory(session)
    assert_frozen(ctx, history)
    final = control(ctx.peer, "close")
    assert final["listenerClosed"] === true and final["threadAlive"] === false
    assert_peer_notifications(final, internal_id)
    assert final["stream"]["peerClosed"] === true and final["stream"]["finished"] === true
    close_peer(ctx.peer)
    assert_frozen(ctx, history)
  end

  defp start_native(ctx) do
    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: make_ref())

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: Path.join(ctx.root, "workspace"),
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => Path.join(ctx.root, "home"),
                      "CODEX_HOME" => Path.join(ctx.root, "codex"),
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "CODEX_REFRESH_TOKEN_URL_OVERRIDE" => ctx.base_url <> "/unused-refresh",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    session = %{pid: pid, connection: connection, identity: identity, capture: capture}
    on_exit(fn -> close_native(session) end)
    id = request_id()
    info = %{"name" => "owned_mcp_event_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    {diagnostics, _response, _request} = call(session, "server/diagnostics", %{})
    native = diagnostics["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    Map.merge(session, %{native: native, generation: Session.status(pid).generation})
  end

  defp stream_params(thread_id),
    do: %{
      "threadId" => thread_id,
      "server" => "codex_apps",
      "subscriptionId" => @subscription,
      "name" => "owned.updated",
      "arguments" => @arguments,
      "_meta" => %{"source" => "owned-client"}
    }

  defp call(session, method, params, id \\ nil) do
    wire = %{"id" => id || request_id(), "method" => method, "params" => params}

    assert {:ok, %{"result" => result} = response} =
             Session.request_native(session.pid, wire, timeout_ms: 5_000)

    assert_exchange(session, wire, response)
    {result, response, wire}
  end

  defp assert_exchange(session, wire, response) do
    assert response["id"] === wire["id"]
    assert [sent, received] = Enum.filter(capture(session), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp read_thread(session, thread_id) do
    {result, _response, _request} =
      call(session, "thread/read", %{"threadId" => thread_id, "includeTurns" => false})

    thread = Map.fetch!(result, "thread")
    assert Map.fetch!(thread, "turns") === []
    Map.take(thread, ~w(id cwd path turns ephemeral name))
  end

  defp await_notice(pid, events, deadline) do
    combined = events ++ drain(pid)
    assert length(combined) <= 128

    if stream_notices(combined) === [] do
      assert now() < deadline, "Native MCP stream notification deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native MCP stream event gap")
      after
        10 -> :ok
      end

      await_notice(pid, combined, deadline)
    else
      combined
    end
  end

  defp assert_notice(session, event, internal_id, kind, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === session.generation

    assert event.wire === %{
             "method" => @stream_method,
             "params" => %{
               "subscriptionId" => @subscription,
               "notification" => %{
                 "method" => "notifications/events/" <> kind,
                 "params" => notification_params(internal_id, kind)
               }
             },
             "emittedAtMs" => emitted
           }

    assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
  end

  defp notification_params(internal_id, kind) do
    base = %{
      "_meta" => %{
        "io.modelcontextprotocol/subscriptionId" => internal_id,
        "provider" => "owned-events"
      }
    }

    case kind do
      "active" -> Map.put(base, "status", "active")
      "event" -> Map.merge(base, %{"name" => "owned.updated", "data" => @data})
    end
  end

  defp assert_activation_interval(session, request, event, response) do
    records = capture(session)
    assert [sent] = positions(records, :out, request)
    assert [notice] = positions(records, :in, event.wire)
    assert [received] = positions(records, :in, response)
    assert sent < notice and notice < received
  end

  defp positions(records, direction, wire),
    do:
      for(
        {record, index} <- Enum.with_index(records),
        record.direction === direction and record.wire === wire,
        do: index
      )

  defp assert_peer_notifications(state, internal_id) do
    assert state["errors"] === []
    assert Enum.count(state["requests"], &(&1["method"] === "events/stream")) === 1

    expected =
      for kind <- ~w(active event) do
        %{
          "jsonrpc" => "2.0",
          "method" => "notifications/events/" <> kind,
          "params" => notification_params(internal_id, kind)
        }
      end

    assert state["stream"]["sent"] === expected
  end

  defp assert_originals(session, selected) do
    originals =
      Enum.filter(
        capture(session),
        &(&1.direction === :in and &1.wire["method"] === @stream_method)
      )

    assert length(originals) === 2
    assert Enum.map(originals, & &1.wire) === Enum.map(selected, & &1.wire)

    for {original, event} <- Enum.zip(originals, selected),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp assert_inventory(session) do
    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/start thread/name/set thread/read mcpServer/event/stream/start mcpServer/event/stream/stop thread/read thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 9
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === 9

    for request <- requests do
      assert [_sent, received] = Enum.filter(records, &(&1.wire["id"] === request.wire["id"]))
      assert_exchange(session, request.wire, received.wire)
    end
  end

  defp assert_idle(session, thread_id) do
    assert {%{"data" => [^thread_id], "nextCursor" => nil}, _response, _request} =
             call(session, "thread/loaded/list", %{})

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    assert Session.uncertain_operations(session.pid) === []
  end

  defp stream_notices(events), do: Enum.filter(events, &(&1.wire["method"] === @stream_method))

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152
    events
  end

  defp wait_stream(peer, predicate, deadline) do
    state = control(peer, "state")

    if predicate.(state) do
      state
    else
      assert now() < deadline, "Owned MCP subscription state deadline"

      receive do
      after
        10 -> :ok
      end

      wait_stream(peer, predicate, deadline)
    end
  end

  defp control(peer, operation) do
    id = request_id()
    wire = %{"id" => id, "op" => operation}
    assert {:ok, _transport} = Stdio.send(peer.transport, JSON.encode!(wire))

    assert %{"id" => ^id, "result" => result} =
             peer_line(peer.transport.port, <<>>, now() + 5_000)

    result
  end

  defp peer_line(port, buffer, deadline) do
    assert now() < deadline, "Owned MCP peer control deadline"
    assert byte_size(buffer) <= 65_536

    receive do
      {^port, {:data, bytes}} ->
        combined = buffer <> bytes
        assert byte_size(combined) <= 65_536

        case String.split(combined, "\n", parts: 2) do
          [line, ""] -> JSON.decode!(line)
          [_line, _extra] -> flunk("Unexpected extra owned MCP peer control output")
          [_partial] -> peer_line(port, combined, deadline)
        end

      {^port, {:exit_status, status}} ->
        flunk("Owned MCP peer exited before control response: #{status}")
    after
      10 -> peer_line(port, buffer, deadline)
    end
  end

  defp assert_frozen(ctx, history) do
    for {path, bytes} <- ctx.frozen, do: assert(snapshot(path) === bytes)
    assert snapshot(history.path) === history.bytes
    assert File.ls!(Path.join(ctx.root, "workspace")) === ["INPUT.md"]
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    File.read!(path)
  end

  defp capture(session),
    do:
      Agent.get(session.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp request_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ClientRequest.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_native(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp close_peer(peer) do
    monitor = Process.monitor(peer.transport.owner.pid)
    assert :ok = Stdio.close(peer.transport)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(peer.transport.owner.completion, 1) === 1
    assert Port.info(peer.transport.port) === nil
    native = :atomics.get(peer.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id,
    do: "owned-mcp-event-envelope-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
