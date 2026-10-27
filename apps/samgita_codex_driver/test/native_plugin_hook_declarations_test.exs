defmodule SamgitaCodexDriver.NativePluginHookDeclarationsTest do
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
  @market "fixture-market"
  @plugin "fixture-hooks"
  @id "fixture-hooks@fixture-market"
  @description "Owned inert hook declaration metadata"
  # Deliberate byte order: SessionEnd precedes PreCompact in this source file.
  @first_json ~S({"hooks":{"SessionEnd":[{"hooks":[{"type":"agent"}]}],"PreCompact":[{"hooks":[{"type":"prompt"},{"type":"agent"}]},{"hooks":[{"type":"prompt"}]}]}})
  @second_json ~S({"hooks":{"PostToolUse":[{"hooks":[{"type":"agent"}]}]}})
  @original [
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:pre_compact:0:0",
      "eventName" => "preCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:pre_compact:0:1",
      "eventName" => "preCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:pre_compact:1:0",
      "eventName" => "preCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:session_end:0:0",
      "eventName" => "sessionEnd"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/second.json:post_tool_use:0:0",
      "eventName" => "postToolUse"
    }
  ]
  @changed [
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:post_compact:0:0",
      "eventName" => "postCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:post_compact:0:1",
      "eventName" => "postCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:post_compact:1:0",
      "eventName" => "postCompact"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/first.json:session_end:0:0",
      "eventName" => "sessionEnd"
    },
    %{
      "key" => "fixture-hooks@fixture-market:hooks/second.json:post_tool_use:0:0",
      "eventName" => "postToolUse"
    }
  ]
  @remaining [
    %{
      "key" => "fixture-hooks@fixture-market:hooks/second.json:post_tool_use:0:0",
      "eventName" => "postToolUse"
    }
  ]

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

      if wire["method"] in ~w(server/diagnostics thread/loaded/list plugin/read) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 24 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [{encoded, wire}]))
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
        "\n[features]\nplugins = true\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\n"
    )

    source = Path.join(ctx.root, "market-source")
    marketplace = Path.join(source, ".agents/plugins/marketplace.json")
    plugin_root = Path.join(source, "plugins/#{@plugin}")
    first = Path.join(plugin_root, "hooks/first.json")
    second = Path.join(plugin_root, "hooks/second.json")
    manifest = Path.join(plugin_root, ".codex-plugin/plugin.json")

    sources = %{
      marketplace =>
        JSON.encode!(%{
          "name" => @market,
          "plugins" => [
            %{
              "name" => @plugin,
              "source" => %{"source" => "local", "path" => "./plugins/#{@plugin}"}
            }
          ]
        }),
      manifest =>
        JSON.encode!(%{
          "name" => @plugin,
          "description" => @description,
          "hooks" => ["./hooks/first.json", "./hooks/second.json"]
        }),
      first => @first_json,
      second => @second_json
    }

    for {path, bytes} <- sources do
      assert byte_size(bytes) <= 8192
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
    end

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

    Map.merge(ctx, %{
      config: config,
      marketplace: marketplace,
      first: first,
      held: first <> ".held",
      source: source,
      sources: sources,
      original_tree: source_tree(source),
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end})
    })
  end

  test "native plugin detail reloads ordered inert hook declarations across source changes and restart",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_idle(ctx, warm.pid)
    assert_sources(ctx, @first_json, false)
    assert_declarations(ctx, warm.pid, @original)
    assert_idle(ctx, warm.pid)

    changed = String.replace(@first_json, "\"PreCompact\"", "\"PostCompact\"", global: false)
    refute changed == @first_json
    File.write!(ctx.first, changed)
    assert_declarations(ctx, warm.pid, @changed)
    assert_sources(ctx, changed, false)
    assert_idle(ctx, warm.pid)

    # Preserve exact original bytes while holding the explicit first source
    # aside. Only the second path remains in the current declaration inventory.
    File.write!(ctx.first, @first_json)
    File.rename!(ctx.first, ctx.held)
    assert_declarations(ctx, warm.pid, @remaining)
    assert_sources(ctx, nil, true)
    assert_idle(ctx, warm.pid)

    File.rename!(ctx.held, ctx.first)
    assert_sources(ctx, @first_json, false)
    assert_declarations(ctx, warm.pid, @original)
    assert_idle(ctx, warm.pid)
    close(warm, warm_native)
    assert source_tree(ctx.source) === ctx.original_tree

    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_idle(ctx, cold.pid)
    assert_sources(ctx, @first_json, false)
    assert_declarations(ctx, cold.pid, @original)
    assert_idle(ctx, cold.pid)
    close(cold, cold_native)
    assert_sources(ctx, @first_json, false)
    assert source_tree(ctx.source) === ctx.original_tree
    assert_wire_inventory(ctx)
  end

  defp assert_declarations(ctx, pid, hooks) do
    # Public identity/status are metadata only. Only the populated declaration
    # array is qualified here; no other response facets are acceptance targets.
    for _read <- 1..2 do
      response = call(ctx, pid, "plugin/read", params(ctx))
      plugin = Map.fetch!(response, "plugin")

      assert Map.take(plugin, ~w(marketplaceName marketplacePath description hooks)) === %{
               "marketplaceName" => @market,
               "marketplacePath" => ctx.marketplace,
               "description" => @description,
               "hooks" => hooks
             }

      assert Map.take(Map.fetch!(plugin, "summary"), ~w(id name installed enabled)) === %{
               "id" => @id,
               "name" => @plugin,
               "installed" => false,
               "enabled" => false
             }

      assert ModelFixture.requests(ctx.fixture) == []
    end
  end

  defp assert_sources(ctx, first, held) do
    for {path, bytes} <- ctx.sources, path != ctx.first do
      assert snapshot(path).bytes === bytes
    end

    if first do
      assert snapshot(ctx.first).bytes === first
      assert byte_size(first) <= 8192
    else
      refute File.exists?(ctx.first)
    end

    if held,
      do: assert(snapshot(ctx.held).bytes === @first_json),
      else: refute(File.exists?(ctx.held))

    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp params(ctx), do: %{"marketplacePath" => ctx.marketplace, "pluginName" => @plugin}

  defp start(ctx) do
    # manager.rs requires plugins_enabled for plugin/read. The supported helper
    # enables only metadata reads after native initialization has completed.
    NativeLaunchFixture.local_plugins_after_initialize(ctx.config, fn ->
      start_initialized(ctx)
    end)
  end

  defp start_initialized(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
      "-c",
      "features.recommended_plugins=false",
      "app-server",
      "--listen",
      "stdio://"
    ]

    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
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

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_plugin_hook_declarations", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-plugin-hook-declarations-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert byte_size(JSON.encode!(response)) <= 65_536
    assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert actual === wire
    assert JSON.decode!(bytes) === wire
    assert bytes === JSON.encode!(wire)
    result
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(session, native) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{native}")
  end

  defp assert_idle(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "hook/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_wire_inventory(ctx) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 19
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 19

    assert Enum.frequencies_by(frames, fn {_bytes, wire} -> wire["method"] end) == %{
             "server/diagnostics" => 2,
             "thread/loaded/list" => 7,
             "plugin/read" => 10
           }

    for {_bytes, wire} <- frames do
      assert wire["params"] === if(wire["method"] == "plugin/read", do: params(ctx), else: %{})
    end
  end

  defp source_tree(root) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 32

    files =
      paths
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.all?(files, fn {_path, saved} -> byte_size(saved.bytes) <= 8192 end)
    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: files}
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
