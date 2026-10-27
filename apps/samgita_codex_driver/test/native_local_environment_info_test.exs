defmodule SamgitaCodexDriver.NativeLocalEnvironmentInfoTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @schema_sha "9b3fdf205daedad7ce230c8b8b2423b325a087b9b960ea3f82289667ecc2e7d4"
  @original "cwd V519 #%.測試"
  @renamed "renamed V519 #%.測試"
  @original_uri "/cwd%20V519%20%23%25.%E6%B8%AC%E8%A9%A6"
  @renamed_uri "/renamed%20V519%20%23%25.%E6%B8%AC%E8%A9%A6"
  @sentinel "Owned launch cwd stays distinct from HOME and CODEX_HOME.\n"
  @home_marker "Owned independent HOME survives native cwd rename.\n"

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
        "samgita-local-environment-#{System.unique_integer([:positive, :monotonic])}"
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

    original = Path.join(root, @original)
    renamed = Path.join(root, @renamed)
    File.mkdir!(original)
    File.write!(Path.join(original, "owned-cwd.txt"), @sentinel, [:exclusive])
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
      original: original,
      renamed: renamed,
      root_uri: root_uri,
      inputs: inputs,
      home_marker: home_marker,
      capture: capture,
      directory: identity(original)
    })
  end

  test "local native metadata re-reads the renamed process cwd as an exact encoded PathUri",
       ctx do
    warm = start(ctx, ctx.original)
    warm_instance = Session.status(warm.pid).instance_id
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert File.read_link!("/proc/#{warm.native}/cwd") === ctx.original
    initial = local_info(ctx, warm.pid, ctx.root_uri <> @original_uri)
    # Shell selection reads the actual passwd/default-shell environment. It is
    # contextual shape/stability evidence, not a fabricated private-shell oracle.
    shell = Map.fetch!(initial, "shell")
    assert local_info(ctx, warm.pid, ctx.root_uri <> @original_uri) === initial
    assert_controls(ctx, ctx.original)

    assert :ok = File.rename(ctx.original, ctx.renamed)
    refute File.exists?(ctx.original)
    assert identity(ctx.renamed) === ctx.directory
    assert File.read_link!("/proc/#{warm.native}/cwd") === ctx.renamed
    assert call(ctx, warm.pid, "server/diagnostics", %{})["process"]["id"] === warm.native
    assert Process.alive?(warm.pid)
    assert Session.status(warm.pid).instance_id === warm_instance
    renamed = local_info(ctx, warm.pid, ctx.root_uri <> @renamed_uri)
    assert renamed === %{"cwd" => ctx.root_uri <> @renamed_uri, "shell" => shell}
    assert local_info(ctx, warm.pid, ctx.root_uri <> @renamed_uri) === renamed
    assert_controls(ctx, ctx.renamed)
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, ctx.renamed)
    refute cold.native == warm.native
    refute Session.status(cold.pid).instance_id == warm_instance
    assert File.read_link!("/proc/#{cold.native}/cwd") === ctx.renamed
    assert local_info(ctx, cold.pid, ctx.root_uri <> @renamed_uri) === renamed
    assert local_info(ctx, cold.pid, ctx.root_uri <> @renamed_uri) === renamed
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, ctx.renamed)
    assert_idle(cold.pid)
    close(cold)
    assert_controls(ctx, ctx.renamed)
    assert_inventory(ctx)
    close_provider(ctx.fixture)
  end

  test "native configured provider capability upper bounds retain exact identities without starting work",
       ctx do
    assert hash(File.read!(schema_path("v2/ModelProviderCapabilitiesReadParams.json"))) ===
             "9db732188a15476cabb42cf05e495ae0803a1ada993fca7348c21c30a998388d"

    assert hash(File.read!(schema_path("v2/ModelProviderCapabilitiesReadResponse.json"))) ===
             "96979d0111a38cb35a313e111c2f7c449441aee7fd51e1757f2d11c2213d4e77"

    warm_ids = [-530_001, 530_001, "owned-provider-upper-bound-warm-λ🙂"]
    cold_ids = [-530_002, 530_002, "owned-provider-upper-bound-cold-λ🙂"]
    warm = start(ctx, ctx.original)
    warm_instance = Session.status(warm.pid).instance_id
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    for id <- warm_ids, do: assert_provider_capabilities(ctx, warm.pid, id)

    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, ctx.original)
    assert_idle(warm.pid)
    close(warm)

    cold = start(ctx, ctx.original)
    refute cold.native === warm.native
    refute Session.status(cold.pid).instance_id === warm_instance
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    for id <- cold_ids, do: assert_provider_capabilities(ctx, cold.pid, id)

    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_controls(ctx, ctx.original)
    assert_idle(cold.pid)
    close(cold)
    assert_controls(ctx, ctx.original)
    assert_provider_capability_inventory(ctx, warm_ids ++ cold_ids)
    close_provider(ctx.fixture)
    assert_controls(ctx, ctx.original)
  end

  defp assert_provider_capabilities(ctx, pid, id) do
    method = "modelProvider/capabilities/read"
    wire = %{"id" => id, "method" => method, "params" => %{}}
    # The configured provider's immutable upper bounds are independent of model
    # calls, model capabilities, thread state and the values returned here.
    expected = %{"imageGeneration" => true, "webSearch" => true}
    envelope = %{"id" => id, "result" => expected}

    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 32)
    assert :ok = Schema.validate(schema("v2/ModelProviderCapabilitiesReadParams.json"), %{})
    assert {:ok, ^envelope} = Session.request_native(pid, wire, timeout_ms: 5_000)
    assert_exchange(ctx, wire, envelope)

    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] === id))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] === id))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(received.encoded) === envelope
    assert {:ok, ^wire} = Wire.decode(sent.encoded, max_depth: 32)
    assert {:ok, ^envelope} = Wire.decode(received.encoded, max_depth: 32)

    assert :ok =
             Schema.validate(
               schema("v2/ModelProviderCapabilitiesReadResponse.json"),
               received.wire["result"],
               max_depth: 32
             )

    assert_controls(ctx, ctx.original)
  end

  defp assert_provider_capability_inventory(ctx, capability_ids) do
    ledger = Agent.get(ctx.capture, & &1)

    one_process =
      ~w(initialize initialized server/diagnostics thread/loaded/list modelProvider/capabilities/read modelProvider/capabilities/read modelProvider/capabilities/read thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === one_process ++ one_process
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 14 and length(Enum.uniq(ids)) === 14
    assert length(replies) === 14
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)

    capabilities =
      Enum.filter(requests, &(&1.wire["method"] === "modelProvider/capabilities/read"))

    assert Enum.map(capabilities, & &1.wire["id"]) === capability_ids
    assert length(capabilities) === 6
    for request <- capabilities, do: assert(request.wire["params"] === %{})
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
    info = %{"name" => "owned_local_environment_info", "version" => "0.1.0"}
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

  defp assert_controls(ctx, cwd) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert File.ls!(cwd) === ["owned-cwd.txt"]
    assert snapshot(Path.join(cwd, "owned-cwd.txt")).bytes === @sentinel
    assert snapshot(ctx.home_marker).bytes === @home_marker
    refute File.exists?(Path.join(ctx.fixture.codex_home, "environments.toml"))
    assert identity(cwd) === ctx.directory
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
      ~w(initialize initialized server/diagnostics thread/loaded/list environment/info environment/info server/diagnostics environment/info environment/info thread/loaded/list initialize initialized server/diagnostics environment/info environment/info thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))

    replies =
      Enum.filter(
        ledger.in,
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 14
    assert length(replies) == 14
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
    do: "owned-local-environment-info-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
