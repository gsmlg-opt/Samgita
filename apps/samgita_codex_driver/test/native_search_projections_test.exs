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

  test "explicit null search sort fields retain independent default created order across cold reads",
       ctx do
    pid = start(ctx)
    first = complete(ctx, pid, "default-first")
    second = complete(ctx, pid, "default-second")
    saved = [first, second]
    timestamps = search_timestamps(ctx)
    assert MapSet.new(Map.keys(timestamps)) == MapSet.new([first.id, second.id])
    expected = timestamp_order(timestamps, "created_at", "desc")
    snippets = %{first.id => first.text, second.id => second.text}

    verify = fn current ->
      for optional <- [
            %{},
            %{"sortKey" => nil},
            %{"sortDirection" => nil},
            %{"sortKey" => nil, "sortDirection" => nil}
          ] do
        params = Map.merge(%{"searchTerm" => @needle, "limit" => 100}, optional)
        response = call(current, "thread/search", params)
        assert_timestamp_page(response, expected, snippets, timestamps)
        assert Map.fetch!(response, "nextCursor") == nil
      end
    end

    verify.(pid)
    assert_no_execution(ctx, pid, saved)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert_unloaded(cold)
    verify.(cold)
    assert_unloaded(cold)
    assert_no_execution(ctx, cold, saved)
    assert :ok = Session.close(cold)
  end

  test "search timestamp projections preserve sort order and expose created cursor precision loss",
       ctx do
    pid = start(ctx)
    first = complete(ctx, pid, "timestamp-first")
    second = complete(ctx, pid, "timestamp-second")
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    control = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    control_turn = timestamp_turn(ctx, pid, control, "Owned nonmatching timestamp control", 3)
    control_read = read(pid, control)
    before = search_timestamps(ctx)
    assert MapSet.new(Map.keys(before)) == MapSet.new([first.id, second.id, control])

    # Advance the earliest matching thread after the others without editing native
    # state. A bounded clock barrier prevents a same-millisecond fixture ambiguity.
    latest = before |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.max()
    await_search_clock(latest, System.monotonic_time(:millisecond) + 2_000)
    next = timestamp_turn(ctx, pid, first.id, "Owned first-thread recency continuation", 4)
    timestamps = search_timestamps(ctx)
    selected = Map.take(timestamps, [first.id, second.id])

    for {_id, row} <- selected do
      assert rem(Map.fetch!(row, "created_at"), 1_000) > 0,
             "Owned created-cursor fixture requires nonzero native millisecond fractions"
    end

    for id <- [first.id, second.id, control] do
      assert timestamps[id]["created_at"] == before[id]["created_at"]
    end

    assert timestamps[first.id]["recency_at"] > before[first.id]["recency_at"]

    refute timestamp_order(selected, "created_at", "desc") ==
             timestamp_order(selected, "recency_at", "desc")

    # updated_at has no UUID tie-breaker in the pinned native store; require
    # distinct observed values rather than inventing a tie-order guarantee.
    assert length(Enum.uniq(Enum.map(selected, fn {_id, row} -> row["updated_at"] end))) == 2

    expected_turns = %{
      first.id => [first.turn, next],
      second.id => [second.turn],
      control => [control_turn]
    }

    saved =
      for id <- [first.id, second.id, control] do
        native = read(pid, id)
        assert Enum.map(native["turns"], & &1["id"]) == Map.fetch!(expected_turns, id)
        assert Enum.all?(native["turns"], &(&1["status"] == "completed"))
        %{id: id, path: native["path"], bytes: File.read!(native["path"]), turns: native["turns"]}
      end

    snippets = %{first.id => first.text, second.id => second.text}
    continuations = timestamp_search_matrix(pid, selected, snippets)
    assert_timestamp_sources(ctx, pid, saved, timestamps)
    assert File.read!(control_read["path"]) == Enum.find(saved, &(&1.id == control)).bytes
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert_unloaded(cold)
    assert timestamp_search_matrix(cold, selected, snippets) == continuations

    for {params, expected, next_cursor} <- continuations do
      response = call(cold, "thread/search", params)
      assert_timestamp_page(response, expected, snippets, selected)
      assert Map.fetch!(response, "nextCursor") == next_cursor
    end

    assert_unloaded(cold)
    assert_timestamp_sources(ctx, cold, saved, timestamps)
    assert_unloaded(cold)
    assert :ok = Session.close(cold)
  end

  defp timestamp_turn(ctx, pid, id, text, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count - 1
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, id, turn)

    for {type, expected} <- [
          {"userMessage",
           %{"content" => [%{"type" => "text", "text" => text, "text_elements" => []}]}},
          {"agentMessage", %{"text" => "Deterministic local fixture answer"}}
        ] do
      completed =
        TurnFixture.notification(events, "item/completed", fn p ->
          p["threadId"] == id and p["turnId"] == turn and p["item"]["type"] == type
        end)

      assert completed
      assert Map.take(completed["item"], Map.keys(expected)) == expected
    end

    assert length(ModelFixture.requests(ctx.fixture)) == count
    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    # As in complete/3, flush canonical history through a synchronous full read
    # before observing native metadata; completion delivery alone is not a disk barrier.
    assert Enum.any?(read(pid, id)["turns"], &(&1["id"] == turn and &1["status"] == "completed"))
    turn
  end

  defp search_timestamps(ctx) do
    # Observe only this explicitly owned fixture database. Never seed or repair it.
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
    assert File.lstat!(path).type == :regular

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        rows = connection.execute(
            'SELECT id, created_at_ms, updated_at_ms, recency_at_ms FROM threads'
        ).fetchall()
        print(json.dumps({
            row[0]: dict(zip(('created_at', 'updated_at', 'recency_at'), row[1:]))
            for row in rows
        }))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned read-only search timestamp observation failed: #{output}"
    timestamps = JSON.decode!(String.trim(output))

    assert Enum.all?(timestamps, fn {id, row} ->
             is_binary(id) and
               Enum.sort(Map.keys(row)) == ["created_at", "recency_at", "updated_at"] and
               Enum.all?(Map.values(row), &is_integer/1)
           end)

    timestamps
  end

  defp await_search_clock(timestamp, deadline) do
    cond do
      System.system_time(:millisecond) > timestamp ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Owned timestamp fixture clock did not advance")

      true ->
        receive do
        after
          1 -> await_search_clock(timestamp, deadline)
        end
    end
  end

  defp timestamp_order(timestamps, key, direction) do
    ordered =
      timestamps
      |> Enum.sort_by(fn {id, row} -> {Map.fetch!(row, key), id} end)
      |> Enum.map(&elem(&1, 0))

    if direction == "asc", do: ordered, else: Enum.reverse(ordered)
  end

  defp timestamp_search_matrix(pid, timestamps, snippets) do
    # Keep every independent full/first-page oracle ahead of the continuation
    # diagnostics, including both created_at directions.
    first_pages =
      for key <- ["created_at", "updated_at", "recency_at"], direction <- ["asc", "desc"] do
        expected = timestamp_order(timestamps, key, direction)

        params = %{
          "searchTerm" => @needle,
          "sortKey" => key,
          "sortDirection" => direction,
          "limit" => 100
        }

        full = call(pid, "thread/search", params)
        assert_timestamp_page(full, expected, snippets, timestamps)
        assert Map.fetch!(full, "nextCursor") == nil
        first_params = Map.put(params, "limit", 1)
        first_page = call(pid, "thread/search", first_params)
        assert_timestamp_page(first_page, Enum.take(expected, 1), snippets, timestamps)
        cursor = Map.fetch!(first_page, "nextCursor")
        assert is_binary(cursor) and byte_size(cursor) > 0
        {Map.put(first_params, "cursor", cursor), expected}
      end

    for {params, expected} <- first_pages do
      {continued, next_cursor} =
        if params["sortKey"] == "created_at" do
          created_cursor_limitation(
            timestamps,
            params["sortDirection"],
            expected,
            params["cursor"]
          )
        else
          # Preserve ordinary no-repeat/no-skip expectations for millisecond
          # updated_at and recency_at cursors.
          {Enum.drop(expected, 1), nil}
        end

      response = call(pid, "thread/search", params)
      assert_timestamp_page(response, continued, snippets, timestamps)
      assert Map.fetch!(response, "nextCursor") == next_cursor
      {params, continued, next_cursor}
    end
  end

  defp created_cursor_limitation(timestamps, direction, ordered, cursor) do
    anchor = hd(ordered)
    raw_ms = Map.fetch!(timestamps[anchor], "created_at")
    assert rem(raw_ms, 1_000) > 0
    floor_ms = div(raw_ms, 1_000) * 1_000
    expected_cursor = floor_ms |> div(1_000) |> DateTime.from_unix!() |> DateTime.to_iso8601()
    assert cursor == expected_cursor

    # Upstream rust-v0.163.0 recorder.rs:2170 drops created_at fractions.
    # search_threads.rs:216-240 reuses that string as its forward cursor,
    # while state/runtime/threads.rs:1507-1539 compares raw milliseconds.
    # This proves the pinned limitation; it does not qualify valid created
    # pagination or repair/renormalize the cursor sent to native Codex.
    eligible =
      Map.filter(timestamps, fn {_id, row} ->
        ms = Map.fetch!(row, "created_at")
        if direction == "asc", do: ms > floor_ms, else: ms < floor_ms
      end)

    eligible_ids = timestamp_order(eligible, "created_at", direction)
    continued = Enum.take(eligible_ids, 1)
    intended_rest = Enum.drop(ordered, 1)

    if direction == "asc" do
      # A fractional anchor always repeats itself and emits the same cursor.
      assert continued == [anchor]
      refute continued == intended_rest
    else
      # Descending search skips precisely those intended rows at or after the
      # truncated boundary. This is empty if the other row is in an older second.
      skipped =
        Enum.filter(intended_rest, fn id ->
          Map.fetch!(timestamps[id], "created_at") >= floor_ms
        end)

      assert intended_rest -- continued == skipped
      assert continued == intended_rest -- skipped
    end

    next_cursor =
      if length(eligible_ids) > 1 do
        next_anchor = hd(continued)
        next_ms = Map.fetch!(timestamps[next_anchor], "created_at")
        next_ms |> div(1_000) |> DateTime.from_unix!() |> DateTime.to_iso8601()
      end

    if direction == "asc", do: assert(next_cursor == cursor)

    {continued, next_cursor}
  end

  defp assert_timestamp_page(response, expected, snippets, timestamps) do
    rows = Map.fetch!(response, "data")
    assert Enum.map(rows, & &1["thread"]["id"]) == expected

    for row <- rows do
      thread = Map.fetch!(row, "thread")
      id = Map.fetch!(thread, "id")
      assert Map.fetch!(row, "snippet") == Map.fetch!(snippets, id)
      assert Map.fetch!(thread, "historyMode") == "paginated"
      assert Map.fetch!(thread, "turns") == []

      for {field, raw} <- [
            {"createdAt", "created_at"},
            {"updatedAt", "updated_at"},
            {"recencyAt", "recency_at"}
          ] do
        assert Map.fetch!(thread, field) == div(Map.fetch!(timestamps[id], raw), 1_000)
      end
    end
  end

  defp assert_timestamp_sources(ctx, pid, saved, timestamps) do
    assert length(ModelFixture.requests(ctx.fixture)) == 4

    for source <- saved do
      assert File.read!(source.path) == source.bytes
      assert read(pid, source.id)["turns"] == source.turns
    end

    assert search_timestamps(ctx) == timestamps
    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or method == "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
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
      assert Map.fetch!(thread, "preview") == source.text
      assert Map.fetch!(thread, "cliVersion") == "0.163.0"
      assert Map.fetch!(thread, "model") == "mock-model"

      expected_environments =
        if status == "idle" do
          [
            %{
              "cwd" => ctx.fixture.workspace,
              "environmentId" => "local",
              "runtimeWorkspaceRoots" => [ctx.fixture.workspace]
            }
          ]
        end

      assert Map.fetch!(thread, "environments") == expected_environments

      for field <-
            ~w(agentNickname agentRole canAcceptDirectInput daybreakEnabled extra forkedFromId gitInfo parentThreadId reasoningEffort) do
        assert Map.fetch!(thread, field) == nil
      end

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
