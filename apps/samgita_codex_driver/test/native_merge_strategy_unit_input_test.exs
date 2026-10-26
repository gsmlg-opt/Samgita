defmodule SamgitaCodexDriver.NativeMergeStrategyUnitInputTest do
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
  @captured ~w(config/value/write config/batchWrite)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @max_frame_bytes 4096

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      limit = Keyword.fetch!(opts, :capture_limit)
      transport_opts = Keyword.drop(opts, [:capture, :capture_limit])

      with {:ok, state} <- Stdio.open(transport_opts),
           do: {:ok, Map.merge(state, %{capture: capture, capture_limit: limit})}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ~w(config/value/write config/batchWrite) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1.frames)) < state.capture_limit and
           byte_size(encoded) <= @max_frame_bytes do
        with {:ok, next} <- Stdio.send(state, encoded) do
          record_capture(state.capture, encoded, wire)

          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    defp record_capture(capture, encoded, wire) do
      Agent.update(capture, fn captured ->
        %{captured | frames: captured.frames ++ [{encoded, wire}]}
      end)
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

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n" <>
        "\n[desktop]\nappearanceTheme = \"dark\"\npreventSleep = true\n"
    )

    inputs =
      Map.new(
        [
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

    capture = start_supervised!({Agent, fn -> %{frames: [], reads: 0} end})
    Map.merge(ctx, %{capture: capture, inputs: inputs, capture_limit: 12, config_path: config})
  end

  test "four strategy unit objects drive real desktop replace and upsert writes on both APIs",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    initial = read_config(ctx, warm)
    initial_desktop = %{"appearanceTheme" => "dark", "preventSleep" => true}
    initial_version = Map.fetch!(initial.layer, "version")
    assert is_binary(initial_version) and byte_size(initial_version) > 0
    assert initial.layer["config"]["desktop"] === initial_desktop
    assert initial.response["config"]["desktop"] === initial_desktop

    original = %{
      metadata: Map.drop(initial.layer, ["config", "version"]),
      non_desktop: Map.delete(Map.fetch!(initial.layer, "config"), "desktop")
    }

    assert initial.layer["name"] === user_source(ctx)
    assert_inputs(ctx.inputs)
    assert_functional_state(ctx, warm)

    final =
      Enum.reduce(
        steps(),
        %{observation: initial, version: initial_version, file: snapshot(ctx.config_path)},
        fn step, previous ->
          params = mutation_params(step, previous.version)
          result = call(ctx, warm, step.method, params)
          assert Map.fetch!(result, "status") == "ok"
          assert Map.fetch!(result, "filePath") == ctx.config_path
          version = Map.fetch!(result, "version")
          assert is_binary(version) and byte_size(version) > 0
          refute version == previous.version

          # Each real config/read observes the persisted layer after the write.
          # The eight exact sentinel expectations are independent of its response.
          observation = read_config(ctx, warm)
          assert_observation(ctx, observation, original, step.desktop, version)
          current = snapshot(ctx.config_path)
          refute current.bytes === previous.file.bytes
          assert_functional_state(ctx, warm)
          assert_inputs(ctx.inputs)
          assert File.ls!(ctx.fixture.workspace) == []
          %{observation: observation, version: version, file: current}
        end
      )

    assert Agent.get(ctx.capture, & &1.reads) == 9
    assert final.observation.layer["config"]["desktop"] === initial_desktop
    close(warm, warm_native)
    assert snapshot(ctx.config_path) === final.file
    assert_inputs(ctx.inputs)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert snapshot(ctx.config_path) === final.file
    persisted = read_config(ctx, cold)
    assert_observation(ctx, persisted, original, initial_desktop, final.version)
    assert persisted.layer === final.observation.layer
    assert snapshot(ctx.config_path) === final.file
    assert_inputs(ctx.inputs)
    assert_functional_state(ctx, cold)
    assert File.ls!(ctx.fixture.workspace) == []
    close(cold, cold_native)
    assert snapshot(ctx.config_path) === final.file
    assert_inputs(ctx.inputs)

    state = Agent.get(ctx.capture, & &1)
    assert state.reads == 10
    assert length(state.frames) == 8
    assert capture_count(state.frames, "config/value/write") == 4
    assert capture_count(state.frames, "config/batchWrite") == 4
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp steps do
    [
      %{
        method: "config/value/write",
        strategy: %{"replace" => nil},
        value: %{"appearanceTheme" => "light"},
        desktop: %{"appearanceTheme" => "light"}
      },
      %{
        method: "config/value/write",
        strategy: %{"replace" => %{}},
        value: %{"preventSleep" => false},
        desktop: %{"preventSleep" => false}
      },
      %{
        method: "config/value/write",
        strategy: %{"upsert" => nil},
        value: %{"appearanceTheme" => "dark"},
        desktop: %{"appearanceTheme" => "dark", "preventSleep" => false}
      },
      %{
        method: "config/value/write",
        strategy: %{"upsert" => %{}},
        value: %{"appearanceTheme" => "light"},
        desktop: %{"appearanceTheme" => "light", "preventSleep" => false}
      },
      %{
        method: "config/batchWrite",
        strategy: %{"replace" => nil},
        value: %{"appearanceTheme" => "dark"},
        desktop: %{"appearanceTheme" => "dark"}
      },
      %{
        method: "config/batchWrite",
        strategy: %{"replace" => %{}},
        value: %{"preventSleep" => true},
        desktop: %{"preventSleep" => true}
      },
      %{
        method: "config/batchWrite",
        strategy: %{"upsert" => nil},
        value: %{"appearanceTheme" => "light"},
        desktop: %{"appearanceTheme" => "light", "preventSleep" => true}
      },
      %{
        method: "config/batchWrite",
        strategy: %{"upsert" => %{}},
        value: %{"appearanceTheme" => "dark"},
        desktop: %{"appearanceTheme" => "dark", "preventSleep" => true}
      }
    ]
  end

  defp mutation_params(step, version) do
    edit = %{"keyPath" => "desktop", "mergeStrategy" => step.strategy, "value" => step.value}

    case step.method do
      "config/value/write" ->
        Map.put(edit, "expectedVersion", version)

      "config/batchWrite" ->
        %{"edits" => [edit], "expectedVersion" => version, "reloadUserConfig" => false}
    end
  end

  defp user_source(ctx),
    do: %{"type" => "user", "file" => ctx.config_path, "profile" => nil}

  defp read_config(ctx, pid) do
    response = call(ctx, pid, "config/read", %{"includeLayers" => true})
    layers = Map.fetch!(response, "layers")
    assert is_list(layers) and length(layers) <= 16
    assert [layer] = Enum.filter(layers, &(&1["name"] === user_source(ctx)))
    assert is_map(Map.fetch!(layer, "config"))
    %{response: response, layer: layer}
  end

  defp assert_observation(ctx, observation, original, expected, version) do
    layer = observation.layer
    assert Map.fetch!(layer, "name") === user_source(ctx)
    assert Map.drop(layer, ["config", "version"]) === original.metadata
    assert Map.fetch!(layer, "version") === version
    assert Map.fetch!(layer, "config")["desktop"] === expected
    assert Map.delete(Map.fetch!(layer, "config"), "desktop") === original.non_desktop
    assert Map.fetch!(observation.response, "config")["desktop"] === expected
  end

  defp assert_functional_state(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp capture_count(captures, method),
    do: Enum.count(captures, fn {_bytes, wire} -> wire["method"] == method end)

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1.frames))

    if method == "config/read" do
      assert Agent.get(ctx.capture, & &1.reads) < 10
    end

    id = "owned-merge-strategy-unit-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1.frames, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
      assert_strategy_object(bytes, method, params)
    else
      assert length(Agent.get(ctx.capture, & &1.frames)) == before
    end

    if method == "config/read" do
      Agent.update(ctx.capture, &%{&1 | reads: &1.reads + 1})
    end

    result
  end

  defp assert_strategy_object(bytes, method, params) do
    object =
      case method do
        "config/value/write" ->
          Map.fetch!(params, "mergeStrategy")

        "config/batchWrite" ->
          assert [edit] = Map.fetch!(params, "edits")
          Map.fetch!(edit, "mergeStrategy")
      end

    assert is_map(object) and map_size(object) == 1
    assert :binary.match(bytes, JSON.encode!(object)) != :nomatch
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
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
             capture_limit: ctx.capture_limit,
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
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_merge_strategy_unit_input", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

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
