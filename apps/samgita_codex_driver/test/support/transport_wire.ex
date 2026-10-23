defmodule SamgitaCodexDriver.TransportWire do
  @moduledoc false
  import Bitwise

  def listen(handler, opts \\ []) do
    owner = self()

    listen_opts =
      [:binary, active: false, packet: :raw, reuseaddr: true] ++
        Keyword.get(opts, :listen_opts, [])

    {:ok, listener} = :gen_tcp.listen(0, listen_opts)
    {:ok, address} = :inet.sockname(listener)

    {:ok, pid} =
      Task.start_link(fn ->
        case :gen_tcp.accept(listener, 5_000) do
          {:ok, socket} -> handler.(socket, owner)
          {:error, :closed} -> :ok
        end
      end)

    %{listener: listener, pid: pid, address: address}
  end

  def stop(server) do
    if Map.get(server, :ssl),
      do: :ssl.close(server.listener),
      else: :gen_tcp.close(server.listener)

    send(server.pid, :stop)
    :ok
  end

  def listen_tls(handler, cert, key) do
    owner = self()

    {:ok, listener} =
      :ssl.listen(0, [
        :binary,
        active: false,
        reuseaddr: true,
        certfile: String.to_charlist(cert),
        keyfile: String.to_charlist(key)
      ])

    {:ok, address} = :ssl.sockname(listener)

    {:ok, pid} =
      Task.start_link(fn ->
        case :ssl.transport_accept(listener, 5_000) do
          {:ok, accepted} ->
            case :ssl.handshake(accepted, 5_000) do
              {:ok, socket} -> handler.({:ssl, socket}, owner)
              {:error, _} -> :ssl.close(accepted)
            end

          {:error, :closed} ->
            :ok
        end
      end)

    %{listener: listener, pid: pid, address: address, ssl: true}
  end

  def write({:ssl, socket}, bytes), do: :ssl.send(socket, bytes)
  def write(socket, bytes), do: :gen_tcp.send(socket, bytes)
  def recv({:ssl, socket}, count, timeout), do: :ssl.recv(socket, count, timeout)
  def recv(socket, count, timeout), do: :gen_tcp.recv(socket, count, timeout)

  def upgrade(socket, owner, opts \\ []) do
    request = read_headers(socket, <<>>)
    send(owner, {:upgrade_request, request})
    status = Keyword.get(opts, :status, 101)

    if status == 101 do
      [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)

      accept =
        :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

      extra = Keyword.get(opts, :extra_headers, "")

      :ok =
        write(socket, [
          "HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: ",
          accept,
          "\r\n",
          extra,
          "\r\n",
          Keyword.get(opts, :initial, <<>>)
        ])
    else
      :ok =
        write(
          socket,
          "HTTP/1.1 #{status} Rejected\r\ncontent-length: 0\r\nretry-after: 3\r\n\r\n"
        )
    end
  end

  def read_headers(socket, data) do
    if String.contains?(data, "\r\n\r\n") do
      data
    else
      {:ok, bytes} = recv(socket, 0, 5_000)
      read_headers(socket, data <> bytes)
    end
  end

  def frame(opcode, payload, final \\ true) do
    first = if(final, do: 128, else: 0) + opcode
    length = byte_size(payload)

    cond do
      length < 126 -> <<first, length, payload::binary>>
      length < 65_536 -> <<first, 126, length::16, payload::binary>>
      true -> <<first, 127, length::64, payload::binary>>
    end
  end

  def read_frame(socket, data \\ <<>>) do
    case parse_frame(data) do
      :more ->
        {:ok, bytes} = recv(socket, 0, 5_000)
        read_frame(socket, data <> bytes)

      result ->
        result
    end
  end

  defp parse_frame(<<first, mask::1, len::7, rest::binary>>) do
    case length_data(len, rest) do
      {:ok, length, payload} when mask == 1 and byte_size(payload) >= length + 4 ->
        <<key::binary-size(4), bytes::binary-size(length), tail::binary>> = payload

        unmasked =
          for {byte, index} <- Enum.with_index(:binary.bin_to_list(bytes)),
              into: <<>>,
              do: <<bxor(byte, :binary.at(key, rem(index, 4)))>>

        {:ok, band(first, 15), unmasked, tail}

      {:ok, length, payload} when mask == 0 and byte_size(payload) >= length ->
        <<bytes::binary-size(length), tail::binary>> = payload
        {:ok, band(first, 15), bytes, tail}

      _ ->
        :more
    end
  end

  defp parse_frame(_), do: :more
  defp length_data(126, <<len::16, rest::binary>>), do: {:ok, len, rest}
  defp length_data(127, <<len::64, rest::binary>>), do: {:ok, len, rest}
  defp length_data(len, rest) when len < 126, do: {:ok, len, rest}
  defp length_data(_, _), do: :more
end
