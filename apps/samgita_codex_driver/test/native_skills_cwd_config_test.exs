defmodule SamgitaCodexDriver.NativeSkillsCwdConfigTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @name "owned-cwd-config-skill"
  @skill "---\nname: owned-cwd-config-skill\ndescription: Owned cwd configuration control.\n---\n\nInert metadata only.\n"
  @git_head "ref: refs/heads/owned-fixture\n"
  @valid "[agents]\nmax_concurrent_threads_per_session = 1\n"
  @invalid "[agents]\nmax_concurrent_threads_per_session = 0\n"
  @message "failed to reload config: agents.max_concurrent_threads_per_session must be at least 1"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})

    roots =
      for index <- 1..6 do
        root = Path.join(ctx.root, "owned-project-#{index}")
        File.mkdir_p!(Path.join(root, ".git"))
        File.write!(Path.join(root, ".git/HEAD"), @git_head)
        File.mkdir_p!(Path.join(root, ".codex"))
        File.write!(Path.join(root, ".codex/config.toml"), @valid)
        root
      end

    trust =
      Enum.map_join(roots, fn root ->
        "\n[projects.#{JSON.encode!(root)}]\ntrust_level = \"trusted\"\n"
      end)

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n" <>
        "\n[skills.bundled]\nenabled = false\n" <> trust
    )

    source = Path.join(ctx.fixture.codex_home, "skills/#{@name}/SKILL.md")
    File.mkdir_p!(Path.dirname(source))
    File.write!(source, @skill)

    Map.merge(ctx, %{
      roots: roots,
      source: source,
      config: config,
      config_bytes: File.read!(config)
    })
  end

  test "a cwd configuration failure isolates repeated entries across cache reuse and restart",
       ctx do
    [bad, second, third, fourth, fifth, sixth] = ctx.roots
    requested = [sixth, bad, third, fifth, bad, second, fourth, sixth]
    broken = Path.join(bad, ".codex/config.toml")
    pid = start(ctx)

    # Warm the catalogue while all six independently trusted project configs are valid.
    assert_entries(ctx, pid, requested, nil, true)
    File.write!(broken, @invalid)

    # The error must precede skill-cache reuse; it is not a malformed SKILL.md error.
    assert_entries(ctx, pid, requested, bad, false)
    assert_entries(ctx, pid, requested, bad, true)
    assert_files(ctx, bad, @invalid)
    assert_idle(ctx, pid)
    process = call(pid, "server/diagnostics", %{})["process"]["id"]
    close_owned(pid)

    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process
    assert_entries(ctx, cold, requested, bad, false)
    assert_files(ctx, bad, @invalid)

    # Fix only the owned configuration. A plain list reloads configuration itself.
    File.write!(broken, @valid)
    assert_entries(ctx, cold, requested, nil, false)
    assert_entries(ctx, cold, requested, nil, true)
    assert_files(ctx, nil, @valid)
    assert_idle(ctx, cold)
    close_owned(cold)
  end

  defp assert_entries(ctx, pid, requested, bad, force) do
    assert %{"data" => entries} =
             call(pid, "skills/list", %{"cwds" => requested, "forceReload" => force})

    assert Enum.map(entries, & &1["cwd"]) == requested

    for entry <- entries do
      if entry["cwd"] == bad do
        assert entry == %{
                 "cwd" => bad,
                 "skills" => [],
                 "errors" => [%{"path" => bad, "message" => @message}]
               }
      else
        assert entry["errors"] == []
        assert [skill] = Enum.filter(entry["skills"], &(&1["name"] == @name))

        assert skill == %{
                 "name" => @name,
                 "description" => "Owned cwd configuration control.",
                 "path" => ctx.source,
                 "scope" => "user",
                 "enabled" => true,
                 "pluginId" => nil
               }
      end
    end
  end

  defp assert_files(ctx, bad, bad_bytes) do
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.read!(ctx.source) == @skill

    for root <- ctx.roots do
      expected = if root == bad, do: bad_bytes, else: @valid
      assert File.read!(Path.join(root, ".codex/config.toml")) == expected
      assert File.read!(Path.join(root, ".git/HEAD")) == @git_head
    end
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => f.bin <> ":/usr/bin:/bin",
               "CODEX_EXEC_SERVER_URL" => "none",
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
               %{"name" => "samgita_skills_cwd_config", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
  end
end
