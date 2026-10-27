defmodule SamgitaCodexDriver.NativeProcessNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 30_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @first_input <<"Owned process input ", 206, 187, 0, 255>>
  @second_input <<" and EOF ", 240, 159, 153, 130, 254, 10>>
  @stdout <<"Owned process stdout ", 206, 187, 0, 255, 10>>
  @stderr <<"Owned process stderr ", 240, 159, 153, 130, 0, 254, 10>>
  @output_method "process/outputDelta"
  @exit_method "process/exited"
  @child ~S"""
  import base64, json, os, select, sys, time
  journal = sys.argv[1]
  maximum_input = 1024
  maximum_journal = 4096
  def record(row):
      encoded = (json.dumps(row, separators=(',', ':')) + '\n').encode()
      if len(encoded) > 1024 or os.stat(journal).st_size + len(encoded) > maximum_journal:
          raise ValueError('Owned child journal bound')
      descriptor = os.open(journal, os.O_WRONLY | os.O_APPEND)
      try:
          if os.write(descriptor, encoded) != len(encoded):
              raise OSError('Incomplete owned child journal write')
      finally:
          os.close(descriptor)
  record({'event': 'started', 'pid': os.getpid()})
  deadline = time.monotonic() + 5
  received = bytearray()
  while True:
      remaining = deadline - time.monotonic()
      if remaining <= 0 or not select.select([0], [], [], remaining)[0]:
          raise ValueError('Owned stdin EOF deadline')
      chunk = os.read(0, min(256, maximum_input + 1 - len(received)))
      if not chunk:
          break
      received.extend(chunk)
      if len(received) > maximum_input:
          raise ValueError('Owned stdin byte bound')
  if bytes(received) != b'Owned process input \xce\xbb\x00\xff and EOF \xf0\x9f\x99\x82\xfe\n':
      raise ValueError('Unexpected owned binary stdin')
  stdout = b'Owned process stdout \xce\xbb\x00\xff\n'
  stderr = b'Owned process stderr \xf0\x9f\x99\x82\x00\xfe\n'
  record({'event': 'eof', 'inputBase64': base64.b64encode(received).decode('ascii')})
  if os.write(1, stdout) != len(stdout) or os.write(2, stderr) != len(stderr):
      raise OSError('Incomplete owned output write')
  record({'event': 'emitted', 'stdoutBase64': base64.b64encode(stdout).decode('ascii'),
          'stderrBase64': base64.b64encode(stderr).decode('ascii'), 'exitCode': 7})
  raise SystemExit(7)
  """

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

    # Original JSONL frame payloads are retained before Session decoding.
    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, &append(&1, direction, encoded))
    end

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 96 and size <= limit and ledger.bytes + size <= 262_144 do
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
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required for owned process"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-process-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: Path.expand(binary), python: python, root: root}
  end

  test "complete native process envelopes follow accepted binary stdin and explicit EOF in cold cap controls",
       ctx do
    for {name, cap} <- [
          {"owned-process-envelope-uncapped", nil},
          {"owned-process-envelope-zero", 0}
        ] do
      run_profile(ctx, name, cap)
    end
  end

  defp run_profile(ctx, name, cap) do
    profile = profile(ctx, name, cap)
    session = start(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    assert {:ok, []} = Session.drain(session.pid, 64)
    assert spawn_process(profile, session.pid) === %{}
    [started] = await_journal(profile, 1)
    assert %{"event" => "started", "pid" => child} = started
    assert Map.keys(started) |> Enum.sort() === ["event", "pid"]
    assert is_integer(child) and child > 0 and child != session.native
    assert File.exists?("/proc/#{child}")
    assert write_input(profile, session.pid, @first_input) === %{}
    assert write_input(profile, session.pid, @second_input) === %{}
    assert diagnostics(profile, session.pid) === session.native
    assert journal(profile) === [%{"event" => "started", "pid" => child}]
    assert File.exists?("/proc/#{child}")
    assert {:ok, []} = Session.drain(session.pid, 64)
    assert raw_notifications(profile) === []

    # The child emits nothing until this public operation delivers actual EOF.
    # Its independent journal verifies both binary chunks and actual writes.
    before_eof = System.system_time(:millisecond)

    assert call(profile, session.pid, "process/writeStdin", %{
             "processHandle" => name,
             "closeStdin" => true
           }) === %{}

    events = collect_exit(session.pid, [], now() + 5_000)
    after_exit = System.system_time(:millisecond)
    assert_effect(profile, child)
    assert_envelopes(profile, events, before_eof, after_exit)
    refute File.exists?("/proc/#{child}")
    assert diagnostics(profile, session.pid) === session.native
    assert {:ok, []} = Session.drain(session.pid, 64)
    assert_inventory(profile)
    assert_inputs(profile)
    assert Session.uncertain_operations(session.pid) === []
    assert Session.interaction_outcomes(session.pid) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    close_resources(session.pid, session.connection, session.native_identity, profile)
    refute File.exists?("/proc/#{child}")
    assert_inputs(profile)
  end

  defp profile(ctx, name, cap) do
    root = Path.join(ctx.root, name)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))
    journal = Path.join(root, "owned-child.jsonl")
    File.write!(journal, "", [:exclusive])
    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
    check_for_update_on_startup = false
    allow_login_shell = false
    [analytics]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [memories]
    generate_memories = false
    use_memories = false
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    memories = false
    shell_snapshot = false
    """)

    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: {Agent, name})

    %{
      binary: ctx.binary,
      python: ctx.python,
      root: root,
      name: name,
      cap: cap,
      journal: journal,
      config: config,
      original_config: File.read!(config),
      workspace: Path.join(root, "workspace"),
      capture: capture
    }
  end

  defp start(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 64,
               max_event_bytes: 262_144,
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
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => Path.join(profile.root, "home"),
                      "CODEX_HOME" => Path.join(profile.root, "codex"),
                      "TMPDIR" => Path.join(profile.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "PYTHONDONTWRITEBYTECODE" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_resources(pid, connection, identity, profile) end)
    id = request_id()
    info = %{"name" => "owned_process_notification_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

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

    native = diagnostics(profile, pid)
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, native_identity: identity}
  end

  defp spawn_process(profile, pid) do
    call(profile, pid, "process/spawn", %{
      "command" => [profile.python, "-I", "-B", "-c", @child, profile.journal],
      "processHandle" => profile.name,
      "cwd" => profile.workspace,
      "streamStdin" => true,
      "streamStdoutStderr" => true,
      "outputBytesCap" => profile.cap,
      "timeoutMs" => 5_000
    })
  end

  defp write_input(profile, pid, bytes) do
    call(profile, pid, "process/writeStdin", %{
      "processHandle" => profile.name,
      "deltaBase64" => Base.encode64(bytes),
      "closeStdin" => false
    })
  end

  defp diagnostics(profile, pid) do
    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    native
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
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Map.keys(response) |> Enum.sort() === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp raw_notifications(profile) do
    profile |> capture() |> Enum.filter(&(&1.direction == :in and is_binary(&1.wire["method"])))
  end

  defp collect_exit(pid, events, deadline) do
    assert {:ok, fresh} = Session.drain(pid, 64)
    events = events ++ fresh
    assert length(events) <= 64
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 262_144
    collect_or_wait(pid, events, deadline)
  end

  defp collect_or_wait(pid, events, deadline) do
    cond do
      Enum.any?(events, &(&1.wire["method"] == @exit_method)) ->
        events

      now() >= deadline ->
        flunk("Native owned process terminal notification deadline")

      true ->
        Process.sleep(10)
        collect_exit(pid, events, deadline)
    end
  end

  defp assert_envelopes(profile, events, before_eof, after_exit) do
    original = raw_notifications(profile)
    assert Enum.map(original, & &1.wire) === Enum.map(events, & &1.wire)
    assert Enum.all?(events, &(&1.kind == :notification))
    assert Enum.map(events, & &1.sequence) === Enum.sort(Enum.map(events, & &1.sequence))
    assert length(Enum.uniq_by(events, & &1.sequence)) === length(events)
    assert Enum.uniq(Enum.map(events, & &1.generation)) === [profile.generation]
    assert Enum.map(events, & &1.wire["method"]) |> List.last() === @exit_method
    deltas = Enum.filter(events, &(&1.wire["method"] == @output_method))
    exits = Enum.filter(events, &(&1.wire["method"] == @exit_method))
    assert length(deltas) >= 2 and length(deltas) <= 60
    assert length(deltas) + length(exits) === length(events)

    assert Enum.sort(Enum.uniq(Enum.map(deltas, & &1.wire["params"]["stream"]))) === [
             "stderr",
             "stdout"
           ]

    assert_delta_envelopes(profile, deltas, before_eof, after_exit)
    assert_exit_envelope(profile, exits, before_eof, after_exit)
  end

  defp assert_delta_envelopes(%{cap: nil} = profile, events, lower, upper) do
    remaining =
      Enum.reduce(
        events,
        %{"stdout" => @stdout, "stderr" => @stderr},
        &consume_delta(&1, &2, profile, lower, upper)
      )

    assert remaining === %{"stdout" => "", "stderr" => ""}
  end

  defp assert_delta_envelopes(%{cap: 0} = profile, events, lower, upper) do
    assert length(events) === 2

    for event <- events,
        do:
          assert_delta(
            event.wire,
            profile.name,
            event.wire["params"]["stream"],
            "",
            true,
            lower,
            upper
          )
  end

  defp consume_delta(event, remaining, profile, lower, upper) do
    stream = event.wire["params"]["stream"]
    assert stream in ["stdout", "stderr"]
    assert {:ok, bytes} = Base.decode64(event.wire["params"]["deltaBase64"])
    target = Map.fetch!(remaining, stream)
    size = byte_size(bytes)
    assert size > 0 and size <= byte_size(target)
    # Only native chunk length selects a slice; bytes come from the independent
    # literal oracle, so arbitrary OS partitioning cannot invent expected data.
    expected = binary_part(target, 0, size)
    assert bytes === expected
    assert_delta(event.wire, profile.name, stream, expected, false, lower, upper)
    Map.put(remaining, stream, binary_part(target, size, byte_size(target) - size))
  end

  defp assert_delta(wire, handle, stream, bytes, cap_reached, lower, upper) do
    emitted_at = timestamp(wire, lower, upper)

    assert wire === %{
             "emittedAtMs" => emitted_at,
             "method" => "process/outputDelta",
             "params" => %{
               "processHandle" => handle,
               "stream" => stream,
               "deltaBase64" => Base.encode64(bytes),
               "capReached" => cap_reached
             }
           }
  end

  defp assert_exit_envelope(profile, [event], lower, upper) do
    emitted_at = timestamp(event.wire, lower, upper)
    capped = profile.cap == 0

    assert event.wire === %{
             "emittedAtMs" => emitted_at,
             "method" => "process/exited",
             "params" => %{
               "processHandle" => profile.name,
               "exitCode" => 7,
               "stdout" => "",
               "stderr" => "",
               "stdoutCapReached" => capped,
               "stderrCapReached" => capped
             }
           }
  end

  defp timestamp(wire, lower, upper) do
    emitted_at = Map.fetch!(wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    emitted_at
  end

  defp assert_effect(profile, child) do
    assert await_journal(profile, 3) === [
             %{"event" => "started", "pid" => child},
             %{"event" => "eof", "inputBase64" => Base.encode64(@first_input <> @second_input)},
             %{
               "event" => "emitted",
               "stdoutBase64" => Base.encode64(@stdout),
               "stderrBase64" => Base.encode64(@stderr),
               "exitCode" => 7
             }
           ]
  end

  defp journal(profile) do
    assert %{type: :regular, size: size} = File.stat!(profile.journal)
    assert size <= 4096
    bytes = File.read!(profile.journal)
    assert byte_size(bytes) <= 4096
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 3
    Enum.map(lines, &decode_row/1)
  end

  defp decode_row(line) do
    assert byte_size(line) <= 1024
    JSON.decode!(line)
  end

  defp await_journal(profile, count), do: await_journal(profile, count, now() + 5_000)

  defp await_journal(profile, count, deadline) do
    rows = journal(profile)

    cond do
      length(rows) == count ->
        rows

      now() >= deadline ->
        flunk("Owned child journal deadline")

      true ->
        Process.sleep(10)
        await_journal(profile, count, deadline)
    end
  end

  defp assert_inventory(profile) do
    records = capture(profile)
    outgoing = Enum.filter(records, &(&1.direction == :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics process/spawn process/writeStdin process/writeStdin server/diagnostics process/writeStdin server/diagnostics)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 8
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === 8
    for record <- records, do: assert_incoming_envelope_kind(record)
    assert length(records) <= 96
  end

  defp assert_incoming_envelope_kind(%{direction: :in, wire: %{"id" => _} = wire}),
    do: refute(Map.has_key?(wire, "method"))

  defp assert_incoming_envelope_kind(_record), do: :ok

  defp assert_inputs(profile) do
    assert File.stat!(profile.config).size <= 4096
    assert File.read!(profile.config) === profile.original_config
    assert File.ls!(profile.workspace) === []
  end

  defp close_resources(pid, connection, identity, profile) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))

    for %{"event" => "started", "pid" => child} <- journal(profile),
        do: refute(File.exists?("/proc/#{child}"))
  end

  defp request_id, do: "owned-process-envelope-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
