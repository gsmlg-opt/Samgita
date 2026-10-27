defmodule SamgitaCodexDriver.NativeMarketplaceGitSelectionTest do
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
  @peer Path.expand("../../../scripts/codex/git_marketplace_fixture.py", __DIR__)
  @peer_sha "7b4a7027181f8b4765e5b26e7fba9480ab36c01c2c606d5b9fd063e0401fe034"
  @market "owned-git-selection"
  @ref "fixture-selected"
  @sparse [".agents/plugins", "plugins/selected"]
  @manifest ".agents/plugins/marketplace.json"
  @plugin "plugins/selected/.codex-plugin/plugin.json"
  @marker "plugins/selected/marker.txt"
  @excluded "excluded/deep/marker.txt"

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

      if wire["method"] in ~w(server/diagnostics thread/loaded/list marketplace/add) do
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
    assert hash(File.read!(@peer)) == @peer_sha
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
    source = Path.join(ctx.root, "export/fixture.git")
    File.mkdir_p!(source)
    git(ctx, source, ["init", "--initial-branch=main"])
    first = authored("A")
    second = authored("B")
    write_files(source, first)
    commit(ctx, source)
    revision_a = git(ctx, source, ["rev-parse", "HEAD"])
    git(ctx, source, ["branch", @ref])
    write_files(source, second)
    commit(ctx, source)
    revision_b = git(ctx, source, ["rev-parse", "HEAD"])
    assert revision_a =~ ~r/\A[0-9a-f]{40}\z/
    assert revision_b =~ ~r/\A[0-9a-f]{40}\z/
    refute revision_a == revision_b
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
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          @peer,
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
      first: first,
      second: second,
      revision_a: revision_a,
      revision_b: revision_b,
      source_snapshot: tree_snapshot(source),
      config: config,
      journal: Path.join(ctx.root, "git-http-journal.json"),
      inputs: inputs,
      installed: Path.join(ctx.fixture.codex_home, ".tmp/marketplaces/#{@market}")
    })
  end

  test "native Git marketplace ref and sparse paths materialize A while source HEAD remains B",
       ctx do
    peer = start_peer(ctx)
    assert journal(ctx) === %{"failure" => nil, "attempts" => 0, "entries" => []}
    original_config = snapshot(ctx.config)
    params = %{"source" => peer.url, "refName" => @ref, "sparsePaths" => @sparse}
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_idle(ctx, warm.pid)
    refute File.exists?(ctx.installed)
    assert snapshot(ctx.config) === original_config
    assert_source(ctx)

    expected = %{
      "marketplaceName" => @market,
      "installedRoot" => ctx.installed,
      "alreadyAdded" => false
    }

    assert call(ctx, warm.pid, "marketplace/add", params) === expected
    assert_materialized(ctx, peer.url)
    installed = tree_snapshot(ctx.installed)
    http = assert_http_journal(ctx)

    retained =
      ctx.inputs
      |> Map.put(ctx.config, snapshot(ctx.config))
      |> Map.put(ctx.journal, snapshot(ctx.journal))

    assert_retained(ctx, warm.pid, peer.url, installed, retained)

    duplicate = Map.put(expected, "alreadyAdded", true)
    assert call(ctx, warm.pid, "marketplace/add", params) === duplicate
    assert_retained(ctx, warm.pid, peer.url, installed, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_retained(ctx, cold.pid, peer.url, installed, retained)
    assert call(ctx, cold.pid, "marketplace/add", params) === duplicate
    assert_retained(ctx, cold.pid, peer.url, installed, retained)
    close(cold, cold_native)
    assert assert_http_journal(ctx) === http
    close_peer(peer)
    assert_inputs(retained)
    assert_source(ctx)
    assert tree_snapshot(ctx.installed) === installed
    assert ModelFixture.requests(ctx.fixture) == []
    assert_wire_inventory(ctx, params)
  end

  defp authored(label) do
    %{
      @manifest =>
        JSON.encode!(%{
          "name" => @market,
          "interface" => %{"displayName" => "Owned #{label} marketplace"},
          "plugins" => [
            %{
              "name" => "owned-selected",
              "source" => %{
                "source" => "local",
                "path" => "./plugins/selected"
              }
            }
          ]
        }),
      @plugin => JSON.encode!(%{"name" => "owned-selected", "description" => "Inert #{label}"}),
      @marker => "Owned selected #{label} bytes λ🙂\n",
      @excluded => "Owned tracked excluded #{label} bytes\n"
    }
  end

  defp write_files(root, files) do
    for {relative, bytes} <- files do
      path = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
    end
  end

  defp assert_source(ctx) do
    assert git(ctx, ctx.source, ["rev-parse", "HEAD"]) == ctx.revision_b
    assert git(ctx, ctx.source, ["rev-parse", "main"]) == ctx.revision_b
    assert git(ctx, ctx.source, ["rev-parse", @ref]) == ctx.revision_a
    assert git(ctx, ctx.source, ["rev-list", "--count", "--all"]) == "2"
    tracked = git(ctx, ctx.source, ["ls-tree", "-r", "--name-only", ctx.revision_a])
    assert String.split(tracked, "\n") == Enum.sort(Map.keys(ctx.first))

    assert git(ctx, ctx.source, ["show", "#{ctx.revision_a}:#{@excluded}"]) ==
             String.trim(ctx.first[@excluded])

    assert tree_snapshot(ctx.source) === ctx.source_snapshot
  end

  defp assert_materialized(ctx, source_url) do
    assert git(ctx, ctx.installed, ["rev-parse", "HEAD"]) == ctx.revision_a

    for path <- [@manifest, @plugin, @marker] do
      bytes = File.read!(Path.join(ctx.installed, path))
      assert bytes === ctx.first[path]
      refute bytes === ctx.second[path]
    end

    refute File.exists?(Path.join(ctx.installed, @excluded))

    script = """
    import json, pathlib, sys, tomllib
    data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
    print(json.dumps(data.get('marketplaces')))
    """

    {output, status} =
      System.cmd("python3", ["-B", "-c", script, ctx.config], stderr_to_stdout: true)

    assert status == 0, "owned marketplace TOML observation failed: #{output}"
    assert byte_size(output) <= 4096

    assert JSON.decode!(output) === %{
             @market => %{
               "source_type" => "git",
               "source" => source_url,
               "ref" => @ref,
               "sparse_paths" => @sparse
             }
           }
  end

  defp assert_retained(ctx, pid, url, installed, inputs) do
    assert_inputs(inputs)
    assert_source(ctx)
    assert tree_snapshot(ctx.installed) === installed
    assert_materialized(ctx, url)
    assert_idle(ctx, pid)
    assert tree_snapshot(ctx.installed) === installed
    assert_inputs(inputs)
  end

  defp assert_http_journal(ctx) do
    result = journal(ctx)
    assert %{"failure" => nil, "attempts" => attempts, "entries" => entries} = result
    assert length(entries) in 2..64
    assert attempts == length(entries)
    assert Enum.any?(entries, &(&1["method"] == "GET"))
    assert Enum.any?(entries, &(&1["method"] == "POST"))

    for entry <- entries do
      assert entry["status"] == 200
      assert entry["backend_returncode"] == 0
      assert entry["request_bytes"] in 0..2_097_152
      assert entry["response_bytes"] in 1..2_097_152
      assert is_integer(entry["backend_pid"]) and entry["backend_pid"] > 0
      refute File.exists?("/proc/#{entry["backend_pid"]}")

      assert {entry["method"], entry["path"]} in [
               {"GET", "/fixture.git/info/refs?service=git-upload-pack"},
               {"POST", "/fixture.git/git-upload-pack"}
             ]
    end

    result
  end

  defp journal(ctx) do
    bytes = snapshot(ctx.journal).bytes
    assert byte_size(bytes) <= 65_536
    JSON.decode!(bytes)
  end

  defp start_peer(ctx) do
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python required"

    assert {:ok, connection} =
             Stdio.open(
               executable: python,
               inherit_env: [],
               env: environment(ctx),
               cwd: ctx.root,
               args: [
                 @peer,
                 "--repository",
                 ctx.source,
                 "--git",
                 ctx.git,
                 "--journal",
                 ctx.journal
               ]
             )

    on_exit(fn -> assert(:ok = Stdio.close(connection)) end)
    proof = await_peer(connection.port, <<>>, System.monotonic_time(:millisecond) + 5_000)
    assert %{"url" => url, "pid" => pid, "backend" => backend} = proof
    uri = URI.parse(url)
    assert uri.scheme == "http" and uri.host == "127.0.0.1" and uri.path == "/fixture.git"
    assert is_integer(uri.port) and uri.port > 0
    assert is_integer(pid) and pid > 0
    expected_backend = Path.join(git(ctx, ctx.source, ["--exec-path"]), "git-http-backend")
    assert backend == expected_backend and File.regular?(backend)
    peer = %{connection: connection, pid: pid, url: url, port: uri.port}
    on_exit(fn -> close_peer(peer) end)
    peer
  end

  defp await_peer(port, bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    assert remaining > 0, "Git HTTP fixture startup deadline"

    receive do
      {^port, {:data, incoming}} ->
        bytes = bytes <> incoming
        assert byte_size(bytes) <= 8192

        case String.split(bytes, "\n", parts: 2) do
          [line, ""] -> JSON.decode!(line)
          [_partial] -> await_peer(port, bytes, deadline)
          _other -> flunk("Unexpected Git HTTP fixture startup output")
        end

      {^port, {:exit_status, status}} ->
        flunk("Git HTTP fixture exited at startup: #{status}")
    after
      remaining -> flunk("Git HTTP fixture startup deadline")
    end
  end

  defp close_peer(peer) do
    assert :ok = Stdio.close(peer.connection)
    assert :atomics.get(peer.connection.owner.completion, 1) == 1
    assert Port.info(peer.connection.port) == nil
    refute File.exists?("/proc/#{peer.pid}")

    assert {:error, :econnrefused} =
             :gen_tcp.connect(~c"127.0.0.1", peer.port, [:binary, active: false], 1000)
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
                    env: environment(ctx)
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_marketplace_git_selection", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-marketplace-git-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

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
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or method == "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_wire_inventory(ctx, params) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 10
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 10

    assert Enum.frequencies_by(frames, fn {_bytes, wire} -> wire["method"] end) == %{
             "server/diagnostics" => 2,
             "thread/loaded/list" => 5,
             "marketplace/add" => 3
           }

    for {_bytes, wire} <- frames do
      assert wire["params"] === if(wire["method"] == "marketplace/add", do: params, else: %{})
    end
  end

  defp commit(ctx, source) do
    git(ctx, source, ["add", "."])

    git(ctx, source, [
      "-c",
      "user.name=Synthetic fixture",
      "-c",
      "user.email=fixture@example.invalid",
      "commit",
      "-m",
      "Owned Git selection fixture"
    ])
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
    assert length(paths) <= 256

    files =
      paths
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, root), snapshot(&1)})

    assert Enum.reduce(files, 0, fn {_path, saved}, size -> size + byte_size(saved.bytes) end) <=
             1_048_576

    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: files}
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
