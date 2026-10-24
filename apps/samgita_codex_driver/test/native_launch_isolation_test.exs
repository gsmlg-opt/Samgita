defmodule SamgitaCodexDriver.NativeLaunchIsolationTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @source_archive_sha "e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567"
  @source_archive Path.expand("../../../tmp/codex/0.163.0/source.tar.gz", __DIR__)

  setup context do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    source_archive = System.get_env("CODEX_SOURCE_ARCHIVE", @source_archive)

    assert File.regular?(source_archive),
           "BLOCKED_ENV: verified rust-v0.163.0 source archive required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(source_archive)), case: :lower) ==
             @source_archive_sha

    TurnFixture.setup(context)
  end

  test "ordinary startup and cold restart override plugin features without altering TOML", ctx do
    config_path = Path.join(ctx.fixture.codex_home, "config.toml")

    # Positive precedence control: the same config enables the flags, so this
    # verifies native effective values rather than merely inspecting argv or
    # observing an idle model fixture. Also covers an existing feature appender.
    File.write!(
      config_path,
      "\n[features]\nplugins = true\nrecommended_plugins = true\nauth_elicitation = false\n",
      [:append]
    )

    original = File.read!(config_path)

    for _ <- 1..2 do
      pid = start(ctx)
      features = call(pid, "experimentalFeature/list", %{})["data"]
      assert Enum.find(features, &(&1["name"] == "plugins"))["enabled"] == false
      assert Enum.find(features, &(&1["name"] == "recommended_plugins"))["enabled"] == false
      assert Enum.find(features, &(&1["name"] == "auth_elicitation"))["enabled"] == false
      effective = call(pid, "config/read", %{})["config"]["features"]
      assert effective["plugins"] == false
      assert effective["recommended_plugins"] == false
      assert effective["auth_elicitation"] == false
      assert File.read!(config_path) == original

      for relative <- [".tmp/plugins", ".tmp/plugins.sha", ".tmp/plugins.sync.lock"] do
        refute File.exists?(Path.join(ctx.fixture.codex_home, relative))
      end

      assert Path.wildcard(Path.join(ctx.fixture.codex_home, ".tmp/plugins-clone-*")) == []
      assert ModelFixture.requests(ctx.fixture) == []
      assert :ok = Session.close(pid)

      for relative <- [".tmp/plugins", ".tmp/plugins.sha", ".tmp/plugins.sync.lock"] do
        refute File.exists?(Path.join(ctx.fixture.codex_home, relative))
      end

      assert Path.wildcard(Path.join(ctx.fixture.codex_home, ".tmp/plugins-clone-*")) == []
    end
  end
end
