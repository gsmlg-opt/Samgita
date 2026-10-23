defmodule SamgitaCodexDriver.TransportWebSocketTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.Transport.{UnixSocket, WebSocket}
  alias SamgitaCodexDriver.TransportWire, as: Wire
  alias SamgitaProtocolCodex.Error

  defp server(fun) do
    server = Wire.listen(fun)
    on_exit(fn -> Wire.stop(server) end)
    {_, port} = server.address
    {server, "ws://localhost:#{port}/app-server"}
  end

  defp pump(state, count, acc \\ []) do
    if length(acc) >= count do
      {acc, state}
    else
      receive do
        message ->
          case WebSocket.handle_info(message, state) do
            {:ok, events, next} -> pump(next, count, acc ++ events)
            :unknown -> pump(state, count, acc)
            error -> error
          end
      after
        5_000 -> flunk("WebSocket did not produce expected events")
      end
    end
  end

  test "upgrade token, pinned destination, coalesced early frames and masked writes" do
    {server, url} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner, initial: Wire.frame(1, ~s({"early":1})))
        {:ok, 1, json, _} = Wire.read_frame(socket)
        send(owner, {:client_json, json})
        Wire.write(socket, Wire.frame(1, ~s({"answer":2})))

        receive do
          :stop -> :ok
        end
      end)

    {:ok, state} =
      WebSocket.open(url: url, token: "synthetic-token", connect_address: {127, 0, 0, 1})

    on_exit(fn -> WebSocket.close(state) end)
    assert_receive {:upgrade_request, request}
    assert request =~ "authorization: Bearer synthetic-token\r\n"
    refute String.contains?(String.downcase(request), "origin:")
    assert {[{:message, ~s({"early":1})}], state} = pump(state, 1)
    assert {:ok, state} = WebSocket.send(state, ~s({"id":1}))
    assert_receive {:client_json, ~s({"id":1})}
    assert {[{:message, ~s({"answer":2})}], state} = pump(state, 1)
    assert :ok = WebSocket.close(state)
    assert Process.alive?(server.pid)
  end

  test "fragmentation, ping/pong and close preserve message order" do
    {_server, url} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        Wire.write(socket, Wire.frame(1, ~s({"value":), false))
        Wire.write(socket, Wire.frame(9, "ping") <> Wire.frame(0, "1}"))
        {:ok, 10, "ping", _} = Wire.read_frame(socket)
        Wire.write(socket, Wire.frame(8, <<1000::16, "private-reason">>))
        {:ok, 8, <<1000::16>>, _} = Wire.read_frame(socket)
      end)

    {:ok, state} = WebSocket.open(url: url)
    assert_receive {:upgrade_request, _}
    assert {[{:message, ~s({"value":1})}, {:closed, %{"close_code" => 1000}}], _} = pump(state, 2)
  end

  test "per-message counters reset across coalesced frames and bounded reads" do
    {_server, url} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        Wire.write(socket, Enum.map(1..20, fn _ -> Wire.frame(1, "12345678") end))

        receive do
          :stop -> :ok
        end
      end)

    {:ok, state} = WebSocket.open(url: url, max_message_bytes: 8)
    assert_receive {:upgrade_request, _}
    assert {messages, _} = pump(state, 20)
    assert messages == List.duplicate({:message, "12345678"}, 20)
  end

  test "oversized advertised frame fails before its payload arrives" do
    {_server, url} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        Wire.write(socket, <<129, 126, 65_000::16>>)

        receive do
          :stop -> :ok
        end
      end)

    {:ok, state} = WebSocket.open(url: url, max_message_bytes: 16)
    assert_receive {:upgrade_request, _}
    assert {:error, %Error{code: :frame_too_large}, %{conn: nil}} = pump(state, 1)
  end

  test "fragmented message sum is bounded even when every frame fits" do
    {_server, url} =
      server(fn socket, owner ->
        Wire.upgrade(socket, owner)
        Wire.write(socket, Wire.frame(1, "12345678", false) <> Wire.frame(0, "12345678", false))

        receive do
          :stop -> :ok
        end
      end)

    {:ok, state} = WebSocket.open(url: url, max_message_bytes: 8)
    assert_receive {:upgrade_request, _}
    assert {:error, %Error{code: :message_too_large}, %{conn: nil}} = pump(state, 1)
  end

  test "binary and invalid control frames fail explicitly" do
    for bytes <- [Wire.frame(2, "binary"), Wire.frame(9, "bad", false)] do
      {_server, url} =
        server(fn socket, owner ->
          Wire.upgrade(socket, owner)
          Wire.write(socket, bytes)

          receive do
            :stop -> :ok
          end
        end)

      {:ok, state} = WebSocket.open(url: url)
      assert_receive {:upgrade_request, _}
      assert {:error, %Error{code: code}, %{conn: nil}} = pump(state, 1)
      assert code in [:unsupported_binary_frame, :invalid_websocket_frame]
    end
  end

  test "401, 403 and 429 remain failures with safe status and retry metadata" do
    for status <- [401, 403, 429] do
      {_server, url} = server(fn socket, owner -> Wire.upgrade(socket, owner, status: status) end)

      assert {:error, %Error{details: %{"http_status" => ^status, "retry_after" => "3"}}} =
               WebSocket.open(url: url)

      assert_receive {:upgrade_request, _}
    end
  end

  test "unsafe URLs, Origin/control headers, TLS bypass and remote plaintext fail before connection" do
    for opts <- [
          [url: "ws://user:secret@localhost/app-server"],
          [url: "ws://localhost/app-server?token=secret"],
          [url: "ws://example.test/app-server"],
          [url: "ws://localhost/app-server", connect_address: {192, 0, 2, 1}],
          [url: "wss://localhost/app-server", tls_opts: [verify: :verify_none]],
          [url: "ws://localhost/app-server", headers: [{"Origin", "https://example.test"}]],
          [url: "ws://localhost/app-server", headers: [{"Sec-WebSocket-Key", "x"}]],
          [url: "ws://localhost/app-server", token: "secret\r\nheader: value"]
        ] do
      assert {:error, %Error{code: :invalid_transport_options}} = WebSocket.open(opts)
    end
  end

  test "UDS is WebSocket, honors peer frame cap and never removes borrowed socket" do
    dir = Path.join(System.tmp_dir!(), "codex-uds-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "server.sock")

    server =
      Wire.listen(
        fn socket, owner ->
          Wire.upgrade(socket, owner,
            extra_headers: "x-codex-websocket-max-unfragmented-message-bytes: 8\r\n"
          )

          {:ok, 1, "{}", _} = Wire.read_frame(socket)
          Wire.write(socket, Wire.frame(1, "{}"))

          receive do
            :stop -> :ok
          end
        end,
        listen_opts: [ip: {:local, path}]
      )

    on_exit(fn ->
      Wire.stop(server)
      File.rm_rf!(dir)
    end)

    assert {:ok, state} = UnixSocket.open(socket_path: path)
    assert_receive {:upgrade_request, _}

    assert {:error, %Error{code: :message_too_large}, ^state} =
             UnixSocket.send(state, "123456789")

    assert {:ok, state} = UnixSocket.send(state, "{}")
    assert {[{:message, "{}"}], state} = pump(state, 1)
    assert :ok = UnixSocket.close(state)
    assert File.exists?(path)
    assert Process.alive?(server.pid)
    assert {:error, %Error{}} = UnixSocket.open(socket_path: path, path: "/daemon/shutdown")
  end

  test "WSS validates trust and hostname while dialing the pinned IP" do
    dir = Path.join(System.tmp_dir!(), "codex-tls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    cert = Path.join(dir, "cert.pem")
    key = Path.join(dir, "key.pem")
    ca = Path.join(dir, "ca.pem")
    ca_key = Path.join(dir, "ca-key.pem")
    csr = Path.join(dir, "server.csr")
    extensions = Path.join(dir, "server.ext")

    File.write!(
      extensions,
      "subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n"
    )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          ca_key,
          "-out",
          ca,
          "-days",
          "1",
          "-subj",
          "/CN=Samgita synthetic transport test CA"
        ],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "req",
          "-new",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          key,
          "-out",
          csr,
          "-subj",
          "/CN=localhost"
        ],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "openssl",
        [
          "x509",
          "-req",
          "-in",
          csr,
          "-CA",
          ca,
          "-CAkey",
          ca_key,
          "-CAcreateserial",
          "-out",
          cert,
          "-days",
          "1",
          "-extfile",
          extensions
        ],
        stderr_to_stdout: true
      )

    for profile <- [:trusted, :untrusted, :wrong_hostname] do
      server =
        Wire.listen_tls(
          fn socket, owner ->
            Wire.upgrade(socket, owner)
            Wire.write(socket, Wire.frame(1, "{}"))

            receive do
              :stop -> :ok
            end
          end,
          cert,
          key
        )

      on_exit(fn -> Wire.stop(server) end)
      {_, port} = server.address
      host = if profile == :wrong_hostname, do: "other.test", else: "localhost"
      tls = if profile == :untrusted, do: [], else: [cacertfile: String.to_charlist(ca)]

      result =
        WebSocket.open(
          url: "wss://#{host}:#{port}/app-server",
          connect_address: {127, 0, 0, 1},
          tls_opts: tls
        )

      if profile == :trusted do
        assert {:ok, state} = result
        assert_receive {:upgrade_request, _}
        assert {[{:message, "{}"}], state} = pump(state, 1)
        WebSocket.close(state)
      else
        assert {:error, %Error{code: :transport_connect_failed}} = result
      end
    end
  end
end
