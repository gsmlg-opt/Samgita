defmodule SamgitaCodexDriver.NativeMarketplacePartialErrorTest do
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
  @manifest ~s({"name":"good","plugins":[]})
  @marker "Owned ordinary marketplace partial-success marker λ🙂\n"
  @failure %{
    "marketplaceName" => "bad",
    "message" => "configured Git marketplace is missing source"
  }

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

      if wire["method"] in ~w(server/diagnostics thread/loaded/list marketplace/upgrade) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 4096 do
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
    git = System.find_executable("git")
    assert is_binary(git) and File.regular?(git), "BLOCKED_ENV: real Git required"
    File.ln_s!(git, Path.join(ctx.fixture.bin, "git"))
    ctx = Map.put(ctx, :git, git)
    source = Path.join(ctx.root, "marketplace-source")
    manifest = Path.join(source, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(manifest))
    File.write!(manifest, @manifest)
    File.write!(Path.join(source, "marker.txt"), @marker)
    git(ctx, source, ["init", "--initial-branch=main"])
    git(ctx, source, ["add", "."])

    git(ctx, source, [
      "-c",
      "user.name=Synthetic fixture",
      "-c",
      "user.email=fixture@example.invalid",
      "commit",
      "-m",
      "Owned ordinary marketplace fixture"
    ])

    revision = git(ctx, source, ["rev-parse", "HEAD"])
    assert revision =~ ~r/\A[0-9a-f]{40}\z/
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n" <>
        "\n[marketplaces.bad]\nsource_type = \"git\"\n" <>
        "\n[marketplaces.good]\nsource_type = \"git\"\nsource = #{JSON.encode!(source)}\n"
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

    Map.merge(ctx, %{
      capture: start_supervised!({Agent, fn -> [] end}),
      source: source,
      source_snapshot: tree_snapshot(source),
      revision: revision,
      installed: Path.join(ctx.fixture.codex_home, ".tmp/marketplaces/good"),
      bad_root: Path.join(ctx.fixture.codex_home, ".tmp/marketplaces/bad"),
      inputs: inputs
    })
  end

  test "native marketplace errors preserve independent local upgrade success across restart",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    assert_idle(ctx, warm)
    refute File.exists?(ctx.installed)
    refute File.exists?(ctx.bad_root)
    assert_inputs(ctx.inputs)

    # The incomplete optional source is real native input. The literal failure
    # is independent of Git stderr and must not prevent the valid local clone.
    assert upgrade(ctx, warm) === %{
             "selectedMarketplaces" => ["bad", "good"],
             "upgradedRoots" => [ctx.installed],
             "errors" => [@failure]
           }

    assert_activated(ctx)
    installed = tree_snapshot(ctx.installed)
    assert_retained(ctx, warm, installed)

    noop = %{
      "selectedMarketplaces" => ["bad", "good"],
      "upgradedRoots" => [],
      "errors" => [@failure]
    }

    assert upgrade(ctx, warm) === noop
    assert_retained(ctx, warm, installed)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native

    # Native diagnostics and idle observation are the cold boundary before any
    # explicit upgrade; no automatic startup refresh may alter the saved root.
    assert_retained(ctx, cold, installed)
    assert upgrade(ctx, cold) === noop
    assert_retained(ctx, cold, installed)
    close(cold, cold_native)
    assert_inputs(ctx.inputs)
    assert tree_snapshot(ctx.source) === ctx.source_snapshot
    assert tree_snapshot(ctx.installed) === installed
    assert ModelFixture.requests(ctx.fixture) == []

    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 10
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 10

    for {method, count} <- [
          {"server/diagnostics", 2},
          {"thread/loaded/list", 5},
          {"marketplace/upgrade", 3}
        ] do
      assert Enum.count(frames, fn {_bytes, wire} -> wire["method"] == method end) == count
    end

    for {_bytes, wire} <- frames do
      assert wire["params"] === %{}
    end
  end

  defp upgrade(ctx, pid), do: call(ctx, pid, "marketplace/upgrade", %{})

  defp assert_activated(ctx) do
    assert git(ctx, ctx.installed, ["rev-parse", "HEAD"]) == ctx.revision
    assert File.read!(Path.join(ctx.installed, "marker.txt")) === @marker
    assert File.read!(Path.join(ctx.installed, ".agents/plugins/marketplace.json")) === @manifest

    metadata =
      ctx.installed
      |> Path.join(".codex-marketplace-install.json")
      |> File.read!()
      |> JSON.decode!()

    assert metadata === %{
             "source_type" => "git",
             "source" => ctx.source,
             "ref_name" => nil,
             "sparse_paths" => [],
             "revision" => ctx.revision
           }

    refute File.exists?(ctx.bad_root)
  end

  defp assert_retained(ctx, pid, installed) do
    assert_inputs(ctx.inputs)
    assert tree_snapshot(ctx.source) === ctx.source_snapshot
    assert tree_snapshot(ctx.installed) === installed
    assert_activated(ctx)
    assert_idle(ctx, pid)
    assert tree_snapshot(ctx.installed) === installed
    assert_inputs(ctx.inputs)
  end

  defp assert_idle(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or method == "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-marketplace-partial-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert actual === wire
    assert JSON.decode!(bytes) === wire
    assert bytes === JSON.encode!(wire)
    result
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
             env: environment(ctx)
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_marketplace_partial_error", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
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

  defp git(ctx, cwd, args) do
    {output, status} =
      System.cmd(ctx.git, args,
        cd: cwd,
        env: Map.to_list(environment(ctx)),
        stderr_to_stdout: true
      )

    assert byte_size(output) <= 16_384
    assert status == 0, "owned ordinary Git fixture failed: #{output}"
    String.trim(output)
  end

  defp environment(ctx),
    do: %{
      "HOME" => ctx.fixture.home,
      "CODEX_HOME" => ctx.fixture.codex_home,
      "TMPDIR" => ctx.root,
      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_TERMINAL_PROMPT" => "0",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "RUST_LOG" => "off",
      "NO_COLOR" => "1"
    }

  defp tree_snapshot(root) do
    assert File.dir?(root)
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 128
    files = Enum.filter(paths, &File.regular?/1)
    contents = Map.new(files, &{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.reduce(contents, 0, fn {_path, saved}, size -> size + byte_size(saved.bytes) end) <=
             4_194_304

    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: contents}
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
