defmodule SamgitaCodexDriver.NativeThreadInputOverrideTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned input override instructions. No execution requested.\n"
  @readonly %{"type" => "readOnly", "networkAccess" => false}

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

    config_bytes = File.read!(config)
    assert config_bytes =~ "approval_policy = \"on-request\""
    on_exit(fn -> assert File.read!(config) == config_bytes end)

    original_extra = Path.join(ctx.root, "owned-original-extra")
    replacement_extra = Path.join(ctx.root, "owned-replacement-extra")
    File.mkdir!(original_extra)
    File.mkdir!(replacement_extra)
    source = Path.join(ctx.fixture.workspace, "AGENTS.md")
    File.write!(source, @instructions)

    ctx
    |> Map.put(:original_extra, original_extra)
    |> Map.put(:replacement_extra, replacement_extra)
    |> Map.put(:source, source)
  end

  test "thread start selects an explicit policy different from configured and sibling defaults",
       ctx do
    pid = TurnFixture.start(ctx)
    baseline = call(pid, "thread/start", start_params(ctx))
    selected = call(pid, "thread/start", Map.put(start_params(ctx), "approvalPolicy", "never"))
    sibling = call(pid, "thread/start", start_params(ctx))

    assert Map.fetch!(baseline, "approvalPolicy") === "on-request"
    assert Map.fetch!(selected, "approvalPolicy") === "never"
    assert Map.fetch!(sibling, "approvalPolicy") === "on-request"

    ids =
      for response <- [baseline, selected, sibling] do
        assert Map.fetch!(response, "model") === "mock-model"
        assert Map.fetch!(response, "modelProvider") === "fixture"
        assert Map.fetch!(response, "cwd") === ctx.fixture.workspace
        assert Map.fetch!(response, "sandbox") === @readonly
        assert Map.fetch!(response, "approvalsReviewer") === "user"
        assert Map.fetch!(response, "instructionSources") === [ctx.source]
        thread = Map.fetch!(response, "thread")
        assert Map.fetch!(thread, "ephemeral") === false
        assert Map.fetch!(thread, "historyMode") === "legacy"
        assert Map.fetch!(thread, "turns") === []
        id = Map.fetch!(thread, "id")

        assert call(pid, "thread/name/set", %{
                 "threadId" => id,
                 "name" => "Owned policy selection " <> id
               }) == %{}

        assert File.regular?(Map.fetch!(thread, "path"))
        assert Map.fetch!(read(pid, id), "turns") === []
        id
      end

    assert MapSet.size(MapSet.new(ids)) == 3
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)

    cold = TurnFixture.start(ctx)
    assert_unloaded(cold)

    for id <- ids do
      assert Map.fetch!(read(cold, id), "id") === id
      assert Map.fetch!(read(cold, id), "turns") === []
    end

    assert_unloaded(cold)
    assert File.read!(ctx.source) === @instructions
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
  end

  for selection <- [:replacement, :empty] do
    @selection selection
    test "cold resume #{@selection} roots replace persisted roots and survive another native restart",
         ctx do
      original = [ctx.fixture.workspace, ctx.original_extra]

      expected =
        case @selection do
          :replacement -> [ctx.fixture.workspace, ctx.replacement_extra]
          :empty -> []
        end

      refute expected == original
      first = TurnFixture.start(ctx)

      started =
        call(
          first,
          "thread/start",
          Map.put(start_params(ctx), "runtimeWorkspaceRoots", original)
        )

      assert Map.fetch!(started, "runtimeWorkspaceRoots") === original
      assert Map.fetch!(started, "instructionSources") === [ctx.source]
      id = Map.fetch!(Map.fetch!(started, "thread"), "id")
      name = "Owned #{@selection} root override"
      assert call(first, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
      saved = read(first, id)
      path = Map.fetch!(saved, "path")
      assert_saved(saved, id, name, path)
      assert_idle(ctx, first)
      assert :ok = Session.close(first)

      original_bytes = File.read!(path)
      original_meta = creation_meta(path, id)
      assert Map.fetch!(original_meta, "runtime_workspace_roots") === original
      assert Map.fetch!(original_meta, "cwd") === ctx.fixture.workspace
      original_projection = durable_projection(saved)

      cold = TurnFixture.start(ctx)
      assert_unloaded(cold)
      assert durable_projection(read(cold, id)) === original_projection
      assert_unloaded(cold)
      assert File.read!(path) === original_bytes

      response =
        call(cold, "thread/resume", %{
          "threadId" => id,
          "runtimeWorkspaceRoots" => expected,
          "permissions" => ":read-only",
          "excludeTurns" => true
        })

      assert Map.fetch!(response, "runtimeWorkspaceRoots") === expected
      refute Map.fetch!(response, "runtimeWorkspaceRoots") == original
      assert Map.fetch!(response, "cwd") === ctx.fixture.workspace
      assert Map.fetch!(response, "instructionSources") === [ctx.source]
      assert Map.fetch!(response, "sandbox") === @readonly

      assert Map.fetch!(response, "activePermissionProfile") === %{
               "id" => ":read-only",
               "extends" => nil
             }

      assert_saved(read(cold, id), id, name, path)
      assert durable_projection(read(cold, id)) === original_projection
      assert File.read!(ctx.source) === @instructions
      assert_idle(ctx, cold)
      assert :ok = Session.close(cold)

      # Resume checkpoints effective settings without creating a model turn.
      # The startup evidence remains A, while the latest owned snapshot becomes B.
      updated_bytes = File.read!(path)
      assert String.starts_with?(updated_bytes, original_bytes)
      assert creation_meta(path, id) === original_meta
      assert latest_root_snapshot(path, id) === expected

      verify = TurnFixture.start(ctx)
      assert_unloaded(verify)
      assert durable_projection(read(verify, id)) === original_projection
      assert_unloaded(verify)
      assert File.read!(path) === updated_bytes

      restored = call(verify, "thread/resume", %{"threadId" => id, "excludeTurns" => true})

      assert Map.fetch!(restored, "runtimeWorkspaceRoots") === expected
      refute Map.fetch!(restored, "runtimeWorkspaceRoots") == original
      assert Map.fetch!(restored, "instructionSources") === [ctx.source]
      assert Map.fetch!(restored, "sandbox") === @readonly
      assert_saved(read(verify, id), id, name, path)
      assert durable_projection(read(verify, id)) === original_projection
      assert File.read!(ctx.source) === @instructions
      assert_idle(ctx, verify)
      assert :ok = Session.close(verify)

      assert creation_meta(path, id) === original_meta
      assert latest_root_snapshot(path, id) === expected
    end
  end

  defp start_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "sandbox" => "read-only",
      "ephemeral" => false,
      "historyMode" => "legacy"
    }
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp assert_saved(thread, id, name, path) do
    assert Map.fetch!(thread, "id") === id
    assert Map.fetch!(thread, "name") === name
    assert Map.fetch!(thread, "path") === path
    assert Map.fetch!(thread, "turns") === []
    assert Map.fetch!(thread, "historyMode") === "legacy"
    assert Map.fetch!(thread, "ephemeral") === false
  end

  defp durable_projection(thread),
    do: Map.take(thread, ~w(id name path turns historyMode ephemeral))

  defp assert_unloaded(pid),
    do: assert(call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp rows(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp creation_meta(path, id) do
    assert [meta] =
             for(
               row <- rows(path),
               row["type"] == "session_meta",
               row["payload"]["id"] == id,
               do: row["payload"]
             )

    meta
  end

  defp latest_root_snapshot(path, id) do
    snapshots =
      for row <- rows(path),
          row["type"] == "event_msg",
          row["payload"]["type"] == "thread_settings_applied",
          row["payload"]["thread_id"] == id,
          do: Map.fetch!(Map.fetch!(row["payload"], "thread_settings"), "runtime_workspace_roots")

    assert snapshots != []
    List.last(snapshots)
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)
  end
end
