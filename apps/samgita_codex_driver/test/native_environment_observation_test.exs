defmodule SamgitaCodexDriver.NativeEnvironmentObservationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @status_schema_sha "43798149b75ee5c6fb8e3113019f9b0db9860102ec87be4f17fb84d8f10068b6"
  @environment "owned-v444-held-environment"
  @startup_methods ["initialize", "initialized", "server/diagnostics"]
  @status_method "environment/status"
  @status_params %{"environmentId" => @environment}
  @pending %{"status" => "pending"}

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
        {:ok, next} -> record_sent(next, encoded)
        other -> other
      end
    end

    defp record_sent(state, encoded) do
      case record(state.capture, :out, encoded) do
        :ok -> {:ok, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} -> record_received(next, events)
        other -> other
      end
    end

    defp record_received(state, events) do
      case Enum.reduce_while(events, :ok, &record_event(&1, &2, state.capture)) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
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

  # One supervised process owns every socket. It never sends any network data.
  # Poll timeouts only service observation/control; none establishes success.
  defmodule HoldPeer do
    @moduledoc false
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    def child_spec(opts),
      do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

    def info(pid), do: GenServer.call(pid, :info, 1000)
    def journal(pid), do: GenServer.call(pid, :journal, 1000)
    def close(pid), do: GenServer.call(pid, :close, 1000)

    @impl true
    def init(opts) do
      Process.flag(:trap_exit, true)

      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

      {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)

      state = %{
        listener: listener,
        observer: Keyword.fetch!(opts, :observer),
        token: Keyword.fetch!(opts, :token),
        destination: "ws://127.0.0.1:#{port}/held-v444",
        deadline: now() + 15_000,
        socket: nil,
        sockets: [listener],
        buffer: <<>>,
        received: 0,
        held: false,
        journal: []
      }

      send(self(), :poll)
      {:ok, state}
    end

    @impl true
    def handle_call(:info, _from, state) do
      {:reply, %{destination: state.destination, listener: state.listener}, state}
    end

    def handle_call(:journal, _from, state) do
      state = barrier(state)
      {:reply, snapshot(state), state}
    end

    def handle_call(:close, _from, state) do
      state = barrier(state)
      {:stop, :normal, snapshot(state), state}
    end

    @impl true
    def handle_info(:poll, state) do
      if now() >= state.deadline do
        state = record(state, %{kind: :failure, reason: :peer_deadline})
        {:stop, :normal, state}
      else
        state = if state.socket, do: receive_bytes(state, 20), else: accept(state, 20)
        send(self(), :poll)
        {:noreply, state}
      end
    end

    @impl true
    def terminate(_reason, state) do
      Enum.each(state.sockets, &:gen_tcp.close/1)
      :ok
    end

    # Check for a currently queued connection before acknowledging a journal barrier.
    # At most one is legitimate; extras are closed and recorded as failures.
    # The listener stays active until the explicit final close.
    defp barrier(state) do
      state = if state.socket, do: receive_bytes(state, 0), else: state
      accept(state, 0)
    end

    defp accept(state, timeout) do
      case :gen_tcp.accept(state.listener, timeout) do
        {:ok, socket} ->
          already_accepted = Enum.any?(state.journal, &(&1.kind == :accepted))
          state = %{state | sockets: [socket | state.sockets]}

          if already_accepted do
            :gen_tcp.close(socket)
            record(state, %{kind: :failure, reason: :extra_connection})
          else
            state = %{state | socket: socket}
            record(state, %{kind: :accepted, at: now()})
          end

        {:error, :timeout} ->
          state

        {:error, reason} ->
          record(state, %{kind: :failure, reason: {:accept, reason}})
      end
    end

    defp receive_bytes(state, timeout) do
      case :gen_tcp.recv(state.socket, 0, timeout) do
        {:ok, bytes} ->
          hold_bytes(state, bytes)

        {:error, :timeout} ->
          state

        {:error, :closed} ->
          :gen_tcp.close(state.socket)
          state = %{state | socket: nil, buffer: <<>>}
          record(state, %{kind: :eof, at: now()})

        {:error, reason} ->
          record(state, %{kind: :failure, reason: {:recv, reason}})
      end
    end

    defp hold_bytes(state, bytes) do
      count = state.received + byte_size(bytes)

      cond do
        state.held ->
          record(state, %{kind: :failure, reason: :unexpected_held_data})

        count > 16_384 ->
          record(state, %{kind: :failure, reason: :header_overflow})

        true ->
          buffer = state.buffer <> bytes
          state = %{state | buffer: buffer, received: count}

          if :binary.match(buffer, "\r\n\r\n") == :nomatch do
            state
          else
            state = %{state | buffer: <<>>, held: true}
            record(state, %{kind: :held, at: now(), bytes: count})
          end
      end
    end

    defp record(state, entry) do
      if length(state.journal) < 8 do
        send(state.observer, {:hold_peer, state.token, entry})
        %{state | journal: state.journal ++ [entry]}
      else
        exit(:peer_journal_overflow)
      end
    end

    defp snapshot(state), do: %{events: state.journal, sockets: state.sockets}
    defp now, do: System.monotonic_time(:millisecond)
  end

  setup tags do
    assert hash(File.read!(@script)) === @script_sha
    assert hash(schema_bytes("v2/EnvironmentStatusResponse.json")) === @status_schema_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) === @binary_sha
    File.mkdir!(Path.join(ctx.root, "tmp"))
    TurnFixture.configure_model(ctx, %{})

    inputs =
      Map.new(~w(config.toml turn-models.json), fn name ->
        path = Path.join(ctx.fixture.codex_home, name)
        {path, File.read!(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "native held startup reports pending then the same cached timeout without reconnect",
       ctx do
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    session = start_native(ctx, capture)
    token = make_ref()
    peer = start_supervised!({HoldPeer, observer: self(), token: token})
    info = HoldPeer.info(peer)
    on_exit(fn -> cleanup_peer(peer, info.listener) end)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_inputs(ctx)

    added =
      exchange(session, "environment/add", %{
        "environmentId" => @environment,
        "execServerUrl" => info.destination,
        "connectTimeoutMs" => 5000
      })

    assert added.result === %{}
    validate_result(added, "v2/EnvironmentAddResponse.json")
    assert_receive {:hold_peer, ^token, %{kind: :accepted, at: accepted_at}}, 1000
    assert_receive {:hold_peer, ^token, %{kind: :held, at: held_at, bytes: bytes}}, 1000
    assert is_integer(bytes) and bytes > 0 and bytes <= 16_384
    assert held_at >= accepted_at

    for _ <- 1..2 do
      pending = exchange(session, @status_method, @status_params)
      assert pending.result === @pending
      validate_result(pending, "v2/EnvironmentStatusResponse.json")
    end

    assert %{events: [%{kind: :accepted}, %{kind: :held}]} = HoldPeer.journal(peer)
    eof_wait = max(1, accepted_at + 6500 - now())
    assert_receive {:hold_peer, ^token, %{kind: :eof, at: eof_at}}, eof_wait
    assert eof_at > held_at
    assert eof_at <= accepted_at + 6500

    expected = %{
      "status" => "disconnected",
      "error" =>
        "exec-server connection attempt failed: timed out connecting to exec-server websocket " <>
          "`#{info.destination}` after 5s"
    }

    observations = await_disconnected(session, expected, now() + 5000, 16, [])
    assert length(observations) in 1..16
    assert List.last(observations).result === expected

    for _ <- 1..3 do
      repeated = exchange(session, @status_method, @status_params)
      assert repeated.result === expected
      validate_result(repeated, "v2/EnvironmentStatusResponse.json")
    end

    loaded = exchange(session, "thread/loaded/list", %{})
    assert loaded.result === %{"data" => [], "nextCursor" => nil}
    validate_result(loaded, "v2/ThreadLoadedListResponse.json")
    assert_ready(session)
    assert {:ok, notices} = Session.drain(session.pid, 128)
    assert length(notices) <= 128

    assert Enum.all?(
             notices,
             &(&1.kind === :notification and &1.generation === session.generation)
           )

    assert_ready(session)

    original_notices =
      Enum.filter(capture(session), &(&1.direction === :in and not Map.has_key?(&1.wire, "id")))

    assert Enum.map(original_notices, & &1.wire) === Enum.map(notices, & &1.wire)
    for original <- original_notices, do: assert_original(original, original.wire)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_inputs(ctx)

    methods =
      @startup_methods ++
        ["environment/add"] ++
        List.duplicate(@status_method, 2 + length(observations) + 3) ++ ["thread/loaded/list"]

    assert_inventory(session, methods)
    prefix = capture(session)

    # Positive EOF plus a final live-listener barrier bounds the observation.
    # Source FailFast semantics separately establish that these reads cannot reconnect.
    journal = HoldPeer.journal(peer)

    assert journal.events === [
             %{kind: :accepted, at: accepted_at},
             %{kind: :held, at: held_at, bytes: bytes},
             %{kind: :eof, at: eof_at}
           ]

    monitor = Process.monitor(peer)
    assert HoldPeer.close(peer) === journal
    assert_receive {:DOWN, ^monitor, :process, ^peer, :normal}, 1000
    for socket <- journal.sockets, do: assert(Port.info(socket) === nil)
    close_native(session)
    close_provider(ctx.fixture)
    assert capture(session) === prefix
    assert ModelFixture.requests(ctx.fixture) === []
    assert_inputs(ctx)
  end

  defp await_disconnected(session, expected, deadline, remaining, seen) do
    assert remaining > 0, "Native startup error was not published within 16 status observations"
    left = deadline - now()

    assert left > 0,
           "Native startup error was not published within the 5000 ms observation deadline"

    observed = exchange(session, @status_method, @status_params, min(5000, left))
    assert now() <= deadline, "Native status response exceeded the observation deadline"
    validate_result(observed, "v2/EnvironmentStatusResponse.json")
    seen = seen ++ [observed]

    cond do
      observed.result === expected ->
        seen

      observed.result === @pending ->
        # Scheduling cadence only: success requires a later exact native result.
        receive do
          {:hold_peer, _token, %{kind: :failure} = failure} -> flunk(inspect(failure))
        after
          20 -> :ok
        end

        await_disconnected(session, expected, deadline, remaining - 1, seen)

      true ->
        flunk("Unexpected native environment status: #{inspect(observed.result)}")
    end
  end

  defp cleanup_peer(peer, listener) do
    monitor = Process.monitor(peer)

    snapshot =
      try do
        if Process.alive?(peer), do: HoldPeer.close(peer)
      catch
        :exit, {reason, {GenServer, :call, [^peer, :close, 1000]}}
        when reason in [:noproc, :normal, :shutdown] ->
          nil
      after
        assert_receive {:DOWN, ^monitor, :process, ^peer, _reason}, 1000
        assert Port.info(listener) === nil
      end

    if snapshot do
      for socket <- snapshot.sockets, do: assert(Port.info(socket) === nil)
    end
  end

  defp start_native(ctx, capture) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: Path.expand(ctx.binary),
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: environment(ctx),
                    max_message_bytes: 65_536
                  ]}
             )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    session = %{pid: pid, capture: capture, connection: connection, identity: identity}
    on_exit(fn -> close_native(session) end)
    info = %{"name" => "owned_environment_observation", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5000)

    assert_exchange(
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = exchange(session, "server/diagnostics", %{}).result["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    status = Session.status(pid)

    Map.merge(session, %{
      native: native,
      generation: status.generation,
      instance_id: status.instance_id
    })
  end

  defp environment(ctx) do
    %{
      "HOME" => ctx.fixture.home,
      "CODEX_HOME" => ctx.fixture.codex_home,
      "TMPDIR" => Path.join(ctx.root, "tmp"),
      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
      "SHELL" => Path.join(ctx.fixture.bin, "sh"),
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }
  end

  defp exchange(session, method, params, timeout_ms \\ 5000) do
    id = request_id()
    request = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), request, max_depth: 32)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(session.pid, request, timeout_ms: timeout_ms)

    received_index = assert_exchange(session, request, response)
    %{result: result, received_index: received_index}
  end

  defp assert_exchange(session, request, response) do
    assert [sent, received] = Enum.filter(capture(session), &(&1.wire["id"] == request["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.index < received.index
    assert sent.encoded === JSON.encode!(request)
    assert_original(sent, request)
    assert response === %{"id" => request["id"], "result" => Map.fetch!(response, "result")}
    assert_original(received, response)
    received.index
  end

  defp assert_original(original, expected) do
    assert original.wire === expected
    assert JSON.decode!(original.encoded) === expected
    assert {:ok, preserved} = Wire.decode(original.encoded, max_depth: 32)
    assert preserved === expected
  end

  defp validate_result(exchange, relative),
    do: assert(:ok = Schema.validate(schema(relative), exchange.result, max_depth: 32))

  defp capture(session),
    do:
      Agent.get(session.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp assert_inventory(session, methods) do
    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === methods
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === length(Enum.uniq(ids))
    replies = Enum.filter(records, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === length(requests)

    for request <- requests do
      assert [reply] = Enum.filter(replies, &(&1.wire["id"] == request.wire["id"]))
      assert request.index < reply.index

      assert_original(reply, %{
        "id" => request.wire["id"],
        "result" => Map.fetch!(reply.wire, "result")
      })
    end

    assert [initialized] = Enum.filter(outgoing, &(&1.wire["method"] == "initialized"))
    assert_original(initialized, %{"method" => "initialized"})
  end

  defp assert_ready(session) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             status = Session.status(session.pid)

    assert status.generation === session.generation
    assert status.instance_id === session.instance_id
    assert Session.uncertain_operations(session.pid) === []
  end

  defp assert_inputs(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
    assert hash(File.read!(@script)) === @script_sha
  end

  defp close_native(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp schema(relative), do: relative |> schema_bytes() |> JSON.decode!()

  defp schema_bytes(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)
      |> File.read!()

  defp request_id, do: "owned-environment-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
