defmodule SamgitaCodexDriver.NativeProcessValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @process_methods ~w(process/spawn process/writeStdin process/resizePty process/kill)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ~w(process/spawn process/writeStdin process/resizePty process/kill) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required for owned native process fixtures"

    prerequisites =
      System.cmd(python, [
        "-I",
        "-c",
        "import os, signal, sys; " <>
          "assert sys.platform.startswith('linux'); " <>
          "assert hasattr(os, 'pidfd_open'); " <>
          "assert hasattr(signal, 'pidfd_send_signal'); " <>
          "fd = os.pidfd_open(os.getpid()); os.close(fd); print('ready')"
      ])

    assert prerequisites == {"ready\n", 0},
           "BLOCKED_ENV: Linux Python pidfd cleanup APIs required"

    records = Path.join(ctx.root, "owned-process-handles.json")
    File.write!(records, "[]")
    capture = start_supervised!({Agent, fn -> [] end})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    Map.merge(ctx, %{
      python: python,
      records: records,
      capture: capture,
      config: config,
      config_bytes: File.read!(config)
    })
  end

  test "real PTY dimensions and selected kill preserve a binary pipe control", ctx do
    {pid, native} = start(ctx)
    pipe = child(ctx, "pipe-control", pipe_source())
    explicit = child(ctx, "pty-explicit", pty_source(), [24, 80])
    default = child(ctx, "pty-null", pty_source(), [24, 80])

    spawn_child(ctx, pid, pipe, %{"streamStdin" => true, "streamStdoutStderr" => true})
    events = ready(pid, pipe, [])

    spawn_child(ctx, pid, explicit, %{
      "tty" => true,
      "size" => %{"rows" => 24, "cols" => 80}
    })

    events = ready(pid, explicit, events, %{"rows" => 24, "cols" => 80})
    spawn_child(ctx, pid, default, %{"tty" => true, "size" => nil})
    events = ready(pid, default, events, %{"rows" => 24, "cols" => 80})

    assert rpc(ctx, pid, "process/resizePty", %{
             "processHandle" => explicit.handle,
             "size" => %{"rows" => 40, "cols" => 120}
           }) == %{}

    write(ctx, pid, explicit, "?", false)

    events =
      collect(
        pid,
        &String.ends_with?(output(&1, explicit.handle, "stdout"), "SIZE:40:120\n"),
        events
      )

    write(ctx, pid, default, "?", false)

    events =
      collect(
        pid,
        &String.ends_with?(output(&1, default.handle, "stdout"), "SIZE:24:80\n"),
        events
      )

    write(ctx, pid, explicit, "q", false)
    events = collect(pid, &exited(&1, explicit.handle), events)
    assert_exit(events, explicit, 7)

    assert output(events, explicit.handle, "stdout") ==
             explicit.ready <> "SIZE:40:120\n" <> <<"out", 0, 255, "err", 0, 254>>

    assert output(events, explicit.handle, "stderr") == ""
    assert Enum.all?(deltas(events, explicit.handle), &(&1["stream"] == "stdout"))
    await_gone(explicit)

    assert rpc(ctx, pid, "process/kill", %{"processHandle" => default.handle}) == %{}
    events = collect(pid, &exited(&1, default.handle), events)
    killed = exited(events, default.handle)
    assert is_integer(killed["exitCode"]) and killed["exitCode"] not in [0, 7, 124, 125]
    assert_exit(events, default, killed["exitCode"])
    assert output(events, default.handle, "stdout") == default.ready <> "SIZE:24:80\n"
    await_gone(default)

    first = <<0, 255, "first", 10>>
    final = <<254, 0, "final">>
    write(ctx, pid, pipe, first, false)
    write(ctx, pid, pipe, final, true)
    events = collect(pid, &exited(&1, pipe.handle), events)
    assert_exit(events, pipe, 0)
    assert output(events, pipe.handle, "stdout") == pipe.ready <> "ACK:" <> first <> final
    assert output(events, pipe.handle, "stderr") == <<"EOF:", 0, 253>>

    assert Enum.sort(Enum.uniq(Enum.map(deltas(events, pipe.handle), & &1["stream"]))) ==
             ["stderr", "stdout"]

    await_gone(pipe)
    assert_retained(ctx, pid, [pipe, explicit, default])

    assert Enum.frequencies_by(Agent.get(ctx.capture, & &1), & &1["method"]) == %{
             "process/spawn" => 3,
             "process/resizePty" => 1,
             "process/writeStdin" => 5,
             "process/kill" => 1
           }

    close(pid, native)
  end

  test "explicit null stdin delta closes a real empty pipe and reports both streams", ctx do
    {pid, native} = start(ctx)
    pipe = child(ctx, "pipe-null", pipe_source())
    spawn_child(ctx, pid, pipe, %{"streamStdin" => true, "streamStdoutStderr" => true})
    events = ready(pid, pipe, [])

    assert rpc(ctx, pid, "process/writeStdin", %{
             "processHandle" => pipe.handle,
             "deltaBase64" => nil,
             "closeStdin" => true
           }) == %{}

    events = collect(pid, &exited(&1, pipe.handle), events)
    assert_exit(events, pipe, 0)
    assert output(events, pipe.handle, "stdout") == pipe.ready <> "ACK:"
    assert output(events, pipe.handle, "stderr") == <<"EOF:", 0, 253>>
    await_gone(pipe)
    assert_retained(ctx, pid, [pipe])

    assert Enum.map(Agent.get(ctx.capture, & &1), & &1["method"]) ==
             ["process/spawn", "process/writeStdin"]

    close(pid, native)
  end

  defp child(ctx, handle, source, dimensions \\ []) do
    cwd = Path.join(ctx.fixture.workspace, handle <> "-cwd")
    File.mkdir!(cwd)
    script = Path.join(ctx.fixture.workspace, handle <> ".py")
    record = Path.join(ctx.root, handle <> "-identity.json")
    source = common_source() <> source
    File.write!(script, source)

    %{
      handle: handle,
      cwd: cwd,
      script: script,
      source: source,
      record: record,
      command: [ctx.python, "-I", "-u", script, handle, record],
      ready: "READY:" <> JSON.encode!([handle, cwd] ++ dimensions) <> "\n"
    }
  end

  defp common_source do
    ~S"""
    import json, os, signal, sys
    # A finite failsafe is cleanup only, never the expected native exit.
    signal.signal(signal.SIGALRM, lambda *_: os._exit(125))
    signal.alarm(20)
    handle, record_path = sys.argv[1:]
    start = open("/proc/self/stat").read().rsplit(")", 1)[1].split()[19]
    record = {"pid": os.getpid(), "start": start, "script": os.path.abspath(__file__)}
    temporary = record_path + ".tmp"
    with open(temporary, "w") as target:
        json.dump(record, target)
    os.replace(temporary, record_path)
    ready = [handle, os.getcwd()]
    """
  end

  defp pipe_source do
    ~S"""
    os.write(1, ("READY:" + json.dumps(ready, separators=(",", ":")) + "\n").encode())
    received = sys.stdin.buffer.read()
    os.write(1, b"ACK:" + received)
    os.write(2, b"EOF:\x00\xfd")
    """
  end

  defp pty_source do
    ~S"""
    import tty
    tty.setraw(0)
    size = os.get_terminal_size(0)
    ready.extend([size.lines, size.columns])
    os.write(1, ("READY:" + json.dumps(ready, separators=(",", ":")) + "\n").encode())
    while True:
        key = os.read(0, 1)
        if key == b"?":
            size = os.get_terminal_size(0)
            os.write(1, f"SIZE:{size.lines}:{size.columns}\n".encode())
        elif key == b"q":
            os.write(1, b"out\x00\xff")
            os.write(2, b"err\x00\xfe")
            sys.exit(7)
        elif not key:
            sys.exit(23)
    """
  end

  defp spawn_child(ctx, pid, child, extra) do
    recorded = JSON.decode!(File.read!(ctx.records))

    File.write!(
      ctx.records,
      JSON.encode!(recorded ++ [%{"handle" => child.handle, "record" => child.record}])
    )

    assert rpc(
             ctx,
             pid,
             "process/spawn",
             Map.merge(
               %{
                 "processHandle" => child.handle,
                 "command" => child.command,
                 "cwd" => child.cwd,
                 "timeoutMs" => nil,
                 "outputBytesCap" => nil
               },
               extra
             )
           ) == %{}
  end

  defp ready(pid, child, events, dimensions \\ %{}) do
    events =
      collect(pid, &(:binary.match(output(&1, child.handle, "stdout"), "\n") != :nomatch), events)

    [line, ""] = :binary.split(output(events, child.handle, "stdout"), "\n")
    assert "READY:" <> encoded = line
    size = if dimensions == %{}, do: [], else: [dimensions["rows"], dimensions["cols"]]
    expected = [child.handle, child.cwd] ++ size
    assert JSON.decode!(encoded) === expected
    identity = JSON.decode!(File.read!(child.record))
    assert is_integer(identity["pid"]) and identity["pid"] > 0
    assert identity["script"] == child.script
    assert is_binary(identity["start"]) and identity["start"] != ""
    events
  end

  defp write(ctx, pid, child, bytes, close) do
    assert rpc(ctx, pid, "process/writeStdin", %{
             "processHandle" => child.handle,
             "deltaBase64" => Base.encode64(bytes),
             "closeStdin" => close
           }) == %{}
  end

  defp rpc(ctx, pid, method, params) when method in @process_methods do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-process-values-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [captured] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert captured === wire
    result
  end

  defp collect(pid, predicate, events, until \\ nil) do
    until = until || deadline()
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native process event bound exceeded"

    assert Enum.sum(Enum.map(events, &byte_size(JSON.encode!(&1.wire)))) <= 65_536,
           "Native process byte bound exceeded"

    for event <- incoming,
        event.wire["method"] in ["process/outputDelta", "process/exited"] do
      assert is_integer(event.wire["emittedAtMs"]) and event.wire["emittedAtMs"] > 0
    end

    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      remaining = max(until - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, events, until)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native process event gap")
      after
        remaining -> flunk("Native process I/O deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp deltas(events, handle) do
    for event <- events,
        event.wire["method"] == "process/outputDelta",
        event.wire["params"]["processHandle"] == handle,
        do: event.wire["params"]
  end

  defp output(events, handle, stream) do
    events
    |> deltas(handle)
    |> Enum.filter(&(&1["stream"] == stream))
    |> Enum.map_join(&Base.decode64!(&1["deltaBase64"]))
  end

  defp exited(events, handle) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == "process/exited" and
           event.wire["params"]["processHandle"] == handle,
         do: event.wire["params"]
    end)
  end

  defp assert_exit(events, child, code) do
    assert exited(events, child.handle) === %{
             "processHandle" => child.handle,
             "exitCode" => code,
             "stdout" => "",
             "stderr" => "",
             "stdoutCapReached" => false,
             "stderrCapReached" => false
           }

    assert Enum.count(events, fn event ->
             event.wire["method"] == "process/exited" and
               event.wire["params"]["processHandle"] == child.handle
           end) == 1

    assert Enum.all?(deltas(events, child.handle), &(&1["capReached"] == false))
  end

  defp await_gone(child, until \\ nil) do
    until = until || deadline()
    identity = JSON.decode!(File.read!(child.record))

    if File.exists?("/proc/#{identity["pid"]}") do
      assert System.monotonic_time(:millisecond) < until, "Owned native child was not reaped"

      receive do
      after
        10 -> await_gone(child, until)
      end
    end
  end

  defp assert_retained(ctx, pid, children) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.read!(ctx.fixture.requests) == "[]"
    assert File.read!(ctx.config) == ctx.config_bytes
    for child <- children, do: assert(File.read!(child.script) == child.source)

    assert TurnFixture.call(pid, "thread/loaded/list", %{}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)

    assert length(Enum.uniq_by(Agent.get(ctx.capture, & &1), & &1["id"])) ==
             length(Agent.get(ctx.capture, & &1))
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => ctx.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)

    # Registered after TurnFixture's root cleanup: records survive until the
    # session, its owned native group, and every recorded child are closed.
    on_exit(fn -> cleanup(ctx, pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "owned_process_values", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    native = TurnFixture.call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {pid, native}
  end

  defp cleanup(ctx, pid, connection) do
    recorded = JSON.decode!(File.read!(ctx.records))

    try do
      if Process.alive?(pid) do
        for owned <- recorded do
          try do
            Session.request(pid, "process/kill", %{"processHandle" => owned["handle"]},
              timeout_ms: 5_000
            )
          catch
            :exit, _ -> :ok
          end
        end
      end

      StdioSessionFixture.close(pid, connection)
    after
      # The PTY library may create a separate process group. Only the exact
      # recorded PID/start-time/script can be signalled through its pinned pidfd.
      for owned <- recorded do
        assert {"", 0} = System.cmd(ctx.python, ["-I", "-c", cleanup_source(), owned["record"]])
      end
    end
  end

  defp cleanup_source do
    ~S"""
    import json, os, select, signal, sys
    if not os.path.exists(sys.argv[1]):
        sys.exit(0)
    with open(sys.argv[1]) as source:
        record = json.load(source)
    pid = record["pid"]
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        sys.exit(0)
    try:
        if select.select([fd], [], [], 0)[0]:
            sys.exit(0)
        try:
            start = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[19]
            argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        except FileNotFoundError:
            sys.exit(0)
        if start != record["start"] or os.fsencode(record["script"]) not in argv:
            if select.select([fd], [], [], 0)[0]:
                sys.exit(0)
            sys.exit("Owned child cleanup identity changed")
        try:
            signal.pidfd_send_signal(fd, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if not select.select([fd], [], [], 5.0)[0]:
            sys.exit("Owned child cleanup deadline")
    finally:
        os.close(fd)
    """
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
