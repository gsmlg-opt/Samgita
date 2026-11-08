defmodule Samgita.CodexHostsSshTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{CodexHosts, FakeCodexServer, Principal}
  alias Samgita.CodexHosts.{Runtime, Ssh}

  @known_hosts "127.0.0.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

  # Stands in for OpenSSH: records argv and the identity file mode, runs
  # `daemon start` as a no-op, and relays `app-server proxy` stdio to the fake
  # app-server at 127.0.0.1:<-p port>.
  defp fake_ssh(dir, opts \\ []) do
    log = Path.join(dir, "ssh.log")
    daemon_exit = Keyword.get(opts, :daemon_exit, 0)
    script = Path.join(dir, "fake-ssh")

    File.write!(script, """
    #!#{System.find_executable("python3")} -I
    import json, os, socket, stat, sys, threading
    argv = sys.argv[1:]
    record = {"argv": argv, "env": sorted(os.environ.keys())}
    if "-i" in argv:
        key = argv[argv.index("-i") + 1]
        record["key_mode"] = oct(stat.S_IMODE(os.stat(key).st_mode))
    kh = [a for a in argv if a.startswith("UserKnownHostsFile=")][0].split("=", 1)[1]
    record["known_hosts"] = open(kh).read()
    with open(#{inspect(log)}, "a") as f:
        f.write(json.dumps(record) + "\\n")
    command = argv[-1]
    if "'daemon'" in command:
        sys.exit(#{daemon_exit})
    port = int(argv[argv.index("-p") + 1])
    s = socket.create_connection(("127.0.0.1", port))
    def pump_in():
        while True:
            data = os.read(0, 65536)
            if not data:
                os._exit(0)
            s.sendall(data)
    threading.Thread(target=pump_in, daemon=True).start()
    while True:
        data = s.recv(65536)
        if not data:
            break
        os.write(1, data)
    """)

    File.chmod!(script, 0o755)
    {script, log}
  end

  defp calls(log) do
    if File.exists?(log),
      do: log |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1),
      else: []
  end

  setup do
    server = FakeCodexServer.start()
    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})
    dir = Path.join(System.tmp_dir!(), "samgita-ssh-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {script, log} = fake_ssh(dir)

    previous = Application.get_env(:samgita, :codex_hosts)
    previous_secrets = Application.get_env(:samgita, :codex_host_secrets)

    Application.put_env(
      :samgita,
      :codex_hosts,
      previous |> Keyword.put(:enabled, true) |> Keyword.put(:ssh_executable, script)
    )

    Phoenix.PubSub.subscribe(Samgita.PubSub, Runtime.topic())

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      Application.put_env(:samgita, :codex_hosts, previous)
      Application.put_env(:samgita, :codex_host_secrets, previous_secrets || %{})
      FakeCodexServer.stop(server)
      File.rm_rf!(dir)
    end)

    %{server: server, agent: agent, dir: dir, log: log}
  end

  defp configure(agent, server, attrs \\ %{}) do
    CodexHosts.configure(
      Principal.operator(),
      command(
        Map.merge(
          %{
            "agent_id" => agent["id"],
            "transport" => "ssh",
            "ssh_host" => "127.0.0.1",
            "ssh_port" => server.port,
            "ssh_user" => "codex",
            "known_hosts" => @known_hosts
          },
          attrs
        )
      )
    )
  end

  defp enable(host),
    do:
      CodexHosts.enable(
        Principal.operator(),
        host["id"],
        command(%{"expected_version" => host["version"]})
      )

  defp disable(id) do
    {:ok, host} = CodexHosts.get(Principal.operator(), id)

    CodexHosts.disable(
      Principal.operator(),
      id,
      command(%{"expected_version" => host["version"]})
    )
  end

  defp await_status(id, state, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex_host_status, ^id, %{"state" => ^state} = status} -> status
      {:codex_host_status, ^id, _} -> await_status(id, state, deadline)
    after
      wait -> flunk("host did not reach #{state}; now #{inspect(Runtime.status(id))}")
    end
  end

  test "validates SSH settings and stores no secret material", %{agent: agent, server: server} do
    for attrs <- [
          %{"known_hosts" => nil},
          %{"known_hosts" => "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n"},
          %{"known_hosts" => "@cert-authority * ssh-ed25519 AAAA"},
          %{"ssh_host" => "-oProxyCommand=evil"},
          %{"ssh_host" => "host name"},
          %{"ssh_user" => "root;id"},
          %{"ssh_port" => 70_000},
          %{"remote_codex_path" => "codex; rm -rf /"},
          %{"remote_socket_path" => "$(id)"},
          %{"ssh_key_ref" => "bad ref"},
          %{"private_key" => "secret"}
        ] do
      assert {:error, %{code: :invalid}} = configure(agent, server, attrs),
             "accepted #{inspect(attrs)}"
    end

    assert {:ok, host} = configure(agent, server, %{"ssh_key_ref" => "codex/ssh-v1"})
    assert host["transport"] == "ssh"
    assert host["ssh_key_ref"] == "codex/ssh-v1"
    assert host["url"] == nil
  end

  test "connects through the SSH proxy command with strict, forwarding-free options",
       %{agent: agent, server: server, log: log} do
    System.put_env("SAMGITA_LEAK_PROBE", "1")
    on_exit(fn -> System.delete_env("SAMGITA_LEAK_PROBE") end)
    {:ok, host} = configure(agent, server, %{"remote_socket_path" => "/run/codex/app.sock"})
    {:ok, _} = enable(host)

    status = await_status(host["id"], "connected")
    assert status["server_version"] == "0.167.0"
    assert status["generation"] == 1

    assert [%{"argv" => argv, "env" => env, "known_hosts" => known_hosts}] = calls(log)

    for option <-
          ~w(BatchMode=yes StrictHostKeyChecking=yes GlobalKnownHostsFile=/dev/null ClearAllForwardings=yes ControlPath=none),
        do: assert(option in argv, "missing #{option}")

    assert ["-F", "/dev/null"] == Enum.slice(argv, Enum.find_index(argv, &(&1 == "-F")), 2)
    assert "-a" in argv and "-x" in argv and "-T" in argv
    assert Enum.slice(argv, Enum.find_index(argv, &(&1 == "-l")), 2) == ["-l", "codex"]

    assert Enum.take(argv, -3) == [
             "--",
             "127.0.0.1",
             "'codex' 'app-server' 'proxy' '--sock' '/run/codex/app.sock'"
           ]

    assert known_hosts == @known_hosts <> "\n"

    # Interpreter/OS-injected names (LC_CTYPE, __CF_USER_TEXT_ENCODING) are allowed.
    refute "SAMGITA_LEAK_PROBE" in env
    assert env -- ~w(HOME LANG PATH SSH_AUTH_SOCK LC_CTYPE __CF_USER_TEXT_ENCODING) == []

    private_dir =
      argv |> Enum.find(&String.starts_with?(&1, "UserKnownHostsFile=")) |> Path.dirname()

    private_dir = String.replace_prefix(private_dir, "UserKnownHostsFile=", "")
    assert File.dir?(private_dir)

    {:ok, _} = disable(host["id"])
    await_status(host["id"], "stopped")
    refute File.exists?(private_dir)
  end

  test "a private key from a credential reference exists only during the connection",
       %{agent: agent, server: server, log: log} do
    Application.put_env(:samgita, :codex_host_secrets, %{
      "codex/ssh-v1" =>
        "-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----"
    })

    {:ok, host} = configure(agent, server, %{"ssh_key_ref" => "codex/ssh-v1"})
    {:ok, _} = enable(host)
    await_status(host["id"], "connected")

    assert [%{"argv" => argv, "key_mode" => "0o600", "env" => env}] = calls(log)
    key = Enum.at(argv, Enum.find_index(argv, &(&1 == "-i")) + 1)
    assert "IdentitiesOnly=yes" in argv
    assert "IdentityAgent=none" in argv
    refute "SSH_AUTH_SOCK" in env
    assert File.exists?(key)

    {:ok, _} = disable(host["id"])
    await_status(host["id"], "stopped")
    refute File.exists?(key)

    events = Repo.all(from e in Samgita.Domain.DomainEvent, where: e.resource_id == ^host["id"])
    refute inspect(events) =~ "PRIVATE KEY"
  end

  test "a missing key reference never invokes ssh", %{agent: agent, server: server, log: log} do
    {:ok, host} = configure(agent, server, %{"ssh_key_ref" => "codex/missing-v1"})
    {:ok, _} = enable(host)

    assert %{"error" => "credential_unavailable"} = await_status(host["id"], "backoff")
    assert calls(log) == []
  end

  test "ensure_daemon starts the remote daemon before the proxy session",
       %{agent: agent, server: server, log: log} do
    {:ok, host} = configure(agent, server, %{"ensure_daemon" => true})
    {:ok, _} = enable(host)
    await_status(host["id"], "connected")

    assert [daemon, proxy] = calls(log)
    assert List.last(daemon["argv"]) == "'codex' 'app-server' 'daemon' 'start'"
    assert List.last(proxy["argv"]) == "'codex' 'app-server' 'proxy'"
  end

  test "a failed daemon start backs off and cleans up", %{agent: agent, server: server, dir: dir} do
    {script, log} = fake_ssh(Path.join(dir, "failing") |> tap(&File.mkdir_p!/1), daemon_exit: 1)
    config = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(config, :ssh_executable, script))

    {:ok, host} =
      configure(agent, server, %{
        "ensure_daemon" => true,
        "remote_codex_path" => "/opt/codex/bin/codex"
      })

    {:ok, _} = enable(host)

    assert %{"error" => "daemon_start_failed"} = await_status(host["id"], "backoff")
    [call | _] = calls(log)
    assert List.last(call["argv"]) == "'/opt/codex/bin/codex' 'app-server' 'daemon' 'start'"

    private_dir =
      call["argv"]
      |> Enum.find(&String.starts_with?(&1, "UserKnownHostsFile="))
      |> String.replace_prefix("UserKnownHostsFile=", "")
      |> Path.dirname()

    refute File.exists?(private_dir)
  end

  test "an initialize failure closes the session instead of leaking it", %{agent: agent} do
    server = FakeCodexServer.start(initialize: :error)
    on_exit(fn -> FakeCodexServer.stop(server) end)

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{"agent_id" => agent["id"], "transport" => "websocket", "url" => server.url})
      )

    {:ok, _} = enable(host)
    assert_receive {:fake_codex, :request, "initialize"}, 3_000
    assert %{"error" => _} = await_status(host["id"], "backoff")
    assert_receive {:fake_codex, :closed}, 3_000
  end

  test "remote command words are shell-quoted" do
    host = %{remote_codex_path: "/opt/it's/codex"}

    assert Ssh.remote_command(host, ["app-server", "proxy"]) ==
             "'/opt/it'\\''s/codex' 'app-server' 'proxy'"
  end
end
