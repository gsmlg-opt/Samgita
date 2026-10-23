defmodule SamgitaCodexDriver.TransportRealCodexTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket, WebSocket}
  @moduletag :real_codex
  @moduletag timeout: 30_000

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: set CODEX_BINARY to the immutable pinned upstream executable"

    dir = Path.join(System.tmp_dir!(), "samgita-real-codex-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{binary: binary, dir: dir}
  end

  defp process_opts(binary, dir, listen) do
    [
      executable: binary,
      args: ["app-server", "--listen", listen],
      cwd: dir,
      env: %{"HOME" => dir, "CODEX_HOME" => dir, "CODEX_DISABLE_REMOTE_CONTROL" => "1"}
    ]
  end

  defp call(module, state, id, method, params) do
    json = JSON.encode!(%{"id" => id, "method" => method, "params" => params})
    {:ok, state} = module.send(state, json)
    wait(module, state, id, System.monotonic_time(:millisecond) + 15_000)
  end

  defp wait(module, state, id, deadline) do
    receive do
      message ->
        case module.handle_info(message, state) do
          {:ok, events, state} ->
            response =
              Enum.find_value(events, fn
                {:message, json} ->
                  decoded = JSON.decode!(json)
                  if decoded["id"] == id, do: decoded

                _ ->
                  nil
              end)

            if response, do: {response, state}, else: wait(module, state, id, deadline)

          :unknown ->
            wait(module, state, id, deadline)

          error ->
            flunk("real Codex transport failure #{inspect(error)}")
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("real Codex response deadline")
    end
  end

  defp qualify(module, state) do
    {response, state} =
      call(module, state, "init", "initialize", %{
        "clientInfo" => %{"name" => "samgita_codex_transport_test", "version" => "0.1.0"}
      })

    assert %{"result" => %{"platformOs" => _, "codexHome" => _, "userAgent" => _}} = response
    {:ok, state} = module.send(state, JSON.encode!(%{"method" => "initialized"}))
    {response, state} = call(module, state, 1, "thread/list", %{})
    assert %{"result" => %{"data" => data}} = response
    assert is_list(data)
    state
  end

  test "pinned binary stdio initializes and reads thread list", %{binary: binary, dir: dir} do
    {:ok, state} = Stdio.open(process_opts(binary, dir, "stdio://"))
    on_exit(fn -> Stdio.close(state) end)
    state = qualify(Stdio, state)
    assert :ok = Stdio.close(state)
  end

  test "pinned binary WebSocket initializes with capability-token authentication", %{
    binary: binary,
    dir: dir
  } do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    token = "synthetic-codex-transport-token"
    digest = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    opts = process_opts(binary, dir, "ws://127.0.0.1:#{port}")

    opts =
      Keyword.update!(
        opts,
        :args,
        &(&1 ++ ["--ws-auth", "capability-token", "--ws-token-sha256", digest])
      )

    {:ok, owner} = Stdio.open(opts)
    on_exit(fn -> Stdio.close(owner) end)
    wait_listener(port)

    assert {:error, %{code: :transport_unauthorized, details: %{"http_status" => 401}}} =
             WebSocket.open(url: "ws://127.0.0.1:#{port}/app-server")

    {:ok, state} = WebSocket.open(url: "ws://127.0.0.1:#{port}/app-server", token: token)
    on_exit(fn -> WebSocket.close(state) end)
    state = qualify(WebSocket, state)
    WebSocket.close(state)
    assert Port.info(owner.port)
  end

  test "pinned binary UDS uses WebSocket and closing client leaves server and socket", %{
    binary: binary,
    dir: dir
  } do
    socket = Path.join(dir, "codex.sock")
    {:ok, owner} = Stdio.open(process_opts(binary, dir, "unix://" <> socket))
    on_exit(fn -> Stdio.close(owner) end)
    await(fn -> File.exists?(socket) end)
    {:ok, state} = UnixSocket.open(socket_path: socket)
    on_exit(fn -> UnixSocket.close(state) end)
    state = qualify(UnixSocket, state)
    UnixSocket.close(state)
    assert Port.info(owner.port)
    assert File.exists?(socket)
  end

  defp wait_listener(port),
    do:
      await(fn ->
        case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 50) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            true

          _ ->
            false
        end
      end)

  defp await(fun, tries \\ 200)
  defp await(fun, 0), do: assert(fun.())

  defp await(fun, tries) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(25)
          await(fun, tries - 1)
        )
  end
end
