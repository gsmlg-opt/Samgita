defmodule SamgitaCodexDriver.NativeCommandControlValuesTest do
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
  @script Path.expand("../../../scripts/codex/command_control_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @methods ~w(command/exec command/exec/resize command/exec/write command/exec/terminate)
  @input "Owned command stdin λ\n"

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

      if wire["method"] in ~w(command/exec command/exec/resize command/exec/write command/exec/terminate) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 4096 do
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
    assert is_binary(python), "BLOCKED_ENV: Python 3 required for owned native commands"
    assert File.regular?(@script), "BLOCKED_ENV: owned command fixture missing"
    script = Path.join(ctx.fixture.workspace, "owned_command_control.py")
    File.cp!(@script, script)
    capture = start_supervised!({Agent, fn -> [] end})
    records = Path.join(ctx.root, "command-control-records.json")
    File.write!(records, "[]")

    Map.merge(ctx, %{
      python: python,
      script: script,
      script_bytes: File.read!(script),
      capture: capture,
      records: records
    })
  end

  test "null PTY size, native resize, stdin and selected termination have real child effects",
       ctx do
    {pid, native} = start(ctx)
    terminal = child(ctx, "pty", "owned-terminal")
    waiter = child(ctx, "wait", "owned-waiter")
    terminal_wire = exec_wire(terminal, %{"tty" => true, "size" => nil})
    terminal_task = begin_exec(pid, terminal_wire)
    events = ready(pid, terminal, [])
    terminal_identity = identity(terminal)
    assert terminal_identity["rows"] == 24
    assert terminal_identity["cols"] == 80

    resize_wire =
      wire("command/exec/resize", "resize-owned-terminal", %{
        "processId" => terminal.handle,
        "size" => %{"rows" => 45, "cols" => 132}
      })

    assert rpc(pid, resize_wire) == %{}

    write_wire =
      wire("command/exec/write", "write-owned-terminal", %{
        "processId" => terminal.handle,
        "deltaBase64" => Base.encode64(@input),
        "closeStdin" => false
      })

    assert rpc(pid, write_wire) == %{}

    events =
      collect(
        pid,
        &String.contains?(output(&1, terminal.handle, "stdout"), "RESULT:"),
        events
      )

    assert_final(terminal_task, terminal_wire["id"], 0)
    # The native server sends every output notification before the final reply.
    events = drain(pid, events)

    expected = %{
      "handle" => terminal.handle,
      "pid" => terminal_identity["pid"],
      "rows" => 45,
      "cols" => 132,
      "inputBase64" => Base.encode64(@input)
    }

    assert JSON.decode!(File.read!(terminal.result)) === expected

    assert ["READY:" <> terminal_handle, "RESULT:" <> result, ""] =
             String.split(output(events, terminal.handle, "stdout"), "\n")

    assert terminal_handle == terminal.handle
    assert JSON.decode!(result) === expected
    assert output(events, terminal.handle, "stderr") == ""
    await_gone(terminal)

    waiter_wire =
      exec_wire(waiter, %{
        "streamStdin" => true,
        "streamStdoutStderr" => true
      })

    waiter_task = begin_exec(pid, waiter_wire)
    events = ready(pid, waiter, events)
    refute File.exists?(waiter.result)

    terminate_wire =
      wire("command/exec/terminate", "terminate-owned-waiter", %{
        "processId" => waiter.handle
      })

    assert rpc(pid, terminate_wire) == %{}
    # Pinned Linux pipe terminator uses SIGKILL; status maps to 128 + signal.
    assert_final(waiter_task, waiter_wire["id"], 137)
    events = drain(pid, events)
    assert output(events, waiter.handle, "stdout") == "READY:#{waiter.handle}\n"
    assert output(events, waiter.handle, "stderr") == ""
    refute File.exists?(waiter.result)
    await_gone(waiter)

    assert Agent.get(ctx.capture, & &1) === [
             terminal_wire,
             resize_wire,
             write_wire,
             waiter_wire,
             terminate_wire
           ]

    assert File.read!(ctx.script) === ctx.script_bytes
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.read!(ctx.fixture.requests) == "[]"
    assert call(pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp child(ctx, mode, handle) do
    record = Path.join(ctx.root, handle <> "-identity.json")
    result = Path.join(ctx.root, handle <> "-result.json")
    registered = JSON.decode!(File.read!(ctx.records))
    File.write!(ctx.records, JSON.encode!(registered ++ [record]))

    %{
      handle: handle,
      mode: mode,
      cwd: ctx.fixture.workspace,
      script: ctx.script,
      record: record,
      result: result,
      command: [ctx.python, "-I", "-u", ctx.script, mode, handle, record, result]
    }
  end

  defp exec_wire(child, extra) do
    params = %{
      "command" => child.command,
      "processId" => child.handle,
      "cwd" => child.cwd,
      "timeoutMs" => 15_000
    }

    wire("command/exec", "exec-" <> child.handle, Map.merge(params, extra))
  end

  defp wire(method, id, params) when method in @methods,
    do: %{"id" => id, "method" => method, "params" => params}

  defp begin_exec(pid, wire) do
    Task.async(fn -> Session.request_native(pid, wire, timeout_ms: 20_000) end)
  end

  defp assert_final(task, id, exit_code) do
    assert {:ok, %{"id" => ^id, "result" => result}} = Task.await(task, 20_000)
    assert result === %{"exitCode" => exit_code, "stdout" => "", "stderr" => ""}
  end

  defp rpc(pid, %{"id" => id} = wire) do
    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    result
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params, timeout_ms: 5_000)
    result
  end

  defp ready(pid, child, events) do
    events =
      collect(pid, &String.contains?(output(&1, child.handle, "stdout"), "\n"), events)

    assert output(events, child.handle, "stdout") == "READY:#{child.handle}\n"
    marker = identity(child)
    assert marker["handle"] == child.handle
    assert marker["mode"] == child.mode
    assert marker["cwd"] == child.cwd
    assert marker["script"] == child.script
    assert is_integer(marker["pid"]) and marker["pid"] > 0
    assert is_binary(marker["start"]) and marker["start"] != ""
    assert File.exists?("/proc/#{marker["pid"]}")
    events
  end

  defp identity(child), do: JSON.decode!(File.read!(child.record))

  defp collect(pid, predicate, events, until \\ nil) do
    until = until || deadline()
    events = drain(pid, events)

    if predicate.(events) do
      events
    else
      remaining = max(until - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, events, until)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native command event gap")
      after
        remaining -> flunk("Native command I/O deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp drain(pid, events) do
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch
    assert length(events) <= 128, "Native command event bound exceeded"

    assert Enum.sum(Enum.map(events, &byte_size(JSON.encode!(&1.wire)))) <= 65_536,
           "Native command byte bound exceeded"

    assert %{phase: :ready, gap: nil} = Session.status(pid)

    for event <- batch, event.wire["method"] == "command/exec/outputDelta" do
      params = event.wire["params"]
      assert params["processId"] in ["owned-terminal", "owned-waiter"]
      assert params["stream"] in ["stdout", "stderr"]
      assert params["capReached"] === false
      assert {:ok, _} = Base.decode64(params["deltaBase64"])
    end

    events
  end

  defp output(events, handle, stream) do
    events
    |> Enum.filter(fn event ->
      event.wire["method"] == "command/exec/outputDelta" and
        event.wire["params"]["processId"] == handle and event.wire["params"]["stream"] == stream
    end)
    |> Enum.map_join(&Base.decode64!(&1.wire["params"]["deltaBase64"]))
  end

  defp await_gone(child, until \\ nil) do
    until = until || deadline()
    marker = identity(child)

    if File.exists?("/proc/#{marker["pid"]}") do
      assert System.monotonic_time(:millisecond) < until, "Owned command was not reaped"

      receive do
      after
        10 -> await_gone(child, until)
      end
    end
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> cleanup(ctx, pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_command_control_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {pid, native}
  end

  defp cleanup(ctx, pid, connection) do
    StdioSessionFixture.close(pid, connection)
  after
    for record <- JSON.decode!(File.read!(ctx.records)) do
      assert {"", 0} = System.cmd(ctx.python, ["-I", ctx.script, "--cleanup", record])
    end
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
