defmodule SamgitaCodexDriver.NativeDiagnosticsSuccessTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144
  @uint64_max 18_446_744_073_709_551_615

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
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 256 and size <= 262_144 and ledger.bytes + size <= 4_194_304 do
          entry = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
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

    binary = Path.expand(binary)
    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@provider)) === @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-diagnostics-success-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
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

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.merge(ctx, %{
      inputs: Map.new(inputs, &{&1, bounded_file(&1)}),
      page_size: independent_page_size(ctx)
    })
  end

  test "native diagnostics report owned process memory and registered live threads across a cold restart",
       ctx do
    assert_retained(ctx)
    warm = start(ctx)
    empty = diagnostics(ctx, warm)
    warm_native = empty["process"]["id"]
    assert_unregistered_threads(empty)
    assert_unloaded(ctx, warm.pid)

    first = start_empty_thread(ctx, warm.pid)
    second = start_empty_thread(ctx, warm.pid)
    refute first === second
    expected_ids = Enum.sort([first, second])
    assert %{"data" => ids, "nextCursor" => nil} = call(ctx, warm.pid, "thread/loaded/list", %{})
    assert Enum.sort(ids) === expected_ids

    loaded = diagnostics(ctx, warm)
    assert loaded["process"]["id"] === warm_native
    assert gauge(loaded, "core.threads.live") === 2

    for id <- expected_ids do
      assert call(ctx, warm.pid, "thread/archive", %{"threadId" => id}) === %{}
    end

    assert_idle(ctx, warm.pid)
    close(warm, warm_native)
    assert_retained(ctx)

    cold = start(ctx)
    restarted = diagnostics(ctx, cold)
    cold_native = restarted["process"]["id"]
    refute cold_native === warm_native
    assert_unregistered_threads(restarted)
    assert_unloaded(ctx, cold.pid)

    for id <- expected_ids do
      assert %{"thread" => thread} = call(ctx, cold.pid, "thread/read", %{"threadId" => id})
      assert thread["id"] === id
      assert thread["turns"] === []
    end

    after_reads = diagnostics(ctx, cold)
    assert after_reads["process"]["id"] === cold_native
    assert_unregistered_threads(after_reads)
    assert_unloaded(ctx, cold.pid)
    assert_idle(ctx, cold.pid)
    close(cold, cold_native)
    assert_retained(ctx)
    assert_wire_inventory(ctx)
  end

  defp diagnostics(ctx, session) do
    result = call(ctx, session.pid, "server/diagnostics", %{})
    assert Enum.sort(Map.keys(result)) === ["gauges", "process"]
    process = Map.fetch!(result, "process")

    assert Enum.sort(Map.keys(process)) ===
             ["id", "physicalFootprintBytes", "residentMemoryBytes"]

    native = Map.fetch!(process, "id")
    assert is_integer(native) and native > 0 and native <= 4_294_967_295
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    assert File.read_link!("/proc/#{native}/exe") === ctx.binary
    assert {:os_pid, helper} = Port.info(session.connection.port, :os_pid)
    status = File.read!("/proc/#{native}/status")
    assert [_, parent] = Regex.run(~r/^PPid:\s+(\d+)$/m, status)
    assert String.to_integer(parent) === helper

    resident = Map.fetch!(process, "residentMemoryBytes")
    assert_uint64(resident)
    assert resident > 0
    assert rem(resident, ctx.page_size) === 0
    assert Map.fetch!(process, "physicalFootprintBytes") === nil

    gauges = Map.fetch!(result, "gauges")
    assert is_list(gauges) and length(gauges) <= 256

    for row <- gauges do
      assert Enum.sort(Map.keys(row)) === ["name", "value"]
      assert is_binary(row["name"]) and byte_size(row["name"]) > 0
      assert_uint64(Map.fetch!(row, "value"))
    end

    names = Enum.map(gauges, &Map.fetch!(&1, "name"))
    assert names === Enum.sort(names)
    assert names === Enum.uniq(names)
    assert gauge(result, "app.requests.in_flight") in [1, 2]
    result
  end

  defp start_empty_thread(ctx, pid) do
    # No per-request permission overrides: ordinary_args supplies the fixed YOLO launch.
    result =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false
      })

    assert %{"thread" => %{"id" => id, "turns" => []}} = result
    assert is_binary(id) and byte_size(id) > 0
    id
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    },
                    max_message_bytes: @max_line_bytes
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_native_diagnostics", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params) do
    id = "owned-native-diagnostics-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [sent, received] = Enum.filter(capture(ctx), &(&1.wire["id"] == id))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and received.wire === response
    assert JSON.decode!(sent.encoded) === wire
    assert JSON.decode!(received.encoded) === response
    result
  end

  defp independent_page_size(ctx) do
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    assert {:ok, probe} =
             Stdio.open(
               executable: python,
               args: [
                 "-I",
                 "-S",
                 "-c",
                 "import json,os; print(json.dumps({'page_size':os.sysconf('SC_PAGE_SIZE')}),flush=True)"
               ],
               cwd: ctx.fixture.workspace,
               inherit_env: [],
               env: %{"CODEX_HOME" => ctx.fixture.codex_home},
               max_message_bytes: 256
             )

    try do
      assert %{"page_size" => size} = page_size_message(probe, now() + 5_000)
      assert is_integer(size) and size > 0
      size
    after
      assert :ok = Stdio.close(probe)
      assert :atomics.get(probe.owner.completion, 1) === 1
      assert Port.info(probe.port) === nil
    end
  end

  defp page_size_message(probe, deadline) do
    remaining = max(0, deadline - now())
    port = probe.port

    receive do
      {^port, {:data, _}} = message ->
        assert {:ok, events, next} = Stdio.handle_info(message, probe)

        case events do
          [] -> page_size_message(next, deadline)
          [{:message, encoded}] -> JSON.decode!(encoded)
          other -> flunk("Unexpected page-size probe events: #{inspect(other)}")
        end

      {^port, {:exit_status, status}} ->
        flunk("Page-size probe exited before its result: #{status}")
    after
      remaining -> flunk("Page-size probe deadline")
    end
  end

  defp gauge(result, name) do
    assert [%{"value" => value}] = Enum.filter(result["gauges"], &(&1["name"] === name))
    value
  end

  defp assert_unregistered_threads(result),
    do: refute(Enum.any?(result["gauges"], &(&1["name"] === "core.threads.live")))

  defp assert_unloaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_uint64(value),
    do: assert(is_integer(value) and value >= 0 and value <= @uint64_max)

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.all?(events, &(&1.wire["method"] != "error"))
    assert ModelFixture.requests(ctx.fixture) === []
  end

  defp close(session, native) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    refute File.exists?("/proc/#{native}")
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp assert_retained(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
    assert ModelFixture.requests(ctx.fixture) === []
  end

  defp assert_wire_inventory(ctx) do
    records = capture(ctx)
    outgoing = for %{direction: :out, wire: wire} <- records, do: wire

    assert Enum.frequencies_by(outgoing, & &1["method"]) === %{
             "initialize" => 2,
             "initialized" => 2,
             "server/diagnostics" => 4,
             "thread/start" => 2,
             "thread/loaded/list" => 4,
             "thread/archive" => 2,
             "thread/read" => 2
           }

    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp capture(ctx), do: Agent.get(ctx.capture, &Enum.reverse(&1.records))

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) === size
    bytes
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
