defmodule Samgita.FakeCodexServer do
  @moduledoc """
  Minimal loopback Codex app-server over WebSocket for host-connection tests.

  Answers `initialize` with a schema-valid response, ignores notifications and
  answers other requests with the `:results` option for that method (default
  an empty result), reporting each request's params to the owner. `drop_connections/1` closes live
  sockets to simulate a server restart; the listener keeps accepting.
  """
  import Bitwise

  def start(opts \\ []) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, table} = Agent.start_link(fn -> [] end)

    acceptor =
      spawn_link(fn -> accept_loop(listener, owner, table, Map.new(opts)) end)

    %{
      listener: listener,
      port: port,
      acceptor: acceptor,
      sockets: table,
      url: "ws://127.0.0.1:#{port}/app-server"
    }
  end

  def drop_connections(server) do
    server.sockets |> Agent.get_and_update(&{&1, []}) |> Enum.each(&:gen_tcp.close/1)
  end

  def stop(server) do
    drop_connections(server)
    :gen_tcp.close(server.listener)
    Process.exit(server.acceptor, :kill)
    Agent.stop(server.sockets)
  catch
    :exit, _ -> :ok
  end

  defp accept_loop(listener, owner, table, opts) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        pid = spawn(fn -> receive(do: (:go -> serve(socket, owner, table, opts))) end)
        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept_loop(listener, owner, table, opts)

      {:error, _} ->
        :ok
    end
  end

  defp serve(socket, owner, table, opts) do
    request = read_headers(socket, <<>>)
    token = Map.get(opts, :token)

    if token && !Regex.match?(~r/^authorization: Bearer #{Regex.escape(token)}\r$/im, request) do
      send(owner, {:fake_codex, :rejected, request})
      :gen_tcp.send(socket, "HTTP/1.1 401 Unauthorized\r\ncontent-length: 0\r\n\r\n")
      :gen_tcp.close(socket)
    else
      [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)

      accept =
        :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

      :ok =
        :gen_tcp.send(socket, [
          "HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: ",
          accept,
          "\r\n\r\n"
        ])

      Agent.update(table, &[socket | &1])
      send(owner, {:fake_codex, :connected})
      loop(socket, owner, opts, <<>>)
    end
  catch
    _, _ -> :gen_tcp.close(socket)
  end

  defp loop(socket, owner, opts, buffer) do
    case read_frame(socket, buffer) do
      {:ok, 1, json, rest} ->
        handle(socket, owner, opts, Jason.decode!(json))
        loop(socket, owner, opts, rest)

      {:ok, 9, payload, rest} ->
        :gen_tcp.send(socket, frame(10, payload))
        loop(socket, owner, opts, rest)

      {:ok, 8, _payload, _rest} ->
        :gen_tcp.send(socket, frame(8, <<1000::16>>))
        :gen_tcp.close(socket)
        send(owner, {:fake_codex, :closed})

      {:ok, _, _, rest} ->
        loop(socket, owner, opts, rest)

      :closed ->
        send(owner, {:fake_codex, :closed})
    end
  end

  defp handle(socket, owner, %{initialize: :error}, %{"id" => id, "method" => "initialize"}) do
    send(owner, {:fake_codex, :request, "initialize"})
    reply(socket, %{"id" => id, "error" => %{"code" => -32_603, "message" => "not ready"}})
  end

  defp handle(socket, owner, opts, %{"id" => id, "method" => "initialize"} = wire) do
    send(owner, {:fake_codex, :request, "initialize"})
    send(owner, {:fake_codex, :params, "initialize", wire["params"]})
    version = Map.get(opts, :version, "0.167.0")

    reply(socket, %{
      "id" => id,
      "result" => %{
        "codexHome" => "/fake/codex-home",
        "platformFamily" => "unix",
        "platformOs" => "linux",
        "userAgent" => "codex_fake/#{version} (Linux; x86_64) fake"
      }
    })
  end

  defp handle(socket, owner, opts, %{"id" => id, "method" => method} = wire) do
    send(owner, {:fake_codex, :request, method})
    send(owner, {:fake_codex, :params, method, wire["params"]})
    result = opts |> Map.get(:results, %{}) |> Map.get(method, %{})
    reply(socket, %{"id" => id, "result" => result})
  end

  defp handle(_socket, owner, _opts, %{"method" => method}),
    do: send(owner, {:fake_codex, :notification, method})

  defp handle(_socket, _owner, _opts, _wire), do: :ok

  defp reply(socket, wire), do: :gen_tcp.send(socket, frame(1, Jason.encode!(wire)))

  defp read_headers(socket, data) do
    if String.contains?(data, "\r\n\r\n") do
      data
    else
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
      read_headers(socket, data <> bytes)
    end
  end

  defp frame(opcode, payload) do
    length = byte_size(payload)

    cond do
      length < 126 -> <<128 + opcode, length, payload::binary>>
      length < 65_536 -> <<128 + opcode, 126, length::16, payload::binary>>
      true -> <<128 + opcode, 127, length::64, payload::binary>>
    end
  end

  defp read_frame(socket, data) do
    case parse(data) do
      :more ->
        case :gen_tcp.recv(socket, 0) do
          {:ok, bytes} -> read_frame(socket, data <> bytes)
          {:error, _} -> :closed
        end

      result ->
        result
    end
  end

  defp parse(<<first, 1::1, len::7, rest::binary>>) do
    with {:ok, length, payload} <- length_data(len, rest),
         true <- byte_size(payload) >= length + 4 do
      <<key::binary-size(4), bytes::binary-size(length), tail::binary>> = payload

      unmasked =
        for {byte, index} <- Enum.with_index(:binary.bin_to_list(bytes)),
            into: <<>>,
            do: <<bxor(byte, :binary.at(key, rem(index, 4)))>>

      {:ok, band(first, 15), unmasked, tail}
    else
      _ -> :more
    end
  end

  defp parse(_), do: :more

  defp length_data(126, <<len::16, rest::binary>>), do: {:ok, len, rest}
  defp length_data(127, <<len::64, rest::binary>>), do: {:ok, len, rest}
  defp length_data(len, rest) when len < 126, do: {:ok, len, rest}
  defp length_data(_, _), do: :more
end
