defmodule SamgitaCodexDriver.NativePluginSkillOptionalMetadataTest do
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
  @market "fixture-skill-market"
  @plugin "fixture-skill-metadata"
  @id "fixture-skill-metadata@fixture-skill-market"
  @description "Owned inert optional skill metadata"
  @skill_description "Owned inert inspection skill"
  @display_name "Owned optional skill interface"
  @rich_yaml """
  interface:
    display_name: "Owned optional skill interface"
    icon_small: "./assets/small.png"
    icon_large: "assets/large.png"
  """
  @stripped_yaml """
  interface:
    display_name: "Owned optional skill interface"
  """
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
         0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

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
    plugin_manifest = Path.join(plugin_root, ".codex-plugin/plugin.json")
    skill_root = Path.join(plugin_root, "skills/inspect")
    skill_source = Path.join(skill_root, "SKILL.md")
    skill_metadata = Path.join(skill_root, "agents/openai.yaml")
    small = Path.join(skill_root, "assets/small.png")
    large = Path.join(skill_root, "assets/large.png")

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
      plugin_manifest =>
        JSON.encode!(%{
          "name" => @plugin,
          "description" => @description,
          "extensions" => %{
            "com.openai" => %{"onboardingSkill" => "skills/inspect/SKILL.md"}
          }
        }),
      skill_source =>
        "---\nname: inspect\ndescription: #{@skill_description}\n---\n\nOwned inert metadata only.\n",
      skill_metadata => @rich_yaml,
      small => @png,
      large => @png
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
      marketplace: marketplace,
      plugin_root: plugin_root,
      skill_source: skill_source,
      skill_metadata: skill_metadata,
      held_metadata: skill_metadata <> ".held",
      small: small,
      large: large,
      sources: sources,
      original_tree: source_tree(source),
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end})
    })
  end

  test "native skill metadata omits icons and interface across warm changes and cold recovery",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_idle(ctx, warm.pid)
    assert_sources(ctx, :rich)
    assert_detail(ctx, warm.pid, expected_interface(ctx, :rich))
    assert_sources(ctx, :rich)
    assert_idle(ctx, warm.pid)

    File.write!(ctx.skill_metadata, @stripped_yaml)
    assert_detail(ctx, warm.pid, expected_interface(ctx, :stripped))
    assert_sources(ctx, :stripped)
    assert_idle(ctx, warm.pid)

    # Only optional YAML moves. SKILL.md and both asset files remain exact.
    File.rename!(ctx.skill_metadata, ctx.held_metadata)
    assert_detail(ctx, warm.pid, nil)
    assert_sources(ctx, :held)
    assert_idle(ctx, warm.pid)
    close(warm, warm_native)
    assert_sources(ctx, :held)

    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_idle(ctx, cold.pid)
    assert_sources(ctx, :held)
    assert_detail(ctx, cold.pid, nil)
    assert_sources(ctx, :held)
    assert_idle(ctx, cold.pid)

    File.rename!(ctx.held_metadata, ctx.skill_metadata)
    assert_detail(ctx, cold.pid, expected_interface(ctx, :stripped))
    assert_sources(ctx, :stripped)
    assert_idle(ctx, cold.pid)

    File.write!(ctx.skill_metadata, @rich_yaml)
    assert_detail(ctx, cold.pid, expected_interface(ctx, :rich))
    assert_sources(ctx, :rich)
    assert_idle(ctx, cold.pid)
    close(cold, cold_native)
    assert_sources(ctx, :rich)
    assert source_tree(ctx.source) === ctx.original_tree
    assert_wire_inventory(ctx)
  end

  defp assert_detail(ctx, pid, interface) do
    skill = %{
      "name" => @plugin <> ":inspect",
      "description" => @skill_description,
      "shortDescription" => nil,
      "path" => ctx.skill_source,
      "enabled" => true,
      "interface" => interface
    }

    for _read <- 1..2 do
      detail = call(ctx, pid, "plugin/read", params(ctx)) |> Map.fetch!("plugin")

      assert Map.take(
               detail,
               ~w(marketplaceName marketplacePath description skills onboardingSkill)
             ) ===
               %{
                 "marketplaceName" => @market,
                 "marketplacePath" => ctx.marketplace,
                 "description" => @description,
                 "skills" => [skill],
                 "onboardingSkill" => nil
               }

      # A real declared onboarding path never becomes an onboarding selection
      # for this fixed uninstalled/disabled plugin. No enablement is changed.
      assert Map.take(Map.fetch!(detail, "summary"), ~w(id name source installed enabled)) === %{
               "id" => @id,
               "name" => @plugin,
               "source" => %{"type" => "local", "path" => ctx.plugin_root},
               "installed" => false,
               "enabled" => false
             }

      assert ModelFixture.requests(ctx.fixture) == []
    end
  end

  defp expected_interface(ctx, mode) do
    %{
      "displayName" => @display_name,
      "shortDescription" => nil,
      "defaultPrompt" => nil,
      "brandColor" => nil,
      "iconSmall" => if(mode == :rich, do: ctx.small, else: nil),
      "iconLarge" => if(mode == :rich, do: ctx.large, else: nil),
      "iconSmallUrl" => nil,
      "iconLargeUrl" => nil
    }
  end

  defp assert_sources(ctx, mode) do
    for {path, bytes} <- ctx.sources, path != ctx.skill_metadata do
      assert snapshot(path).bytes === bytes
    end

    relative = Path.relative_to(ctx.skill_metadata, ctx.source)
    held_relative = Path.relative_to(ctx.held_metadata, ctx.source)
    bytes = if mode == :rich, do: @rich_yaml, else: @stripped_yaml
    saved = %{bytes: bytes, sha256: hash(bytes)}

    expected =
      if mode == :held do
        refute File.exists?(ctx.skill_metadata)
        assert snapshot(ctx.held_metadata) === saved

        %{
          entries:
            ctx.original_tree.entries
            |> Enum.map(fn entry -> if entry == relative, do: held_relative, else: entry end)
            |> Enum.sort(),
          files:
            ctx.original_tree.files
            |> Map.delete(relative)
            |> Map.put(held_relative, saved)
        }
      else
        refute File.exists?(ctx.held_metadata)
        assert snapshot(ctx.skill_metadata) === saved
        %{ctx.original_tree | files: Map.put(ctx.original_tree.files, relative, saved)}
      end

    assert source_tree(ctx.source) === expected
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp params(ctx), do: %{"marketplacePath" => ctx.marketplace, "pluginName" => @plugin}

  defp start(ctx) do
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
               %{"name" => "owned_plugin_skill_optional_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-plugin-skill-optional-metadata-#{System.unique_integer([:positive, :monotonic])}"
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
    assert length(frames) == 22
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 22

    assert Enum.frequencies_by(frames, fn {_bytes, wire} -> wire["method"] end) == %{
             "server/diagnostics" => 2,
             "thread/loaded/list" => 8,
             "plugin/read" => 12
           }

    for {_bytes, wire} <- frames do
      assert wire["params"] === if(wire["method"] == "plugin/read", do: params(ctx), else: %{})
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
