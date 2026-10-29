defmodule StandaloneCodex.StartCleanupTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaProtocolCodex.Error

  @moduletag timeout: 15_000

  test "scripted initialization failure closes its owned peer before start returns" do
    assert {:unix, :linux} = :os.type()
    python = System.find_executable("python3")
    assert is_binary(python), "Python 3 is required for the scripted cleanup peer"

    root =
      Path.join(
        System.tmp_dir!(),
        "standalone-start-cleanup-#{System.unique_integer([:positive, :monotonic])}"
      )

    [home, codex_home, workspace] =
      for name <- ~w(home codex workspace) do
        path = Path.join(root, name)
        File.mkdir_p!(path)
        path
      end

    executable = Path.join(root, "scripted-peer")
    pid_file = Path.join(codex_home, "scripted-peer.pid")

    # This is a local scripted app-server peer, not actual Codex evidence.
    File.write!(executable, """
    #!#{python}
    import json, os, pathlib, sys

    pathlib.Path(os.environ["CODEX_HOME"], "scripted-peer.pid").write_text(str(os.getpid()))
    request = json.loads(sys.stdin.readline())
    print(json.dumps({"id": request["id"], "error": {
        "code": -32000, "message": "Owned scripted initialization failure"
    }}), flush=True)
    for line in sys.stdin:
        pass
    """)

    File.chmod!(executable, 0o700)
    parent = self()

    # Keep the caller alive after start returns: caller death must not conceal
    # a leaked Session. Only this caller creates linked sessions in this test.
    {caller, monitor} =
      spawn_monitor(fn ->
        parent_monitor = Process.monitor(parent)

        try do
          result = StandaloneCodex.start(executable, home, codex_home, workspace)
          send(parent, {:scripted_start_result, self(), result})

          receive do
            :cleanup -> :ok
            {:DOWN, ^parent_monitor, :process, ^parent, _reason} -> :ok
          end
        after
          {:links, sessions} = Process.info(self(), :links)

          for session <- sessions, is_pid(session), Process.alive?(session) do
            assert :ok = Session.close(session)
          end
        end
      end)

    on_exit(fn ->
      cleanup_monitor = Process.monitor(caller)
      send(caller, :cleanup)

      assert_receive {:DOWN, ^cleanup_monitor, :process, ^caller, reason}, 6_000
      assert reason in [:normal, :noproc]

      if File.exists?(pid_file) do
        peer_pid = pid_file |> File.read!() |> String.to_integer()
        refute File.exists?("/proc/#{peer_pid}"), "scripted peer cleanup was not confirmed"
      end

      File.rm_rf!(root)
    end)

    assert_receive {:scripted_start_result, ^caller,
                    {:error, %Error{code: :upstream_error, wire: wire}}},
                   5_000

    assert wire["error"] === %{
             "code" => -32_000,
             "message" => "Owned scripted initialization failure"
           }

    assert Process.alive?(caller)
    peer_pid = pid_file |> File.read!() |> String.to_integer()
    assert peer_pid > 0

    refute File.exists?("/proc/#{peer_pid}"),
           "start returned its initialization error before closing its owned peer"

    refute_receive {:DOWN, ^monitor, :process, ^caller, _reason}, 0
  end
end
