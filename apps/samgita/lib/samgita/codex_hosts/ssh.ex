defmodule Samgita.CodexHosts.Ssh do
  @moduledoc """
  Builds the OpenSSH command that reaches a Codex app-server daemon through
  `codex app-server proxy` (design §11).

  The command uses a fixed argument list (never a shell string on this side),
  `BatchMode`, strict host-key checking against a private known-hosts file
  written from the host's configuration, no forwarding and a minimal
  environment. A private key comes from a credential reference and exists only
  in a private directory for the lifetime of one connection.

  Like the Codex desktop app, the remote command runs in the remote user's
  login shell (`$SHELL -l -i`), so profile-managed PATH entries resolve, and
  `${CODEX_INSTALL_DIR:-$HOME/.local/bin}` is prepended to PATH. A login shell
  may print banners, so the proxy session first prints a random per-connection
  marker and the transport discards stdout before it.

  With `use_ssh_config`, the operator chose to run OpenSSH like their own
  terminal does: their `~/.ssh/config` (host aliases, users, ports, key files,
  proxies), their known_hosts and their environment. Batch mode, strict
  host-key checking, no forwarding and no connection sharing still apply.
  """

  @ensure_daemon_timeout 30_000

  # Runs `$1` with /bin/sh inside the remote user's login shell. Mirrors the
  # Codex desktop app launcher, including csh/tcsh, nu, fish and xonsh.
  @launcher String.trim(~S"""
            if [ -z "$SHELL" ] || [ ! -x "$SHELL" ]; then echo "Codex remote SSH requires SHELL to point to an executable login shell" >&2; exit 127; fi; SAMGITA_REMOTE_PAYLOAD="$1"; export SAMGITA_REMOTE_PAYLOAD; case "${SHELL##*/}" in csh|tcsh) exec "$SHELL" -i -c 'set loginsh=1; if ( -r /etc/csh.login ) source /etc/csh.login; if ( -r ~/.login ) source ~/.login; exec /bin/sh -c "$SAMGITA_REMOTE_PAYLOAD"' ;; nu) exec "$SHELL" -l -i -c 'exec /bin/sh -c $env.SAMGITA_REMOTE_PAYLOAD' ;; fish|xonsh) exec "$SHELL" -l -i -c 'exec /bin/sh -c "$SAMGITA_REMOTE_PAYLOAD"' ;; *) exec "$SHELL" -l -i -c 'CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"; export CODEX_HOME; exec /bin/sh -c "$SAMGITA_REMOTE_PAYLOAD"' ;; esac
            """)

  @doc """
  Prepare private files and transport options. The caller must `cleanup/1` the
  result; if the caller dies first (even by a kill that skips `after` and
  `terminate`), a watcher removes the private directory.
  """
  def prepare(host) do
    with {:ok, ssh} <- executable(),
         {:ok, key} <- key(host.ssh_key_ref),
         {:ok, dir} <- private_dir() do
      guard = guard(dir)

      known_hosts =
        if host.known_hosts do
          path = Path.join(dir, "known_hosts")
          write_private!(path, normalize(host.known_hosts))
          path
        end

      key_file =
        if key do
          path = Path.join(dir, "identity")
          write_private!(path, normalize(key))
          path
        end

      base = options(host, known_hosts, key_file)
      env = env(host, dir, key_file)
      marker = "samgita-ready:" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      {:ok,
       %{
         dir: dir,
         guard: guard,
         executable: ssh,
         base_args: base,
         env: env,
         transport: [
           executable: ssh,
           args:
             base ++ [remote_command(host, ["app-server", "proxy"] ++ socket_args(host), marker)],
           env: env,
           stdout_marker: marker
         ]
       }}
    end
  end

  @doc "Run `codex app-server daemon start` remotely before the proxy session."
  def ensure_daemon(host, prepared) do
    args = prepared.base_args ++ [remote_command(host, ["app-server", "daemon", "start"])]
    env = Enum.map(clear_env(prepared.env), fn {name, value} -> {name, value} end)

    task =
      Task.async(fn ->
        System.cmd(prepared.executable, args, env: env, stderr_to_stdout: true)
      end)

    case Task.yield(task, @ensure_daemon_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0}} -> :ok
      _ -> {:error, :daemon_start_failed}
    end
  end

  def cleanup(nil), do: :ok

  def cleanup(%{dir: dir, guard: guard}) do
    send(guard, :release)
    File.rm_rf(dir)
    :ok
  end

  # Unlinked on purpose: it must outlive an owner that is killed.
  defp guard(dir) do
    owner = self()

    spawn(fn ->
      ref = Process.monitor(owner)

      receive do
        :release -> :ok
        {:DOWN, ^ref, :process, _, _} -> File.rm_rf(dir)
      end
    end)
  end

  @doc false
  def remote_command(host, args, marker \\ nil) do
    codex = Enum.map_join([host.remote_codex_path || "codex" | args], " ", &quote_arg/1)
    ready = if marker, do: "printf '%s' " <> quote_arg(marker) <> "; ", else: ""

    payload =
      ready <>
        ~S|PATH="${CODEX_INSTALL_DIR:-$HOME/.local/bin}:$PATH"; export PATH; exec | <> codex

    Enum.map_join(["sh", "-c", @launcher, "sh", payload], " ", &quote_arg/1)
  end

  defp options(host, known_hosts, key_file) do
    identity =
      if key_file,
        do: ["-o", "IdentitiesOnly=yes", "-i", key_file],
        else: []

    user = if host.ssh_user, do: ["-l", host.ssh_user], else: []

    common = [
      "-T",
      "-a",
      "-x",
      "-o",
      "BatchMode=yes",
      "-o",
      "StrictHostKeyChecking=yes",
      "-o",
      "ClearAllForwardings=yes",
      "-o",
      "ControlPath=none",
      "-o",
      "ConnectTimeout=10",
      "-o",
      "ServerAliveInterval=15",
      "-o",
      "ServerAliveCountMax=3",
      "-o",
      "LogLevel=ERROR"
    ]

    if host.use_ssh_config do
      port = if host.ssh_port, do: ["-p", Integer.to_string(host.ssh_port)], else: []
      common ++ port ++ identity ++ user ++ ["--", host.ssh_host]
    else
      isolated(host, known_hosts, key_file, identity, user)
    end
  end

  defp isolated(host, known_hosts, key_file, identity, user) do
    [
      "-T",
      "-F",
      "/dev/null",
      "-a",
      "-x",
      "-o",
      "BatchMode=yes",
      "-o",
      "StrictHostKeyChecking=yes",
      "-o",
      "UserKnownHostsFile=" <> known_hosts,
      "-o",
      "GlobalKnownHostsFile=/dev/null",
      "-o",
      "UpdateHostKeys=no",
      "-o",
      "ClearAllForwardings=yes",
      "-o",
      "ControlPath=none",
      "-o",
      "ConnectTimeout=10",
      "-o",
      "ServerAliveInterval=15",
      "-o",
      "ServerAliveCountMax=3",
      "-o",
      "LogLevel=ERROR",
      "-o",
      "IdentityAgent=" <> if(key_file, do: "none", else: "SSH_AUTH_SOCK"),
      "-p",
      Integer.to_string(host.ssh_port || 22)
    ] ++ identity ++ user ++ ["--", host.ssh_host]
  end

  defp socket_args(%{remote_socket_path: nil}), do: []
  defp socket_args(%{remote_socket_path: path}), do: ["--sock", path]

  # Remote sshd passes the command to the user's shell; quote every word.
  defp quote_arg(arg), do: "'" <> String.replace(arg, "'", "'\\''") <> "'"

  # The operator's own environment, so their agent, config and keys resolve.
  defp env(%{use_ssh_config: true}, _dir, _key_file),
    do:
      for(
        name <- ~w(PATH HOME USER LOGNAME LANG SSH_AUTH_SOCK),
        value = System.get_env(name),
        do: {name, value}
      )

  defp env(_host, dir, key_file) do
    base = [{"PATH", "/usr/bin:/bin:/usr/sbin:/sbin"}, {"HOME", dir}, {"LANG", "C"}]
    agent = System.get_env("SSH_AUTH_SOCK")

    if is_nil(key_file) and is_binary(agent),
      do: [{"SSH_AUTH_SOCK", agent} | base],
      else: base
  end

  defp clear_env(env) do
    supplied = Map.new(env)

    removed =
      for {name, _} <- System.get_env(), not Map.has_key?(supplied, name), do: {name, nil}

    removed ++ env
  end

  defp executable do
    configured =
      :samgita
      |> Application.get_env(:codex_hosts, [])
      |> Keyword.get(:ssh_executable)

    path = configured || System.find_executable("ssh")

    if is_binary(path) and Path.type(path) == :absolute and File.regular?(path),
      do: {:ok, path},
      else: {:error, :ssh_unavailable}
  end

  defp key(nil), do: {:ok, nil}

  defp key(reference) do
    case Application.get_env(:samgita, :codex_host_secrets, %{}) do
      %{^reference => value} when is_binary(value) and byte_size(value) in 1..65_536 ->
        {:ok, value}

      _ ->
        {:error, :credential_unavailable}
    end
  end

  defp private_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "samgita-ssh-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
      )

    with :ok <- File.mkdir(dir), :ok <- File.chmod(dir, 0o700) do
      {:ok, dir}
    else
      _ -> {:error, :ssh_setup_failed}
    end
  end

  defp write_private!(path, contents) do
    File.write!(path, "")
    File.chmod!(path, 0o600)
    File.write!(path, contents)
  end

  defp normalize(text), do: String.trim_trailing(text) <> "\n"
end
