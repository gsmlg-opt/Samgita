defmodule SamgitaCodexDriver.NativeLaunchFixtureTest do
  use ExUnit.Case, async: true
  alias SamgitaCodexDriver.NativeLaunchFixture

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "native-launch-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, "config.toml")}
  end

  test "local startup disables the owned fragment and restores exact bytes after initialize",
       ctx do
    original = "model = 'mock'\n\n[features]\nplugins = true\nremote_plugin = false\n"
    File.write!(ctx.path, original)

    assert :initialized ==
             NativeLaunchFixture.local_plugins_after_initialize(ctx.path, fn ->
               assert File.read!(ctx.path) ==
                        "model = 'mock'\n\n[features]\nplugins = false\nremote_plugin = false\nrecommended_plugins = false\n"

               :initialized
             end)

    assert File.read!(ctx.path) == original
    assert File.ls!(ctx.root) == ["config.toml"]
  end

  test "failed initialization restores the local plugin config", ctx do
    original = "\n[features]\nplugins = true\nremote_plugin = false\n"
    File.write!(ctx.path, original)

    assert_raise RuntimeError, "synthetic initialization failure", fn ->
      NativeLaunchFixture.local_plugins_after_initialize(ctx.path, fn ->
        raise "synthetic initialization failure"
      end)
    end

    assert File.read!(ctx.path) == original
    assert File.ls!(ctx.root) == ["config.toml"]
  end

  test "unrecognized or duplicate plugin fragments fail before invoking native", ctx do
    for original <- [
          "\n[features]\nplugins = false\n",
          String.duplicate("\n[features]\nplugins = true\nremote_plugin = false\n", 2)
        ] do
      File.write!(ctx.path, original)

      assert_raise ExUnit.AssertionError, fn ->
        NativeLaunchFixture.local_plugins_after_initialize(ctx.path, fn ->
          flunk("Native must not be started")
        end)
      end

      assert File.read!(ctx.path) == original
      assert File.ls!(ctx.root) == ["config.toml"]
    end
  end
end
