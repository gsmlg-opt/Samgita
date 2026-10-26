defmodule SamgitaCodexDriver.NativeInitializeTitleValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @name "samgita_owned_initialize_title"
  @version "1.2.3"
  @title "Owned initialization display λ🙂"

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

      if wire["method"] == "initialize" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if Agent.get(state.capture, & &1) == [] and byte_size(encoded) <= 4096 do
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
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    assert ModelFixture.requests(ctx.fixture) == []
    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "native initialization with absent title retains name version and ordinary readiness",
       ctx do
    qualify(ctx, "absent", %{})
  end

  test "native initialization with null title retains name version and ordinary readiness", ctx do
    qualify(ctx, "null", %{"title" => nil})
  end

  test "native initialization with a Unicode title retains name version and ordinary readiness",
       ctx do
    qualify(ctx, "string", %{"title" => @title})
  end

  defp qualify(ctx, label, title) do
    pid = start(ctx)
    info = Map.merge(%{"name" => @name, "version" => @version}, title)
    id = "owned-initialize-title-#{label}"

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => %{"experimentalApi" => true}}
    }

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [captured] = Agent.get(ctx.capture, & &1)
    assert captured.wire === wire
    assert JSON.decode!(captured.encoded) === wire

    assert Map.has_key?(captured.wire["params"]["clientInfo"], "title") ==
             Map.has_key?(title, "title")

    assert Enum.sort(Map.keys(result)) == ~w(codexHome platformFamily platformOs userAgent)
    assert Map.fetch!(result, "codexHome") == ctx.fixture.codex_home
    assert Map.fetch!(result, "platformFamily") == "unix"
    assert Map.fetch!(result, "platformOs") == "linux"
    agent = Map.fetch!(result, "userAgent")
    assert String.starts_with?(agent, @name <> "/0.163.0 (")
    assert String.ends_with?(agent, " (#{@name}; #{@version})")

    # The pinned handler deliberately destructures title as _title for runtime
    # identity, but clones params for analytics first. These native boundaries
    # qualify only name/version-based runtime metadata and ordinary readiness;
    # analytics propagation or a globally unused title is not established.
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)

    assert call(pid, "thread/loaded/list", %{}, "owned-title-list-#{label}") == %{
             "data" => [],
             "nextCursor" => nil
           }

    native = native_id(pid, label)
    assert_retained(ctx, pid)
    assert Agent.get(ctx.capture, & &1) === [captured]
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    assert_inputs(ctx.inputs)
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp call(pid, method, params, id) do
    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(
               pid,
               %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

    result
  end

  defp native_id(pid, label) do
    native =
      call(pid, "server/diagnostics", %{}, "owned-title-diagnostics-#{label}")["process"]["id"]

    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp assert_retained(ctx, pid) do
    assert_inputs(ctx.inputs)
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/*.jsonl")) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    pid
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
