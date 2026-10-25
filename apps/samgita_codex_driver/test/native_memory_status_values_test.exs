defmodule SamgitaCodexDriver.NativeMemoryStatusValuesTest do
  @moduledoc """
  Real pinned status reader with synthetic persisted count/summary inputs.
  This does not qualify generation, consolidation, its writer, or context use.
  """
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
  @input_fixture Path.expand("../../../scripts/codex/memory_status_input_fixture.py", __DIR__)
  @summary """
  v1
  ## User Profile
  Synthetic reader fixture.
  ## User preferences
  Synthetic preference.
  ## General Tips
  Synthetic tip.
  ## What's in Memory
  Synthetic source.
  """

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] == "memory/status" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha
    assert File.regular?(@input_fixture)
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      for path <- [
            config,
            Path.join(ctx.fixture.codex_home, "turn-models.json"),
            ctx.fixture.requests
          ],
          into: %{} do
        {path, snapshot(path)}
      end

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "real memory status reads synthetic progress summary threshold defaults and cold state",
       ctx do
    database = Path.join(ctx.fixture.codex_home, "memories_v2_1.sqlite")
    summary = Path.join([ctx.fixture.codex_home, "memories_v2", "memory_summary.md"])
    refute File.exists?(database)
    refute File.exists?(summary)
    assert File.ls!(ctx.fixture.workspace) == []

    {first, first_native} = start(ctx)
    # Only the public request initializes the genuine native database/schema.
    status(ctx, first, %{}, 0, false)
    assert_retained(ctx, first, ctx.inputs)
    close(first, first_native)
    assert File.regular?(database)
    assert_input(ctx, "read", first_native, 0, 0)

    # Synthetic reader input, not a production consolidation success.
    assert_input(ctx, "seed-two", first_native, 2, 1)
    assert_input(ctx, "read", first_native, 2, 0)
    refute File.exists?(summary)

    {without_summary, second_native} = start(ctx)
    refute second_native == first_native
    status(ctx, without_summary, %{"minConsolidatedThreads" => 2}, 2, false)
    refute File.exists?(summary)
    assert_retained(ctx, without_summary, ctx.inputs)
    close(without_summary, second_native)
    assert_input(ctx, "read", second_native, 2, 0)

    # This literal is controlled saved input to the real reader. No generator,
    # consolidation Agent, production success transaction or writer ran.
    File.mkdir_p!(Path.dirname(summary))
    File.write!(summary, @summary)
    inputs = Map.put(ctx.inputs, summary, %{bytes: @summary, sha256: hash(@summary)})

    {with_summary, third_native} = start(ctx)
    refute third_native in [first_native, second_native]

    for {params, ready} <- [
          {%{"minConsolidatedThreads" => 1}, true},
          {%{"minConsolidatedThreads" => 2}, true},
          {%{"minConsolidatedThreads" => 3}, false},
          {%{}, false},
          {%{"minConsolidatedThreads" => nil}, false},
          {%{"minConsolidatedThreads" => 4096}, false}
        ] do
      status(ctx, with_summary, params, 2, ready)
      assert_retained(ctx, with_summary, inputs)
    end

    close(with_summary, third_native)
    assert_input(ctx, "read", third_native, 2, 0)

    {cold, fourth_native} = start(ctx)
    refute fourth_native in [first_native, second_native, third_native]
    status(ctx, cold, %{"minConsolidatedThreads" => 2}, 2, true)
    assert_retained(ctx, cold, inputs)
    close(cold, fourth_native)
    assert_input(ctx, "read", fourth_native, 2, 0)

    # Bracket the actual omitted/null default using independently prepared
    # counts. A different default such as three cannot satisfy both states.
    assert_input(ctx, "seed-nineteen", fourth_native, 19, 1)
    assert_input(ctx, "read", fourth_native, 19, 0)
    {below_default, fifth_native} = start(ctx)
    refute fifth_native in [first_native, second_native, third_native, fourth_native]
    status(ctx, below_default, %{}, 19, false)
    status(ctx, below_default, %{"minConsolidatedThreads" => nil}, 19, false)
    assert_retained(ctx, below_default, inputs)
    close(below_default, fifth_native)
    assert_input(ctx, "read", fifth_native, 19, 0)

    assert_input(ctx, "seed-twenty", fifth_native, 20, 1)
    assert_input(ctx, "read", fifth_native, 20, 0)
    {at_default, sixth_native} = start(ctx)

    refute sixth_native in [
             first_native,
             second_native,
             third_native,
             fourth_native,
             fifth_native
           ]

    status(ctx, at_default, %{}, 20, true)
    status(ctx, at_default, %{"minConsolidatedThreads" => nil}, 20, true)
    assert_retained(ctx, at_default, inputs)
    close(at_default, sixth_native)
    assert_input(ctx, "read", sixth_native, 20, 0)

    assert snapshot(summary) === Map.fetch!(inputs, summary)
    assert snapshot(ctx.fixture.requests) === Map.fetch!(ctx.inputs, ctx.fixture.requests)

    assert Enum.map(Agent.get(ctx.capture, & &1), & &1.wire["params"]) === [
             %{},
             %{"minConsolidatedThreads" => 2},
             %{"minConsolidatedThreads" => 1},
             %{"minConsolidatedThreads" => 2},
             %{"minConsolidatedThreads" => 3},
             %{},
             %{"minConsolidatedThreads" => nil},
             %{"minConsolidatedThreads" => 4096},
             %{"minConsolidatedThreads" => 2},
             %{},
             %{"minConsolidatedThreads" => nil},
             %{},
             %{"minConsolidatedThreads" => nil}
           ]
  end

  defp status(ctx, pid, params, count, ready) do
    assert call(ctx, pid, "memory/status", params) === %{
             "v2ConsolidatedThreads" => count,
             "v2Ready" => ready
           }
  end

  defp assert_input(ctx, operation, stopped_native, count, updated) do
    refute File.exists?("/proc/#{stopped_native}")
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    assert {:ok, connection} =
             Stdio.open(
               executable: python,
               cwd: ctx.fixture.workspace,
               inherit_env: [],
               env: %{
                 "HOME" => ctx.fixture.home,
                 "CODEX_HOME" => ctx.fixture.codex_home,
                 "TMPDIR" => ctx.root
               },
               args: [
                 "-B",
                 @input_fixture,
                 operation,
                 "--codex-home",
                 ctx.fixture.codex_home,
                 "--stopped-native-pid",
                 to_string(stopped_native)
               ]
             )

    try do
      assert read_input_output(connection.port, <<>>, deadline(5_000)) === %{
               "singleton" => 1,
               "max_thread_count" => count,
               "updated_rows" => updated
             }
    after
      assert :ok = Stdio.close(connection)
    end
  end

  defp read_input_output(port, bytes, until) do
    remaining = max(until - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, incoming}} ->
        bytes = bytes <> incoming
        assert byte_size(bytes) <= 4096, "Memory input observation exceeded its byte bound"
        assert System.monotonic_time(:millisecond) < until, "memory input observation deadline"
        read_input_output(port, bytes, until)

      {^port, {:exit_status, 0}} ->
        assert System.monotonic_time(:millisecond) < until, "memory input observation deadline"
        JSON.decode!(String.trim(bytes))

      {^port, {:exit_status, code}} ->
        flunk("Memory input helper exited #{code}: #{bytes}")
    after
      remaining -> flunk("memory input observation deadline")
    end
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-memory-status-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    captured = Agent.get(ctx.capture, &Enum.drop(&1, before))

    if method == "memory/status" do
      assert [%{encoded: encoded, wire: recorded}] = captured
      assert recorded === wire
      assert JSON.decode!(encoded) === wire
    else
      assert captured == []
    end

    result
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, expected} <- inputs, do: assert(snapshot(path) === expected)
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_memory_status_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {pid, native}
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
