defmodule SamgitaCodexDriver.TransportCommandTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.Transport.Command
  alias SamgitaCodexDriver.TransportWire, as: Wire
  alias SamgitaProtocolCodex.Error

  # Stands in for `codex app-server proxy`: relays its stdio to a TCP server.
  @proxy """
  import os, socket, sys, threading
  if os.environ.get("SAMGITA_LEAK_PROBE"):
      sys.exit(3)
  s = socket.create_connection((sys.argv[1], int(sys.argv[2])))
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
  """

  defp python, do: System.find_executable("python3")

  defp server(fun) do
    server = Wire.listen(fun)
    on_exit(fn -> Wire.stop(server) end)
    {_, port} = server.address
    {server, port}
  end

  defp open(port, extra \\ []) do
    Command.open(
      [
        executable: python(),
        args: ["-I", "-c", @proxy, "127.0.0.1", Integer.to_string(port)],
        env: [{"PATH", System.get_env("PATH")}]
      ] ++ extra
    )
  end

  defp pump(state) do
    receive do
      message ->
        case Command.handle_info(message, state) do
          {:ok, [_ | _] = events, next} -> {events, next}
          {:ok, [], next} -> pump(next)
          :unknown -> pump(state)
          {:error, error, next} -> {{:error, error}, next}
        end
    after
      5_000 -> flunk("no transport event")
    end
  end

  test "carries WebSocket messages over the command's stdio and cleans up on close" do
    {_server, port} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        {:ok, 1, json, _} = Wire.read_frame(socket)
        send(owner, {:client_json, json})
        Wire.write(socket, Wire.frame(1, ~s({"id":1,"result":{}})))

        receive do
          :stop -> :ok
        end
      end)

    System.put_env("SAMGITA_LEAK_PROBE", "1")
    on_exit(fn -> System.delete_env("SAMGITA_LEAK_PROBE") end)

    assert {:ok, state} = open(port)
    assert_receive {:upgrade_request, request}, 5_000
    assert request =~ "GET /app-server HTTP/1.1"
    assert {:ok, state} = Command.send(state, ~s({"id":1,"method":"initialize"}))
    assert_receive {:client_json, ~s({"id":1,"method":"initialize"})}, 5_000
    assert {[{:message, ~s({"id":1,"result":{}})}], state} = pump(state)
    assert Command.metadata(state)["transport"] == "command"
    refute File.exists?(Path.join(state.dir, "relay.sock"))

    assert :ok = Command.close(state)
    refute File.exists?(state.dir)
    refute Process.alive?(state.relay)
  end

  test "a command exit surfaces as a closed connection" do
    {server, port} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)

        receive do
          :drop -> :gen_tcp.close(socket)
        end
      end)

    assert {:ok, state} = open(port)
    assert_receive {:upgrade_request, _}, 5_000
    send(server.pid, :drop)
    assert {result, _state} = pump(state)
    assert match?([{:closed, _}], result) or match?({:error, %Error{}}, result)
  end

  test "a command that ignores stdin EOF is killed on close" do
    stubborn =
      String.replace(@proxy, "            os._exit(0)", "            threading.Event().wait()")

    {_server, port} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)

        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, state} =
             Command.open(
               executable: python(),
               args: ["-I", "-c", stubborn, "127.0.0.1", Integer.to_string(port)],
               env: [],
               cleanup_timeout_ms: 300
             )

    assert_receive {:upgrade_request, _}, 5_000
    assert :ok = Command.close(state)
    refute Process.alive?(state.relay)
  end

  test "stdout before the marker is discarded and client bytes wait for it" do
    # Prints login-shell noise and a marker split across writes; exits if any
    # client byte reaches stdin before the marker was printed.
    noisy =
      String.replace(
        @proxy,
        "s = socket.create_connection",
        """
        import select, time
        os.write(1, b"Welcome banner\\nMA")
        if select.select([0], [], [], 0.3)[0]:
            sys.exit(4)
        time.sleep(0.1)
        os.write(1, b"RK")
        s = socket.create_connection\
        """
      )

    {_server, port} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        {:ok, 1, json, _} = Wire.read_frame(socket)
        send(owner, {:client_json, json})

        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, state} =
             Command.open(
               executable: python(),
               args: ["-I", "-c", noisy, "127.0.0.1", Integer.to_string(port)],
               env: [],
               stdout_marker: "MARK"
             )

    assert_receive {:upgrade_request, request}, 5_000
    assert request =~ "GET /app-server HTTP/1.1"
    assert {:ok, state} = Command.send(state, ~s({"id":1}))
    assert_receive {:client_json, ~s({"id":1})}, 5_000
    assert :ok = Command.close(state)
  end

  test "a command that never prints the marker fails to open" do
    assert {:error, %Error{}} =
             Command.open(
               executable: python(),
               args: ["-I", "-c", "import time; print('motd'); time.sleep(5)"],
               env: [],
               stdout_marker: "MARK",
               connect_timeout_ms: 2_000,
               cleanup_timeout_ms: 200
             )
  end

  test "rejects relative executables and unsafe arguments or environment" do
    assert {:error, %Error{code: :invalid_transport_options}} =
             Command.open(executable: "python3", args: [])

    assert {:error, %Error{code: :invalid_transport_options}} =
             Command.open(executable: python(), args: ["a" <> <<0>>])

    assert {:error, %Error{code: :invalid_transport_options}} =
             Command.open(executable: python(), args: [], env: [{"BAD NAME", "x"}])

    assert {:error, %Error{code: :invalid_transport_options}} =
             Command.open(executable: python(), args: [], stdout_marker: "")
  end

  test "a command that never connects fails to open without leaking resources" do
    assert {:error, %Error{}} =
             Command.open(
               executable: python(),
               args: ["-I", "-c", "import sys; sys.exit(0)"],
               env: [],
               connect_timeout_ms: 500
             )
  end
end
