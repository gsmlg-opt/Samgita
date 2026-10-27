defmodule SamgitaCodexDriver.NativePluginInstalledErrorsTest do
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
  @market "fixture-good-market"
  @plugin "fixture-suggested"
  @id "fixture-suggested@fixture-good-market"
  @malformed "{}"
  @repaired ~S({"name":"fixture-repaired-empty","plugins":[]})

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

      if wire["method"] in ~w(server/diagnostics thread/loaded/list plugin/installed) do
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

    source = Path.join(ctx.root, "market-sources")
    good_root = Path.join(source, "good")
    bad_root = Path.join(source, "bad")
    good_marketplace = Path.join(good_root, ".agents/plugins/marketplace.json")
    bad_marketplace = Path.join(bad_root, ".agents/plugins/marketplace.json")
    plugin_root = Path.join(good_root, "plugins/#{@plugin}")
    plugin_manifest = Path.join(plugin_root, ".codex-plugin/plugin.json")

    sources = %{
      good_marketplace =>
        JSON.encode!(%{
          "name" => @market,
          "plugins" => [
            %{
              "name" => @plugin,
              "source" => %{"source" => "local", "path" => "./plugins/#{@plugin}"}
            }
          ]
        }),
      plugin_manifest =>
        JSON.encode!(%{
          "name" => @plugin,
          "description" => "Owned inert suggested plugin metadata"
        }),
      bad_marketplace => @malformed
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
      source: source,
      good_root: good_root,
      bad_root: bad_root,
      good_marketplace: good_marketplace,
      bad_marketplace: bad_marketplace,
      plugin_root: plugin_root,
      sources: sources,
      original_tree: source_tree(source),
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end})
    })
  end

  test "native installed inventory preserves discovered errors across repeat repair restore and restart",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_idle(ctx, warm.pid)
    assert_sources(ctx, @malformed)
    assert_inventory(ctx, warm.pid, malformed_errors(ctx))
    assert_sources(ctx, @malformed)
    assert_idle(ctx, warm.pid)

    # A valid empty marketplace removes only its former diagnostic. It has no
    # suggested plugin and must not displace the separate good marketplace.
    File.write!(ctx.bad_marketplace, @repaired)
    assert_inventory(ctx, warm.pid, [])
    assert_sources(ctx, @repaired)
    assert_idle(ctx, warm.pid)

    File.write!(ctx.bad_marketplace, @malformed)
    assert_inventory(ctx, warm.pid, malformed_errors(ctx))
    assert_sources(ctx, @malformed)
    assert_idle(ctx, warm.pid)
    close(warm, warm_native)
    assert source_tree(ctx.source) === ctx.original_tree

    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_idle(ctx, cold.pid)
    assert_sources(ctx, @malformed)
    assert_inventory(ctx, cold.pid, malformed_errors(ctx))
    assert_sources(ctx, @malformed)
    assert_idle(ctx, cold.pid)
    close(cold, cold_native)
    assert_sources(ctx, @malformed)
    assert source_tree(ctx.source) === ctx.original_tree
    assert_wire_inventory(ctx)
  end

  defp assert_inventory(ctx, pid, errors) do
    for _read <- 1..2 do
      response = call(ctx, pid, "plugin/installed", params(ctx))
      assert Map.fetch!(response, "marketplaceLoadErrors") === errors
      assert [marketplace] = Map.fetch!(response, "marketplaces")

      assert Map.take(marketplace, ~w(name path)) === %{
               "name" => @market,
               "path" => ctx.good_marketplace
             }

      assert [plugin] = Map.fetch!(marketplace, "plugins")

      assert Map.take(plugin, ~w(id name source installed enabled)) === %{
               "id" => @id,
               "name" => @plugin,
               "source" => %{"type" => "local", "path" => ctx.plugin_root},
               "installed" => false,
               "enabled" => false
             }

      assert ModelFixture.requests(ctx.fixture) == []
    end
  end

  defp malformed_errors(ctx) do
    # Pinned marketplace.rs wraps serde's required-name diagnostic. The source
    # bytes are exactly {}, without a trailing newline; do not infer this
    # expectation from a returned native diagnostic or substitute a substring.
    [
      %{
        "marketplacePath" => ctx.bad_marketplace,
        "message" =>
          "invalid marketplace file `#{ctx.bad_marketplace}`: missing field `name` at line 1 column 2"
      }
    ]
  end

  defp assert_sources(ctx, bad_bytes) do
    for {path, bytes} <- ctx.sources, path != ctx.bad_marketplace do
      assert snapshot(path).bytes === bytes
    end

    assert snapshot(ctx.bad_marketplace).bytes === bad_bytes
    assert byte_size(bad_bytes) <= 8192
    relative = Path.relative_to(ctx.bad_marketplace, ctx.source)

    expected = %{
      ctx.original_tree
      | files:
          Map.put(ctx.original_tree.files, relative, %{
            bytes: bad_bytes,
            sha256: hash(bad_bytes)
          })
    }

    assert source_tree(ctx.source) === expected
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp params(ctx) do
    %{
      "cwds" => [ctx.good_root, ctx.bad_root],
      "installSuggestionPluginNames" => [@plugin]
    }
  end

  defp start(ctx) do
    # Enable local metadata discovery only after native initialization, using
    # the existing exact-fragment helper rather than a persistent CLI override.
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
               %{"name" => "owned_plugin_installed_errors", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-plugin-installed-errors-#{System.unique_integer([:positive, :monotonic])}"
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
             method = Map.get(event, :wire, %{})["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or
               method == "error" or String.starts_with?(method, "hook/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_wire_inventory(ctx) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 16
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 16

    assert Enum.frequencies_by(frames, fn {_bytes, wire} -> wire["method"] end) == %{
             "server/diagnostics" => 2,
             "thread/loaded/list" => 6,
             "plugin/installed" => 8
           }

    for {_bytes, wire} <- frames do
      assert wire["params"] ===
               if(wire["method"] == "plugin/installed", do: params(ctx), else: %{})
    end
  end

  defp source_tree(root) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 64

    files =
      paths
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.all?(files, fn {_path, saved} -> byte_size(saved.bytes) <= 8192 end)

    assert Enum.reduce(files, 0, fn {_path, saved}, size -> size + byte_size(saved.bytes) end) <=
             1_048_576

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
