defmodule SamgitaCodexDriver.NativeSearchProjectionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @needle "Owned search projection λ marker"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    # Native content search invokes ripgrep. Add only this reviewed executable
    # to the owned fixture PATH instead of inheriting the host environment.
    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    config_bytes = File.read!(config)
    on_exit(fn -> assert File.read!(config) == config_bytes end)
    ctx
  end

  test "search projects current section identity and appearance across rename deletion and cold reads",
       ctx do
    pid = start(ctx)
    selected = complete(ctx, pid, "selected")
    control = complete(ctx, pid, "control")
    saved = [selected, control]
    baseline = search(ctx, pid, saved, "idle")
    for id <- [selected.id, control.id], do: assert_unsectioned(baseline[id])

    appearance = %{"icon" => "folder", "color" => "purple"}

    created =
      call(pid, "threadSection/create", %{
        "name" => "Owned selected section",
        "appearance" => appearance
      })["section"]

    section_id = Map.fetch!(created, "id")

    expected = %{
      "id" => section_id,
      "name" => "Owned selected section",
      "appearance" => appearance
    }

    assert created == expected
    before_move = System.system_time(:second)

    assert call(pid, "thread/section/move", %{
             "threadId" => selected.id,
             "sectionId" => section_id,
             "beforeThreadId" => nil
           }) == %{}

    selected_read = read(pid, selected.id)
    entered = Map.fetch!(selected_read, "sectionEnteredAt")

    assert is_integer(entered) and entered >= before_move and
             entered <= System.system_time(:second)

    assert Map.fetch!(selected_read, "section") == expected
    assert_unsectioned(read(pid, control.id))
    moved = search(ctx, pid, saved, "idle")
    assert Map.fetch!(moved[selected.id], "section") == expected
    assert Map.fetch!(moved[selected.id], "sectionEnteredAt") == entered
    assert_unsectioned(moved[control.id])
    assert_no_execution(ctx, pid, saved)
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert_unloaded(cold)
    restored = search(ctx, cold, saved, "notLoaded")
    assert Map.fetch!(restored[selected.id], "section") == expected
    assert Map.fetch!(restored[selected.id], "sectionEnteredAt") == entered
    assert_unsectioned(restored[control.id])
    assert_unloaded(cold)

    replacement = %{"icon" => "star", "color" => "blue"}

    renamed =
      call(cold, "threadSection/update", %{
        "sectionId" => section_id,
        "name" => "Owned renamed section",
        "appearance" => replacement
      })["section"]

    expected_renamed = %{
      "id" => section_id,
      "name" => "Owned renamed section",
      "appearance" => replacement
    }

    assert renamed == expected_renamed
    assert Map.fetch!(read(cold, selected.id), "section") == expected_renamed
    changed = search(ctx, cold, saved, "notLoaded")
    assert Map.fetch!(changed[selected.id], "section") == expected_renamed
    refute Map.fetch!(changed[selected.id], "section") == expected
    assert Map.fetch!(changed[selected.id], "sectionEnteredAt") == entered
    assert_unsectioned(changed[control.id])

    assert call(cold, "threadSection/delete", %{"sectionId" => section_id}) == %{}
    assert_unsectioned(read(cold, selected.id))
    deleted = search(ctx, cold, saved, "notLoaded")
    for id <- [selected.id, control.id], do: assert_unsectioned(deleted[id])
    assert_unloaded(cold)
    assert_no_execution(ctx, cold, saved)
    assert :ok = Session.close(cold)
  end

  test "search project membership follows import identity and deletion without rewriting matching content",
       ctx do
    pid = start(ctx)
    selected = complete(ctx, pid, "selected")
    control = complete(ctx, pid, "control")
    saved = [selected, control]
    initial = search(ctx, pid, saved, "idle")
    assert Map.fetch!(initial[selected.id], "projectId") == nil
    assert Map.fetch!(initial[control.id], "projectId") == nil

    selected_params = %{
      "name" => "Owned selected project",
      "roots" => [],
      "metadata" => %{"label" => "selected"},
      "threads" => [selected.id],
      "idempotencyKey" => "owned-search-selected-project"
    }

    control_params = %{
      "name" => "Owned control project",
      "roots" => [],
      "metadata" => %{"label" => "control"},
      "threads" => [control.id],
      "idempotencyKey" => "owned-search-control-project"
    }

    project = call(pid, "project/import", selected_params)["project"]
    other = call(pid, "project/import", control_params)["project"]
    project_id = Map.fetch!(project, "id")
    other_id = Map.fetch!(other, "id")
    refute project_id == other_id
    assert Map.fetch!(project, "metadata") == %{"label" => "selected"}
    assert Map.fetch!(other, "metadata") == %{"label" => "control"}
    assert Map.fetch!(read(pid, selected.id), "projectId") == project_id
    assert Map.fetch!(read(pid, control.id), "projectId") == other_id
    assert_project_ids(search(ctx, pid, saved, "idle"), selected, control, project_id, other_id)

    replay =
      call(pid, "project/import", %{
        selected_params
        | "threads" => [control.id],
          "metadata" => %{"label" => "must not persist"}
      })["project"]

    assert Map.fetch!(replay, "id") == project_id
    assert Map.fetch!(replay, "metadata") == %{"label" => "selected"}
    assert_project_ids(search(ctx, pid, saved, "idle"), selected, control, project_id, other_id)
    assert_no_execution(ctx, pid, saved)
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert_unloaded(cold)

    assert_project_ids(
      search(ctx, cold, saved, "notLoaded"),
      selected,
      control,
      project_id,
      other_id
    )

    assert Map.fetch!(
             call(cold, "project/read", %{"projectId" => project_id})["project"],
             "metadata"
           ) ==
             %{"label" => "selected"}

    assert call(cold, "project/delete", %{"projectId" => project_id}) == %{}
    assert Map.fetch!(read(cold, selected.id), "projectId") == nil
    assert Map.fetch!(read(cold, control.id), "projectId") == other_id
    assert_project_ids(search(ctx, cold, saved, "notLoaded"), selected, control, nil, other_id)
    assert_unloaded(cold)
    assert_no_execution(ctx, cold, saved)
    assert :ok = Session.close(cold)

    verify = start(ctx)
    assert_unloaded(verify)
    assert_project_ids(search(ctx, verify, saved, "notLoaded"), selected, control, nil, other_id)
    assert_unloaded(verify)
    assert_no_execution(ctx, verify, saved)
    assert :ok = Session.close(verify)
  end

  defp complete(ctx, pid, suffix) do
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    text = suffix <> " " <> @needle
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, id, turn)

    completed =
      TurnFixture.notification(events, "item/completed", &(&1["item"]["type"] == "userMessage"))

    assert completed["threadId"] == id and completed["turnId"] == turn
    assert [%{"type" => "text", "text" => ^text}] = completed["item"]["content"]
    name = "Owned search " <> suffix
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    # The synchronous full read is the native persistence barrier, as in the
    # retained search/timeline suite. Query polling never manufactures success.
    thread = read(pid, id)
    assert Map.fetch!(thread, "name") == name
    assert [%{"id" => ^turn, "status" => "completed"}] = Map.fetch!(thread, "turns")
    path = Map.fetch!(thread, "path")
    bytes = File.read!(path)
    assert byte_size(bytes) > 0
    %{id: id, turn: turn, text: text, name: name, path: path, bytes: bytes}
  end

  defp search(ctx, pid, saved, status) do
    response = call(pid, "thread/search", %{"searchTerm" => @needle, "limit" => 100})
    assert Map.fetch!(response, "nextCursor") == nil
    rows = Map.fetch!(response, "data")
    assert length(rows) == length(saved)
    expected = Map.new(saved, &{&1.id, &1})
    assert MapSet.new(Enum.map(rows, & &1["thread"]["id"])) == MapSet.new(Map.keys(expected))

    Map.new(rows, fn row ->
      thread = Map.fetch!(row, "thread")
      id = Map.fetch!(thread, "id")
      source = Map.fetch!(expected, id)
      assert Map.fetch!(row, "snippet") == source.text
      assert Map.fetch!(thread, "name") == source.name
      assert Map.fetch!(thread, "cwd") == ctx.fixture.workspace
      assert Map.fetch!(thread, "path") == source.path
      assert Map.fetch!(thread, "historyMode") == "paginated"
      assert Map.fetch!(thread, "ephemeral") == false
      assert Map.fetch!(thread, "modelProvider") == "fixture"
      assert Map.fetch!(thread, "sessionId") == id
      assert Map.fetch!(thread, "status") == %{"type" => status}
      # Search returns metadata, while full native reads retain the real turn.
      assert Map.fetch!(thread, "turns") == []
      {id, thread}
    end)
  end

  defp assert_project_ids(rows, selected, control, selected_project, control_project) do
    assert Map.fetch!(rows[selected.id], "projectId") == selected_project
    assert Map.fetch!(rows[control.id], "projectId") == control_project
  end

  defp assert_unsectioned(thread) do
    assert Map.fetch!(thread, "section") == nil
    assert Map.fetch!(thread, "sectionEnteredAt") == nil
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp assert_unloaded(pid),
    do: assert(call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp assert_no_execution(ctx, pid, saved) do
    assert length(ModelFixture.requests(ctx.fixture)) == length(saved)

    for source <- saved do
      assert File.read!(source.path) == source.bytes

      assert [%{"id" => turn, "status" => "completed"}] =
               Map.fetch!(read(pid, source.id), "turns")

      assert turn == source.turn
    end

    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "samgita_owned_search_projections", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
