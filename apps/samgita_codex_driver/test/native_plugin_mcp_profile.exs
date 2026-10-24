defmodule SamgitaCodexDriver.NativePluginMcpProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_plugin_mcp_fixture.py", __DIR__)
  @launcher Path.expand("../../../scripts/codex/isolated_plugin_fixture.py", __DIR__)
  @fixture_sha "a28705ee5a69837f317129df1f1586240bfec064583762f635867eb89a04b858"
  @launcher_sha "f2ba1e6f507d2e26e58cea4498cb8b73c46f92ce636266d525af705760e97122"
  @native_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @market "fixture-mcp-lifecycle"
  @plugin "fixture-orbit"
  @id "#{@plugin}@#{@market}"
  @server "owned-plugin"
  @message "owned plugin capability λ"

  # Pinned Codex source 83086188ae0614bd882818ff1aa23f3194962012:
  # app-server/request_processors/plugins.rs:1540-1591,2010-2038 refreshes install/uninstall.
  # core-plugins/loader.rs:982-995 applies plugin disabled_tools policy.
  # codex-mcp/connection_manager.rs:991-1021 rejects unknown servers/filtered tools before dispatch.
  # app-server/tests/suite/v2/plugin_install.rs:2460-2557 proves same-thread bundled stdio install.
  # SHA256 plugins.rs: 78268f03497b38a9e02bc00b765b0929a7f50cd5c4df2378180d9625a51181de
  # SHA256 loader.rs: 5e7134b8a50a72792420e3d2bc2d480bb219398a225d673fb3545bc68bfd27df
  # SHA256 connection_manager.rs: 6b0fe696c3e6b89079a9e6c013622e11fa23a1f08f65f01af4a835a5c1975c86

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @native_sha
    assert hash(File.read!(@script)) == @fixture_sha
    assert hash(File.read!(@launcher)) == @launcher_sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-plugin-mcp-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      python: System.find_executable("python3"),
      workspace: Path.join(root, "workspace"),
      plugin_root: Path.join(root, "workspace/#{@plugin}"),
      marketplace: Path.join(root, "workspace/.agents/plugins/marketplace.json"),
      config: Path.join(root, "codex/config.toml"),
      journal: Path.join(root, "plugin-mcp.jsonl")
    }

    on_exit(fn ->
      for row <- starts(ctx), do: await_process_exit(row["pid"])
      File.rm_rf!(root)
    end)

    File.write!(Path.join(root, "parent-netns"), File.read_link!("/proc/self/ns/net"))
    File.mkdir_p!(Path.join(ctx.workspace, ".git"))
    configure(ctx)
    sources = source_files(ctx)
    for {path, bytes} <- sources, do: File.write!(path, bytes)
    Map.put(ctx, :sources, sources)
  end

  test "local plugin install enables one same-thread tool while policy and uninstall prevent dispatch",
       ctx do
    assert_sources(ctx)
    refute File.exists?(cache_root(ctx))
    warm = start(ctx)
    thread = thread(ctx, warm.pid)

    assert error(warm.pid, "mcpServer/tool/call", tool_params(thread, "echo")) ==
             unknown_server()

    assert_calls(ctx, [])

    assert call(warm.pid, "plugin/install", selectors(ctx)) === %{
             "authPolicy" => "ON_INSTALL",
             "appsNeedingAuth" => []
           }

    persisted = File.read!(ctx.config)
    assert persisted =~ ~s(disabled_tools = ["hidden"])
    refute persisted =~ "[mcp_servers.#{@server}]"
    assert_installed(ctx, warm.pid)

    assert call(warm.pid, "mcpServer/tool/call", tool_params(thread, "echo")) === %{
             "content" => [
               %{"type" => "text", "text" => "Synthetic plugin MCP result: " <> @message}
             ],
             "structuredContent" => %{
               "echo" => @message,
               "association" => "owned-plugin-echo-1",
               "threadId" => thread
             },
             "isError" => false
           }

    expected_call = %{
      "name" => "echo",
      "arguments" => %{"message" => @message},
      "_meta" => %{"threadId" => thread}
    }

    assert_calls(ctx, [expected_call])

    assert error(warm.pid, "mcpServer/tool/call", tool_params(thread, "hidden")) == %{
             "code" => -32_603,
             "message" => "tool 'hidden' is disabled for MCP server '#{@server}'"
           }

    assert_calls(ctx, [expected_call])
    assert call(warm.pid, "plugin/read", selectors(ctx))["plugin"]["mcpServers"] === [@server]

    assert %{"data" => [server], "nextCursor" => nil} =
             call(warm.pid, "mcpServerStatus/list", %{
               "threadId" => thread,
               "serverName" => @server,
               "detail" => "full"
             })

    assert server["name"] === @server
    assert server["pluginId"] === @id
    assert server["runtimeStatus"] === "connected"
    assert server["serverInfo"]["name"] === "owned-plugin-peer"
    assert server["serverInfo"]["version"] === "1"
    assert_cache(ctx)
    assert_sources(ctx)
    assert_no_turn(warm.pid)

    # A successful empty response is followed by an independent stale-runtime dispatch check.
    assert call(warm.pid, "plugin/uninstall", %{"pluginId" => @id}) === %{}

    assert error(warm.pid, "mcpServer/tool/call", tool_params(thread, "echo")) ==
             unknown_server()

    assert_empty_catalog(ctx, warm.pid)
    assert_calls(ctx, [expected_call])
    refute File.exists?(cache_root(ctx))
    assert_sources(ctx)
    assert_no_turn(warm.pid)
    close_native(ctx, warm)

    cold = start(ctx)
    refute cold.proof["native_pid"] == warm.proof["native_pid"]
    # Namespace inode numbers may be reused after the old owner is reaped.
    # Each start independently proves isolation from the parent and live ownership.
    refute File.exists?("/proc/#{warm.proof["native_pid"]}")
    cold_thread = thread(ctx, cold.pid)

    assert error(cold.pid, "mcpServer/tool/call", tool_params(cold_thread, "echo")) ==
             unknown_server()

    assert_empty_catalog(ctx, cold.pid)
    assert_calls(ctx, [expected_call])
    refute File.exists?(cache_root(ctx))
    assert_sources(ctx)
    assert_no_turn(cold.pid)
    assert Enum.all?(starts(ctx), &(&1["namespace"] == warm.proof["namespace"]))
    close_native(ctx, cold)
    assert_calls(ctx, [expected_call])
    assert_sources(ctx)
  end

  defp configure(ctx) do
    catalog = Path.join(ctx.root, "codex/catalog.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "mock-model",
            "display_name" => "Owned MCP only; no inference",
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{"instructions_template" => "No turns in this profile."},
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    File.write!(ctx.config, """
    model = "mock-model"
    model_provider = "fixture"
    model_catalog_json = #{JSON.encode!(catalog)}
    chatgpt_base_url = "http://127.0.0.1:1/backend-api"
    openai_base_url = "http://127.0.0.1:1/v1"
    cli_auth_credentials_store = "file"
    check_for_update_on_startup = false
    [features]
    plugins = true
    remote_plugin = false
    plugin_sharing = false
    mcp_2026_07_28 = false
    shell_tool = false
    unified_exec = false
    shell_snapshot = false
    apps = false
    hooks = false
    [analytics]
    enabled = false
    [model_providers.fixture]
    name = "Owned MCP only; no provider listener"
    base_url = "http://127.0.0.1:1/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    [plugins."#{@id}"]
    enabled = false
    [plugins."#{@id}".mcp_servers.#{@server}]
    disabled_tools = ["hidden"]
    """)
  end

  defp source_files(ctx) do
    files = %{
      ctx.marketplace =>
        JSON.encode!(%{
          "name" => @market,
          "plugins" => [
            %{"name" => @plugin, "source" => %{"source" => "local", "path" => "./#{@plugin}"}}
          ]
        }),
      Path.join(ctx.plugin_root, ".codex-plugin/plugin.json") =>
        JSON.encode!(%{"name" => @plugin, "description" => "Owned local MCP plugin"}),
      Path.join(ctx.plugin_root, ".mcp.json") =>
        JSON.encode!(%{
          "mcpServers" => %{
            @server => %{
              "command" => ctx.python,
              "args" => ["-B", @script, "--peer", "--root", ctx.root],
              "env" => %{
                "HOME" => Path.join(ctx.root, "home"),
                "CODEX_HOME" => Path.join(ctx.root, "codex"),
                "TMPDIR" => Path.join(ctx.root, "tmp")
              }
            }
          }
        })
    }

    for path <- Map.keys(files), do: File.mkdir_p!(Path.dirname(path))
    files
  end

  defp start(ctx) do
    proof_path = Path.join(ctx.root, "proof-#{System.unique_integer([:positive])}.json")

    {:ok, pid} =
      Session.start_link(
        request_timeout_ms: 5_000,
        transport:
          {Stdio,
           [
             executable: ctx.python,
             args: [
               "-B",
               @script,
               "--root",
               ctx.root,
               "--codex",
               ctx.binary,
               "--proof",
               proof_path
             ],
             cwd: ctx.workspace,
             inherit_env: [],
             env: environment(ctx),
             max_message_bytes: 1_048_576
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      await_native_exit(ctx, proof_path)
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_plugin_mcp", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    proof = proof(proof_path)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"]
    assert proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]
    assert call(pid, "server/diagnostics", %{})["process"]["id"] == proof["native_pid"]
    %{pid: pid, connection: connection, proof: proof, proof_path: proof_path}
  end

  defp thread(ctx, pid) do
    result =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "ephemeral" => true
      })

    assert %{"thread" => %{"id" => id, "turns" => []}} = result
    assert is_binary(id) and id != ""
    id
  end

  defp assert_installed(ctx, pid) do
    summary = %{
      "id" => @id,
      "remotePluginId" => nil,
      "version" => nil,
      "localVersion" => nil,
      "name" => @plugin,
      "shareContext" => nil,
      "source" => %{"type" => "local", "path" => ctx.plugin_root},
      "installed" => true,
      "installedAt" => nil,
      "enabled" => true,
      "installPolicy" => "AVAILABLE",
      "installPolicySource" => nil,
      "mustShowInstallationInterstitial" => nil,
      "authPolicy" => "ON_INSTALL",
      "availability" => "AVAILABLE",
      "disabledReason" => nil,
      "eligiblePlanTypes" => nil,
      "interface" => nil,
      "keywords" => []
    }

    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === %{
             "marketplaces" => [
               %{
                 "name" => @market,
                 "path" => ctx.marketplace,
                 "interface" => nil,
                 "plugins" => [summary]
               }
             ],
             "marketplaceLoadErrors" => []
           }
  end

  defp assert_empty_catalog(ctx, pid) do
    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === %{
             "marketplaces" => [],
             "marketplaceLoadErrors" => []
           }
  end

  defp assert_sources(ctx) do
    for {path, bytes} <- ctx.sources do
      assert File.lstat!(path).type == :regular
      assert File.read!(path) === bytes
    end

    assert hash(File.read!(@script)) == @fixture_sha
    assert hash(File.read!(@launcher)) == @launcher_sha

    for path <- ~w(codex/auth.json home/.git-credentials home/.netrc) do
      refute File.exists?(Path.join(ctx.root, path))
    end
  end

  defp assert_cache(ctx) do
    assert File.lstat!(cache_root(ctx)).type == :directory

    for relative <- [".codex-plugin/plugin.json", ".mcp.json"] do
      path = Path.join(cache_root(ctx), relative)
      assert File.lstat!(path).type == :regular
      assert File.read!(path) === Map.fetch!(ctx.sources, Path.join(ctx.plugin_root, relative))
    end
  end

  defp assert_calls(ctx, expected) do
    rows = journal(ctx)
    refute Enum.any?(rows, &(&1["event"] == "fatal"))
    calls = Enum.filter(rows, &(&1["event"] == "request" and &1["method"] == "tools/call"))
    assert Enum.map(calls, & &1["params"]) === expected
    if expected != [], do: assert(starts(ctx) != [])

    for row <- starts(ctx) do
      assert is_integer(row["pid"]) and row["pid"] > 0
      assert row["credentialsPresent"] === false
      refute row["namespace"] == File.read!(Path.join(ctx.root, "parent-netns"))
    end
  end

  defp assert_no_turn(pid) do
    assert {:ok, events} = Session.drain(pid, 1_000)

    for event <- events do
      refute event.kind == :server_request

      refute event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/mcpToolCall/progress",
               "error"
             ]
    end

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp journal(ctx) do
    if File.exists?(ctx.journal) do
      raw = File.read!(ctx.journal)
      assert byte_size(raw) <= 1_048_576
      rows = raw |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      assert length(rows) <= 128
      rows
    else
      []
    end
  end

  defp starts(ctx), do: Enum.filter(journal(ctx), &(&1["event"] == "start"))

  defp close_native(ctx, native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    await_native_exit(ctx, native.proof_path)
  end

  defp await_native_exit(ctx, proof_path) do
    if File.exists?(proof_path) do
      native = proof(proof_path)
      for key <- ~w(native_pid namespace_owner_pid), do: await_process_exit(native[key])

      peers = for row <- starts(ctx), row["namespace"] == native["namespace"], do: row["pid"]
      for peer <- peers, do: await_process_exit(peer)

      exits =
        for row <- journal(ctx), row["event"] == "exit" and row["pid"] in peers, do: row["pid"]

      assert Enum.sort(exits) == Enum.sort(peers)
    end
  end

  defp proof(path), do: path |> File.read!() |> JSON.decode!()
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp cache_root(ctx), do: Path.join(ctx.root, "codex/plugins/cache/#{@market}/#{@plugin}/local")
  defp selectors(ctx), do: %{"marketplacePath" => ctx.marketplace, "pluginName" => @plugin}

  defp tool_params(thread, name),
    do: %{
      "threadId" => thread,
      "server" => @server,
      "tool" => name,
      "arguments" => %{"message" => @message},
      "_meta" => %{"threadId" => "untrusted-client-placeholder"}
    }

  defp unknown_server,
    do: %{"code" => -32_603, "message" => "unknown MCP server '#{@server}'"}

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params, timeout_ms: 5_000)
    result
  end

  defp error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => failure}}} =
             Session.request(pid, method, params, timeout_ms: 5_000)

    failure
  end

  defp environment(ctx),
    do: %{
      "HOME" => Path.join(ctx.root, "home"),
      "CODEX_HOME" => Path.join(ctx.root, "codex"),
      "TMPDIR" => Path.join(ctx.root, "tmp"),
      "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_TERMINAL_PROMPT" => "0",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "RUST_LOG" => "off",
      "NO_COLOR" => "1"
    }

  defp await_process_exit(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)
  defp await(predicate, remaining \\ 500)

  defp await(predicate, remaining) when remaining > 0 do
    if predicate.() do
      :ok
    else
      Process.sleep(10)
      await(predicate, remaining - 1)
    end
  end

  defp await(_predicate, 0), do: flunk("owned native or MCP peer was not reaped")
end
