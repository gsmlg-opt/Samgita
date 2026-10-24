defmodule SamgitaCodexDriver.NativeSkillMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @name "owned-rich-metadata"
  @frontmatter """
  ---
  name: owned-rich-metadata
  description: "  Owned   skill metadata.  "
  metadata:
    short-description: "  Legacy   summary.  "
  ---

  Owned catalog input only. No invocation is requested.
  """

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    directory = Path.join(ctx.fixture.codex_home, "skills/#{@name}")
    File.mkdir_p!(Path.join(directory, "agents"))
    File.mkdir_p!(Path.join(directory, "assets"))
    source = Path.join(directory, "SKILL.md")
    File.write!(source, @frontmatter)
    File.write!(Path.join(directory, "assets/small.svg"), "<svg>owned-small</svg>\n")
    File.write!(Path.join(directory, "assets/large.svg"), "<svg>owned-large</svg>\n")
    marker = Path.join(ctx.root, "unexpected-dependency-execution")
    command = Path.join(ctx.fixture.bin, "owned-skill-dependency")
    File.write!(command, "#!/bin/sh\nprintf unexpected > '#{marker}'\n")
    File.chmod!(command, 0o755)
    config_bytes = File.read!(config)

    on_exit(fn ->
      assert File.read!(config) == config_bytes
      assert File.read!(source) == @frontmatter
      refute File.exists?(marker)
    end)

    Map.merge(ctx, %{
      directory: directory,
      source: source,
      metadata: Path.join(directory, "agents/openai.yaml"),
      command: command,
      marker: marker,
      dependency_url: ctx.fixture.url <> "/owned-metadata-only"
    })
  end

  test "native list returns exact normalized rich metadata while leaving declarations inert",
       ctx do
    yaml = rich_yaml(ctx)
    File.write!(ctx.metadata, yaml)
    pid = start(ctx)
    assert listed(ctx, pid) == rich_skill(ctx)
    assert File.read!(ctx.metadata) == yaml
    assert File.read!(Path.join(ctx.directory, "assets/small.svg")) == "<svg>owned-small</svg>\n"
    assert File.read!(Path.join(ctx.directory, "assets/large.svg")) == "<svg>owned-large</svg>\n"
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "force reload and cold stable negotiation expose new disk metadata with legacy summary intact",
       ctx do
    File.write!(ctx.metadata, rich_yaml(ctx))
    pid = start(ctx)
    assert listed(ctx, pid) == rich_skill(ctx)

    replacement = """
    interface:
      display_name: "  Reloaded   display  "
      short_description: "  Reloaded   interface summary  "
      default_prompt: "  Describe   metadata only  "
    dependencies:
      tools:
        - type: "  owned_catalog  "
          value: "  reloaded-entry  "
    """

    File.write!(ctx.metadata, replacement)

    expected =
      Map.merge(base_skill(ctx), %{
        "interface" => %{
          "displayName" => "Reloaded display",
          "shortDescription" => "Reloaded interface summary",
          "defaultPrompt" => "Describe metadata only",
          "brandColor" => nil,
          "iconSmall" => nil,
          "iconLarge" => nil,
          "iconSmallUrl" => nil,
          "iconLargeUrl" => nil
        },
        "dependencies" => %{
          "tools" => [%{"type" => "owned_catalog", "value" => "reloaded-entry"}]
        }
      })

    assert listed(ctx, pid) == expected
    assert File.read!(ctx.metadata) == replacement
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
    cold = start(ctx, false)
    assert listed(ctx, cold) == expected
    assert File.read!(ctx.metadata) == replacement
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
  end

  test "invalid optional entries are filtered and metadata removal preserves the valid frontmatter",
       ctx do
    yaml = """
    interface:
      display_name: "  Still   visible  "
      icon_small: "../outside.svg"
      icon_large: "large.svg"
      brand_color: "blue"
    dependencies:
      tools:
        - type: "mcp"
          value: "   "
        - type: "   "
          value: "ignored"
        - type: "  owned_catalog  "
          value: "  kept-entry  "
          description: "  Kept   description  "
          command: "   "
          url: "   "
    """

    File.write!(ctx.metadata, yaml)
    pid = start(ctx)

    assert listed(ctx, pid) ==
             Map.merge(base_skill(ctx), %{
               "interface" => %{
                 "displayName" => "Still visible",
                 "shortDescription" => nil,
                 "defaultPrompt" => nil,
                 "brandColor" => nil,
                 "iconSmall" => nil,
                 "iconLarge" => nil,
                 "iconSmallUrl" => nil,
                 "iconLargeUrl" => nil
               },
               "dependencies" => %{
                 "tools" => [
                   %{
                     "type" => "owned_catalog",
                     "value" => "kept-entry",
                     "description" => "Kept description"
                   }
                 ]
               }
             })

    assert File.read!(ctx.metadata) == yaml
    File.write!(ctx.metadata, "interface: [not-an-interface]\n")
    assert listed(ctx, pid) == base_skill(ctx)
    File.rm!(ctx.metadata)
    assert listed(ctx, pid) == base_skill(ctx)
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
  end

  defp rich_yaml(ctx) do
    """
    interface:
      display_name: "  Owned   display  "
      short_description: "  Interface   summary.  "
      icon_small: "./assets/small.svg"
      icon_large: "assets/large.svg"
      brand_color: " #123ABC "
      default_prompt: "  Inspect   metadata only.  "
    dependencies:
      tools:
        - type: "  mcp  "
          value: "  owned-stdio  "
          description: "  Owned   stdio declaration  "
          transport: "  stdio  "
          command: "  #{ctx.command}   --metadata-only  "
        - type: "mcp"
          value: "owned-http"
          description: "Owned HTTP declaration"
          transport: "streamable_http"
          url: "  #{ctx.dependency_url}  "
        - type: "owned_catalog"
          value: "owned-minimal"
    """
  end

  defp rich_skill(ctx) do
    Map.merge(base_skill(ctx), %{
      "interface" => %{
        "displayName" => "Owned display",
        "shortDescription" => "Interface summary.",
        "iconSmall" => Path.join(ctx.directory, "assets/small.svg"),
        "iconLarge" => Path.join(ctx.directory, "assets/large.svg"),
        "iconSmallUrl" => nil,
        "iconLargeUrl" => nil,
        "brandColor" => "#123ABC",
        "defaultPrompt" => "Inspect metadata only."
      },
      "dependencies" => %{
        "tools" => [
          %{
            "type" => "mcp",
            "value" => "owned-stdio",
            "description" => "Owned stdio declaration",
            "transport" => "stdio",
            "command" => ctx.command <> " --metadata-only"
          },
          %{
            "type" => "mcp",
            "value" => "owned-http",
            "description" => "Owned HTTP declaration",
            "transport" => "streamable_http",
            "url" => ctx.dependency_url
          },
          %{"type" => "owned_catalog", "value" => "owned-minimal"}
        ]
      }
    })
  end

  defp base_skill(ctx) do
    %{
      "name" => @name,
      "description" => "Owned skill metadata.",
      "shortDescription" => "Legacy summary.",
      "path" => ctx.source,
      "scope" => "user",
      "enabled" => true,
      "pluginId" => nil
    }
  end

  defp listed(ctx, pid) do
    assert [%{"cwd" => cwd, "errors" => [], "skills" => skills}] =
             call(pid, "skills/list", %{"cwds" => [ctx.fixture.workspace], "forceReload" => true})[
               "data"
             ]

    assert cwd == ctx.fixture.workspace
    assert [skill] = Enum.filter(skills, &(&1["name"] == @name))
    skill
  end

  defp start(ctx, experimental \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
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

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_skill_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => experimental}
             )

    pid
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    refute File.exists?(ctx.marker)
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).pending == 0
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
  end
end
