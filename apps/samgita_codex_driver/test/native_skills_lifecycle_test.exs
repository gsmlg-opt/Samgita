defmodule SamgitaCodexDriver.NativeSkillsLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @plugin "fixture-skills"
  @plugin_id "fixture-skills@fixture-market"

  setup tags do
    TurnFixture.setup(tags)
  end

  test "list preserves requested cwd order and isolates malformed skill metadata until reload",
       ctx do
    valid = user_skill(ctx, "catalog-valid")
    broken = Path.join(ctx.fixture.codex_home, "skills/catalog-broken/SKILL.md")
    File.mkdir_p!(Path.dirname(broken))
    File.write!(broken, "Synthetic invalid skill without frontmatter")
    relative = "relative-skills"
    File.mkdir_p!(Path.join(ctx.fixture.workspace, relative))

    paths =
      for index <- 1..6 do
        path = Path.join(ctx.root, "cwd-#{index}")
        File.mkdir_p!(path)
        path
      end

    pid = start(ctx)

    for params <- [%{}, %{"cwds" => []}] do
      assert [%{"cwd" => cwd} = entry] = call(pid, "skills/list", params)["data"]
      assert cwd == ctx.fixture.workspace
      assert_skill(entry, "catalog-valid", valid, true, "user")

      assert entry["errors"] == [
               %{"path" => broken, "message" => "missing YAML frontmatter delimited by ---"}
             ]
    end

    requested = [List.last(paths) | paths] ++ [hd(paths), relative]
    entries = call(pid, "skills/list", %{"cwds" => requested, "forceReload" => true})["data"]
    assert Enum.map(entries, & &1["cwd"]) == requested

    for entry <- entries do
      assert_skill(entry, "catalog-valid", valid, true, "user")

      assert entry["errors"] == [
               %{"path" => broken, "message" => "missing YAML frontmatter delimited by ---"}
             ]
    end

    write_skill(broken, "catalog-repaired")

    for entry <- call(pid, "skills/list", %{"cwds" => requested, "forceReload" => true})["data"] do
      assert entry["errors"] == []
      assert_skill(entry, "catalog-repaired", broken, true, "user")
    end

    assert_idle(ctx, pid)
  end

  test "path configuration canonicalizes owned aliases and persists without duplicate overrides",
       ctx do
    path = user_skill(ctx, "persistent-path")
    alias_path = Path.join(ctx.root, "owned-skill-alias.md")
    File.ln_s!(path, alias_path)
    config = config_path(ctx)
    original = File.read!(config)
    pid = start(ctx)
    assert_enabled(pid, "persistent-path", true)
    assert write(pid, %{"path" => alias_path}, false) == %{"effectiveEnabled" => false}
    disabled_config = File.read!(config)
    assert disabled_config =~ path
    refute disabled_config =~ alias_path
    assert_enabled(pid, "persistent-path", false)
    assert write(pid, %{"path" => path}, false) == %{"effectiveEnabled" => false}
    assert File.read!(config) == disabled_config
    assert length(Regex.scan(~r/\[\[skills\.config\]\]/, disabled_config)) == 1
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert_enabled(cold, "persistent-path", false)
    assert write(cold, %{"path" => path}, true) == %{"effectiveEnabled" => true}
    assert_enabled(cold, "persistent-path", true)
    assert File.read!(config) == original
    assert_idle(ctx, cold)
  end

  test "name and path selectors remain independent and requested enablement is not a resolved snapshot",
       ctx do
    path = user_skill(ctx, "selector-skill")
    user_skill(ctx, "selector-unrelated")
    pid = start(ctx)
    assert write(pid, %{"name" => "  selector-skill  "}, false) == %{"effectiveEnabled" => false}
    assert File.read!(config_path(ctx)) =~ "name = \"selector-skill\""
    assert_enabled(pid, "selector-skill", false)
    assert_enabled(pid, "selector-unrelated", true)
    assert write(pid, %{"path" => path}, false) == %{"effectiveEnabled" => false}
    assert write(pid, %{"name" => "selector-skill"}, true) == %{"effectiveEnabled" => true}
    assert_enabled(pid, "selector-skill", false)
    assert write(pid, %{"path" => path}, true) == %{"effectiveEnabled" => true}
    assert_enabled(pid, "selector-skill", true)
    assert write(pid, %{"name" => "late-selector"}, false) == %{"effectiveEnabled" => false}
    late = user_skill(ctx, "late-selector")
    assert_skill(list(pid, nil, true), "late-selector", late, false, "user")
    assert_enabled(pid, "selector-unrelated", true)
    assert_idle(ctx, pid)
  end

  test "explicit null path selects a name and persists only that override across restart", ctx do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    path = user_skill(ctx, "explicit-null-path")
    unrelated = user_skill(ctx, "explicit-null-unrelated")
    sources = Enum.map([path, unrelated], &{&1, File.read!(&1)})
    config = config_path(ctx)
    original = File.read!(config)
    selector = %{"path" => nil, "name" => "  explicit-null-path  "}
    pid = start(ctx)
    entry = list(pid, nil, true)
    assert_skill(entry, "explicit-null-path", path, true, "user")
    assert_skill(entry, "explicit-null-unrelated", unrelated, true, "user")

    assert write(pid, selector, false) == %{"effectiveEnabled" => false}
    disabled_config = File.read!(config)
    assert disabled_config =~ "name = \"explicit-null-path\""
    refute disabled_config =~ path
    assert length(Regex.scan(~r/\[\[skills\.config\]\]/, disabled_config)) == 1
    entry = list(pid, nil, true)
    assert_skill(entry, "explicit-null-path", path, false, "user")
    assert_skill(entry, "explicit-null-unrelated", unrelated, true, "user")
    assert write(pid, selector, false) == %{"effectiveEnabled" => false}
    assert File.read!(config) == disabled_config
    for {source, bytes} <- sources, do: assert(File.read!(source) == bytes)
    assert_idle(ctx, pid)
    assert %{interactions: 0} = Session.status(pid)
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
    process_id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)

    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process_id
    entry = list(cold, nil, true)
    assert_skill(entry, "explicit-null-path", path, false, "user")
    assert_skill(entry, "explicit-null-unrelated", unrelated, true, "user")
    assert File.read!(config) == disabled_config
    assert write(cold, selector, true) == %{"effectiveEnabled" => true}
    entry = list(cold, nil, true)
    assert_skill(entry, "explicit-null-path", path, true, "user")
    assert_skill(entry, "explicit-null-unrelated", unrelated, true, "user")
    assert File.read!(config) == original
    for {source, bytes} <- sources, do: assert(File.read!(source) == bytes)
    assert_idle(ctx, cold)
    assert %{interactions: 0} = Session.status(cold)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert {:ok, events} = Session.drain(cold)
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert :ok = Session.close(cold)
  end

  test "concurrent independent configuration writes retain both serialized durable edits", ctx do
    paths = for name <- ["concurrent-first", "concurrent-second"], do: user_skill(ctx, name)
    original = File.read!(config_path(ctx))
    pid = start(ctx)
    concurrent_write(pid, paths, false)
    for name <- ["concurrent-first", "concurrent-second"], do: assert_enabled(pid, name, false)
    persisted = File.read!(config_path(ctx))
    for path <- paths, do: assert(persisted =~ path)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    for name <- ["concurrent-first", "concurrent-second"], do: assert_enabled(cold, name, false)
    concurrent_write(cold, paths, true)
    for name <- ["concurrent-first", "concurrent-second"], do: assert_enabled(cold, name, true)
    assert File.read!(config_path(ctx)) == original
    assert_idle(ctx, cold)
  end

  test "extra roots replace deduplicate clear and disappear on restart without configuration writes",
       ctx do
    first = Path.join(ctx.root, "runtime-first")
    second = Path.join(ctx.root, "runtime-second")
    first_path = write_skill(Path.join(first, "extra-first/SKILL.md"), "extra-first")
    second_path = write_skill(Path.join(second, "extra-second/SKILL.md"), "extra-second")
    original = File.read!(config_path(ctx))
    pid = start(ctx)
    set_roots(pid, [first, first])
    entry = list(pid)
    assert Enum.count(entry["skills"], &(&1["name"] == "extra-first")) == 1
    assert_skill(entry, "extra-first", first_path, true, "user")
    set_roots(pid, [second])
    refute skill(list(pid), "extra-first")
    assert_skill(list(pid), "extra-second", second_path, true, "user")
    set_roots(pid, [Path.join(ctx.root, "missing-runtime-root")])
    entry = list(pid)
    assert entry["errors"] == []
    refute skill(entry, "extra-first")
    refute skill(entry, "extra-second")
    set_roots(pid, [first])
    assert skill(list(pid), "extra-first")
    set_roots(pid, [])
    refute skill(list(pid), "extra-first")
    set_roots(pid, [second])
    assert skill(list(pid), "extra-second")
    assert File.read!(config_path(ctx)) == original
    assert :ok = Session.close(pid)
    cold = start(ctx)
    refute skill(list(cold), "extra-second")
    assert File.read!(config_path(ctx)) == original
    assert_idle(ctx, cold)
  end

  test "force reload follows installed local plugin roots and feature or plugin disablement",
       ctx do
    marketplace = local_plugin(ctx)
    pid = start(ctx, local_plugins: true)
    assert call(pid, "config/read", %{})["config"]["features"]["plugins"] == true
    params = %{"marketplacePath" => marketplace, "pluginName" => @plugin}

    listing =
      call(pid, "plugin/list", %{
        "cwds" => [ctx.fixture.workspace],
        "marketplaceKinds" => ["local"],
        "forceRefetch" => false
      })

    assert listing["marketplaceLoadErrors"] == []
    assert call(pid, "plugin/install", params)["appsNeedingAuth"] == []
    selected = skill(list(pid, nil, true), @plugin <> ":inspect")

    assert %{"enabled" => true, "pluginId" => @plugin_id, "scope" => "user", "path" => path} =
             selected

    plugin_root = path |> Path.dirname() |> Path.dirname() |> Path.dirname()
    manifest = Path.join(plugin_root, ".codex-plugin/plugin.json")
    assert File.regular?(manifest)
    File.write!(manifest, JSON.encode!(%{"name" => @plugin, "skills" => "./replacement-skills"}))

    replacement =
      write_skill(Path.join(plugin_root, "replacement-skills/refreshed/SKILL.md"), "refreshed")

    entry = list(pid, nil, true)
    refute skill(entry, @plugin <> ":inspect")

    assert %{"path" => ^replacement, "pluginId" => @plugin_id, "enabled" => true} =
             skill(entry, @plugin <> ":refreshed")

    other = Path.join(ctx.root, "plugin-other-cwd")
    File.mkdir_p!(other)
    assert skill(list(pid, other), @plugin <> ":refreshed")
    config_value(pid, "features.plugins", false)
    refute skill(list(pid, nil, true), @plugin <> ":refreshed")
    config_value(pid, "features.plugins", true)
    assert skill(list(pid, nil, true), @plugin <> ":refreshed")
    config_value(pid, "plugins", %{@plugin_id => %{"enabled" => false}})
    refute skill(list(pid, nil, true), @plugin <> ":refreshed")
    assert_idle(ctx, pid)
  end

  test "disabled execution environment excludes repository roots while owned user and runtime roots remain",
       ctx do
    home = user_skill(ctx, "boundary-user")

    repo =
      write_skill(
        Path.join(ctx.fixture.workspace, ".agents/skills/boundary-repo/SKILL.md"),
        "boundary-repo"
      )

    File.mkdir_p!(Path.join(ctx.fixture.workspace, ".git"))
    extra = Path.join(ctx.root, "boundary-runtime")
    runtime = write_skill(Path.join(extra, "boundary-extra/SKILL.md"), "boundary-extra")
    normal = start(ctx)
    assert_skill(list(normal, nil, true), "boundary-repo", repo, true, "repo")
    assert :ok = Session.close(normal)
    pid = start(ctx, env: %{"CODEX_EXEC_SERVER_URL" => "none"})
    set_roots(pid, [extra])
    entry = list(pid, nil, true)
    assert entry["errors"] == []
    assert_skill(entry, "boundary-user", home, true, "user")
    assert_skill(entry, "boundary-extra", runtime, true, "user")
    refute skill(entry, "boundary-repo")
    assert_idle(ctx, pid)
  end

  test "stable negotiation and malformed selectors or roots preserve the native settings boundary",
       ctx do
    path = user_skill(ctx, "stable-skill")
    root = Path.join(ctx.root, "stable-extra")
    write_skill(Path.join(root, "stable-extra/SKILL.md"), "stable-extra")

    for negotiation <- [:absent, false] do
      pid = start(ctx, experimental: negotiation)
      assert_skill(list(pid), "stable-skill", path, true, "user")
      assert write(pid, %{"path" => path}, false) == %{"effectiveEnabled" => false}
      assert_enabled(pid, "stable-skill", false)
      assert write(pid, %{"path" => path}, true) == %{"effectiveEnabled" => true}
      set_roots(pid, [root])
      assert skill(list(pid), "stable-extra")
      set_roots(pid, [])
      assert :ok = Session.close(pid)
    end

    pid = start(ctx)
    set_roots(pid, [root])
    original = File.read!(config_path(ctx))

    for selector <- [%{}, %{"path" => path, "name" => "stable-skill"}, %{"name" => " \t "}] do
      assert upstream_error(pid, "skills/config/write", Map.put(selector, "enabled", false)) == %{
               "code" => -32_602,
               "message" => "skills/config/write requires exactly one of path or name"
             }

      assert File.read!(config_path(ctx)) == original
      assert_enabled(pid, "stable-skill", true)
    end

    for {method, params} <- [
          {"skills/list", %{"cwds" => 42}},
          {"skills/list", %{"forceReload" => "yes"}},
          {"skills/config/write", %{"path" => path}},
          {"skills/config/write", %{"name" => 42, "enabled" => false}},
          {"skills/extraRoots/set", %{}},
          {"skills/extraRoots/set", %{"extraRoots" => [42]}}
        ] do
      assert {:error, %Error{code: :schema_violation}} = Session.request(pid, method, params)
      assert_invalid_wire(pid, method, params)
      assert File.read!(config_path(ctx)) == original
      assert skill(list(pid), "stable-extra")
    end

    assert_invalid_wire(pid, "skills/extraRoots/set", %{"extraRoots" => ["relative/path"]})
    assert File.read!(config_path(ctx)) == original
    assert skill(list(pid), "stable-extra")
    assert_idle(ctx, pid)
  end

  defp start(ctx, opts \\ []) do
    args = ["app-server", "--listen", "stdio://"]

    if Keyword.get(opts, :local_plugins, false) do
      NativeLaunchFixture.local_plugins_after_initialize(config_path(ctx), fn ->
        start_initialized(ctx, opts, args)
      end)
    else
      start_initialized(ctx, opts, NativeLaunchFixture.ordinary_args(args))
    end
  end

  defp start_initialized(ctx, opts, args) do
    fixture = ctx.fixture

    env =
      Map.merge(
        %{
          "HOME" => fixture.home,
          "CODEX_HOME" => fixture.codex_home,
          "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "NO_COLOR" => "1",
          "RUST_LOG" => "off"
        },
        Keyword.get(opts, :env, %{})
      )

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: args,
             cwd: fixture.workspace,
             env: env
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capability = Keyword.get(opts, :experimental, true)
    capabilities = if capability == :absent, do: %{}, else: %{"experimentalApi" => capability}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_skills_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp call(pid, method, params), do: TurnFixture.call(pid, method, params)

  defp upstream_error(pid, method, params, opts \\ []),
    do: TurnFixture.upstream_error(pid, method, params, opts)

  defp config_path(ctx), do: Path.join(ctx.fixture.codex_home, "config.toml")

  defp user_skill(ctx, name),
    do: write_skill(Path.join(ctx.fixture.codex_home, "skills/#{name}/SKILL.md"), name)

  defp write_skill(path, name) do
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      "---\nname: #{name}\ndescription: Synthetic #{name} metadata\n---\n\nSynthetic instructions only.\n"
    )

    path
  end

  defp list(pid, cwd \\ nil, force \\ false) do
    params = %{"forceReload" => force}
    params = if cwd, do: Map.put(params, "cwds", [cwd]), else: params
    assert [entry] = call(pid, "skills/list", params)["data"]
    entry
  end

  defp skill(entry, name), do: Enum.find(entry["skills"], &(&1["name"] == name))

  defp assert_skill(entry, name, path, enabled, scope) do
    assert %{
             "name" => ^name,
             "path" => ^path,
             "enabled" => ^enabled,
             "scope" => ^scope,
             "description" => description
           } = skill(entry, name)

    assert description == "Synthetic #{name} metadata"
  end

  defp assert_enabled(pid, name, enabled),
    do: assert(%{"enabled" => ^enabled} = skill(list(pid), name))

  defp write(pid, selector, enabled),
    do: call(pid, "skills/config/write", Map.put(selector, "enabled", enabled))

  defp concurrent_write(pid, paths, enabled) do
    tasks =
      for path <- paths do
        Task.async(fn ->
          Session.request(pid, "skills/config/write", %{"path" => path, "enabled" => enabled})
        end)
      end

    for result <- Task.await_many(tasks, 10_000) do
      assert {:ok, %{"result" => %{"effectiveEnabled" => ^enabled}}} = result
    end
  end

  defp set_roots(pid, roots) do
    assert {:ok, _} = Session.drain(pid)
    assert call(pid, "skills/extraRoots/set", %{"extraRoots" => roots}) == %{}
    assert %{} == await_changed(pid, System.monotonic_time(:millisecond) + 10_000)
  end

  defp await_changed(pid, deadline) do
    assert {:ok, events} = Session.drain(pid)

    case Enum.find(events, &(&1.wire["method"] == "skills/changed")) do
      nil ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Native skills changed notification deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Native skills gap: #{inspect(gap)}")
        after
          10 -> :ok
        end

        await_changed(pid, deadline)

      event ->
        event.wire["params"]
    end
  end

  defp config_value(pid, key, value) do
    call(pid, "config/value/write", %{
      "keyPath" => key,
      "value" => value,
      "mergeStrategy" => "replace"
    })
  end

  defp assert_invalid_wire(pid, method, params) do
    error = upstream_error(pid, method, params, validation: :wire)
    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "Invalid request: ")
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp local_plugin(ctx) do
    workspace = ctx.fixture.workspace
    marketplace = Path.join(workspace, ".agents/plugins/marketplace.json")
    plugin = Path.join(workspace, @plugin)
    File.mkdir_p!(Path.join(workspace, ".git"))
    File.mkdir_p!(Path.dirname(marketplace))
    File.mkdir_p!(Path.join(plugin, ".codex-plugin"))

    File.write!(
      marketplace,
      JSON.encode!(%{
        "name" => "fixture-market",
        "plugins" => [
          %{"name" => @plugin, "source" => %{"source" => "local", "path" => "./#{@plugin}"}}
        ]
      })
    )

    File.write!(
      Path.join(plugin, ".codex-plugin/plugin.json"),
      JSON.encode!(%{"name" => @plugin, "description" => "Synthetic local skills"})
    )

    write_skill(Path.join(plugin, "skills/inspect/SKILL.md"), "inspect")

    File.write!(config_path(ctx), "\n[features]\nplugins = true\nremote_plugin = false\n", [
      :append
    ])

    marketplace
  end
end
