defmodule SamgitaCodexDriver.NativePluginLifecycleProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_plugin_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @market "fixture-lifecycle"
  @plugin "fixture-orbit"
  @id "#{@plugin}@#{@market}"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ["python3", "unshare", "ip", "git"], do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-plugin-lifecycle-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp"], do: File.mkdir_p!(Path.join(root, dir))
    on_exit(fn -> File.rm_rf!(root) end)
    catalog = Path.join(root, "codex/catalog.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "mock-model",
            "display_name" => "Synthetic metadata only",
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

    File.write!(Path.join(root, "codex/config.toml"), """
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
    [model_providers.fixture]
    name = "Synthetic metadata only, no listener"
    base_url = "http://127.0.0.1:1/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    ctx = %{root: root, binary: Path.expand(binary), workspace: Path.join(root, "workspace")}
    File.mkdir_p!(Path.join(ctx.workspace, ".git"))
    marketplace(ctx.workspace, @market, [@plugin, "fixture-hidden"])
    Map.put(ctx, :marketplace, Path.join(ctx.workspace, ".agents/plugins/marketplace.json"))
  end

  test "installed suggestions deduplicate and installation survives a native process restart",
       ctx do
    pid = start(ctx)
    assert installed(pid, ctx) == []

    result =
      call(pid, "plugin/installed", %{
        "cwds" => [ctx.workspace],
        "installSuggestionPluginNames" => [@plugin, @plugin, "missing"]
      })

    assert [%{"id" => @id, "installed" => false}] = summaries(result)
    assert result["marketplaceLoadErrors"] == []
    install(pid, ctx)
    assert [%{"id" => @id, "installed" => true, "enabled" => true}] = installed(pid, ctx)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert [%{"id" => @id, "installed" => true, "enabled" => true}] = installed(cold, ctx)
    assert_idle(cold)
  end

  test "installed local marketplace metadata retains exact identity and display interface after restart",
       ctx do
    display_name = "Owned Marketplace λ"
    manifest = ctx.marketplace |> File.read!() |> JSON.decode!()
    manifest = Map.put(manifest, "interface", %{"displayName" => display_name})
    manifest_bytes = JSON.encode!(manifest)
    File.write!(ctx.marketplace, manifest_bytes)

    expected = %{
      "marketplaces" => [
        %{
          "name" => @market,
          "path" => ctx.marketplace,
          "interface" => %{"displayName" => display_name},
          "plugins" => [
            %{
              "id" => @id,
              "remotePluginId" => nil,
              "version" => nil,
              "localVersion" => nil,
              "name" => @plugin,
              "shareContext" => nil,
              "source" => %{"type" => "local", "path" => Path.join(ctx.workspace, @plugin)},
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
              "keywords" => ["synthetic-#{@plugin}-keyword"]
            }
          ]
        }
      ],
      "marketplaceLoadErrors" => []
    }

    pid = start(ctx)

    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === %{
             "marketplaces" => [],
             "marketplaceLoadErrors" => []
           }

    install(pid, ctx)

    # This is local installed-catalog metadata, not plugin execution or policy enforcement.
    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert File.read!(ctx.marketplace) === manifest_bytes
    assert_idle(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    await_process_exit(native)

    cold = start(ctx)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    refute cold_native == native
    assert call(cold, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert File.read!(ctx.marketplace) === manifest_bytes
    assert_idle(cold)
    %{connection: cold_connection} = :sys.get_state(cold)
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    await_process_exit(cold_native)
  end

  test "local plugin detail and search retain rich metadata and onboarding after restart",
       ctx do
    plugin_root = Path.join(ctx.workspace, @plugin)
    assets = Path.join(plugin_root, "assets")
    File.mkdir_p!(assets)

    png =
      <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
        2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
        0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

    composer = Path.join(assets, "composer.png")
    logo = Path.join(assets, "logo.png")
    screenshot = Path.join(assets, "screen.png")
    asset_paths = [composer, logo, screenshot]
    for path <- asset_paths, do: File.write!(path, png)

    skill_root = Path.join(plugin_root, "skills/inspect")
    skill_source = Path.join(skill_root, "SKILL.md")
    skill_source_bytes = File.read!(skill_source)
    skill_metadata = Path.join(skill_root, "agents/openai.yaml")
    skill_assets = Path.join(skill_root, "assets")
    File.mkdir_p!(Path.dirname(skill_metadata))
    File.mkdir_p!(skill_assets)
    skill_small = Path.join(skill_assets, "small.png")
    skill_large = Path.join(skill_assets, "large.png")
    for path <- [skill_small, skill_large], do: File.write!(path, png)

    skill_yaml = """
    interface:
      display_name: "  Owned   plugin skill λ  "
      short_description: "  Owned   skill interface summary  "
      default_prompt: "  Inspect   owned plugin metadata only  "
      brand_color: " #123ABC "
      icon_small: "./assets/small.png"
      icon_large: "assets/large.png"
    """

    File.write!(skill_metadata, skill_yaml)

    manifest_path = Path.join(plugin_root, ".codex-plugin/plugin.json")
    manifest = manifest_path |> File.read!() |> JSON.decode!()

    manifest =
      Map.put(manifest, "interface", %{
        "displayName" => "Owned Local Plugin λ",
        "shortDescription" => "Owned short metadata λ",
        "longDescription" => "Owned long metadata; no execution.",
        "developerName" => "Owned Fixture",
        "category" => "Owned Tools",
        "capabilities" => ["metadata-only", "fixture"],
        "websiteUrl" => "https://plugin.example.invalid/",
        "privacyPolicyUrl" => "https://plugin.example.invalid/privacy",
        "termsOfServiceUrl" => "https://plugin.example.invalid/terms",
        "defaultPrompt" => ["  Inspect \n owned   plugin ", "Review synthetic metadata λ"],
        "brandColor" => "#123ABC",
        "composerIcon" => "./assets/composer.png",
        "logo" => "./assets/logo.png",
        "screenshots" => ["./assets/screen.png"]
      })

    manifest =
      Map.put(manifest, "extensions", %{
        "com.openai" => %{"onboardingSkill" => "skills/inspect/SKILL.md"}
      })

    manifest_bytes = JSON.encode!(manifest)
    File.write!(manifest_path, manifest_bytes)
    marketplace_bytes = File.read!(ctx.marketplace)
    auth_path = Path.join(ctx.root, "codex/auth.json")

    assert_sources = fn ->
      assert File.lstat!(manifest_path).type == :regular
      assert File.read!(manifest_path) === manifest_bytes
      assert File.read!(ctx.marketplace) === marketplace_bytes
      assert Enum.sort(File.ls!(assets)) == ["composer.png", "logo.png", "screen.png"]

      for path <- asset_paths do
        assert File.lstat!(path).type == :regular
        assert File.read!(path) === png
      end

      assert File.read!(skill_source) === skill_source_bytes
      assert File.read!(skill_metadata) === skill_yaml
      assert Enum.sort(File.ls!(skill_assets)) == ["large.png", "small.png"]

      for path <- [skill_small, skill_large] do
        assert File.lstat!(path).type == :regular
        assert File.read!(path) === png
      end

      refute File.exists?(auth_path)
    end

    expected_interface = %{
      "displayName" => "Owned Local Plugin λ",
      "shortDescription" => "Owned short metadata λ",
      "longDescription" => "Owned long metadata; no execution.",
      "developerName" => "Owned Fixture",
      "category" => "Owned Tools",
      "capabilities" => ["metadata-only", "fixture"],
      "websiteUrl" => "https://plugin.example.invalid/",
      "privacyPolicyUrl" => "https://plugin.example.invalid/privacy",
      "termsOfServiceUrl" => "https://plugin.example.invalid/terms",
      "defaultPrompt" => ["Inspect owned plugin", "Review synthetic metadata λ"],
      "brandColor" => "#123ABC",
      "composerIcon" => composer,
      "composerIconUrl" => nil,
      "logo" => logo,
      "logoDark" => nil,
      "logoUrl" => nil,
      "logoUrlDark" => nil,
      "screenshots" => [screenshot],
      "screenshotUrls" => []
    }

    expected_summary = %{
      "id" => @id,
      "remotePluginId" => nil,
      "version" => nil,
      "localVersion" => nil,
      "name" => @plugin,
      "shareContext" => nil,
      "source" => %{"type" => "local", "path" => plugin_root},
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
      "interface" => expected_interface,
      "keywords" => ["synthetic-#{@plugin}-keyword"]
    }

    expected = %{
      "marketplaces" => [
        %{
          "name" => @market,
          "path" => ctx.marketplace,
          "interface" => nil,
          "plugins" => [expected_summary]
        }
      ],
      "marketplaceLoadErrors" => []
    }

    expected_skill = %{
      "name" => @plugin <> ":inspect",
      "description" => "Synthetic lifecycle inspection",
      "shortDescription" => nil,
      "path" => skill_source,
      "enabled" => true,
      "interface" => %{
        "displayName" => "Owned plugin skill λ",
        "shortDescription" => "Owned skill interface summary",
        "defaultPrompt" => "Inspect owned plugin metadata only",
        "brandColor" => "#123ABC",
        "iconSmall" => skill_small,
        "iconLarge" => skill_large,
        "iconSmallUrl" => nil,
        "iconLargeUrl" => nil
      }
    }

    expected_detail = %{
      "marketplaceName" => @market,
      "marketplacePath" => ctx.marketplace,
      "summary" => expected_summary,
      "shareUrl" => nil,
      "description" => "Synthetic lifecycle plugin",
      "skills" => [expected_skill],
      "onboardingSkill" => expected_skill,
      "hooks" => [],
      "apps" => [],
      "appTemplates" => [],
      "mcpServers" => [],
      "scheduledTasks" => nil
    }

    # The pinned discovery projection always reports enabled=false, even for an
    # installed active plugin. Its native query is independently asserted here.
    expected_search = %{
      "data" => [
        %{
          "plugin" => Map.put(expected_summary, "enabled", false),
          "marketplaceName" => @market,
          "marketplacePath" => ctx.marketplace
        }
      ],
      "nextCursor" => nil
    }

    assert_sources.()
    pid = start(ctx)

    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === %{
             "marketplaces" => [],
             "marketplaceLoadErrors" => []
           }

    install(pid, ctx)

    # Informational local metadata does not authorize or execute plugin capabilities.
    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert call(pid, "plugin/read", params(ctx)) === %{"plugin" => expected_detail}
    assert search(pid, ctx, @plugin) === expected_search
    assert_sources.()
    assert_idle(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    await_process_exit(native)

    cold = start(ctx)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    refute cold_native == native
    assert call(cold, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert call(cold, "plugin/read", params(ctx)) === %{"plugin" => expected_detail}
    assert search(cold, ctx, @plugin) === expected_search
    assert_sources.()
    assert_idle(cold)
    %{connection: cold_connection} = :sys.get_state(cold)
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    await_process_exit(cold_native)
    assert_sources.()
  end

  test "owned Git plugin source preserves pinned revision metadata and cache across restart",
       ctx do
    source = Path.join(ctx.root, "owned-plugin-git")
    plugin_root = Path.join(source, "plugins/owned")
    manifest_path = Path.join(plugin_root, ".codex-plugin/plugin.json")
    skill_path = Path.join(plugin_root, "skills/inspect/SKILL.md")
    template = Path.join(ctx.root, "empty-git-template")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.mkdir_p!(Path.dirname(skill_path))
    File.mkdir_p!(template)

    # Fixture Git commands also discard inherited Git settings; no global config is changed.
    git_environment =
      System.get_env()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "GIT_"))
      |> Map.new(&{&1, nil})
      |> Map.merge(environment(ctx))
      |> Map.to_list()

    owned_git = fn args ->
      {output, status} =
        System.cmd("git", args,
          cd: source,
          env: git_environment,
          stderr_to_stdout: true
        )

      assert status == 0, "owned Git plugin fixture failed: #{output}"
      String.trim(output)
    end

    owned_git.([
      "init",
      "--initial-branch=main",
      "--object-format=sha1",
      "--template=#{template}"
    ])

    File.mkdir_p!(Path.join(source, ".git/hooks"))

    manifest_bytes =
      JSON.encode!(%{"name" => @plugin, "description" => "Owned Git plugin metadata"})

    skill_a =
      "---\nname: inspect\ndescription: Owned pinned Git inspection\n---\nOWNED_GIT_COMMIT_A\n"

    skill_b =
      "---\nname: inspect\ndescription: Owned pinned Git inspection\n---\nOWNED_GIT_MAIN_B\n"

    File.write!(manifest_path, manifest_bytes)
    File.write!(skill_path, skill_a)

    commit_owned = fn message ->
      owned_git.(["add", "."])

      owned_git.([
        "-c",
        "user.name=Owned synthetic fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "-c",
        "commit.gpgSign=false",
        "commit",
        "-m",
        message
      ])
    end

    commit_owned.("Owned plugin commit A")
    sha_a = owned_git.(["rev-parse", "HEAD"])
    File.write!(skill_path, skill_b)
    commit_owned.("Owned plugin main B")
    sha_b = owned_git.(["rev-parse", "HEAD"])
    assert Regex.match?(~r/\A[0-9a-f]{40}\z/, sha_a)
    assert Regex.match?(~r/\A[0-9a-f]{40}\z/, sha_b)
    refute sha_a == sha_b

    assert owned_git.(["show", "#{sha_a}:plugins/owned/skills/inspect/SKILL.md"]) ===
             String.trim(skill_a)

    git_config = Path.join(source, ".git/config")
    git_config_bytes = File.read!(git_config)

    marketplace = ctx.marketplace |> File.read!() |> JSON.decode!()

    entries =
      Enum.map(marketplace["plugins"], fn
        %{"name" => @plugin} = plugin ->
          Map.put(plugin, "source", %{
            "source" => "git-subdir",
            "url" => source,
            "path" => "./plugins/owned",
            "ref" => "main",
            "sha" => sha_a
          })

        plugin ->
          plugin
      end)

    marketplace_bytes = marketplace |> Map.put("plugins", entries) |> JSON.encode!()
    File.write!(ctx.marketplace, marketplace_bytes)

    expected_source = %{
      "type" => "git",
      "url" => source,
      "path" => "plugins/owned",
      "refName" => "main",
      "sha" => sha_a
    }

    expected_summary = %{
      "id" => @id,
      "remotePluginId" => nil,
      "version" => nil,
      "localVersion" => nil,
      "name" => @plugin,
      "shareContext" => nil,
      "source" => expected_source,
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

    expected = %{
      "marketplaces" => [
        %{
          "name" => @market,
          "path" => ctx.marketplace,
          "interface" => nil,
          "plugins" => [expected_summary]
        }
      ],
      "marketplaceLoadErrors" => []
    }

    cache_root = Path.join(ctx.root, "codex/plugins/cache/#{@market}/#{@plugin}/local")
    cached_manifest = Path.join(cache_root, ".codex-plugin/plugin.json")
    cached_skill = Path.join(cache_root, "skills/inspect/SKILL.md")

    assert_sources = fn ->
      assert owned_git.(["symbolic-ref", "--short", "HEAD"]) === "main"
      assert owned_git.(["rev-parse", "HEAD"]) === sha_b
      assert owned_git.(["rev-parse", "refs/heads/main"]) === sha_b
      assert owned_git.(["rev-parse", "#{sha_b}^"]) === sha_a
      assert owned_git.(["status", "--porcelain"]) === ""
      assert owned_git.(["remote"]) === ""
      assert File.read!(git_config) === git_config_bytes
      assert File.ls!(Path.join(source, ".git/hooks")) == []
      refute File.exists?(Path.join(source, ".gitmodules"))
      assert File.lstat!(manifest_path).type == :regular
      assert File.read!(manifest_path) === manifest_bytes
      assert File.lstat!(skill_path).type == :regular
      assert File.read!(skill_path) === skill_b
      assert File.read!(ctx.marketplace) === marketplace_bytes

      for path <- ["codex/auth.json", "home/.git-credentials", "home/.netrc"] do
        refute File.exists?(Path.join(ctx.root, path))
      end
    end

    assert_cache = fn ->
      assert File.lstat!(cache_root).type == :directory
      assert File.lstat!(cached_manifest).type == :regular
      assert File.read!(cached_manifest) === manifest_bytes
      assert File.lstat!(cached_skill).type == :regular
      assert File.read!(cached_skill) === skill_a
      refute File.exists?(Path.join(cache_root, ".git"))
    end

    assert_sources.()
    refute File.exists?(cache_root)
    pid = start(ctx)

    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === %{
             "marketplaces" => [],
             "marketplaceLoadErrors" => []
           }

    install(pid, ctx)

    # SHA wins over ref during materialization; refName here remains source metadata.
    assert call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert call(pid, "plugin/read", params(ctx))["plugin"]["summary"] === expected_summary
    assert_cache.()
    assert_sources.()
    assert_idle(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    await_process_exit(native)

    cold = start(ctx)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    refute cold_native == native
    assert call(cold, "plugin/installed", %{"cwds" => [ctx.workspace]}) === expected
    assert call(cold, "plugin/read", params(ctx))["plugin"]["summary"] === expected_summary
    assert_cache.()
    assert_sources.()
    assert_idle(cold)
    %{connection: cold_connection} = :sys.get_state(cold)
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    await_process_exit(cold_native)
    assert_cache.()
    assert_sources.()
  end

  test "uninstall removes installed runtime skills while retaining owned source and cold state",
       ctx do
    pid = start(ctx)
    install(pid, ctx)
    assert [%{"name" => @plugin <> ":inspect", "path" => runtime_path}] = skills(pid, ctx)
    assert File.regular?(runtime_path)
    assert call(pid, "plugin/uninstall", %{"pluginId" => @id}) == %{}
    assert installed(pid, ctx) == []
    assert skills(pid, ctx) == []
    refute call(pid, "plugin/read", params(ctx))["plugin"]["summary"]["installed"]
    assert File.regular?(Path.join(ctx.workspace, "#{@plugin}/skills/inspect/SKILL.md"))
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert installed(cold, ctx) == []
    assert skills(cold, ctx) == []
    assert_idle(cold)
  end

  test "unauthenticated reconcile is an explicit empty pass rather than a local readiness ACK",
       ctx do
    pid = start(ctx)
    install(pid, ctx)
    config = File.read!(config(ctx))

    expected = %{
      "changedPlugins" => [],
      "failedRemotePluginIds" => [],
      "failedMaterializationRemotePluginIds" => []
    }

    assert call(pid, "plugin/reconcile", %{}) == expected
    assert call(pid, "plugin/reconcile", %{"reason" => "synthetic-repeat"}) == expected
    assert File.read!(config(ctx)) == config
    assert [%{"id" => @id, "installed" => true}] = installed(pid, ctx)
    assert_idle(pid)
  end

  test "remote-only skill read validates selectors and requires backend authentication", ctx do
    pid = start(ctx)

    base = %{
      "remoteMarketplaceName" => "openai-curated-remote",
      "remotePluginId" => "plugins~Plugin_00000000000000000000000000000000",
      "skillName" => "inspect"
    }

    invalid = error(pid, "plugin/skill/read", Map.put(base, "remotePluginId", "bad id"))
    assert invalid["code"] == -32_600
    assert invalid["message"] =~ "invalid remote plugin id"
    empty = error(pid, "plugin/skill/read", Map.put(base, "skillName", ""))
    assert empty["code"] == -32_600
    assert empty["message"] == "invalid remote plugin skill name: cannot be empty"
    unauthenticated = error(pid, "plugin/skill/read", base)
    assert unauthenticated["code"] == -32_600
    assert unauthenticated["message"] =~ "chatgpt authentication required"
    assert_idle(pid)
  end

  test "local marketplace add is durable and duplicate-safe while removal preserves its source",
       ctx do
    source = Path.join(ctx.root, "market-source")
    marketplace(source, "fixture-added", ["fixture-added-plugin"])
    pid = start(ctx)

    expected = %{
      "marketplaceName" => "fixture-added",
      "installedRoot" => source,
      "alreadyAdded" => false
    }

    assert call(pid, "marketplace/add", %{"source" => source}) == expected

    assert call(pid, "marketplace/add", %{"source" => source}) ==
             Map.put(expected, "alreadyAdded", true)

    assert File.read!(config(ctx)) =~ "[marketplaces.fixture-added]"
    collision = Path.join(ctx.root, "market-collision")
    marketplace(collision, "fixture-added", [])
    failure = error(pid, "marketplace/add", %{"source" => collision})
    assert failure["code"] == -32_600
    assert failure["message"] =~ "already added from a different source"
    assert :ok = Session.close(pid)
    cold = start(ctx)
    listing = call(cold, "plugin/list", %{"marketplaceKinds" => ["local"]})
    assert Enum.any?(listing["marketplaces"], &(&1["name"] == "fixture-added"))

    assert call(cold, "marketplace/remove", %{"marketplaceName" => "fixture-added"}) == %{
             "marketplaceName" => "fixture-added",
             "installedRoot" => nil
           }

    refute File.read!(config(ctx)) =~ "[marketplaces.fixture-added]"
    assert File.regular?(Path.join(source, ".agents/plugins/marketplace.json"))
    assert_idle(cold)
  end

  test "marketplace selectors reject invalid inputs without persisting configuration", ctx do
    pid = start(ctx)
    original = File.read!(config(ctx))

    for {params, message} <- [
          {%{"source" => " "}, "marketplace source must not be empty"},
          {%{"source" => ctx.workspace, "sparsePaths" => ["plugins"]},
           "--sparse is only supported for git marketplace sources"},
          {%{"source" => ctx.workspace, "refName" => "main"},
           "--ref is only supported for git marketplace sources"}
        ] do
      assert error(pid, "marketplace/add", params) == %{"code" => -32_600, "message" => message}
    end

    missing = error(pid, "marketplace/remove", %{"marketplaceName" => "missing"})
    assert missing["code"] == -32_600
    assert missing["message"] == "marketplace `missing` is not configured or installed"
    invalid = error(pid, "marketplace/remove", %{"marketplaceName" => "../escape"})
    assert invalid["code"] == -32_600
    assert File.read!(config(ctx)) == original
    assert_idle(pid)
  end

  test "local search normalizes identity and scopes and never reports discovery as enablement",
       ctx do
    pid = start(ctx)
    install(pid, ctx)

    for query <- ["  FIXTURE_ORBIT  ", "synthetic-fixture-orbit-keyword"] do
      result = search(pid, ctx, query)

      assert [
               %{
                 "plugin" => %{"id" => @id, "installed" => true, "enabled" => false},
                 "marketplaceName" => @market,
                 "marketplacePath" => path
               }
             ] = result["data"]

      assert path == ctx.marketplace
      assert result["nextCursor"] == nil
    end

    assert search(pid, ctx, @plugin, %{"scope" => "personal"})["data"] != []

    for options <- [
          %{"scope" => "workspace"},
          %{"scope" => "global"},
          %{"cursor" => "synthetic-next"}
        ] do
      assert search(pid, ctx, @plugin, options) == %{"data" => [], "nextCursor" => nil}
    end

    assert search(pid, ctx, "  ") == %{"data" => [], "nextCursor" => nil}
    assert_idle(pid)
  end

  test "local search ranks competing name and keyword matches exactly across restart", ctx do
    expected_rows = [
      {"rank-visible", "ORBIT", []},
      {"orbit", "Independent internal exact", []},
      {"orbit-prefix", "Independent prefix", []},
      {"contains-orbit", "Independent substring", []},
      {"rank-keyword", "Independent keyword", ["orbit"]},
      {"rank-substring", "Independent keyword substring", ["xx-orbit-xx"]}
    ]

    control = {"rank-nomatch", "Independent control", []}
    fixture_rows = Enum.reverse(expected_rows ++ [control])
    fixture_names = Enum.map(fixture_rows, &elem(&1, 0))
    assert marketplace(ctx.workspace, @market, fixture_names) == ctx.marketplace

    for {name, display_name, keywords} <- fixture_rows do
      description =
        if name == "rank-nomatch",
          do: "Only-description-token",
          else: "Synthetic ranking metadata"

      File.write!(
        Path.join(ctx.workspace, "#{name}/.codex-plugin/plugin.json"),
        JSON.encode!(%{
          "name" => name,
          "description" => description,
          "keywords" => keywords,
          "interface" => %{"displayName" => display_name}
        })
      )
    end

    source_paths =
      [config(ctx), ctx.marketplace] ++
        Enum.flat_map(fixture_names ++ [@plugin, "fixture-hidden"], fn name ->
          [
            Path.join(ctx.workspace, "#{name}/.codex-plugin/plugin.json"),
            Path.join(ctx.workspace, "#{name}/skills/inspect/SKILL.md")
          ]
        end)

    source_bytes = Enum.map(source_paths, &{&1, File.read!(&1)})
    auth_path = Path.join(ctx.root, "codex/auth.json")

    assert_sources = fn ->
      for {path, bytes} <- source_bytes do
        assert File.lstat!(path).type == :regular
        assert File.read!(path) === bytes
      end

      refute File.exists?(auth_path)
    end

    expected_ids = [
      "rank-visible@#{@market}",
      "orbit@#{@market}",
      "orbit-prefix@#{@market}",
      "contains-orbit@#{@market}",
      "rank-keyword@#{@market}",
      "rank-substring@#{@market}"
    ]

    assert_ranked_search = fn pid ->
      for options <- [%{}, %{"scope" => "personal"}] do
        result = search(pid, ctx, "  ORBIT!!!  ", options)
        rows = Map.fetch!(result, "data")
        assert Enum.map(rows, &Map.fetch!(Map.fetch!(&1, "plugin"), "id")) === expected_ids
        assert Map.fetch!(result, "nextCursor") === nil

        for {row, {name, display_name, keywords}} <- Enum.zip(rows, expected_rows) do
          plugin = Map.fetch!(row, "plugin")
          assert Map.fetch!(plugin, "name") === name
          assert Map.fetch!(plugin, "keywords") === keywords
          assert Map.fetch!(Map.fetch!(plugin, "interface"), "displayName") === display_name
          assert Map.fetch!(plugin, "installed") === false
          assert Map.fetch!(plugin, "enabled") === false

          assert Map.fetch!(plugin, "source") === %{
                   "type" => "local",
                   "path" => Path.join(ctx.workspace, name)
                 }

          assert Map.fetch!(row, "marketplaceName") === @market
          assert Map.fetch!(row, "marketplacePath") === ctx.marketplace
        end

        assert search(pid, ctx, "Only-description-token", options) === %{
                 "data" => [],
                 "nextCursor" => nil
               }

        assert search(pid, ctx, "  ORBIT!!!  ", Map.put(options, "cursor", "synthetic-next")) ===
                 %{"data" => [], "nextCursor" => nil}
      end

      assert_idle(pid)
      assert_sources.()
    end

    assert_sources.()
    pid = start(ctx)
    assert_ranked_search.(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    %{connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    await_process_exit(native)
    assert_sources.()

    cold = start(ctx)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    refute cold_native == native
    assert_ranked_search.(cold)
    %{connection: cold_connection} = :sys.get_state(cold)
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    await_process_exit(cold_native)
    assert_sources.()
  end

  test "configured local Git upgrades materialize revisions and distinguish noops and invalid kinds",
       ctx do
    source = Path.join(ctx.root, "git-source")
    marketplace(source, "fixture-git", [])
    git(ctx, source, ["init", "--initial-branch=main"])
    File.write!(Path.join(source, "marker.txt"), "initial")
    commit(ctx, source)
    initial = git(ctx, source, ["rev-parse", "HEAD"])

    File.write!(
      config(ctx),
      "\n[marketplaces.fixture-git]\nsource_type = \"git\"\nsource = #{JSON.encode!(source)}\n",
      [:append]
    )

    # Match upstream's explicit-upgrade profile: no automatic plugin startup work.
    File.write!(
      config(ctx),
      String.replace(File.read!(config(ctx)), "plugins = true", "plugins = false")
    )

    pid = start(ctx)
    root = Path.join(ctx.root, "codex/.tmp/marketplaces/fixture-git")

    expected = %{
      "selectedMarketplaces" => ["fixture-git"],
      "upgradedRoots" => [root],
      "errors" => []
    }

    assert call(pid, "marketplace/upgrade", %{"marketplaceName" => "fixture-git"}) == expected
    assert git(ctx, root, ["rev-parse", "HEAD"]) == initial
    assert File.read!(Path.join(root, "marker.txt")) == "initial"
    assert call(pid, "marketplace/upgrade", %{}) == Map.put(expected, "upgradedRoots", [])
    File.write!(Path.join(source, "marker.txt"), "updated")
    commit(ctx, source)
    updated = git(ctx, source, ["rev-parse", "HEAD"])
    assert updated != initial
    assert call(pid, "marketplace/upgrade", %{}) == expected
    assert git(ctx, root, ["rev-parse", "HEAD"]) == updated
    assert File.read!(Path.join(root, "marker.txt")) == "updated"
    assert call(pid, "marketplace/upgrade", %{}) == Map.put(expected, "upgradedRoots", [])
    call(pid, "marketplace/add", %{"source" => ctx.workspace})

    for name <- ["missing", @market] do
      assert error(pid, "marketplace/upgrade", %{"marketplaceName" => name}) == %{
               "code" => -32_600,
               "message" => "marketplace `#{name}` is not configured as a Git marketplace"
             }
    end

    assert call(pid, "marketplace/remove", %{"marketplaceName" => "fixture-git"}) == %{
             "marketplaceName" => "fixture-git",
             "installedRoot" => root
           }

    refute File.exists?(root)
    assert File.regular?(Path.join(source, "marker.txt"))
    assert_idle(pid)
  end

  defp start(ctx) do
    proof_path = Path.join(ctx.root, "proof-#{System.unique_integer([:positive])}.json")

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--root", ctx.root, "--codex", ctx.binary, "--proof", proof_path],
             cwd: ctx.workspace,
             inherit_env: [],
             env: environment(ctx)
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      StdioSessionFixture.close(pid, connection)
      await_fixture_processes(proof_path)
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_plugin_lifecycle", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    proof = JSON.decode!(File.read!(proof_path))
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"]
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    pid
  end

  defp await_fixture_processes(proof_path) do
    if File.exists?(proof_path) do
      proof = JSON.decode!(File.read!(proof_path))

      for key <- ["native_pid", "namespace_owner_pid"], do: await_process_exit(proof[key])
    end
  end

  defp await_process_exit(os_pid), do: await(fn -> not File.exists?("/proc/#{os_pid}") end)

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

  defp config(ctx), do: Path.join(ctx.root, "codex/config.toml")
  defp params(ctx), do: %{"marketplacePath" => ctx.marketplace, "pluginName" => @plugin}

  defp install(pid, ctx),
    do: assert(call(pid, "plugin/install", params(ctx))["appsNeedingAuth"] == [])

  defp summaries(result), do: Enum.flat_map(result["marketplaces"], & &1["plugins"])

  defp installed(pid, ctx),
    do: summaries(call(pid, "plugin/installed", %{"cwds" => [ctx.workspace]}))

  defp search(pid, ctx, query, extra \\ %{}),
    do:
      call(
        pid,
        "plugin/search",
        Map.merge(%{"searchTerm" => query, "cwds" => [ctx.workspace]}, extra)
      )

  defp skills(pid, ctx),
    do:
      call(pid, "skills/list", %{"cwds" => [ctx.workspace], "forceReload" => true})["data"]
      |> Enum.flat_map(& &1["skills"])
      |> Enum.filter(&String.starts_with?(&1["name"], @plugin <> ":"))

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, %Error{wire: wire}} -> flunk("Native #{method}: #{inspect(wire)}")
    end
  end

  defp error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end

  defp marketplace(root, name, plugins) do
    path = Path.join(root, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(path))

    entries =
      for plugin <- plugins,
          do: %{"name" => plugin, "source" => %{"source" => "local", "path" => "./#{plugin}"}}

    File.write!(path, JSON.encode!(%{"name" => name, "plugins" => entries}))

    for plugin <- plugins do
      manifest = Path.join(root, "#{plugin}/.codex-plugin/plugin.json")
      File.mkdir_p!(Path.dirname(manifest))

      File.write!(
        manifest,
        JSON.encode!(%{
          "name" => plugin,
          "description" => "Synthetic lifecycle plugin",
          "keywords" => ["synthetic-#{plugin}-keyword"]
        })
      )

      skill = Path.join(root, "#{plugin}/skills/inspect/SKILL.md")
      File.mkdir_p!(Path.dirname(skill))

      File.write!(
        skill,
        "---\nname: inspect\ndescription: Synthetic lifecycle inspection\n---\nSYNTHETIC_PLUGIN_LIFECYCLE\n"
      )
    end

    path
  end

  defp commit(ctx, cwd) do
    git(ctx, cwd, ["add", "."])

    git(ctx, cwd, [
      "-c",
      "user.name=Synthetic fixture",
      "-c",
      "user.email=fixture@example.invalid",
      "commit",
      "-m",
      "Synthetic local fixture"
    ])
  end

  defp git(ctx, cwd, args) do
    {output, status} =
      System.cmd("git", args, cd: cwd, env: Map.to_list(environment(ctx)), stderr_to_stdout: true)

    assert status == 0, "owned Git fixture failed: #{output}"
    String.trim(output)
  end

  defp assert_idle(pid), do: assert(call(pid, "thread/loaded/list", %{})["data"] == [])
  defp await(predicate, remaining \\ 500)

  defp await(predicate, remaining) when remaining > 0 do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await(predicate, remaining - 1)
        )
  end

  defp await(_predicate, 0), do: flunk("owned fixture process was not reaped")
end
