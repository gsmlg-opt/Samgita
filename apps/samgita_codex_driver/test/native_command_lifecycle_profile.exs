defmodule SamgitaCodexDriver.NativeCommandLifecycleProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @command_script ~S"""
  import fcntl, ipaddress, json, os, select, signal, socket, struct, subprocess, sys, termios, time
  from pathlib import Path

  mode, marker, route_program, parent_netns = sys.argv[1:]
  netns = os.readlink('/proc/self/ns/net')
  interfaces = [name for _, name in socket.if_nameindex()]
  routes = json.loads(subprocess.check_output([route_program, '-j', 'route', 'show', 'table', 'all']))
  assert netns != parent_netns, 'BLOCKED_ENV: network namespace unchanged'
  assert interfaces == ['lo'], 'BLOCKED_ENV: nonloopback interface'
  assert all(row.get('dst') != 'default' and row.get('dev') == 'lo' for row in routes)
  assert all(not row.get('prefsrc') or ipaddress.ip_address(row['prefsrc']).is_loopback for row in routes)
  Path(marker).write_text(json.dumps({'pid': os.getpid(), 'native_pid': os.getppid(),
      'namespace': netns, 'interfaces': interfaces, 'default_route': False,
      'cwd': os.getcwd(), 'stdin_tty': sys.stdin.isatty(), 'stdout_tty': sys.stdout.isatty()}))
  if mode == 'inspect':
      print(json.dumps({'cwd': os.getcwd(), 'keep': os.getenv('SAMGITA_COMMAND_KEEP'),
                        'drop': os.getenv('SAMGITA_COMMAND_DROP')}), end='', flush=True)
      print('synthetic-error', end='', file=sys.stderr, flush=True)
      sys.exit(7)
  elif mode == 'pipe':
      print('out-start', flush=True)
      print('err-start', file=sys.stderr, flush=True)
      data = sys.stdin.buffer.read()
      sys.stdout.buffer.write(b'out:' + data); sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b'err:' + data); sys.stderr.buffer.flush()
  elif mode == 'cap':
      print('abcdefghij', end='', flush=True)
      print('uvwxyz0123', end='', file=sys.stderr, flush=True)
      sys.stdin.buffer.read()
  elif mode == 'large':
      sys.stdout.buffer.write(b'O' * (1024 * 1024 + 13)); sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b'E' * (1024 * 1024 + 29)); sys.stderr.buffer.flush()
  elif mode == 'byte-cap':
      sys.stdout.buffer.write(b'A\xe4\xb8\xad\x00\xffZ'); sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b'B\xf0\x9f\x98\x80\x00\xfeY'); sys.stderr.buffer.flush()
      sys.stdin.buffer.read()
  elif mode == 'past-default':
      print('ready', flush=True)
      started = time.monotonic()
      readable, _, _ = select.select([sys.stdin], [], [], 10.1)
      assert not readable, 'stdin released before the native default timeout boundary'
      print('survived:' + str(int((time.monotonic() - started) * 1000)), flush=True)
      sys.stdin.buffer.read()
  elif mode == 'wait':
      print('ready', flush=True)
      signal.pause()
  elif mode == 'tty':
      attrs = termios.tcgetattr(sys.stdin.fileno())
      attrs[1] &= ~termios.OPOST
      attrs[3] &= ~termios.ECHO
      termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, attrs)
      def size():
          rows, cols, _, _ = struct.unpack('HHHH', fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, bytes(8)))
          return f'{rows} {cols}'
      print('before:' + size(), flush=True)
      print('pty-error', file=sys.stderr, flush=True)
      line = sys.stdin.readline().rstrip('\n')
      print('after:' + size(), flush=True)
      print('echo:' + line, flush=True)
  elif mode == 'process-owner':
      label = Path(marker).stem.encode('ascii')
      effect = Path(marker).with_suffix('.input')
      data = b''
      effect.write_bytes(data)
      sys.stdout.buffer.write(b'ready-out:' + label + b'\n'); sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b'ready-err:' + label + b'\n'); sys.stderr.buffer.flush()
      while True:
          chunk = os.read(sys.stdin.fileno(), 4096)
          if not chunk:
              break
          data += chunk
          effect.write_bytes(data)
      sys.stdout.buffer.write(b'out:' + label + b':' + data); sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b'err:' + label + b':' + data); sys.stderr.buffer.flush()
  else:
      raise AssertionError('unowned synthetic command mode')
  """

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"
    assert System.find_executable("python3"), "BLOCKED_ENV: python3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-command-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ["home", "codex", "workspace", "tmp", "markers"] do
      File.mkdir_p!(Path.join(root, directory))
    end

    on_exit(fn -> File.rm_rf!(root) end)
    script = Path.join(root, "workspace/owned_command.py")
    File.write!(script, @command_script)

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      script: script,
      workspace: Path.join(root, "workspace"),
      codex_home: Path.join(root, "codex"),
      socket: Path.join(root, "native.sock"),
      parent_netns: File.read_link!("/proc/self/ns/net"),
      python: System.find_executable("python3"),
      ip: System.find_executable("ip")
    }

    configure(ctx)

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("unshare"),
        args: [
          "--user",
          "--map-root-user",
          "--net",
          "--fork",
          "--kill-child=TERM",
          ctx.binary,
          "app-server",
          "--listen",
          "unix://" <> ctx.socket
        ],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => ctx.codex_home,
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "SAMGITA_COMMAND_KEEP" => "server-value",
          "SAMGITA_COMMAND_DROP" => "remove-me"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      for path <- Path.wildcard(Path.join(ctx.root, "markers/*.json")) do
        marker = path |> File.read!() |> JSON.decode!()
        await(fn -> not File.exists?("/proc/#{marker["pid"]}") end, "owned command reaping")

        await(
          fn -> not File.exists?("/proc/#{marker["native_pid"]}") end,
          "owned native server reaping"
        )
      end
    end)

    await(fn -> File.exists?(ctx.socket) end, "private native UDS startup")
    Map.put(ctx, :owner, owner)
  end

  test "buffered command reports nonzero exit cwd and environment with native parameter errors",
       ctx do
    pid = client(ctx)
    cwd = Path.join(ctx.workspace, "owned-subdirectory")
    File.mkdir!(cwd)

    result =
      call(
        pid,
        "command/exec",
        params(ctx, "inspect", "buffered", %{
          "cwd" => cwd,
          "env" => %{"SAMGITA_COMMAND_KEEP" => "request-value", "SAMGITA_COMMAND_DROP" => nil}
        })
      )

    assert result["exitCode"] == 7
    assert result["stderr"] == "synthetic-error"

    assert JSON.decode!(result["stdout"]) == %{
             "cwd" => cwd,
             "keep" => "request-value",
             "drop" => nil
           }

    assert_marker(ctx, "buffered")
    assert_gone(ctx, "buffered")
    base = params(ctx, "inspect", "must-not-run")

    for {changes, code, message} <- [
          {%{"command" => []}, -32_600, "command must not be empty"},
          {%{"streamStdoutStderr" => true}, -32_600, "requires a client-supplied processId"},
          {%{"size" => %{"rows" => 1, "cols" => 1}}, -32_602, "size requires tty: true"},
          {%{"disableOutputCap" => true, "outputBytesCap" => 1}, -32_602,
           "both outputBytesCap and disableOutputCap"},
          {%{"disableTimeout" => true}, -32_602, "both timeoutMs and disableTimeout"},
          {%{"timeoutMs" => -1}, -32_602, "timeoutMs must be non-negative"},
          {%{"permissionProfile" => "synthetic-missing"}, -32_600, "cannot be combined with"}
        ] do
      error = upstream_error(pid, "command/exec", Map.merge(base, changes))
      assert error["code"] == code
      assert error["message"] =~ message
    end

    refute File.exists?(marker_path(ctx, "must-not-run"))
    assert_no_command_output(pid)
    assert :ok = Session.close(pid)
  end

  test "pipe stdin accepts binary chunks and EOF while streamed bytes retain process correlation",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "pipe", "pipe", %{"streamStdin" => true, "streamStdoutStderr" => true})

    events =
      output_until(
        pid,
        "pipe",
        &(output(&1, "stdout") == "out-start\n" and output(&1, "stderr") == "err-start\n")
      )

    assert_marker(ctx, "pipe")
    assert Task.yield(task, 0) == nil
    first = <<0, 255, "line\n">>
    assert write(pid, "pipe", first, false) == %{}
    assert Task.yield(task, 0) == nil
    assert write(pid, "pipe", "tail", true) == %{}

    events =
      output_until(
        pid,
        "pipe",
        &(output(&1, "stdout") == "out-start\nout:" <> first <> "tail" and
            output(&1, "stderr") == "err-start\nerr:" <> first <> "tail"),
        events
      )

    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert Enum.all?(deltas(events, "pipe"), &(&1["capReached"] == false))
    assert_gone(ctx, "pipe")

    assert upstream_error(pid, "command/exec/write", %{
             "processId" => "pipe",
             "deltaBase64" => Base.encode64("late")
           })["code"] == -32_600

    assert :ok = Session.close(pid)
  end

  test "stream output caps each stream and signals capReached without buffering the final result",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "cap", "capped", %{
        "streamStdin" => true,
        "streamStdoutStderr" => true,
        "outputBytesCap" => 3
      })

    events =
      output_until(pid, "capped", fn events ->
        output(events, "stdout") == "abc" and output(events, "stderr") == "uvw" and
          Enum.all?(deltas(events, "capped"), & &1["capReached"])
      end)

    assert_marker(ctx, "capped")
    assert Enum.count(deltas(events, "capped"), &(&1["stream"] == "stdout")) == 1
    assert Enum.count(deltas(events, "capped"), &(&1["stream"] == "stderr")) == 1
    assert Task.yield(task, 0) == nil
    assert write(pid, "capped", nil, true) == %{}
    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert_gone(ctx, "capped")
    assert_no_command_output(pid)
    assert :ok = Session.close(pid)
  end

  test "buffered output disables the native per-stream default cap only when explicitly requested",
       ctx do
    pid = client(ctx)
    cap = 1_048_576

    for {name, options, stdout_size, stderr_size} <- [
          {"large-default", %{}, cap, cap},
          {"large-full", %{"disableOutputCap" => true}, cap + 13, cap + 29}
        ] do
      result = call(pid, "command/exec", params(ctx, "large", name, options))
      assert Map.keys(result) |> Enum.sort() == ["exitCode", "stderr", "stdout"]
      assert result["exitCode"] == 0
      assert byte_size(result["stdout"]) == stdout_size
      assert byte_size(result["stderr"]) == stderr_size

      assert :crypto.hash(:sha256, result["stdout"]) ==
               :crypto.hash(:sha256, String.duplicate("O", stdout_size))

      assert :crypto.hash(:sha256, result["stderr"]) ==
               :crypto.hash(:sha256, String.duplicate("E", stderr_size))

      assert_marker(ctx, name)
      assert_gone(ctx, name)
      assert_no_command_output(pid)
    end

    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "zero stream cap still emits one empty explicit cap notification per nonempty stream",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "cap", "zero-cap", %{
        "streamStdin" => true,
        "streamStdoutStderr" => true,
        "outputBytesCap" => 0
      })

    events =
      output_until(pid, "zero-cap", fn events ->
        Enum.sort(Enum.map(deltas(events, "zero-cap"), & &1["stream"])) ==
          ["stderr", "stdout"]
      end)

    assert Enum.all?(deltas(events, "zero-cap"), fn delta ->
             delta == %{
               "processId" => "zero-cap",
               "stream" => delta["stream"],
               "deltaBase64" => "",
               "capReached" => true
             }
           end)

    assert_marker(ctx, "zero-cap")
    assert Task.yield(task, 0) == nil
    assert write(pid, "zero-cap", nil, true) == %{}
    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert_gone(ctx, "zero-cap")
    assert_no_command_output(pid)
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "stream byte caps preserve exact base64 prefixes even when they split UTF-8", ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "byte-cap", "binary-cap", %{
        "streamStdin" => true,
        "streamStdoutStderr" => true,
        "outputBytesCap" => 3
      })

    events =
      output_until(pid, "binary-cap", fn events ->
        output(events, "stdout") == <<?A, 0xE4, 0xB8>> and
          output(events, "stderr") == <<?B, 0xF0, 0x9F>>
      end)

    assert Enum.sort(Enum.map(deltas(events, "binary-cap"), & &1["stream"])) ==
             ["stderr", "stdout"]

    assert Enum.all?(deltas(events, "binary-cap"), & &1["capReached"])
    refute String.valid?(output(events, "stdout"))
    refute String.valid?(output(events, "stderr"))
    assert_marker(ctx, "binary-cap")
    assert Task.yield(task, 0) == nil
    assert write(pid, "binary-cap", nil, true) == %{}
    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert_gone(ctx, "binary-cap")
    assert_no_command_output(pid)
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "explicit disableTimeout survives the native ten-second default until owner EOF", ctx do
    pid = client(ctx)
    request_id = "past-default-request"

    task =
      Task.async(fn ->
        Session.request(
          pid,
          "command/exec",
          params(ctx, "past-default", "past-default", %{
            "processId" => "past-default",
            "streamStdin" => true,
            "streamStdoutStderr" => true,
            "timeoutMs" => nil,
            "disableTimeout" => true
          }),
          id: request_id,
          timeout_ms: 15_000
        )
      end)

    events = output_until(pid, "past-default", &(output(&1, "stdout") == "ready\n"))
    assert_marker(ctx, "past-default")
    assert Task.yield(task, 0) == nil

    events =
      events_until(
        pid,
        &(output(&1, "stdout") =~ "survived:"),
        events,
        now() + 12_000
      )

    assert [elapsed] =
             Regex.run(~r/\Aready\nsurvived:(\d+)\n\z/, output(events, "stdout"),
               capture: :all_but_first
             )

    assert String.to_integer(elapsed) >= 10_100
    assert output(events, "stderr") == ""
    assert Enum.all?(deltas(events, "past-default"), &(&1["capReached"] == false))
    assert Task.yield(task, 0) == nil
    assert write(pid, "past-default", nil, true) == %{}
    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert_gone(ctx, "past-default")
    assert_no_command_output(pid)
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "PTY implies both streams supports initial size and validates resize before accepting stdin",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "tty", "terminal", %{
        "tty" => true,
        "size" => %{"rows" => 24, "cols" => 80}
      })

    events =
      output_until(
        pid,
        "terminal",
        &(output(&1, "stdout") =~ "before:24 80\n" and output(&1, "stdout") =~ "pty-error\n")
      )

    marker = assert_marker(ctx, "terminal")
    assert marker["stdin_tty"] and marker["stdout_tty"]
    assert output(events, "stderr") == ""

    assert upstream_error(pid, "command/exec/resize", %{
             "processId" => "terminal",
             "size" => %{"rows" => 0, "cols" => 80}
           })["code"] == -32_602

    assert call(pid, "command/exec/resize", %{
             "processId" => "terminal",
             "size" => %{"rows" => 45, "cols" => 132}
           }) == %{}

    assert write(pid, "terminal", "world\n", false) == %{}

    events =
      output_until(
        pid,
        "terminal",
        &(output(&1, "stdout") =~ "after:45 132\n" and output(&1, "stdout") =~ "echo:world\n"),
        events
      )

    assert final(task, request_id) == %{"exitCode" => 0, "stdout" => "", "stderr" => ""}
    assert output(events, "stderr") == ""
    assert_gone(ctx, "terminal")
    assert :ok = Session.close(pid)
  end

  test "active IDs reject duplicates and unsupported controls while explicit termination returns a separate outcome",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "wait", "controlled", %{"streamStdoutStderr" => true})

    output_until(pid, "controlled", &(output(&1, "stdout") == "ready\n"))
    assert_marker(ctx, "controlled")
    duplicate = params(ctx, "inspect", "duplicate-must-not-run", %{"processId" => "controlled"})

    assert upstream_error(pid, "command/exec", duplicate)["message"] ==
             "duplicate active command/exec process id: \"controlled\""

    refute File.exists?(marker_path(ctx, "duplicate-must-not-run"))

    assert upstream_error(pid, "command/exec/write", %{
             "processId" => "controlled",
             "deltaBase64" => Base.encode64("x")
           })["message"] == "stdin streaming is not enabled for this command/exec"

    assert upstream_error(pid, "command/exec/write", %{"processId" => "controlled"})["code"] ==
             -32_602

    assert upstream_error(pid, "command/exec/write", %{
             "processId" => "controlled",
             "deltaBase64" => "!invalid!"
           })["code"] == -32_602

    error =
      upstream_error(pid, "command/exec/resize", %{
        "processId" => "controlled",
        "size" => %{"rows" => 2, "cols" => 2}
      })

    assert error["code"] == -32_600
    assert error["message"] =~ "failed to resize PTY"
    assert terminate(pid, "controlled") == %{}
    result = final(task, request_id)
    assert result["exitCode"] != 0
    assert result["stdout"] == "" and result["stderr"] == ""
    assert_gone(ctx, "controlled")

    for {method, extra} <- [
          {"command/exec/write", %{"closeStdin" => true}},
          {"command/exec/resize", %{"size" => %{"rows" => 2, "cols" => 2}}},
          {"command/exec/terminate", %{}}
        ] do
      error = upstream_error(pid, method, Map.put(extra, "processId", "missing"))
      assert error["code"] == -32_600
      assert error["message"] == "no active command/exec for process id \"missing\""
    end

    assert :ok = Session.close(pid)
  end

  test "native execution timeout produces exit 124 and reaps the owned command", ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "wait", "timeout", %{"streamStdoutStderr" => true, "timeoutMs" => 500})

    output_until(pid, "timeout", &(output(&1, "stdout") == "ready\n"))
    assert_marker(ctx, "timeout")
    assert final(task, request_id) == %{"exitCode" => 124, "stdout" => "", "stderr" => ""}
    assert_gone(ctx, "timeout")
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "local abandonment preserves unknown outcome until explicit native termination and a late response",
       ctx do
    pid = client(ctx)

    {task, request_id} =
      exec_async(pid, ctx, "wait", "abandoned", %{"streamStdoutStderr" => true})

    events = output_until(pid, "abandoned", &(output(&1, "stdout") == "ready\n"))
    marker = assert_marker(ctx, "abandoned")
    assert :ok = Session.abandon(pid, request_id)
    assert {:error, %Error{code: :locally_abandoned, uncertain: true}} = Task.await(task, 5_000)
    assert File.exists?("/proc/#{marker["pid"]}")

    assert [%{id: ^request_id, method: "command/exec", reason: :locally_abandoned}] =
             Session.uncertain_operations(pid)

    assert terminate(pid, "abandoned") == %{}

    events =
      events_until(
        pid,
        fn events ->
          Enum.any?(events, &(&1.kind == :late_response and &1.wire["id"] == request_id))
        end,
        events
      )

    late = Enum.find(events, &(&1.kind == :late_response and &1.wire["id"] == request_id))
    assert late.wire["result"]["exitCode"] != 0
    assert_gone(ctx, "abandoned")
    assert length(Session.uncertain_operations(pid)) == 1
    assert length(Path.wildcard(Path.join(ctx.root, "markers/*.json"))) == 1
    assert :ok = Session.close(pid)
  end

  test "borrowed connections fence identical process IDs and reconnect stops only the old connection command",
       ctx do
    first = client(ctx)
    second = client(ctx)

    {task1, id1} =
      exec_async(first, ctx, "wait", "owner-one", %{
        "processId" => "shared-id",
        "streamStdoutStderr" => true
      })

    output_until(first, "shared-id", &(output(&1, "stdout") == "ready\n"))
    one = assert_marker(ctx, "owner-one")

    for {method, extra} <- [
          {"command/exec/write", %{"deltaBase64" => Base.encode64("x")}},
          {"command/exec/resize", %{"size" => %{"rows" => 2, "cols" => 2}}},
          {"command/exec/terminate", %{}}
        ] do
      error = upstream_error(second, method, Map.put(extra, "processId", "shared-id"))
      assert error["code"] == -32_600
      assert error["message"] == "no active command/exec for process id \"shared-id\""
    end

    assert File.exists?("/proc/#{one["pid"]}")
    assert_no_command_output(second)

    {task2, id2} =
      exec_async(second, ctx, "wait", "owner-two", %{
        "processId" => "shared-id",
        "streamStdoutStderr" => true
      })

    output_until(second, "shared-id", &(output(&1, "stdout") == "ready\n"))
    two = assert_marker(ctx, "owner-two")
    assert one["native_pid"] == two["native_pid"]
    generation = Session.status(first).generation
    assert :ok = Session.reconnect(first)
    assert {:error, %Error{uncertain: true}} = Task.await(task1, 5_000)
    assert_gone(ctx, "owner-one")
    assert File.exists?("/proc/#{two["pid"]}")
    assert Port.info(ctx.owner.port)
    assert File.exists?(ctx.socket)
    assert Session.status(first).generation == generation + 1
    initialize(first)
    assert [%{id: ^id1, method: "command/exec"}] = Session.uncertain_operations(first)

    assert upstream_error(first, "command/exec/terminate", %{"processId" => "shared-id"})["code"] ==
             -32_600

    assert call(first, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_no_command_output(first)
    assert terminate(second, "shared-id") == %{}
    assert final(task2, id2)["exitCode"] != 0
    assert_gone(ctx, "owner-two")
    assert length(Path.wildcard(Path.join(ctx.root, "markers/*.json"))) == 2
    assert :ok = Session.close(first)
    assert :ok = Session.close(second)
    assert Port.info(ctx.owner.port)
    survivor = client(ctx)
    assert call(survivor, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert :ok = Session.close(survivor)
  end

  # rust-v0.163.0 / 83086188ae0614bd882818ff1aa23f3194962012:
  # process_exec_processor.rs:290-360 keys by connection + handle; :427-453
  # removes and kills only the disconnected connection's children. Output and
  # exit callbacks target that connection (:513-531, :595-607, :651-662).
  test "process handles are connection-owned and reconnect reaps only the old generation",
       ctx do
    first = client(ctx)
    second = client(ctx)
    process_initialized(first)
    process_initialized(second)
    handle = "shared-process-handle"
    first_name = "process-owner-one"
    second_name = "process-owner-two"
    fresh_name = "process-owner-fresh"

    assert process_spawn(first, ctx, handle, first_name) == %{}
    first_events = process_ready(first, handle, first_name)
    one = assert_marker(ctx, first_name)
    refute one["stdin_tty"] or one["stdout_tty"]
    assert process_effect(ctx, first_name) == ""

    # These are valid controls: errors must come from ownership lookup, rather
    # than base64, empty-write, or terminal-size validation.
    process_unknown_controls(second, handle)
    process_no_notices(second)
    assert File.exists?("/proc/#{one["pid"]}")
    assert process_effect(ctx, first_name) == ""
    first_bytes = <<0, 255, "first-owner\n">>
    assert process_write(first, handle, first_bytes) == %{}
    process_effect_until(ctx, first_name, first_bytes)

    # The identical handle is legal on a different borrowed UDS connection.
    assert process_spawn(second, ctx, handle, second_name) == %{}
    second_events = process_ready(second, handle, second_name)
    two = assert_marker(ctx, second_name)
    assert one["pid"] != two["pid"]
    assert one["native_pid"] == two["native_pid"]
    refute two["stdin_tty"] or two["stdout_tty"]
    process_no_notices(first)
    second_prefix = <<254, 0, "second-owner\n">>
    assert process_write(second, handle, second_prefix) == %{}
    process_effect_until(ctx, second_name, second_prefix)
    assert process_effect(ctx, first_name) == first_bytes

    generation = Session.status(first).generation
    assert %{gap: nil, uncertain: 0} = Session.status(first)
    assert :ok = Session.reconnect(first)
    assert Session.status(first).generation == generation + 1
    reconnect_gap = Session.status(first).gap

    assert %{reason: :explicit_reconnect, generation: ^generation, after_sequence: sequence} =
             reconnect_gap

    assert is_integer(sequence)
    assert_receive {:codex_driver, ^first, {:gap, ^reconnect_gap}}
    assert_gone(ctx, first_name)
    assert process_effect(ctx, first_name) == first_bytes
    assert File.exists?("/proc/#{two["pid"]}")
    assert File.exists?("/proc/#{one["native_pid"]}")
    assert Port.info(ctx.owner.port)
    assert File.exists?(ctx.socket)
    initialize(first)
    process_initialized(first)
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: ^reconnect_gap} = Session.status(first)
    assert Session.uncertain_operations(first) == []

    # No old-handle control or reconnect automatically creates/replays a child.
    process_unknown_controls(first, handle)
    process_no_notices(first)
    process_no_notices(second)
    assert process_effect(ctx, second_name) == second_prefix
    assert File.exists?("/proc/#{two["pid"]}")
    assert length(Path.wildcard(Path.join(ctx.root, "markers/*.json"))) == 2
    refute File.exists?(marker_path(ctx, fresh_name))

    # Only an explicit spawn and its native reply create the fresh generation.
    assert process_spawn(first, ctx, handle, fresh_name) == %{}
    fresh_events = process_ready(first, handle, fresh_name)
    fresh = assert_marker(ctx, fresh_name)
    assert fresh["pid"] not in [one["pid"], two["pid"]]
    assert fresh["native_pid"] == two["native_pid"]
    assert process_effect(ctx, fresh_name) == ""
    process_no_notices(second)
    fresh_bytes = <<253, 0, "fresh-owner\n">>
    assert process_write(first, handle, fresh_bytes) == %{}
    process_effect_until(ctx, fresh_name, fresh_bytes)

    assert call(first, "process/writeStdin", %{
             "processHandle" => handle,
             "closeStdin" => true
           }) == %{}

    fresh_events = process_finished(first, handle, fresh_name, fresh_bytes, fresh_events)
    assert Enum.all?(fresh_events, &(&1.generation == generation + 1))
    process_stale_controls(first, handle)
    assert_gone(ctx, fresh_name)
    assert File.exists?("/proc/#{two["pid"]}")
    assert process_effect(ctx, first_name) == first_bytes
    assert process_effect(ctx, second_name) == second_prefix

    # Independent binary stdin and explicit EOF complete only the second child.
    second_tail = <<0, 252, "second-tail">>
    assert process_write(second, handle, second_tail) == %{}
    process_effect_until(ctx, second_name, second_prefix <> second_tail)

    assert call(second, "process/writeStdin", %{
             "processHandle" => handle,
             "closeStdin" => true
           }) == %{}

    second_events =
      process_finished(second, handle, second_name, second_prefix <> second_tail, second_events)

    assert Enum.all?(first_events ++ second_events, &(&1.generation == generation))
    process_stale_controls(second, handle)
    assert_gone(ctx, second_name)
    process_no_notices(first)
    process_no_notices(second)
    assert process_effect(ctx, fresh_name) == fresh_bytes
    assert process_effect(ctx, first_name) == first_bytes
    assert length(Path.wildcard(Path.join(ctx.root, "markers/*.json"))) == 3

    for {pid, expected_gap} <- [{first, reconnect_gap}, {second, nil}] do
      assert %{phase: :ready, pending: 0, uncertain: 0, gap: ^expected_gap} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
      assert :ok = Session.close(pid)
    end

    assert Port.info(ctx.owner.port)
    assert File.exists?("/proc/#{two["native_pid"]}")
    assert File.exists?(ctx.socket)
    survivor = client(ctx)
    process_initialized(survivor)
    process_no_notices(survivor)
    assert :ok = Session.close(survivor)
  end

  defp configure(ctx) do
    catalog = Path.join(ctx.codex_home, "models.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "fixture-model",
            "display_name" => "No inference",
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{"instructions_template" => "No turns are authorized."},
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    File.write!(Path.join(ctx.codex_home, "config.toml"), """
    model = "fixture-model"
    model_provider = "fixture"
    model_catalog_json = #{JSON.encode!(catalog)}
    cli_auth_credentials_store = "file"
    web_search = "disabled"
    sandbox_mode = "danger-full-access"
    chatgpt_base_url = "http://127.0.0.1:9/backend-api"
    openai_base_url = "http://127.0.0.1:9/v1"
    [features]
    apps = false
    plugins = false
    recommended_plugins = false
    shell_snapshot = false
    [shell_environment_policy]
    inherit = "all"
    [model_providers.fixture]
    name = "Owned synthetic commands only"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = true
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)
  end

  defp client(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    initialize(pid)
    pid
  end

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_command_lifecycle", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )
  end

  defp params(ctx, mode, marker, changes \\ %{}) do
    Map.merge(
      %{
        "command" => [
          ctx.python,
          ctx.script,
          mode,
          marker_path(ctx, marker),
          ctx.ip,
          ctx.parent_netns
        ],
        "cwd" => ctx.workspace,
        "sandboxPolicy" => %{"type" => "dangerFullAccess"},
        "timeoutMs" => 8_000
      },
      changes
    )
  end

  defp exec_async(pid, ctx, mode, marker, changes) do
    request_id = "request-#{marker}"
    params = params(ctx, mode, marker, Map.put_new(changes, "processId", marker))

    task =
      Task.async(fn ->
        Session.request(pid, "command/exec", params, id: request_id, timeout_ms: 10_000)
      end)

    {task, request_id}
  end

  defp final(task, id) do
    assert {:ok, %{"id" => ^id, "result" => result}} = Task.await(task, 10_000)
    result
  end

  defp write(pid, process_id, data, close) do
    params = %{"processId" => process_id, "closeStdin" => close}
    params = if data, do: Map.put(params, "deltaBase64", Base.encode64(data)), else: params
    call(pid, "command/exec/write", params)
  end

  defp terminate(pid, process_id),
    do: call(pid, "command/exec/terminate", %{"processId" => process_id})

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, %Error{wire: wire}} -> flunk("native #{method} failed: #{inspect(wire)}")
      other -> flunk("native #{method} unexpected result: #{inspect(other)}")
    end
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end

  defp marker_path(ctx, name), do: Path.join(ctx.root, "markers/#{name}.json")

  defp assert_marker(ctx, name) do
    path = marker_path(ctx, name)
    assert File.regular?(path)
    marker = path |> File.read!() |> JSON.decode!()
    assert marker["namespace"] != ctx.parent_netns
    assert marker["interfaces"] == ["lo"]
    refute marker["default_route"]
    assert Path.expand(marker["cwd"]) |> String.starts_with?(ctx.workspace)
    marker
  end

  defp assert_gone(ctx, name) do
    marker = marker_path(ctx, name) |> File.read!() |> JSON.decode!()
    await(fn -> not File.exists?("/proc/#{marker["pid"]}") end, "owned command exit")
  end

  defp output_until(pid, process_id, predicate, acc \\ []) do
    events_until(
      pid,
      fn events ->
        predicate.(
          Enum.filter(
            events,
            &(&1.wire["method"] == "command/exec/outputDelta" and
                &1.wire["params"]["processId"] == process_id)
          )
        )
      end,
      acc
    )
  end

  defp events_until(pid, predicate, acc, deadline \\ nil) do
    deadline = deadline || now() + 5_000
    assert {:ok, batch} = Session.drain(pid)

    refute Enum.any?(batch, &(&1.kind == :server_request)),
           "unexpected interaction in local command profile"

    for event <- batch, event.wire["method"] == "command/exec/outputDelta" do
      assert is_binary(event.wire["params"]["processId"])
      assert event.wire["params"]["stream"] in ["stdout", "stderr"]
      assert is_boolean(event.wire["params"]["capReached"])
      assert {:ok, _} = Base.decode64(event.wire["params"]["deltaBase64"])
    end

    events = acc ++ batch

    if predicate.(events) do
      events
    else
      assert now() < deadline, "native command observable barrier deadline"

      receive do
      after
        10 -> :ok
      end

      events_until(pid, predicate, events, deadline)
    end
  end

  defp deltas(events, process_id),
    do:
      for(
        event <- events,
        event.wire["method"] == "command/exec/outputDelta" and
          event.wire["params"]["processId"] == process_id,
        do: event.wire["params"]
      )

  defp output(events, stream),
    do:
      events
      |> Enum.filter(
        &(&1.wire["method"] == "command/exec/outputDelta" and
            &1.wire["params"]["stream"] == stream)
      )
      |> Enum.map_join(&Base.decode64!(&1.wire["params"]["deltaBase64"]))

  defp assert_no_command_output(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] == "command/exec/outputDelta"))
  end

  defp await(predicate, message, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, message

      receive do
      after
        10 -> :ok
      end

      await(predicate, message, deadline)
    end
  end

  defp process_spawn(pid, ctx, handle, name) do
    spawn_params =
      params(ctx, "process-owner", name)
      |> Map.delete("sandboxPolicy")
      |> Map.merge(%{
        "processHandle" => handle,
        "streamStdin" => true,
        "streamStdoutStderr" => true,
        "outputBytesCap" => nil,
        "timeoutMs" => nil
      })

    call(pid, "process/spawn", spawn_params)
  end

  defp process_write(pid, handle, bytes),
    do:
      call(pid, "process/writeStdin", %{
        "processHandle" => handle,
        "deltaBase64" => Base.encode64(bytes)
      })

  defp process_controls do
    [
      {"process/writeStdin", %{"deltaBase64" => Base.encode64(<<0, 255, "unowned">>)}},
      {"process/resizePty", %{"size" => %{"rows" => 2, "cols" => 2}}},
      {"process/kill", %{}}
    ]
  end

  defp process_unknown_controls(pid, handle) do
    for {method, extra} <- process_controls() do
      assert upstream_error(pid, method, Map.put(extra, "processHandle", handle)) == %{
               "code" => -32_600,
               "message" => "no active process for process handle \"#{handle}\""
             }
    end
  end

  defp process_stale_controls(pid, handle) do
    # run_process sends exited and awaits the transport write callback before
    # start's task removes the key (:342-360, :595-607). Seeing exited does not
    # guarantee removal; a closed control channel has a distinct native error
    # (:455-483, :726-734). Both reject control; neither is retried or swallowed.
    for {method, extra} <- process_controls() do
      error = upstream_error(pid, method, Map.put(extra, "processHandle", handle))

      assert error in [
               %{
                 "code" => -32_600,
                 "message" => "no active process for process handle \"#{handle}\""
               },
               %{
                 "code" => -32_600,
                 "message" => "process \"#{handle}\" is no longer running"
               }
             ]
    end
  end

  defp process_initialized(pid) do
    # lib.rs:1238-1251 always sends this after initialize, independently of the
    # response. Consume and validate that observable barrier before any spawn;
    # it is not a process event and must not race with ownership assertions.
    assert [event] =
             events_until(
               pid,
               &Enum.any?(&1, fn event ->
                 event.wire["method"] == "remoteControl/status/changed"
               end),
               []
             )

    assert event.kind == :notification
    assert event.wire["method"] == "remoteControl/status/changed"
    assert is_integer(event.wire["emittedAtMs"]) and event.wire["emittedAtMs"] > 0
    status = event.wire["params"]
    assert Enum.sort(Map.keys(status)) == ~w(environmentId installationId serverName status)
    assert status["status"] == "disabled"
    assert status["environmentId"] == nil
    assert is_binary(status["serverName"]) and status["serverName"] != ""
    assert is_binary(status["installationId"]) and status["installationId"] != ""
    assert call(pid, "remoteControl/status/read", nil) == status
  end

  defp process_ready(pid, handle, name) do
    process_events_until(pid, fn events ->
      process_output(events, "stdout") == "ready-out:#{name}\n" and
        process_output(events, "stderr") == "ready-err:#{name}\n"
    end)
    |> tap(fn events ->
      assert Enum.all?(events, &(&1.wire["params"]["processHandle"] == handle))
      refute Enum.any?(events, &(&1.wire["method"] == "process/exited"))
    end)
  end

  defp process_finished(pid, handle, name, bytes, events) do
    events =
      process_events_until(
        pid,
        &Enum.any?(&1, fn event -> event.wire["method"] == "process/exited" end),
        events
      )

    assert process_output(events, "stdout") == "ready-out:#{name}\nout:#{name}:" <> bytes
    assert process_output(events, "stderr") == "ready-err:#{name}\nerr:#{name}:" <> bytes
    assert Enum.all?(events, &(&1.wire["params"]["processHandle"] == handle))

    assert [exit] =
             for(
               event <- events,
               event.wire["method"] == "process/exited",
               do: event.wire["params"]
             )

    assert exit == %{
             "processHandle" => handle,
             "exitCode" => 0,
             "stdout" => "",
             "stderr" => "",
             "stdoutCapReached" => false,
             "stderrCapReached" => false
           }

    events
  end

  defp process_events_until(pid, predicate, acc \\ []) do
    expected_gap = Session.status(pid).gap
    events = events_until(pid, predicate, acc)

    for event <- events do
      assert event.kind == :notification
      assert event.wire["method"] in ["process/outputDelta", "process/exited"]
      # outgoing_message.rs:905-908 stamps the envelope, not the params.
      assert is_integer(event.wire["emittedAtMs"]) and event.wire["emittedAtMs"] > 0

      if event.wire["method"] == "process/outputDelta" do
        assert event.wire["params"]["stream"] in ["stdout", "stderr"]
        assert event.wire["params"]["capReached"] == false
        assert {:ok, _} = Base.decode64(event.wire["params"]["deltaBase64"])
      end
    end

    assert %{gap: ^expected_gap, uncertain: 0} = Session.status(pid)
    events
  end

  defp process_output(events, stream) do
    events
    |> Enum.filter(
      &(&1.wire["method"] == "process/outputDelta" and
          &1.wire["params"]["stream"] == stream)
    )
    |> Enum.map_join(&Base.decode64!(&1.wire["params"]["deltaBase64"]))
  end

  defp process_no_notices(pid) do
    expected_gap = Session.status(pid).gap
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert {:ok, events} = Session.drain(pid)
    assert events == []
    assert %{gap: ^expected_gap, uncertain: 0} = Session.status(pid)
  end

  defp process_effect(ctx, name),
    do: File.read!(Path.rootname(marker_path(ctx, name)) <> ".input")

  defp process_effect_until(ctx, name, bytes) do
    await(fn -> process_effect(ctx, name) == bytes end, "owned process stdin effect")
  end

  defp now, do: System.monotonic_time(:millisecond)
end
