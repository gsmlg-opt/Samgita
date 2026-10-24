defmodule SamgitaCodexDriver.NativeThreadListFieldsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @missing "00000000-0000-0000-0000-000000000000"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    File.mkdir!(Path.join(ctx.fixture.workspace, "owned-b"))
    ctx
  end

  test "ordinary list applies exact cwd provider source and literal title filters", ctx do
    pid = start(ctx)
    rows = histories(ctx, pid)
    [first, second, third, fourth] = rows
    all = Enum.map(rows, & &1.id)

    for extra <- [
          %{},
          %{"cwd" => nil},
          %{"modelProviders" => nil},
          %{"modelProviders" => []},
          %{"modelProviders" => ["fixture"]},
          %{"sourceKinds" => nil},
          %{"sourceKinds" => []},
          %{"sourceKinds" => ["vscode"]},
          %{"sourceKinds" => ["exec", "vscode"]},
          %{"searchTerm" => nil},
          %{"searchTerm" => ""}
        ] do
      assert_id_set(list(pid, extra), all)
    end

    for cwd <- [ctx.fixture.workspace, ctx.fixture.workspace <> "/.", "."] do
      assert_id_set(list(pid, %{"cwd" => cwd}), [first.id, third.id])
    end

    assert_id_set(list(pid, %{"cwd" => second.cwd}), [second.id, fourth.id])
    assert_id_set(list(pid, %{"cwd" => [first.cwd, second.cwd, first.cwd]}), all)
    assert_empty(list(pid, %{"cwd" => []}))
    assert_empty(list(pid, %{"cwd" => Path.join(ctx.fixture.workspace, "owned-missing")}))
    assert_empty(list(pid, %{"modelProviders" => ["owned-unconfigured-provider"]}))
    assert_empty(list(pid, %{"sourceKinds" => ["exec"]}))

    # These selectors match native stored names. The turn text has none of the
    # needle marker, percent, underscore or lambda characters.
    assert_id_set(list(pid, %{"searchTerm" => "needle%_"}), [first.id, second.id])
    assert_id_set(list(pid, %{"searchTerm" => "λ"}), [first.id, second.id, third.id])
    assert_empty(list(pid, %{"searchTerm" => "NEEDLE%_"}))
    assert_id_set(list(pid, %{"searchTerm" => "needle%_", "cwd" => second.cwd}), [second.id])

    for native <- list(pid)["data"] do
      expected = Enum.find(rows, &(&1.id == native["id"]))
      assert expected
      assert native["name"] == expected.name
      assert native["cwd"] == expected.cwd
      assert native["modelProvider"] == "fixture"
      assert native["source"] == "vscode"
    end

    assert_no_execution(ctx, pid, 4)
  end

  test "created-at forward pages, exclusions and native reverse-cursor limitation survive cold restart",
       ctx do
    pid = start(ctx)
    rows = histories(ctx, pid)
    asc = list(pid, %{"sortDirection" => "asc"})
    order = ids(asc)
    assert MapSet.new(order) == MapSet.new(Enum.map(rows, & &1.id))
    assert length(order) == 4
    times = Enum.map(asc["data"], & &1["createdAt"])
    assert Enum.all?(times, &is_integer/1)
    assert times == Enum.sort(times)
    stored_times = stored_created_at(ctx)
    assert MapSet.new(Map.keys(stored_times)) == MapSet.new(order)
    assert order == timestamp_order(stored_times, "asc")

    for row <- asc["data"] do
      assert row["createdAt"] == div(Map.fetch!(stored_times, row["id"]), 1_000)
    end

    assert Map.fetch!(asc, "nextCursor") == nil
    assert ids(list(pid, %{"sortDirection" => "desc"})) == Enum.reverse(order)

    for extra <- [
          %{},
          %{"cursor" => nil, "limit" => nil, "sortKey" => nil, "sortDirection" => nil}
        ] do
      assert ids(list(pid, extra)) == Enum.reverse(order)
    end

    assert ids(list(pid, %{"limit" => 0, "sortDirection" => "asc"})) == Enum.take(order, 1)

    for direction <- ["asc", "desc"] do
      expected = if direction == "asc", do: order, else: Enum.reverse(order)
      params = %{"limit" => 2, "sortDirection" => direction}
      first = list(pid, params)
      assert ids(first) == Enum.take(expected, 2)
      assert is_binary(Map.fetch!(first, "nextCursor"))
      assert is_binary(Map.fetch!(first, "backwardsCursor"))
      second = list(pid, Map.put(params, "cursor", first["nextCursor"]))
      assert ids(second) == Enum.drop(expected, 2)
      assert Map.fetch!(second, "nextCursor") == nil
      assert_native_reverse_limitation(pid, second, stored_times, direction)
    end

    excluded = [Enum.at(order, 0), Enum.at(order, 2)]
    params = %{"sortDirection" => "asc", "limit" => 2, "excludedThreadIds" => excluded}
    kept = list(pid, params)
    assert ids(kept) == [Enum.at(order, 1), Enum.at(order, 3)]
    assert Map.fetch!(kept, "nextCursor") == nil
    assert_empty(list(pid, %{"excludedThreadIds" => order, "limit" => 1}))

    for values <- [nil, [], [@missing]] do
      assert ids(list(pid, %{"excludedThreadIds" => values, "sortDirection" => "asc"})) == order
    end

    assert ids(
             list(pid, %{
               "excludedThreadIds" => [String.upcase(hd(order))],
               "sortDirection" => "asc"
             })
           ) == tl(order)

    assert ids(
             list(pid, %{
               "excludedThreadIds" => List.duplicate(hd(order), 100),
               "sortDirection" => "asc"
             })
           ) == tl(order)

    first = list(pid, %{"sortDirection" => "asc", "limit" => 2})
    continuation = %{"sortDirection" => "asc", "limit" => 2, "cursor" => first["nextCursor"]}
    hot = list(pid, continuation)
    process = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert_no_execution(ctx, pid, 4)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    result = list(cold, continuation)
    assert durable_rows(result) == durable_rows(hot)
    assert Map.fetch!(result, "nextCursor") == Map.fetch!(hot, "nextCursor")
    assert Map.fetch!(result, "backwardsCursor") == Map.fetch!(hot, "backwardsCursor")
    assert ids(list(cold, %{"sortDirection" => "asc"})) == order
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_no_execution(ctx, cold, 4)
  end

  test "native malformed list filters preserve the existing persisted result", ctx do
    pid = start(ctx)
    [row] = histories(ctx, pid, 1)
    baseline = durable_rows(list(pid))

    assert upstream_error(pid, "thread/list", %{"cursor" => "owned-invalid-cursor"}) ==
             %{"code" => -32_600, "message" => "invalid cursor: owned-invalid-cursor"}

    assert upstream_error(pid, "thread/list", %{
             "excludedThreadIds" => List.duplicate(row.id, 101)
           }) ==
             %{"code" => -32_602, "message" => "excludedThreadIds accepts at most 100 entries"}

    error = upstream_error(pid, "thread/list", %{"excludedThreadIds" => ["not-a-thread-id"]})
    assert error["code"] == -32_602
    assert String.starts_with?(error["message"], "invalid excluded thread id:")

    for params <- [
          %{"cwd" => 17},
          %{"cwd" => [17]},
          %{"excludedThreadIds" => [17]},
          %{"limit" => -1},
          %{"limit" => 4_294_967_296},
          %{"modelProviders" => [false]},
          %{"sourceKinds" => ["owned-unknown-source"]},
          %{"sortDirection" => "sideways"},
          %{"sortKey" => "owned-unknown-sort"}
        ] do
      error = upstream_error(pid, "thread/list", params, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert durable_rows(list(pid)) == baseline
      assert_no_execution(ctx, pid, 1)
    end

    assert durable_rows(list(pid)) == baseline
    assert_no_execution(ctx, pid, 1)
  end

  defp histories(ctx, pid, count \\ 4) do
    names = [
      "Owned list needle%_ λ alpha",
      "Owned list needle%_ λ beta",
      "Owned list needleAB λ gamma",
      "Owned list other 🙂 delta"
    ]

    for i <- 0..(count - 1) do
      cwd =
        if rem(i, 2) == 0,
          do: ctx.fixture.workspace,
          else: Path.join(ctx.fixture.workspace, "owned-b")

      id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated", "cwd" => cwd})
      text = "Owned list input #{i + 1}"
      turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
      TurnFixture.finish_turn(pid, id, turn)
      native = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

      assert [%{"id" => ^turn, "status" => "completed", "items" => [user, agent]}] =
               native["turns"]

      assert user["type"] == "userMessage"

      assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) == [
               %{"type" => "text", "text" => text}
             ]

      assert agent["type"] == "agentMessage"
      assert agent["text"] == "Deterministic local fixture answer"
      name = Enum.at(names, i)
      assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
      assert File.regular?(native["path"])
      %{id: id, name: name, cwd: cwd}
    end
  end

  defp list(pid, extra \\ %{}) do
    call(
      pid,
      "thread/list",
      Map.merge(%{"limit" => 100, "sortKey" => "created_at", "useStateDbOnly" => true}, extra)
    )
  end

  defp ids(page), do: Enum.map(page["data"], & &1["id"])

  defp durable_rows(page),
    do:
      Enum.map(
        page["data"],
        &Map.take(&1, ["id", "name", "cwd", "modelProvider", "source", "preview", "createdAt"])
      )

  defp assert_id_set(page, expected) do
    assert length(ids(page)) == length(expected)
    assert MapSet.new(ids(page)) == MapSet.new(expected)
    assert Map.fetch!(page, "nextCursor") == nil
  end

  defp assert_empty(page) do
    assert page["data"] == []
    assert Map.fetch!(page, "nextCursor") == nil
    assert Map.fetch!(page, "backwardsCursor") == nil
  end

  defp assert_no_execution(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp stored_created_at(ctx) do
    # Observe only owned native state. Never seed, repair or change this database.
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
    assert File.regular?(path)

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        rows = connection.execute('SELECT id, created_at_ms FROM threads').fetchall()
        print(json.dumps(dict(rows)))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned read-only timestamp observation failed: #{output}"
    timestamps = JSON.decode!(String.trim(output))
    assert Enum.all?(timestamps, fn {id, ms} -> is_binary(id) and is_integer(ms) end)
    timestamps
  end

  defp timestamp_order(timestamps, direction) do
    ordered = timestamps |> Enum.sort_by(fn {id, ms} -> {ms, id} end) |> Enum.map(&elem(&1, 0))
    if direction == "asc", do: ordered, else: Enum.reverse(ordered)
  end

  defp assert_native_reverse_limitation(pid, page, timestamps, direction) do
    # Immutable native source drops created_at milliseconds at recorder.rs:2170
    # before thread_processor.rs:5902-5930 offsets its reverse cursor. The earlier
    # advertised anchor-inclusion assertion FAILED. This diagnostic preserves
    # that upstream limitation; it does not qualify the missing anchor guarantee.
    anchor_ms = Map.fetch!(timestamps, hd(ids(page)))
    cursor = Map.fetch!(page, "backwardsCursor")
    assert {:ok, timestamp, 0} = DateTime.from_iso8601(cursor)
    cursor_ms = DateTime.to_unix(timestamp, :millisecond)
    offset = if direction == "asc", do: 1, else: -1
    assert cursor_ms == div(anchor_ms, 1_000) * 1_000 + offset
    opposite = if direction == "asc", do: "desc", else: "asc"

    selected =
      Map.filter(timestamps, fn {_id, ms} ->
        if opposite == "desc", do: ms < cursor_ms, else: ms > cursor_ms
      end)

    reverse = list(pid, %{"cursor" => cursor, "sortDirection" => opposite})
    assert ids(reverse) == timestamp_order(selected, opposite)
    assert Map.fetch!(reverse, "nextCursor") == nil
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: ["app-server", "--listen", "stdio://"],
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_list_fields", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    pid
  end
end
