defmodule SamgitaCodexDriver.ProcessLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    ctx = TurnFixture.setup(tags)
    Map.put(ctx, :session, TurnFixture.start(ctx))
  end

  test "child cwd and inherited environment retain override and unset semantics per spawn", ctx do
    assert :ok = Session.close(ctx.session)

    pid =
      start_with_env(ctx, %{
        "SAMGITA_PROCESS_KEEP" => "server-keep",
        "SAMGITA_PROCESS_OVERRIDE" => "server-override",
        "SAMGITA_PROCESS_UNSET" => "server-unset"
      })

    first_cwd = Path.join(ctx.fixture.workspace, "first-cwd")
    second_cwd = Path.join(ctx.fixture.workspace, "second-cwd")
    File.mkdir_p!(first_cwd)
    File.mkdir_p!(second_cwd)

    command =
      python(ctx, "cwd-env", ~S"""
      import json, os
      observed = {
          "cwd": os.getcwd(),
          "keep": os.getenv("SAMGITA_PROCESS_KEEP"),
          "override": os.getenv("SAMGITA_PROCESS_OVERRIDE"),
          "unset": os.getenv("SAMGITA_PROCESS_UNSET"),
      }
      print(json.dumps(observed, ensure_ascii=False), end="")
      """)

    inherited = %{
      "keep" => "server-keep",
      "override" => "server-override",
      "unset" => "server-unset"
    }

    changed = %{
      "env" => %{
        "SAMGITA_PROCESS_OVERRIDE" => "child-λ",
        "SAMGITA_PROCESS_UNSET" => nil
      }
    }

    for {handle, cwd, changes, expected} <- [
          {"env-inherited", first_cwd, %{}, inherited},
          {"env-changed", second_cwd, changed,
           %{inherited | "override" => "child-λ", "unset" => nil}},
          {"env-inherited-again", first_cwd, %{}, inherited}
        ] do
      params = Map.merge(spawn_params(ctx, handle, command), Map.put(changes, "cwd", cwd))
      assert rpc(pid, "process/spawn", params) == %{}
      events = collect(pid, &exited(&1, handle))
      stdout = exited(events, handle)["stdout"]

      assert JSON.decode!(stdout) == Map.put(expected, "cwd", cwd)
      assert deltas(events, handle) == []
      assert_exit(events, handle, 0, %{"stdout" => stdout})
      assert_no_model_requests(ctx)
    end

    assert :ok = Session.close(pid)
  end

  test "omitted output cap uses the native per-stream MiB default while null retains every byte",
       ctx do
    default_cap = 1024 * 1024

    command =
      python(ctx, "past-output-default", ~S"""
      import sys
      sys.stdout.buffer.write(b"O" * (1024 * 1024 + 13))
      sys.stdout.buffer.flush()
      sys.stderr.buffer.write(b"E" * (1024 * 1024 + 29))
      sys.stderr.buffer.flush()
      """)

    for {handle, changes, stdout_size, stderr_size, capped} <- [
          {"default-output-cap", %{}, default_cap, default_cap, true},
          {"null-output-cap", %{"outputBytesCap" => nil}, default_cap + 13, default_cap + 29,
           false}
        ] do
      assert spawn_process(ctx, handle, command, changes) == %{}
      events = collect(ctx.session, &exited(&1, handle))

      assert deltas(events, handle) == []

      assert_exit(events, handle, 0, %{
        "stdout" => String.duplicate("O", stdout_size),
        "stderr" => String.duplicate("E", stderr_size),
        "stdoutCapReached" => capped,
        "stderrCapReached" => capped
      })

      assert_no_model_requests(ctx)
    end
  end

  test "PTY implies streaming and applies validated initial and resized terminal dimensions",
       ctx do
    pid = ctx.session
    handle = "pty-é"

    command =
      python(ctx, "pty", ~S"""
      import os, sys, tty
      tty.setraw(0)
      def size(label):
          current = os.get_terminal_size(0)
          os.write(1, f"{label}:{current.lines}:{current.columns}\n".encode())
      size("READY")
      while True:
          key = os.read(0, 1)
          if key == b"?":
              size("SIZE")
          elif key == b"q":
              os.write(1, b"out\x00\xff")
              os.write(2, b"err\x00\xfe")
              sys.exit(7)
          elif not key:
              sys.exit(23)
      """)

    assert spawn_process(ctx, handle, command, %{
             "tty" => true,
             "size" => %{"rows" => 24, "cols" => 80},
             "outputBytesCap" => nil,
             "timeoutMs" => nil
           }) == %{}

    events = collect(pid, &(output(&1, handle, "stdout") == "READY:24:80\n"))

    assert rpc_error(pid, "process/resizePty", %{
             "processHandle" => handle,
             "size" => %{"rows" => 0, "cols" => 120}
           }) == %{
             "code" => -32_602,
             "message" => "process size rows and cols must be greater than 0"
           }

    assert rpc(pid, "process/resizePty", %{
             "processHandle" => handle,
             "size" => %{"rows" => 40, "cols" => 120}
           }) == %{}

    write(pid, handle, "?")

    events =
      collect(pid, &(output(&1, handle, "stdout") == "READY:24:80\nSIZE:40:120\n"), events)

    write(pid, handle, "q")
    events = collect(pid, &exited(&1, handle), events)

    assert output(events, handle, "stdout") ==
             "READY:24:80\nSIZE:40:120\n" <> <<"out", 0, 255, "err", 0, 254>>

    assert output(events, handle, "stderr") == ""
    assert_exit(events, handle, 7)
    assert Enum.all?(deltas(events, handle), &(&1["stream"] == "stdout" and !&1["capReached"]))
    assert_no_model_requests(ctx)
  end

  test "stream caps preserve raw bytes independently including zero exact-boundary and null",
       ctx do
    pid = ctx.session
    stdout = <<0, 255, 1, 2, 3, 4>>
    stderr = <<254, 0, 5, 6, 7, 8>>

    command =
      python(ctx, "raw-output", ~S"""
      import os
      os.write(1, b"\x00\xff\x01\x02\x03\x04")
      os.write(2, b"\xfe\x00\x05\x06\x07\x08")
      """)

    for cap <- [0, 3, 6, nil] do
      handle = "stream-cap-#{inspect(cap)}"

      assert spawn_process(ctx, handle, command, %{
               "streamStdoutStderr" => true,
               "outputBytesCap" => cap,
               "timeoutMs" => nil
             }) == %{}

      events = collect(pid, &exited(&1, handle))
      expected_cap = cap != nil
      length = cap || 6
      assert output(events, handle, "stdout") == binary_part(stdout, 0, length)
      assert output(events, handle, "stderr") == binary_part(stderr, 0, length)

      assert_exit(events, handle, 0, %{
        "stdoutCapReached" => expected_cap,
        "stderrCapReached" => expected_cap
      })

      for stream <- ["stdout", "stderr"] do
        chunks = Enum.filter(deltas(events, handle), &(&1["stream"] == stream))
        assert chunks != []
        assert List.last(chunks)["capReached"] == expected_cap
      end
    end

    assert_no_model_requests(ctx)
  end

  test "stdin validation preserves a live binary stream and explicit EOF drains accepted bytes",
       ctx do
    pid = ctx.session
    handle = "binary-stdin"

    command =
      python(ctx, "stdin", ~S"""
      import os, sys
      os.write(1, b"READY\n")
      received = sys.stdin.buffer.read()
      os.write(1, b"ACK:" + received)
      os.write(2, b"EOF")
      """)

    assert spawn_process(ctx, handle, command, %{
             "streamStdin" => true,
             "streamStdoutStderr" => true,
             "outputBytesCap" => nil
           }) == %{}

    events = collect(pid, &(output(&1, handle, "stdout") == "READY\n"))

    assert rpc_error(pid, "process/writeStdin", %{"processHandle" => handle}) == %{
             "code" => -32_602,
             "message" => "process/writeStdin requires deltaBase64 or closeStdin"
           }

    assert rpc_error(pid, "process/writeStdin", %{
             "processHandle" => handle,
             "deltaBase64" => "%%%%"
           }) == %{
             "code" => -32_602,
             "message" => "invalid deltaBase64: Invalid symbol 37, offset 0."
           }

    write(pid, handle, "")
    bytes = <<0, 255, 195, 40, 10, 1>>
    write(pid, handle, bytes)

    assert rpc(pid, "process/writeStdin", %{"processHandle" => handle, "closeStdin" => true}) ==
             %{}

    events = collect(pid, &exited(&1, handle), events)
    assert output(events, handle, "stdout") == "READY\nACK:" <> bytes
    assert output(events, handle, "stderr") == "EOF"
    assert_exit(events, handle, 0)
    assert_no_model_requests(ctx)
  end

  test "non-PTY controls fail explicitly while kill leaves another owned process usable", ctx do
    pid = ctx.session

    blocked =
      python(ctx, "blocked", ~S"""
      import os, signal
      os.write(1, b"BLOCKED\n")
      signal.pause()
      """)

    survivor =
      python(ctx, "survivor", ~S"""
      import os
      os.write(1, b"SURVIVOR\n")
      received = os.read(0, 1)
      os.write(1, b"RECEIVED:" + received)
      """)

    assert spawn_process(ctx, "selected", blocked, %{"streamStdoutStderr" => true}) == %{}

    assert spawn_process(ctx, "survivor", survivor, %{
             "streamStdin" => true,
             "streamStdoutStderr" => true
           }) == %{}

    events =
      collect(pid, fn events ->
        output(events, "selected", "stdout") == "BLOCKED\n" and
          output(events, "survivor", "stdout") == "SURVIVOR\n"
      end)

    assert rpc_error(pid, "process/writeStdin", %{
             "processHandle" => "selected",
             "closeStdin" => true
           }) == %{
             "code" => -32_600,
             "message" => "stdin streaming is not enabled for this process"
           }

    assert rpc_error(pid, "process/resizePty", %{
             "processHandle" => "selected",
             "size" => %{"rows" => 20, "cols" => 60}
           }) == %{
             "code" => -32_600,
             "message" => "failed to resize PTY: process is not attached to a PTY"
           }

    assert rpc(pid, "process/kill", %{"processHandle" => "selected"}) == %{}
    events = collect(pid, &exited(&1, "selected"), events)
    refute exited(events, "selected")["exitCode"] == 0
    refute exited(events, "survivor")
    write(pid, "survivor", "X")
    events = collect(pid, &exited(&1, "survivor"), events)
    assert output(events, "survivor", "stdout") == "SURVIVOR\nRECEIVED:X"
    assert_exit(events, "survivor", 0)

    # Reuse is explicit after terminal notification, never an automatic retry.
    command = [Path.join(ctx.fixture.bin, "sh"), "-c", "printf reused; exit 19"]
    assert spawn_process(ctx, "selected", command) == %{}
    reused = collect(pid, &exited(&1, "selected"))
    assert_exit(reused, "selected", 19, %{"stdout" => "reused"})
    assert_no_model_requests(ctx)
  end

  test "spawn validation and exec failure retain correlation and release only failed reservations",
       ctx do
    pid = ctx.session
    command = [Path.join(ctx.fixture.bin, "sh"), "-c", "printf recovered; exit 17"]
    params = spawn_params(ctx, "recoverable", command)

    for {changes, expected} <- [
          {%{"command" => []}, %{"code" => -32_600, "message" => "command must not be empty"}},
          {%{"processHandle" => ""},
           %{"code" => -32_600, "message" => "processHandle must not be empty"}},
          {%{"size" => %{"rows" => 1, "cols" => 1}},
           %{"code" => -32_602, "message" => "process/spawn size requires tty: true"}},
          {%{"timeoutMs" => -1},
           %{
             "code" => -32_602,
             "message" => "process/spawn timeoutMs must be non-negative, got -1"
           }},
          {%{"tty" => true, "size" => %{"rows" => 1, "cols" => 0}},
           %{"code" => -32_602, "message" => "process size rows and cols must be greater than 0"}}
        ] do
      assert rpc_error(pid, "process/spawn", Map.merge(params, changes)) == expected
    end

    failed = Map.put(params, "command", [Path.join(ctx.fixture.workspace, "missing-executable")])
    error = rpc_error(pid, "process/spawn", failed)
    assert error["code"] == -32_603
    assert error["message"] =~ "failed to spawn process:"
    assert error["message"] =~ "No such file or directory"
    assert rpc(pid, "process/spawn", params) == %{}
    events = collect(pid, &exited(&1, "recoverable"))
    assert_exit(events, "recoverable", 17, %{"stdout" => "recovered"})

    for {method, extra} <- [
          {"process/kill", %{}},
          {"process/writeStdin", %{"deltaBase64" => ""}},
          {"process/resizePty", %{"size" => %{"rows" => 10, "cols" => 10}}}
        ] do
      assert rpc_error(pid, method, Map.put(extra, "processHandle", "never-created")) == %{
               "code" => -32_600,
               "message" => "no active process for process handle \"never-created\""
             }
    end

    assert_no_model_requests(ctx)
  end

  test "an explicit finite timeout reports native exit 124 without relaunching the process",
       ctx do
    handle = "finite-timeout"
    command = [Path.join(ctx.fixture.bin, "sh"), "-c", "read value"]

    assert spawn_process(ctx, handle, command, %{"streamStdin" => true, "timeoutMs" => 50}) == %{}
    events = collect(ctx.session, &exited(&1, handle))
    assert_exit(events, handle, 124)
    assert Enum.count(events, &(&1.wire["method"] == "process/exited")) == 1
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(ctx.session)
    assert_no_model_requests(ctx)
  end

  defp start_with_env(ctx, env) do
    tmp = Path.join(ctx.root, "process-env-tmp")
    File.mkdir_p!(tmp)

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env:
               Map.merge(
                 %{
                   "HOME" => ctx.fixture.home,
                   "CODEX_HOME" => ctx.fixture.codex_home,
                   "TMPDIR" => tmp,
                   "SHELL" => Path.join(ctx.fixture.bin, "sh"),
                   "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                   "PATH" => ctx.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
                   "NO_COLOR" => "1",
                   "RUST_LOG" => "off"
                 },
                 env
               )
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_process_env_fixture", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp python(ctx, name, source) do
    executable = System.find_executable("python3")

    assert is_binary(executable),
           "BLOCKED_ENV: Python 3 required for owned native process fixtures"

    script = Path.join(ctx.fixture.workspace, name <> ".py")
    File.write!(script, source)
    [executable, "-I", "-u", script]
  end

  defp spawn_process(ctx, handle, command, extra \\ %{}),
    do: rpc(ctx.session, "process/spawn", Map.merge(spawn_params(ctx, handle, command), extra))

  defp spawn_params(ctx, handle, command),
    do: %{"processHandle" => handle, "cwd" => ctx.fixture.workspace, "command" => command}

  defp write(pid, handle, bytes) do
    assert rpc(pid, "process/writeStdin", %{
             "processHandle" => handle,
             "deltaBase64" => Base.encode64(bytes)
           }) == %{}
  end

  defp rpc(pid, method, params) do
    id = "process-request-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    result
  end

  defp rpc_error(pid, method, params) do
    id = System.unique_integer([:positive])

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    error
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000
    assert {:ok, events} = Session.drain(pid)

    for event <- events do
      refute event.kind == :server_request or event.wire["method"] == "error"

      if event.wire["method"] in ["process/outputDelta", "process/exited"] do
        assert is_integer(event.wire["emittedAtMs"]) and event.wire["emittedAtMs"] > 0
      end
    end

    acc = acc ++ events

    if predicate.(acc) do
      acc
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, acc, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected native process event gap")
      after
        remaining -> flunk("native process event deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp deltas(events, handle) do
    for event <- events,
        event.wire["method"] == "process/outputDelta",
        event.wire["params"]["processHandle"] == handle,
        do: event.wire["params"]
  end

  defp output(events, handle, stream),
    do:
      events
      |> deltas(handle)
      |> Enum.filter(&(&1["stream"] == stream))
      |> Enum.map_join(&Base.decode64!(&1["deltaBase64"]))

  defp exited(events, handle),
    do: TurnFixture.notification(events, "process/exited", &(&1["processHandle"] == handle))

  defp assert_exit(events, handle, code, overrides \\ %{}) do
    assert exited(events, handle) ==
             Map.merge(
               %{
                 "processHandle" => handle,
                 "exitCode" => code,
                 "stdout" => "",
                 "stderr" => "",
                 "stdoutCapReached" => false,
                 "stderrCapReached" => false
               },
               overrides
             )

    assert Enum.count(events, fn event ->
             event.wire["method"] == "process/exited" and
               event.wire["params"]["processHandle"] == handle
           end) == 1
  end

  defp assert_no_model_requests(ctx), do: assert(ModelFixture.requests(ctx.fixture) == [])
end
