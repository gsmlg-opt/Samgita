defmodule SamgitaCodexDriver.InitializedFixture do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias SamgitaCodexDriver.NativeLaunchFixture
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket, WebSocket}
  alias SamgitaProtocolCodex.Wire

  def setup(_tags) do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-initialized-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    home = Path.join(root, "home")
    codex_home = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    Enum.each([home, codex_home, workspace], &File.mkdir!/1)
    %{binary: binary, root: root, home: home, codex_home: codex_home, workspace: workspace}
  end

  def open(context, :stdio) do
    {:ok, state} = Stdio.open(process_opts(context, "stdio://"))
    on_exit(fn -> assert :ok = Stdio.close(state) end)
    %{module: Stdio, state: state, owner: nil, socket: nil}
  end

  def open(context, :websocket) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_, port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)
    token = "synthetic-initialized-token"
    digest = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    opts =
      context
      |> process_opts("ws://127.0.0.1:#{port}")
      |> Keyword.update!(
        :args,
        &(&1 ++ ["--ws-auth", "capability-token", "--ws-token-sha256", digest])
      )

    owner = owner(opts)
    await(fn -> listening?(port) end, now() + 10_000)
    client_opts = [url: "ws://127.0.0.1:#{port}/app-server", token: token]
    {:ok, state} = WebSocket.open(client_opts)
    on_exit(fn -> assert :ok = WebSocket.close(state) end)
    %{module: WebSocket, state: state, owner: owner, socket: nil, client_opts: client_opts}
  end

  def open(context, :unix_socket) do
    socket = Path.join(context.root, "codex.sock")
    owner = owner(process_opts(context, "unix://" <> socket))
    await(fn -> File.exists?(socket) end, now() + 10_000)
    client_opts = [socket_path: socket]
    {:ok, state} = UnixSocket.open(client_opts)
    on_exit(fn -> assert :ok = UnixSocket.close(state) end)
    %{module: UnixSocket, state: state, owner: owner, socket: socket, client_opts: client_opts}
  end

  def assert_borrowed_survival(%{owner: nil}, _negotiation), do: :ok

  def assert_borrowed_survival(%{module: module, client_opts: opts}, negotiation) do
    {:ok, state} = module.open(opts)
    on_exit(fn -> assert :ok = module.close(state) end)
    id = "survival-initialize-#{System.unique_integer([:positive])}"
    {response, state} = initialize(module, state, negotiation, id)
    assert %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response
    state = assert_read(module, state, id <> "-read")
    assert :ok = module.close(state)
  end

  def close_owner(%{owner: nil}), do: :ok

  def close_owner(%{owner: owner, socket: socket}) do
    assert Port.info(owner.port)
    if socket, do: assert(File.exists?(socket))
    assert :ok = Stdio.close(owner)
  end

  def notify(module, state, wire) do
    assert {:ok, encoded} = Wire.encode(wire)
    assert {:ok, state} = module.send(state, encoded)
    state
  end

  def initialize(module, state, negotiation, id \\ "initialize") do
    params = %{"clientInfo" => %{"name" => "samgita_initialized_probe", "version" => "0.1.0"}}

    params =
      if negotiation == :absent,
        do: params,
        else: Map.put(params, "capabilities", %{"experimentalApi" => negotiation})

    request(module, state, id, "initialize", params)
  end

  def read(module, state, id), do: request(module, state, id, "thread/list", %{})

  def assert_read(module, state, id) do
    {response, state} = read(module, state, id)
    assert %{"id" => ^id, "result" => %{"data" => data}} = response
    assert is_list(data)
    state
  end

  def assert_quiet(module, state), do: receive_until(module, state, nil, now() + 100)

  defp request(module, state, id, method, params) do
    state = notify(module, state, %{"id" => id, "method" => method, "params" => params})
    receive_until(module, state, id, now() + 10_000)
  end

  defp receive_until(module, state, id, deadline) do
    if now() >= deadline,
      do: deadline_result(state, id),
      else: receive_more(module, state, id, deadline)
  end

  defp receive_more(module, state, id, deadline) do
    receive do
      message ->
        case module.handle_info(message, state) do
          {:ok, events, state} ->
            response = inspect_events(events, id)

            if response,
              do: {response, state},
              else: receive_until(module, state, id, deadline)

          :unknown ->
            receive_until(module, state, id, deadline)

          error ->
            flunk("Initialized transport failure: #{inspect(error)}")
        end
    after
      max(deadline - now(), 0) ->
        deadline_result(state, id)
    end
  end

  defp deadline_result(state, nil), do: state
  defp deadline_result(_state, id), do: flunk("Initialized response deadline for #{id}")

  defp inspect_events(events, id) do
    Enum.reduce(events, nil, fn
      {:message, encoded}, response ->
        assert {:ok, wire} = Wire.decode(encoded)

        if Map.has_key?(wire, "id") do
          assert not is_nil(id), "Unexpected acknowledgement: #{inspect(wire)}"
          assert wire["id"] == id, "Unexpected response: #{inspect(wire)}"
          assert is_nil(response), "Duplicate response for #{id}"
          wire
        else
          assert Wire.classify(wire) == :notification
          refute wire["method"] == "initialized"
          response
        end

      event, _response ->
        flunk("Unexpected initialized transport event: #{inspect(event)}")
    end)
  end

  defp owner(opts) do
    {:ok, owner} = Stdio.open(opts)
    on_exit(fn -> assert :ok = Stdio.close(owner) end)
    owner
  end

  defp process_opts(context, listen) do
    [
      executable: context.binary,
      args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", listen]),
      cwd: context.workspace,
      env: %{
        "HOME" => context.home,
        "CODEX_HOME" => context.codex_home,
        "CODEX_DISABLE_REMOTE_CONTROL" => "1"
      }
    ]
  end

  defp listening?(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 25) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp await(predicate, deadline) do
    if predicate.() do
      :ok
    else
      assert now() < deadline, "Initialized listener startup deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
