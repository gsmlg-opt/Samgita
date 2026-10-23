defmodule SamgitaCodexDriver.TransportStdioTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  setup do
    dir =
      Path.join(System.tmp_dir!(), "samgita-codex-stdio-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp opts(dir, script, extra \\ []),
    do:
      Keyword.merge(
        [
          executable: "python3",
          args: ["-u", "-c", script],
          env: %{"CODEX_HOME" => dir, "HOME" => dir}
        ],
        extra
      )

  defp receive_events(state, count, acc \\ []) do
    if length(acc) >= count do
      {acc, state}
    else
      receive do
        message ->
          case Stdio.handle_info(message, state) do
            {:ok, events, next} -> receive_events(next, count, acc ++ events)
            :unknown -> receive_events(state, count, acc)
            error -> flunk("unexpected transport result #{inspect(error)}")
          end
      after
        5_000 -> flunk("stdio transport did not produce expected events")
      end
    end
  end

  test "JSONL split/coalesced framing, stderr isolation and explicit environment", %{dir: dir} do
    script = """
    import os, sys, time
    sys.stderr.write('not-json synthetic-secret\\n' * 10000); sys.stderr.flush()
    sys.stdout.write('{"fragment":'); sys.stdout.flush(); time.sleep(0.03)
    sys.stdout.write('1}\\r\\n{"second":2}\\n'); sys.stdout.flush()
    for line in sys.stdin:
      print(line.strip(), flush=True)
    """

    {:ok, state} = Stdio.open(opts(dir, script))
    on_exit(fn -> Stdio.close(state) end)

    assert {[{:message, ~s({"fragment":1})}, {:message, ~s({"second":2})}], state} =
             receive_events(state, 2)

    assert {:ok, state} = Stdio.send(state, ~s({"id":1}))
    assert {[{:message, ~s({"id":1})}], _} = receive_events(state, 1)
  end

  test "ambient credentials and home are removed unless explicitly supplied", %{dir: dir} do
    name = "SAMGITA_CODEX_SYNTHETIC_SECRET"
    System.put_env(name, "do-not-inherit")
    on_exit(fn -> System.delete_env(name) end)

    script =
      "import os,json,time;print(json.dumps({'secret':os.getenv('#{name}'),'home':os.getenv('HOME'),'codex':os.getenv('CODEX_HOME')}),flush=True);time.sleep(2)"

    {:ok, state} = Stdio.open(opts(dir, script))
    on_exit(fn -> Stdio.close(state) end)
    {[{:message, json}], _} = receive_events(state, 1)
    assert %{"secret" => nil, "home" => ^dir, "codex" => ^dir} = JSON.decode!(json)

    assert {:error, %Error{code: :invalid_transport_options}} =
             Stdio.open(executable: "python3")
  end

  test "oversized partial input and outgoing newlines are explicit failures", %{dir: dir} do
    {:ok, state} = Stdio.open(opts(dir, "import time;time.sleep(3)", max_message_bytes: 8))

    assert {:error, %Error{code: :message_too_large}, ^state} =
             Stdio.send(state, String.duplicate("a", 9))

    assert {:error, %Error{code: :invalid_jsonl_message}, ^state} = Stdio.send(state, "{}\n")

    assert {:error, %Error{code: :message_too_large}, next} =
             Stdio.handle_info({state.port, {:data, String.duplicate("a", 9)}}, state)

    assert next.closed
  end

  test "child final stdout is drained and partial EOF is reported", %{dir: dir} do
    {:ok, state} =
      Stdio.open(opts(dir, "import sys;sys.stdout.write('{}\\npartial');sys.stdout.flush()"))

    {events, _} = receive_events(state, 2)

    assert [{:message, "{}"}, {:closed, %{"exit_status" => 0, "partial_message" => true}}] =
             events
  end

  test "port owner death terminates and reaps owned child and descendants", %{dir: dir} do
    parent = self()
    file = Path.join(dir, "children")

    script = """
    import os,subprocess,time
    child=subprocess.Popen(['python3','-c','import time;time.sleep(60)'])
    open(#{inspect(file)},'w').write(str(os.getpid())+' '+str(child.pid))
    print('{}',flush=True)
    time.sleep(60)
    """

    owner =
      spawn(fn ->
        {:ok, state} = Stdio.open(opts(dir, script))
        send(parent, {:owned_port, state.port})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:owned_port, _port}
    await(fn -> File.exists?(file) end)
    pids = file |> File.read!() |> String.split() |> Enum.map(&String.to_integer/1)
    Process.exit(owner, :kill)
    await(fn -> Enum.all?(pids, &(not process_running?(&1))) end)
  end

  test "close waits for owned child shutdown after explicit close and owner death", %{dir: dir} do
    for scenario <- [:explicit, :owner_down] do
      marker = Path.join(dir, Atom.to_string(scenario))

      script = """
      import signal,time
      def stop(*_args):
        time.sleep(0.2)
        open(#{inspect(marker)},'w').write('stopped')
        raise SystemExit(0)
      signal.signal(signal.SIGTERM,stop)
      print('{}',flush=True)
      while True: time.sleep(1)
      """

      parent = self()

      owner =
        spawn(fn ->
          {:ok, state} = Stdio.open(opts(dir, script))
          {[_ready], state} = receive_events(state, 1)
          send(parent, {:shutdown_fixture, state})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:shutdown_fixture, state}, 5_000
      if scenario == :owner_down, do: Process.exit(owner, :kill)
      assert :ok = Stdio.close(state)
      assert File.read!(marker) == "stopped"
      assert :ok = Stdio.close(state)
      if Process.alive?(owner), do: send(owner, :stop)
    end
  end

  test "close reaps a TERM-ignoring owned descendant before returning", %{dir: dir} do
    ready = Path.join(dir, "descendant-ready")

    script = """
    import os,subprocess,time,json
    grandchild = subprocess.Popen(['python3','-c',
      'import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);open(#{inspect(ready)},"w").close();time.sleep(60)'])
    while not os.path.exists(#{inspect(ready)}): time.sleep(0.01)
    print(json.dumps([os.getpid(),grandchild.pid]),flush=True)
    time.sleep(60)
    """

    {:ok, state} = Stdio.open(opts(dir, script))
    {[{:message, json}], _} = receive_events(state, 1)
    pids = JSON.decode!(json)
    assert :ok = Stdio.close(state)
    assert Enum.all?(pids, &(not process_running?(&1)))
    assert Enum.all?(pids, &(not File.exists?("/proc/#{&1}")))
  end

  test "helper crash remains unconfirmed after its guardian exits", %{dir: dir} do
    marker = Path.join(dir, "orphan-finished")

    script = """
    import os,signal,time
    print('{}',flush=True)
    time.sleep(0.05)
    os.kill(os.getppid(),signal.SIGKILL)
    time.sleep(0.1)
    open(#{inspect(marker)},'w').write('finished')
    """

    {:ok, state} = Stdio.open(opts(dir, script, max_message_bytes: 8))
    {_events, _} = receive_events(state, 2)

    assert {:error, %Error{code: :owned_process_shutdown_unconfirmed}, closed_state} =
             Stdio.handle_info({state.port, {:data, String.duplicate("a", 9)}}, state)

    assert closed_state.closed
    assert closed_state.buffer == <<>>

    for _ <- 1..2 do
      assert_raise Error, "Codex request failed: owned_process_shutdown_unconfirmed", fn ->
        Stdio.close(state)
      end
    end

    await(fn -> File.exists?(marker) end)
  end

  test "helper retains the group leader until its final main-thread signal", %{dir: dir} do
    helper = Path.join(:code.priv_dir(:samgita_codex_driver), "stdio_owner.py")
    marker = Path.join(dir, "group-signals.json")

    script = """
    import importlib.util,json,os,signal,sys,threading
    spec=importlib.util.spec_from_file_location('owned_helper',sys.argv[1])
    helper=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    marker=sys.argv[2]
    original_killpg=os.killpg
    signals=[]
    def checked_killpg(pid,sig):
      assert threading.current_thread() is threading.main_thread()
      # Raises ChildProcessError if the leader was already reaped.
      os.waitid(os.P_PID,pid,os.WEXITED|os.WNOHANG|os.WNOWAIT)
      original_killpg(pid,sig)
      signals.append(int(sig))
    os.killpg=checked_killpg
    source,keep_open=os.pipe()
    os.dup2(source,0)
    sys.argv=['owned_helper',sys.executable,'-c','pass']
    result=helper.main()
    with open(marker,'w') as output: json.dump(signals,output)
    sys.exit(result)
    """

    assert {<<0>>, 0} = System.cmd("python3", ["-c", script, helper, marker])
    assert File.read!(marker) |> JSON.decode!() == [15, 9]
  end

  test "invalid child NUL output cannot become a cleanup acknowledgement", %{dir: dir} do
    {:ok, state} =
      Stdio.open(opts(dir, "import os,time;os.write(1,b'\\0');time.sleep(60)"))

    assert {[{:closed, _}], _} = receive_events(state, 1)
    assert :ok = Stdio.close(state)
  end

  test "close remains bounded when the owned child never reads its input", %{dir: dir} do
    {:ok, state} = Stdio.open(opts(dir, "import time;print('{}',flush=True);time.sleep(60)"))
    {[_ready], state} = receive_events(state, 1)
    assert {:ok, state} = Stdio.send(state, String.duplicate("x", 1_048_576))
    started = System.monotonic_time(:millisecond)
    assert :ok = Stdio.close(state)
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  defp process_running?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} -> not String.contains?(stat, ") Z ")
      {:error, :enoent} -> false
    end
  end

  defp await(fun, tries \\ 100)
  defp await(fun, 0), do: assert(fun.())

  defp await(fun, tries) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(25)
          await(fun, tries - 1)
        )
  end
end
