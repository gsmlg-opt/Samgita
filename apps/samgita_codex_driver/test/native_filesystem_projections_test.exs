defmodule SamgitaCodexDriver.NativeFilesystemProjectionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n" <>
        "\n[analytics]\nenabled = false\n"
    )

    Map.put(ctx, :session, TurnFixture.start(ctx))
  end

  test "selected metadata paths return exact independently prescribed modification milliseconds",
       ctx do
    first = Path.join(ctx.fixture.workspace, "first-é.bin")
    second = Path.join(ctx.fixture.workspace, "second-🙂.bin")
    File.write!(first, <<0, 255, 1>>)
    File.write!(second, <<254, 0, 2>>)

    # Both targets are ordinary files, so timestamps distinguish path selection.
    set_mtime(first, 1_600_000_123)
    set_mtime(second, 1_600_000_456)

    for {path, expected_ms} <- [
          {first, 1_600_000_123_000},
          {second, 1_600_000_456_000},
          {first, 1_600_000_123_000}
        ] do
      assert_metadata(ctx.session, path, expected_ms)
    end

    # A later read must observe the owned file change and leave its neighbor distinct.
    set_mtime(first, 1_600_000_789)
    assert_metadata(ctx.session, first, 1_600_000_789_000)
    assert_metadata(ctx.session, second, 1_600_000_456_000)
    assert File.read!(first) == <<0, 255, 1>>
    assert File.read!(second) == <<254, 0, 2>>
    assert_idle_and_close(ctx)
  end

  test "directory selection returns exact ordinary-file entries before and after an owned rename",
       ctx do
    left = Path.join(ctx.fixture.workspace, "left-é")
    right = Path.join(ctx.fixture.workspace, "right-🙂")
    nested = Path.join(left, "nested")
    File.mkdir_p!(nested)
    File.mkdir!(right)
    left_file = Path.join(left, "left-only-é.bin")
    right_file = Path.join(right, "right-only-🙂.bin")
    File.write!(left_file, <<0, 255>>)
    File.write!(right_file, <<254, 0>>)
    File.write!(Path.join(nested, "grandchild.bin"), "not a direct child")
    assert File.lstat!(left_file).type == :regular
    assert File.lstat!(right_file).type == :regular

    assert_entries(ctx.session, left, [
      %{"fileName" => "left-only-é.bin", "isDirectory" => false, "isFile" => true},
      %{"fileName" => "nested", "isDirectory" => true, "isFile" => false}
    ])

    assert_entries(ctx.session, right, [
      %{"fileName" => "right-only-🙂.bin", "isDirectory" => false, "isFile" => true}
    ])

    moved = Path.join(right, "moved-é.bin")
    File.rename!(left_file, moved)
    refute File.exists?(left_file)
    assert File.read!(moved) == <<0, 255>>

    assert_entries(ctx.session, left, [
      %{"fileName" => "nested", "isDirectory" => true, "isFile" => false}
    ])

    assert_entries(ctx.session, right, [
      %{"fileName" => "moved-é.bin", "isDirectory" => false, "isFile" => true},
      %{"fileName" => "right-only-🙂.bin", "isDirectory" => false, "isFile" => true}
    ])

    assert_idle_and_close(ctx)
  end

  defp set_mtime(path, seconds) do
    File.touch!(path, seconds)
    assert File.stat!(path, time: :posix).mtime === seconds
  end

  defp assert_metadata(pid, path, expected_ms) do
    metadata = rpc(pid, "fs/getMetadata", %{"path" => path})
    assert Map.fetch!(metadata, "modifiedAtMs") === expected_ms
    assert Map.fetch!(metadata, "isFile") === true
    assert Map.fetch!(metadata, "isDirectory") === false
    assert Map.fetch!(metadata, "isSymlink") === false
  end

  defp assert_entries(pid, path, expected) do
    response = rpc(pid, "fs/readDirectory", %{"path" => path})
    assert Enum.sort_by(Map.fetch!(response, "entries"), & &1["fileName"]) === expected
  end

  defp rpc(pid, method, params) do
    id = "fs-projection-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    result
  end

  defp assert_idle_and_close(ctx) do
    assert ModelFixture.requests(ctx.fixture) == []

    assert TurnFixture.call(ctx.session, "thread/loaded/list", %{}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} =
             Session.status(ctx.session)

    assert Session.uncertain_operations(ctx.session) == []
    assert {:ok, events} = Session.drain(ctx.session)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""
             String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)

    assert :ok = Session.close(ctx.session)
  end
end
