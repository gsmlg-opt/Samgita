defmodule SamgitaWeb.RawHTTPTelemetryTest do
  use ExUnit.Case, async: false

  # Exposure evidence only: these passing tests do not clear A11. ConnTest does
  # not exercise the server's pre-Plug instrumentation or HTTP/1 body buffer.
  defmodule DiagnosticIngress do
    @behaviour Plug
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      send(opts[:owner], {:diagnostic_entered, self()})

      # Model an early ingress that keeps raw and decoded credentials local.
      # Neither the body nor decoded attrs are assigned to the connection.
      {:ok, body, conn} = read_body(conn, length: 16_384, read_timeout: 1_000)

      case Jason.decode(body) do
        {:ok, %{"credential" => credential}} when is_binary(credential) ->
          send(opts[:owner], {:diagnostic_decoded, byte_size(credential)})

        _ ->
          raise "synthetic diagnostic invalid input"
      end

      if opts[:raise?], do: raise("synthetic diagnostic failure")
      send_resp(conn, 204, "")
    end
  end

  @events [
    [:bandit, :request, :start],
    [:bandit, :request, :stop],
    [:bandit, :request, :exception],
    [:phoenix, :endpoint, :start],
    [:phoenix, :endpoint, :stop],
    [:phoenix, :router_dispatch, :start],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :router_dispatch, :exception],
    [:phoenix, :error_rendered]
  ]

  setup do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    path = "/api/agents/#{Ecto.UUID.generate()}/credentials"
    canary = "synthetic-raw-http-credential-#{suffix}"
    key = "synthetic-raw-http-api-key-#{suffix}"
    handler = {__MODULE__, make_ref()}

    :ok = :telemetry.attach_many(handler, @events, &__MODULE__.capture/4, {self(), path})
    on_exit(fn -> :telemetry.detach(handler) end)

    %{path: path, canary: canary, key: key}
  end

  test "A11 exposure: server start sees plaintext before an ingress that never assigns decoded params",
       %{path: path, canary: canary, key: key} do
    port = listener({DiagnosticIngress, owner: self()})
    response = raw_request(port, path, Jason.encode!(%{credential: canary}), key)
    assert response =~ "HTTP/1.1 204"
    refute response =~ canary
    refute response =~ key

    # These messages originate in the same server process. Matching the first
    # message proves the raw event preceded entry into the diagnostic Plug.
    assert_receive first, 1_000
    assert {:raw_http_telemetry, [:bandit, :request, :start], start} = first
    assert_receive {:diagnostic_entered, _server}, 1_000
    assert_receive {:diagnostic_decoded, size}, 1_000
    assert size == byte_size(canary)
    assert_unparsed_exposure(start, canary, key)

    stop = observation([:bandit, :request, :stop])
    assert %Plug.Conn.Unfetched{} = stop.conn.params
    assert %Plug.Conn.Unfetched{} = stop.conn.body_params
    refute contains?(stop, canary)
    assert contains?(stop, key)
  end

  @tag capture_log: true
  test "A11 exposure: a generic ingress exception reuses the credential-bearing server start metadata",
       %{path: path, canary: canary, key: key} do
    port = listener({DiagnosticIngress, owner: self(), raise?: true})
    response = raw_request(port, path, Jason.encode!(%{credential: canary}), key)
    assert response =~ "HTTP/1.1 500"
    refute response =~ canary
    refute response =~ key

    start = observation([:bandit, :request, :start])
    assert_unparsed_exposure(start, canary, key)
    exception = observation([:bandit, :request, :exception])
    assert %RuntimeError{message: "synthetic diagnostic failure"} = exception.exception
    refute contains?(exception.exception, canary)
    assert_unparsed_exposure(exception, canary, key)
  end

  test "A11 exposure: the real endpoint parses a credential before rejecting an unauthorized API key",
       %{path: path, canary: canary, key: key} do
    previous = Application.get_env(:samgita, :api_keys, [])
    Application.put_env(:samgita, :api_keys, ["synthetic-configured-key-never-submitted"])
    on_exit(fn -> Application.put_env(:samgita, :api_keys, previous) end)
    port = listener(SamgitaWeb.Endpoint)
    response = raw_request(port, path, Jason.encode!(%{credential: canary}), key)
    assert response =~ "HTTP/1.1 401"
    refute response =~ canary
    refute response =~ key

    assert_unparsed_exposure(observation([:bandit, :request, :start]), canary, key)
    assert_unparsed_exposure(observation([:phoenix, :endpoint, :start]), canary, key)

    for event <- [
          [:phoenix, :router_dispatch, :start],
          [:phoenix, :router_dispatch, :stop],
          [:phoenix, :endpoint, :stop],
          [:bandit, :request, :stop]
        ] do
      metadata = observation(event)
      assert metadata.conn.body_params["credential"] == canary
      assert contains?(metadata, canary)
      assert contains?(metadata, key)
    end
  end

  test "A11 exposure: malformed credential JSON reaches real endpoint and server exception metadata",
       %{path: path, canary: canary, key: key} do
    port = listener(SamgitaWeb.Endpoint)
    # Missing closing brace deliberately exercises the retained parser's error.
    response = raw_request(port, path, ~s({"credential":"#{canary}"), key)
    assert response =~ "HTTP/1.1 400"
    refute response =~ canary
    refute response =~ key

    assert_unparsed_exposure(observation([:bandit, :request, :start]), canary, key)
    assert_unparsed_exposure(observation([:phoenix, :endpoint, :start]), canary, key)
    rendered = observation([:phoenix, :error_rendered])
    assert rendered.status == 400
    assert contains?(rendered, canary)
    assert contains?(rendered, key)
    exception = observation([:bandit, :request, :exception])
    assert %Plug.Parsers.ParseError{} = exception.exception
    assert contains?(exception, canary)
    assert contains?(exception, key)
  end

  def capture(event, _measurements, %{conn: %{request_path: path}} = metadata, {owner, path}),
    do: send(owner, {:raw_http_telemetry, event, metadata})

  def capture(_event, _measurements, _metadata, _config), do: :ok

  defp listener(plug) do
    listener =
      start_supervised!(
        {Bandit,
         plug: plug,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false,
         http_2_options: [enabled: false]}
      )

    # ExUnit stops supervised children before on_exit callbacks. Confirm the
    # disposable listener is gone, including when an assertion fails.
    on_exit(fn ->
      ref = Process.monitor(listener)
      assert_receive {:DOWN, ^ref, :process, ^listener, _reason}, 1_000
    end)

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(listener)
    port
  end

  defp raw_request(port, path, body, key) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :raw], 1_000)

    try do
      # One small loopback write coalesces headers and body. Sending the body
      # only after server start would miss the pre-Plug HTTP/1 buffer exposure.
      request =
        "POST #{path} HTTP/1.1\r\n" <>
          "Host: localhost\r\nContent-Type: application/json\r\n" <>
          "X-API-Key: #{key}\r\nContent-Length: #{byte_size(body)}\r\n" <>
          "Connection: close\r\n\r\n" <> body

      assert byte_size(request) < 1_024
      assert :ok = :gen_tcp.send(socket, request)
      response(socket, [])
    after
      :gen_tcp.close(socket)
    end
  end

  defp response(socket, chunks) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} -> response(socket, [chunk | chunks])
      {:error, :closed} -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
      other -> flunk("Expected a complete response and connection close, got: #{inspect(other)}")
    end
  end

  defp observation(event) do
    assert_receive {:raw_http_telemetry, ^event, metadata}, 1_000
    metadata
  end

  defp assert_unparsed_exposure(metadata, canary, key) do
    assert %Plug.Conn.Unfetched{} = metadata.conn.params
    assert %Plug.Conn.Unfetched{} = metadata.conn.body_params
    assert contains?(metadata, canary)
    assert contains?(metadata, key)
    {_adapter, state} = metadata.conn.adapter
    assert contains?(state.transport.buffer, canary)
  end

  # Inspect implementations can hide fields. External-term encoding traverses
  # the actual metadata, including the private adapter/transport structs.
  defp contains?(term, canary),
    do: :binary.match(:erlang.term_to_binary(term), canary) != :nomatch
end
