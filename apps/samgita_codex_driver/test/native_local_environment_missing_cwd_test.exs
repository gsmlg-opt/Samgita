defmodule SamgitaCodexDriver.NativeLocalEnvironmentMissingCwdTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @schema_sha "9b3fdf205daedad7ce230c8b8b2423b325a087b9b960ea3f82289667ecc2e7d4"
  @launch "missing cwd V520 #%.測試"
  @launch_uri "/missing%20cwd%20V520%20%23%25.%E6%B8%AC%E8%A9%A6"
  @home_marker "Owned independent HOME survives missing native cwd.\n"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 32, else: 128
      message_limit = if direction == :out, do: 4096, else: 65_536
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 1_048_576 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-local-environment-missing-cwd-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> close_provider(fixture) end)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    launch = Path.join(root, @launch)
    File.mkdir!(launch)
    home_marker = Path.join(fixture.home, "owned-home.txt")
    File.write!(home_marker, @home_marker, [:exclusive])
    # The URI root is solely our generated input; each interesting suffix is
    # authored literally above, independently of native replies or PathUri.
    root_uri = "file://" <> URI.encode(root, &(&1 == ?/ or URI.char_unreserved?(&1)))
    schema_path = schema_path("v2/EnvironmentInfoResponse.json")
    assert hash(File.read!(schema_path)) == @schema_sha

    inputs =
      Map.new(
        [
          config,
          Path.join(fixture.codex_home, "turn-models.json"),
          fixture.requests,
          home_marker,
          schema_path,
          @provider,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    Map.merge(ctx, %{
      launch: launch,
      root_uri: root_uri,
      inputs: inputs,
      home_marker: home_marker,
      capture: capture,
      directory: identity(launch)
    })
  end

  test "an unlinked owned local cwd stays explicitly null until a distinct native process starts",
       ctx do
    warm = start(ctx, ctx.launch)
    warm_instance = Session.status(warm.pid).instance_id
    initial = local_info(ctx, warm.pid, ctx.root_uri <> @launch_uri)
    shell = Map.fetch!(initial, "shell")
    assert File.read_link!("/proc/#{warm.native}/cwd") === ctx.launch
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, warm, :original)

    # This is a new empty fixture directory only. The running native process
    # retains its original inode; no permissions or provider result changes.
    assert File.ls!(ctx.launch) === []
    assert :ok = File.rmdir(ctx.launch)
    assert_controls(ctx, warm, :unlinked)
    missing = local_info(ctx, warm.pid, nil)
    assert missing === %{"cwd" => nil, "shell" => shell}
    assert local_info(ctx, warm.pid, nil) === missing
    assert Session.status(warm.pid).instance_id === warm_instance
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, warm, :unlinked)

    # A newly created directory at the same pathname cannot reattach the old
    # process cwd. Its actual held inode and the native explicit-null reply
    # distinguish this from a cached path or a constant synthetic response.
    assert :ok = File.mkdir(ctx.launch)
    assert_controls(ctx, warm, :recreated)
    assert local_info(ctx, warm.pid, nil) === missing
    assert local_info(ctx, warm.pid, nil) === missing
    assert Session.status(warm.pid).instance_id === warm_instance
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, warm, :recreated)
    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, ctx.launch)
    refute cold.native == warm.native
    refute Session.status(cold.pid).instance_id == warm_instance
    assert File.read_link!("/proc/#{cold.native}/cwd") === ctx.launch
    assert_controls(ctx, cold, :cold)
    assert local_info(ctx, cold.pid, ctx.root_uri <> @launch_uri) === initial
    assert local_info(ctx, cold.pid, ctx.root_uri <> @launch_uri) === initial
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, cold, :cold)
    assert_idle(cold.pid)
    close(cold)
    assert File.ls!(ctx.launch) === []
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_inventory(ctx)
    close_provider(ctx.fixture)
  end

  defp local_info(ctx, pid, expected_cwd) do
    result = call(ctx, pid, "environment/info", %{"environmentId" => "local"})
    assert :ok = Schema.validate(schema("v2/EnvironmentInfoResponse.json"), result, max_depth: 32)
    assert Map.keys(result) |> Enum.sort() === ["cwd", "shell"]
    assert Map.fetch!(result, "cwd") === expected_cwd
    shell = Map.fetch!(result, "shell")
    assert Map.keys(shell) |> Enum.sort() === ["name", "path"]
    assert is_binary(shell["name"]) and shell["name"] != ""
    assert is_binary(shell["path"]) and shell["path"] != ""
    result
  end

  defp start(ctx, cwd) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 262_144,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: cwd,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_local_environment_missing_cwd", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert Port.info(connection.port) != nil
    assert %{transport: CaptureStdio} = :sys.get_state(pid)
    assert_idle(pid)
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))

    assert [received] =
             Enum.filter(
               ledger.in,
               &(&1.wire["id"] == wire["id"] and not Map.has_key?(&1.wire, "method"))
             )

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() === ["id", "result"]
  end

  defp assert_controls(ctx, session, stage) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert snapshot(ctx.home_marker).bytes === @home_marker
    refute File.exists?(Path.join(ctx.fixture.codex_home, "environments.toml"))
    assert Process.alive?(session.pid)
    assert File.exists?("/proc/#{session.native}/exe")
    held = identity("/proc/#{session.native}/cwd")

    case stage do
      :original ->
        assert File.ls!(ctx.launch) === []
        assert identity(ctx.launch) === ctx.directory
        assert held === ctx.directory

      :unlinked ->
        refute File.exists?(ctx.launch)
        assert held === ctx.directory

      :recreated ->
        assert File.ls!(ctx.launch) === []
        refute identity(ctx.launch) === ctx.directory
        assert held === ctx.directory

      :cold ->
        assert File.ls!(ctx.launch) === []
        refute identity(ctx.launch) === ctx.directory
        assert held === identity(ctx.launch)
    end
  end

  defp assert_idle(pid) do
    assert Session.uncertain_operations(pid) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 262_144
    assert {:ok, []} = Session.drain(pid, 128)
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    expected =
      ~w(initialize initialized server/diagnostics environment/info thread/loaded/list environment/info environment/info thread/loaded/list environment/info environment/info thread/loaded/list initialize initialized server/diagnostics environment/info environment/info thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))

    replies =
      Enum.filter(
        ledger.in,
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 15
    assert length(replies) == 15
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)

    for request <- Enum.filter(requests, &(&1.wire["method"] == "environment/info")),
        do: assert(request.wire["params"] === %{"environmentId" => "local"})
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp identity(path) do
    stat = File.stat!(path)
    %{inode: stat.inode, major_device: stat.major_device, minor_device: stat.minor_device}
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(relative), do: relative |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)

  defp request_id,
    do: "owned-local-environment-missing-cwd-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
