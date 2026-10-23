defmodule SamgitaCodexDriver.TransportStdioTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Failure

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

    assert {:error, %Failure{code: :invalid_transport_options}} =
             Stdio.open(executable: "python3")
  end

  test "oversized partial input and outgoing newlines are explicit failures", %{dir: dir} do
    {:ok, state} = Stdio.open(opts(dir, "import time;time.sleep(3)", max_message_bytes: 8))

    assert {:error, %Failure{code: :message_too_large}, ^state} =
             Stdio.send(state, String.duplicate("a", 9))

    assert {:error, %Failure{code: :invalid_jsonl_message}, ^state} = Stdio.send(state, "{}\n")

    assert {:error, %Failure{code: :message_too_large}, next} =
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
