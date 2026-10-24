defmodule SamgitaCodexDriver.NativeConfigOverrideMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @feature_args [
    "-c",
    "features.apps=false",
    "-c",
    "features.plugins=false",
    "-c",
    "features.recommended_plugins=false",
    "-c",
    "features.shell_snapshot=false"
  ]
  @desktop_args ["-c", "desktop.appearanceTheme=\"dark\"", "-c", "desktop.preventSleep=true"]
  # Independent source-derived oracle: version_for_toml sorts every JSON object
  # and hashes compact bytes. Include every CLI override owned by this fixture.
  @session_json ~s({"desktop":{"appearanceTheme":"dark","preventSleep":true},"features":{"apps":false,"plugins":false,"recommended_plugins":false,"shell_snapshot":false}})

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

    Map.put(ctx, :config_path, config)
  end

  test "a displaced user write reports exact session metadata while persisting the requested value",
       ctx do
    pid = start(ctx)
    response = call(pid, "config/value/write", edit("desktop.appearanceTheme", "light"))
    assert_overridden(ctx, pid, response, "dark")
    assert get_in(user_layer(ctx, pid), ["config", "desktop", "appearanceTheme"]) == "light"
    assert File.read!(ctx.config_path) =~ ~s(appearanceTheme = "light")

    assert get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"]) ==
             "dark"

    persisted = File.read!(ctx.config_path)
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)

    # Removing only the desktop CLI overrides exposes the already persisted user
    # value; the write response never claimed that the file edit was rejected.
    restarted = start(ctx, false)

    assert get_in(call(restarted, "config/read", %{}), ["config", "desktop", "appearanceTheme"]) ==
             "light"

    assert File.read!(ctx.config_path) == persisted
    assert user_layer(ctx, restarted)["version"] == response["version"]
    assert_idle(ctx, restarted)
    assert :ok = Session.close(restarted)
  end

  test "equal effective values omit displacement but deleting the user value reports the override",
       ctx do
    pid = start(ctx)
    same = call(pid, "config/value/write", edit("desktop.appearanceTheme", "dark"))
    assert Map.fetch!(same, "status") == "ok"
    assert Map.fetch!(same, "overriddenMetadata") == nil
    assert get_in(user_layer(ctx, pid), ["config", "desktop", "appearanceTheme"]) == "dark"
    assert File.read!(ctx.config_path) =~ ~s(appearanceTheme = "dark")

    deleted = call(pid, "config/value/write", edit("desktop.appearanceTheme", nil))
    assert_overridden(ctx, pid, deleted, "dark")
    assert deleted["version"] != same["version"]

    refute Map.has_key?(
             get_in(user_layer(ctx, pid), ["config", "desktop"]) || %{},
             "appearanceTheme"
           )

    refute File.read!(ctx.config_path) =~ "appearanceTheme"

    assert get_in(call(pid, "config/read", %{}), ["config", "desktop", "appearanceTheme"]) ==
             "dark"

    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "batch metadata selects the first displaced edit in request order and preserves other writes",
       ctx do
    pid = start(ctx)
    unrelated = edit("desktop.ownedFixtureMarker", "persisted")
    sleep = edit("desktop.preventSleep", false)
    theme = edit("desktop.appearanceTheme", "light")

    first = call(pid, "config/batchWrite", %{"edits" => [unrelated, sleep, theme]})
    assert_overridden(ctx, pid, first, true)
    second = call(pid, "config/batchWrite", %{"edits" => [unrelated, theme, sleep]})
    assert_overridden(ctx, pid, second, "dark")

    assert get_in(user_layer(ctx, pid), ["config", "desktop"]) == %{
             "ownedFixtureMarker" => "persisted",
             "appearanceTheme" => "light",
             "preventSleep" => false
           }

    assert get_in(call(pid, "config/read", %{}), ["config", "desktop"]) == %{
             "ownedFixtureMarker" => "persisted",
             "appearanceTheme" => "dark",
             "preventSleep" => true
           }

    persisted = File.read!(ctx.config_path)
    assert persisted =~ ~s(ownedFixtureMarker = "persisted")
    assert persisted =~ ~s(appearanceTheme = "light")
    assert persisted =~ "preventSleep = false"
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
  end

  defp start(ctx, desktop_override \\ true) do
    args = @feature_args ++ if(desktop_override, do: @desktop_args, else: [])

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: args ++ ["app-server", "--listen", "stdio://"],
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_config_override_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp assert_overridden(ctx, pid, response, effective_value) do
    version = "sha256:" <> Base.encode16(:crypto.hash(:sha256, @session_json), case: :lower)

    assert Map.fetch!(response, "status") == "okOverridden"

    assert Map.fetch!(response, "overriddenMetadata") == %{
             "message" => "Overridden by session flags",
             "overridingLayer" => %{"name" => %{"type" => "sessionFlags"}, "version" => version},
             "effectiveValue" => effective_value
           }

    assert response["filePath"] == ctx.config_path
    assert response["version"] == user_layer(ctx, pid)["version"]
  end

  defp user_layer(ctx, pid) do
    source = %{"type" => "user", "file" => ctx.config_path, "profile" => nil}

    call(pid, "config/read", %{"includeLayers" => true})["layers"]
    |> Enum.find(&(&1["name"] == source))
    |> tap(&assert(is_map(&1)))
  end

  defp edit(key, value), do: %{"keyPath" => key, "value" => value, "mergeStrategy" => "replace"}

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""
             String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end
end
