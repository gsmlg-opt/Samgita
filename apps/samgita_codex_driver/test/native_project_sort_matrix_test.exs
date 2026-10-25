defmodule SamgitaCodexDriver.NativeProjectSortMatrixTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3, notification: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @project_names ["Owned empty first", "Owned older", "Owned empty second", "Owned newer"]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ["project/create", "project/delete", "project/list"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 256 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    capture = start_supervised!({Agent, fn -> [] end})
    Map.put(ctx, :capture, capture)
  end

  test "position defaults nulls and both directions retain exact pages across cold restart",
       ctx do
    pid = start(ctx)
    [first, second, third, last] = create_projects(ctx, pid)

    assert call(pid, "project/move", %{
             "projectId" => last["id"],
             "beforeProjectId" => first["id"]
           }) == %{}

    assert_project_changes(pid, [%{"projectId" => last["id"], "changeType" => "updated"}])

    expected = Enum.map([last, first, second, third], & &1["id"])
    ledger = read_projects(pid, expected)

    qualify_position(ctx, pid, expected, ledger)
    assert_functional_state(ctx, pid, 0)
    cold = restart(ctx, pid, 0)
    qualify_position(ctx, cold, expected, ledger)
    assert_functional_state(ctx, cold, 0)
    assert :ok = Session.close(cold)
  end

  test "deletion emits its committed change and retains survivor records and historical keys",
       ctx do
    pid = start(ctx)
    [first, target, third, last] = projects = create_projects(ctx, pid)
    target_id = Map.fetch!(target, "id")
    ids = Enum.map([first, third, last], &Map.fetch!(&1, "id"))
    ledger = read_projects(pid, ids)
    stored = stored_projects(ctx)
    assert map_size(Map.fetch!(stored, "projects")) == 4
    assert Map.fetch!(stored, "thread_count") == 0

    assert Map.fetch!(stored, "keys") ===
             Map.new(Enum.zip(@project_names, projects), fn {name, project} ->
               {name, Map.fetch!(project, "id")}
             end)

    expected = Map.update!(stored, "projects", &Map.delete(&1, target_id))
    params = %{"projectId" => target_id}
    before = length(Agent.get(ctx.capture, & &1))
    assert call(pid, "project/delete", params) === %{}
    sent = Agent.get(ctx.capture, & &1)
    assert length(sent) == before + 1
    assert %{"method" => "project/delete", "params" => ^params} = List.last(sent)
    assert_project_changes(pid, [%{"projectId" => target_id, "changeType" => "deleted"}])
    assert_deleted(ctx, pid, target_id, ids, ledger, expected)

    cold = restart(ctx, pid, 0)
    assert_deleted(ctx, cold, target_id, ids, ledger, expected)
    assert :ok = Session.close(cold)
  end

  test "created project roots and second timestamps match committed native storage", ctx do
    pid = start(ctx)

    paths =
      Enum.map(["declared-project-beta", "declared-project-alpha"], &Path.join(ctx.root, &1))

    Enum.each(paths, &File.mkdir!/1)
    roots = Enum.map(paths, &%{"path" => &1})
    name = "Owned declared root project"
    key = "owned-declared-root-project"

    params = %{
      "name" => name,
      "idempotencyKey" => key,
      "metadata" => %{"label" => "Owned declared roots"},
      "roots" => roots
    }

    before_ms = System.system_time(:millisecond)
    project = call(pid, "project/create", params)["project"]
    after_ms = System.system_time(:millisecond)
    assert [%{"method" => "project/create", "params" => ^params}] = Agent.get(ctx.capture, & &1)
    stored = stored_creation(ctx, key, name)
    assert Map.fetch!(project, "id") === Map.fetch!(stored, "id")
    assert Map.fetch!(project, "name") === name
    assert Map.fetch!(project, "metadata") === %{"label" => "Owned declared roots"}
    assert Map.fetch!(project, "position") === 0
    assert Map.fetch!(project, "recencyAt") === nil
    assert Map.fetch!(project, "roots") === roots

    assert Map.fetch!(stored, "roots") ===
             Enum.with_index(paths, fn path, index -> [index, path] end)

    created_ms = Map.fetch!(stored, "created_at_ms")
    updated_ms = Map.fetch!(stored, "updated_at_ms")
    assert before_ms <= created_ms and created_ms <= after_ms
    assert updated_ms === created_ms
    assert Map.fetch!(project, "createdAt") === div(created_ms, 1000)
    assert Map.fetch!(project, "updatedAt") === div(updated_ms, 1000)
    id = Map.fetch!(stored, "id")
    assert_project_changes(pid, [%{"projectId" => id, "changeType" => "created"}])
    assert_functional_state(ctx, pid, 0)

    cold = restart(ctx, pid, 0)
    assert call(cold, "project/read", %{"projectId" => id}) === %{"project" => project}
    assert stored_creation(ctx, key, name) === stored
    assert File.ls!(ctx.fixture.workspace) == []
    Enum.each(paths, fn path -> assert File.ls!(path) == [] end)
    assert_functional_state(ctx, cold, 0)
    assert :ok = Session.close(cold)
  end

  defp assert_deleted(ctx, pid, target, ids, ledger, expected) do
    assert_pages(ctx, pid, %{}, ids, ledger, "position", "asc")
    assert read_projects(pid, ids) === ledger

    assert upstream_error(pid, "project/read", %{"projectId" => target}, []) === %{
             "code" => -32_602,
             "message" => "project not found: #{target}"
           }

    assert stored_projects(ctx) === expected
    assert_functional_state(ctx, pid, 0)
  end

  test "recency defaults descend while explicit directions retain empty projects last", ctx do
    pid = start(ctx)
    [empty_first, older, empty_second, newer] = create_projects(ctx, pid)
    first_turn = complete(ctx, pid, older["id"], "owned-project-older")
    first_times = recencies(ctx)
    older_time = Map.fetch!(first_times, older["id"])
    assert is_integer(older_time)
    await_clock(older_time, System.monotonic_time(:millisecond) + 5000)
    second_turn = complete(ctx, pid, newer["id"], "owned-project-newer")
    times = recencies(ctx)
    assert Map.fetch!(times, newer["id"]) > older_time
    assert Map.fetch!(times, older["id"]) == older_time

    for project <- [empty_first, empty_second],
        do: assert(Map.fetch!(times, project["id"]) == nil)

    projects = [empty_first, older, empty_second, newer]
    ledger = read_projects(pid, Enum.map(projects, & &1["id"]))
    expected_asc = recency_order(times, :asc)
    expected_desc = recency_order(times, :desc)
    position_order = Enum.map(projects, & &1["id"])
    refute position_order == expected_asc
    refute position_order == expected_desc
    refute expected_asc == expected_desc

    qualify_recency(ctx, pid, expected_asc, expected_desc, ledger, times)
    assert_functional_state(ctx, pid, 2)
    cold = restart(ctx, pid, 2)
    qualify_recency(ctx, cold, expected_asc, expected_desc, ledger, times)
    assert recencies(ctx) == times

    for {thread, turn} <- [first_turn, second_turn] do
      saved = call(cold, "thread/read", %{"threadId" => thread, "includeTurns" => true})
      assert [%{"id" => ^turn, "status" => "completed"}] = saved["thread"]["turns"]
    end

    assert_functional_state(ctx, cold, 2)
    assert :ok = Session.close(cold)
  end

  defp qualify_position(ctx, pid, expected, ledger) do
    for params <- [
          %{},
          %{"sortKey" => nil},
          %{"sortDirection" => nil},
          %{"sortKey" => nil, "sortDirection" => nil},
          %{"sortKey" => "position"},
          %{"sortKey" => "position", "sortDirection" => nil},
          %{"sortKey" => "position", "sortDirection" => "asc"}
        ] do
      assert_pages(ctx, pid, params, expected, ledger, "position", "asc")
    end

    descending = %{"sortKey" => "position", "sortDirection" => "desc"}
    assert_pages(ctx, pid, descending, Enum.reverse(expected), ledger, "position", "desc")

    for direction <- ["asc", "desc"], optional <- [%{}, %{"sortKey" => nil}] do
      params = Map.put(optional, "sortDirection", direction)

      assert list_error(ctx, pid, params) == %{
               "code" => -32_602,
               "message" => "sortDirection requires sortKey"
             }
    end

    assert_cursor_binding(ctx, pid, ledger, "position", "asc")
    assert_cursor_binding(ctx, pid, ledger, "position", "desc")
  end

  defp qualify_recency(ctx, pid, ascending, descending, ledger, times) do
    for params <- [
          %{"sortKey" => "recencyAt"},
          %{"sortKey" => "recencyAt", "sortDirection" => nil},
          %{"sortKey" => "recencyAt", "sortDirection" => "desc"}
        ] do
      assert_pages(ctx, pid, params, descending, ledger, "recencyAt", "desc", times)
    end

    assert_pages(
      ctx,
      pid,
      %{"sortKey" => "recencyAt", "sortDirection" => "asc"},
      ascending,
      ledger,
      "recencyAt",
      "asc",
      times
    )

    assert_cursor_binding(ctx, pid, ledger, "recencyAt", "asc")
    assert_cursor_binding(ctx, pid, ledger, "recencyAt", "desc")
  end

  defp assert_pages(ctx, pid, params, expected, ledger, key, direction, times \\ %{}) do
    full = list(ctx, pid, Map.put(params, "limit", 100))
    assert full["data"] == Enum.map(expected, &Map.fetch!(ledger, &1))
    assert Map.fetch!(full, "nextCursor") == nil

    Enum.reduce(Enum.with_index(expected), nil, fn {id, index}, cursor ->
      page_params = Map.put(params, "limit", 1)
      page_params = if cursor, do: Map.put(page_params, "cursor", cursor), else: page_params
      page = list(ctx, pid, page_params)
      assert page["data"] == [Map.fetch!(ledger, id)]

      if index == length(expected) - 1 do
        assert Map.fetch!(page, "nextCursor") == nil
        nil
      else
        expected_cursor = cursor_for(id, ledger, key, direction, times)
        assert Map.fetch!(page, "nextCursor") == expected_cursor
        expected_cursor
      end
    end)
  end

  defp cursor_for(id, ledger, "position", "asc", _times),
    do: "#{Map.fetch!(ledger, id)["position"]}|#{id}"

  defp cursor_for(id, ledger, "position", "desc", _times),
    do: "v1|position|desc|#{Map.fetch!(ledger, id)["position"]}|#{id}"

  defp cursor_for(id, _ledger, "recencyAt", direction, times) do
    value = Map.fetch!(times, id)
    "v1|recencyAt|#{direction}|#{if is_nil(value), do: "null", else: value}|#{id}"
  end

  defp assert_cursor_binding(ctx, pid, ledger, key, direction) do
    params = %{"sortKey" => key, "sortDirection" => direction, "limit" => 1}
    page = list(ctx, pid, params)
    assert [project] = page["data"]
    assert Map.has_key?(ledger, project["id"])
    cursor = Map.fetch!(page, "nextCursor")
    assert is_binary(cursor)
    other_direction = if direction == "asc", do: "desc", else: "asc"
    other_key = if key == "position", do: "recencyAt", else: "position"

    for conflicting <- [
          %{params | "sortDirection" => other_direction},
          %{params | "sortKey" => other_key}
        ] do
      error = list_error(ctx, pid, Map.put(conflicting, "cursor", cursor))
      assert error["code"] == -32_602
      assert error["message"] =~ "invalid project cursor: malformed or mismatched sort anchor"
    end
  end

  defp list(ctx, pid, params) do
    before = length(Agent.get(ctx.capture, & &1))
    result = call(pid, "project/list", params)
    assert_capture(ctx, params, before)
    result
  end

  defp list_error(ctx, pid, params) do
    before = length(Agent.get(ctx.capture, & &1))
    error = upstream_error(pid, "project/list", params, [])
    assert_capture(ctx, params, before)
    error
  end

  defp assert_capture(ctx, params, before) do
    sent = Agent.get(ctx.capture, & &1)
    assert length(sent) == before + 1
    assert List.last(sent)["method"] == "project/list"
    assert List.last(sent)["params"] === params
  end

  defp create_projects(ctx, pid) do
    names = @project_names

    projects =
      for {name, position} <- Enum.with_index(names) do
        params = %{
          "name" => name,
          "roots" => [],
          "metadata" => %{"label" => name},
          "idempotencyKey" => name
        }

        before = length(Agent.get(ctx.capture, & &1))
        project = call(pid, "project/create", params)["project"]
        sent = Agent.get(ctx.capture, & &1)
        assert length(sent) == before + 1
        assert %{"method" => "project/create", "params" => ^params} = List.last(sent)
        assert Map.fetch!(project, "name") === name
        assert Map.fetch!(project, "metadata") === %{"label" => name}
        assert Map.fetch!(project, "position") === position
        assert Map.fetch!(project, "recencyAt") === nil
        {name, project}
      end

    ids = created_project_ids(ctx, names)
    assert length(Enum.uniq(Map.values(ids))) == 4

    for {name, project} <- projects do
      assert Map.fetch!(project, "id") === Map.fetch!(ids, name)
    end

    assert_project_changes(
      pid,
      Enum.map(Map.values(ids), &%{"projectId" => &1, "changeType" => "created"})
    )

    Enum.map(projects, &elem(&1, 1))
  end

  defp assert_project_changes(pid, expected) do
    events = collect_project_changes(pid, length(expected), [], deadline(5_000))

    for event <- events, event.wire["method"] == "project/changed" do
      refute Map.has_key?(event.wire, "id")
    end

    actual =
      for event <- events,
          event.wire["method"] == "project/changed",
          do: Map.fetch!(event.wire, "params")

    assert Enum.sort(actual) === Enum.sort(expected)
  end

  defp collect_project_changes(pid, count, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "project notification count exceeded its bound"

    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576,
           "project notification bytes exceeded their bound"

    if Enum.count(events, &(&1.wire["method"] == "project/changed")) >= count do
      events
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native project change deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during project change")
      after
        10 -> :ok
      end

      collect_project_changes(pid, count, events, until)
    end
  end

  defp created_project_ids(ctx, names) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    ids = {}
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        for name in json.loads(sys.argv[2]):
            rows = connection.execute('''
                SELECT p.id FROM project_idempotency_keys AS k
                JOIN projects AS p ON p.id = k.project_id
                WHERE k.key = ? AND p.name = ?
            ''', (name, name)).fetchall()
            assert len(rows) == 1, 'expected one committed project per requested key/name'
            ids[name] = rows[0][0]
    print(json.dumps(ids))
    """

    {output, status} =
      System.cmd("python3", ["-B", "-c", script, path, JSON.encode!(names)],
        stderr_to_stdout: true
      )

    assert status == 0, "owned project creation observation failed: #{output}"
    JSON.decode!(String.trim(output))
  end

  defp stored_projects(ctx) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        connection.row_factory = sqlite3.Row
        projects = {row['id']: dict(row) for row in connection.execute(
            'SELECT * FROM projects ORDER BY id LIMIT 5')}
        keys = dict(connection.execute(
            'SELECT key, project_id FROM project_idempotency_keys ORDER BY key LIMIT 5'))
        thread_count = connection.execute('SELECT COUNT(*) FROM threads').fetchone()[0]
    print(json.dumps({'projects': projects, 'keys': keys, 'thread_count': thread_count}))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned project storage observation failed: #{output}"
    JSON.decode!(String.trim(output))
  end

  defp stored_creation(ctx, key, name) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        rows = connection.execute('''
            SELECT p.id, p.created_at_ms, p.updated_at_ms
            FROM project_idempotency_keys AS k JOIN projects AS p ON p.id = k.project_id
            WHERE k.key = ? AND p.name = ?
        ''', (sys.argv[2], sys.argv[3])).fetchall()
        assert len(rows) == 1, 'expected one committed project for requested key/name'
        roots = connection.execute('''
            SELECT r.position, r.path FROM project_idempotency_keys AS k
            JOIN projects AS p ON p.id = k.project_id
            JOIN project_roots AS r ON r.project_id = p.id
            WHERE k.key = ? AND p.name = ? ORDER BY r.position
        ''', (sys.argv[2], sys.argv[3])).fetchall()
    print(json.dumps({'id': rows[0][0], 'created_at_ms': rows[0][1],
                     'updated_at_ms': rows[0][2], 'roots': roots}))
    """

    {output, status} =
      System.cmd("python3", ["-B", "-c", script, path, key, name], stderr_to_stdout: true)

    assert status == 0, "owned project root/timestamp observation failed: #{output}"
    JSON.decode!(String.trim(output))
  end

  defp read_projects(pid, ids) do
    Map.new(ids, fn id ->
      project = call(pid, "project/read", %{"projectId" => id})["project"]
      assert Map.fetch!(project, "id") == id
      {id, project}
    end)
  end

  defp complete(ctx, pid, project, marker) do
    thread =
      TurnFixture.thread(ctx, pid, %{
        "projectId" => project,
        "historyMode" => "legacy",
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    turn = TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => marker}])
    collect_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert [%{"id" => ^turn, "status" => "completed"}] = saved["turns"]
    assert saved["projectId"] == project
    {thread, turn}
  end

  defp collect_turn(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    completed =
      notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if completed do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               completed

      refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    else
      assert System.monotonic_time(:millisecond) < deadline, "native project turn deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during project turn")
      after
        20 -> :ok
      end

      collect_turn(pid, thread, turn, events, deadline)
    end
  end

  defp recencies(ctx) do
    # Read the native fixture's millisecond clock without seeding or updating it.
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        rows = connection.execute('''
            SELECT p.id, MAX(t.recency_at_ms) FROM projects p
            LEFT JOIN threads t ON t.project_id = p.id AND t.archived = 0
            GROUP BY p.id
        ''').fetchall()
        print(json.dumps(dict(rows)))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned project recency observation failed: #{output}"
    JSON.decode!(String.trim(output))
  end

  defp recency_order(times, direction) do
    {empty, occupied} = Enum.split_with(times, fn {_id, time} -> is_nil(time) end)
    sorter = if direction == :asc, do: :asc, else: :desc
    active = Enum.sort_by(occupied, fn {id, time} -> {time, id} end, sorter)
    inactive = Enum.sort_by(empty, &elem(&1, 0), sorter)
    Enum.map(active ++ inactive, &elem(&1, 0))
  end

  defp await_clock(timestamp, deadline) do
    if System.system_time(:millisecond) <= timestamp do
      assert System.monotonic_time(:millisecond) < deadline,
             "native project recency clock deadline"

      receive do
      after
        1 -> :ok
      end

      await_clock(timestamp, deadline)
    end
  end

  defp assert_functional_state(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp restart(ctx, pid, count) do
    assert_functional_state(ctx, pid, count)
    original = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(original)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{original}")
    cold = start(ctx)
    replacement = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(replacement) and replacement != original
    assert_functional_state(ctx, cold, count)
    cold
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_project_sort_matrix", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
end
