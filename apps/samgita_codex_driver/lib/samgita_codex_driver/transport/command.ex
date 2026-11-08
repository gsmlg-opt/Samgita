defmodule SamgitaCodexDriver.Transport.Command do
  @moduledoc """
  Native WebSocket carried over the stdio of an owned command.

  This is how a client reaches a Codex app-server daemon through
  `codex app-server proxy`, typically run remotely as
  `ssh <host> codex app-server proxy`: the proxy forwards raw bytes to the
  daemon control socket, which speaks WebSocket. The command's stdio is relayed
  through a private, per-connection Unix socket so the existing
  `Transport.WebSocket` client handles framing, limits and close semantics.

  Options:

    * `:executable` - absolute path of the command (required)
    * `:args` - argument list, passed without a shell (required)
    * `:env` - exact environment for the command as `[{name, value}]`;
      everything else from the BEAM environment is removed
    * `:path` - WebSocket request path, default `/app-server`
    * `:connect_timeout_ms` - time to accept the relayed connection
    * `:cleanup_timeout_ms` - grace period before the command is killed on close

  Closing ends only the command. It never stops the remote daemon or its threads.
  The command's stderr is not part of the byte stream; it goes to the BEAM's
  stderr, so commands must not print secrets there.
  """
  @behaviour SamgitaCodexDriver.Transport
  import Kernel, except: [send: 2]
  alias SamgitaCodexDriver.Transport.WebSocket
  alias SamgitaProtocolCodex.Error

  @cleanup_timeout 5_000

  defp cleanup_timeout(opts), do: Keyword.get(opts, :cleanup_timeout_ms, @cleanup_timeout)

  @impl true
  def open(opts) do
    with {:ok, executable, args, env} <- command(opts),
         {:ok, dir} <- private_dir(),
         socket_path = Path.join(dir, "relay.sock"),
         {:ok, listener} <- listen(socket_path, dir),
         relay = start_relay(listener, executable, args, env, opts),
         {:ok, ws} <- open_websocket(socket_path, opts, relay, dir) do
      File.rm(socket_path)
      {:ok, %{ws: ws, relay: relay, dir: dir, cleanup_timeout: cleanup_timeout(opts)}}
    end
  end

  @impl true
  def send(state, json) do
    case WebSocket.send(state.ws, json) do
      {:ok, ws} -> {:ok, %{state | ws: ws}}
      {:error, error, ws} -> {:error, error, %{state | ws: ws}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case WebSocket.handle_info(message, state.ws) do
      {:ok, events, ws} -> {:ok, events, %{state | ws: ws}}
      {:error, error, ws} -> {:error, error, %{state | ws: ws}}
      :unknown -> :unknown
    end
  end

  @impl true
  def close(state) do
    # Stop the command first: the WebSocket close then completes locally instead
    # of waiting for a close echo relayed by the command being shut down.
    relay_result = stop_relay(state.relay, state.cleanup_timeout)

    ws_result =
      try do
        WebSocket.close(state.ws)
      rescue
        error in Error -> error
      end

    File.rm_rf(state.dir)

    case {relay_result, ws_result} do
      {:ok, :ok} -> :ok
      _ -> raise Error.new(:owned_process_shutdown_unconfirmed)
    end
  end

  @impl true
  def metadata(state), do: state.ws |> WebSocket.metadata() |> Map.put("transport", "command")

  defp command(opts) do
    executable = opts[:executable]
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])

    if is_binary(executable) and Path.type(executable) == :absolute and
         File.regular?(executable) and is_list(args) and Enum.all?(args, &safe_arg?/1) and
         is_list(env) and Enum.all?(env, &safe_env?/1),
       do: {:ok, executable, args, env},
       else: {:error, Error.new(:invalid_transport_options)}
  end

  defp safe_arg?(arg), do: is_binary(arg) and not String.contains?(arg, <<0>>)

  defp safe_env?({name, value}),
    do: is_binary(name) and name =~ ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/ and safe_arg?(value)

  defp safe_env?(_), do: false

  defp private_dir do
    dir = Path.join(System.tmp_dir!(), "scd-" <> Base.url_encode64(:crypto.strong_rand_bytes(9)))

    with :ok <- File.mkdir(dir), :ok <- File.chmod(dir, 0o700) do
      {:ok, dir}
    else
      _ -> {:error, Error.new(:transport_open_failed)}
    end
  end

  defp listen(path, dir) do
    case :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, path}]) do
      {:ok, listener} ->
        {:ok, listener}

      {:error, _} ->
        File.rm_rf(dir)
        {:error, Error.new(:transport_open_failed)}
    end
  end

  defp open_websocket(path, opts, relay, dir) do
    ws_opts =
      opts
      |> Keyword.drop([:executable, :args, :env])
      |> Keyword.put_new(:path, "/app-server")

    case WebSocket.open_unix(path, ws_opts) do
      {:ok, ws} ->
        {:ok, ws}

      {:error, error} ->
        stop_relay(relay, cleanup_timeout(opts))
        File.rm_rf(dir)
        {:error, error}
    end
  end

  # The relay is linked to the Session process that opened the transport, so the
  # command's port closes if the Session dies.
  defp start_relay(listener, executable, args, env, opts) do
    timeout = Keyword.get(opts, :connect_timeout_ms, 10_000)
    cleanup = cleanup_timeout(opts)
    owner = self()

    spawn_link(fn ->
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: args,
          env: command_env(env)
        ])

      case :gen_tcp.accept(listener, timeout) do
        {:ok, client} ->
          :gen_tcp.close(listener)
          :ok = :inet.setopts(client, active: true)
          relay(port, client, owner, cleanup)

        {:error, _} ->
          :gen_tcp.close(listener)
          stop_port(port, cleanup)
      end
    end)
  end

  defp relay(port, client, owner, cleanup) do
    receive do
      {^port, {:data, data}} ->
        :gen_tcp.send(client, data)
        relay(port, client, owner, cleanup)

      {:tcp, ^client, data} ->
        Port.command(port, data)
        relay(port, client, owner, cleanup)

      {:tcp_closed, ^client} ->
        stop_port(port, cleanup)

      {^port, {:exit_status, _}} ->
        :gen_tcp.close(client)

      {:stop, from, ref} ->
        :gen_tcp.close(client)
        Kernel.send(from, {ref, stop_port(port, cleanup)})
    end
  end

  # Unset every inherited variable that is not explicitly supplied.
  defp command_env(env) do
    supplied = Map.new(env, fn {name, value} -> {name, value} end)

    removed =
      for {name, _} <- System.get_env(), not Map.has_key?(supplied, name), do: {name, false}

    Enum.map(removed ++ Map.to_list(supplied), fn {name, value} ->
      {to_charlist(name), value && to_charlist(value)}
    end)
  end

  defp stop_port(port, cleanup) do
    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        nil -> nil
      end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    await_exit(os_pid, cleanup)
  end

  defp await_exit(nil, _cleanup), do: :ok

  defp await_exit(os_pid, cleanup),
    do: await_exit_until(os_pid, System.monotonic_time(:millisecond) + cleanup)

  defp await_exit_until(os_pid, deadline) do
    cond do
      not alive?(os_pid) ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], stderr_to_stdout: true)
        await_killed(os_pid, 40)

      true ->
        Process.sleep(25)
        await_exit_until(os_pid, deadline)
    end
  end

  defp await_killed(_os_pid, 0), do: :unconfirmed

  defp await_killed(os_pid, attempts) do
    if alive?(os_pid) do
      Process.sleep(25)
      await_killed(os_pid, attempts - 1)
    else
      :ok
    end
  end

  defp alive?(os_pid) do
    match?({_, 0}, System.cmd("kill", ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true))
  end

  defp stop_relay(relay, cleanup) do
    if Process.alive?(relay) do
      ref = make_ref()
      monitor = Process.monitor(relay)
      Kernel.send(relay, {:stop, self(), ref})

      receive do
        {^ref, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, _, _} ->
          :ok
      after
        cleanup + 2_000 -> :unconfirmed
      end
    else
      :ok
    end
  end
end
