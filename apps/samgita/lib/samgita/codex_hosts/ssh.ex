defmodule Samgita.CodexHosts.Ssh do
  @moduledoc """
  Builds the OpenSSH command that reaches a Codex app-server daemon through
  `codex app-server proxy` (design §11).

  The command uses a fixed argument list (never a shell string on this side),
  `BatchMode`, strict host-key checking against a private known-hosts file
  written from the host's configuration, no forwarding and a minimal
  environment. A private key comes from a credential reference and exists only
  in a private directory for the lifetime of one connection.
  """

  @ensure_daemon_timeout 30_000

  @doc "Prepare private files and transport options. The caller must `cleanup/1` the dir."
  def prepare(host) do
    with {:ok, ssh} <- executable(),
         {:ok, key} <- key(host.ssh_key_ref),
         {:ok, dir} <- private_dir() do
      known_hosts = Path.join(dir, "known_hosts")
      write_private!(known_hosts, normalize(host.known_hosts))

      key_file =
        if key do
          path = Path.join(dir, "identity")
          write_private!(path, normalize(key))
          path
        end

      base = options(host, known_hosts, key_file)
      env = env(dir, key_file)

      {:ok,
       %{
         dir: dir,
         executable: ssh,
         base_args: base,
         env: env,
         transport: [
           executable: ssh,
           args: base ++ [remote_command(host, ["app-server", "proxy"] ++ socket_args(host))],
           env: env
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
  def cleanup(dir), do: File.rm_rf(dir) && :ok

  @doc false
  def remote_command(host, args) do
    [host.remote_codex_path || "codex" | args]
    |> Enum.map_join(" ", &quote_arg/1)
  end

  defp options(host, known_hosts, key_file) do
    identity =
      if key_file,
        do: ["-o", "IdentitiesOnly=yes", "-i", key_file],
        else: []

    user = if host.ssh_user, do: ["-l", host.ssh_user], else: []

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

  defp env(dir, key_file) do
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
