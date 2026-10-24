defmodule SamgitaCodexDriver.NativeHistoryCursorSemanticsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @texts ["Owned cursor first λ", "Owned cursor second 🙂", "Owned cursor third"]
  @answer "Deterministic local fixture answer"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  for mode <- ["legacy", "paginated"] do
    @history_mode mode
    test "#{mode} turn cursors exclude next anchors include reverse anchors and survive restart",
         ctx do
      pid = start(ctx)
      {id, turns, _items} = completed_history(ctx, pid, @history_mode)

      query = %{"threadId" => id, "limit" => 2, "itemsView" => "full"}
      calls = qualify_pages(pid, "thread/turns/list", query, turns)
      cold_replay(ctx, pid, calls, 3)
    end
  end

  test "paginated item cursors preserve original event identities order and inclusive reversal",
       ctx do
    pid = start(ctx)
    {id, _turns, items} = completed_history(ctx, pid, "paginated")
    assert length(items) == 6
    assert MapSet.size(MapSet.new(Enum.map(items, & &1["item"]["id"]))) == 6

    query = %{"threadId" => id, "limit" => 2}
    calls = qualify_pages(pid, "thread/items/list", query, items)
    cold_replay(ctx, pid, calls, 3)
  end

  for mode <- ["legacy", "paginated"] do
    @history_mode mode
    test "#{mode} malformed and foreign history cursors fail without changing either history",
         ctx do
      pid = start(ctx)
      {id, turns, _items} = completed_history(ctx, pid, @history_mode)

      {foreign, foreign_turns, _items} =
        completed_history(ctx, pid, @history_mode, ["Owned separate history"])

      query = %{
        "threadId" => id,
        "limit" => 2,
        "sortDirection" => "asc",
        "itemsView" => "full"
      }

      page = call(pid, "thread/turns/list", query)
      assert_rows("thread/turns/list", page["data"], Enum.take(turns, 2))
      cursor = Map.fetch!(page, "nextCursor")
      assert is_binary(cursor)

      snapshots =
        for thread_id <- [id, foreign] do
          all = Map.merge(query, %{"threadId" => thread_id, "limit" => 100})
          {all, call(pid, "thread/turns/list", all)}
        end

      for malformed <- ["not-json", "{}"] do
        assert upstream_error(pid, "thread/turns/list", Map.put(query, "cursor", malformed)) == %{
                 "code" => -32_600,
                 "message" => "invalid cursor: #{malformed}"
               }
      end

      foreign_query = Map.merge(query, %{"threadId" => foreign, "cursor" => cursor})

      message =
        if @history_mode == "legacy",
          do: "invalid cursor: anchor turn is no longer present",
          else: "invalid cursor: #{cursor}"

      assert upstream_error(pid, "thread/turns/list", foreign_query) == %{
               "code" => -32_600,
               "message" => message
             }

      if @history_mode == "paginated" do
        item_query = %{"threadId" => id, "limit" => 2, "sortDirection" => "asc"}
        item_page = call(pid, "thread/items/list", item_query)
        item_cursor = Map.fetch!(item_page, "nextCursor")
        assert is_binary(item_cursor)

        # Exact server-issued strings cross method/thread boundaries unchanged.
        # Cursor formats are deliberately not parsed, forged or normalized here.
        for {method, params, invalid} <- [
              {"thread/items/list", Map.put(item_query, "cursor", cursor), cursor},
              {"thread/turns/list", Map.put(query, "cursor", item_cursor), item_cursor},
              {"thread/items/list",
               Map.merge(item_query, %{"threadId" => foreign, "cursor" => item_cursor}),
               item_cursor},
              {"thread/items/list", Map.put(item_query, "cursor", "not-json"), "not-json"},
              {"thread/items/list", Map.put(item_query, "cursor", "{}"), "{}"}
            ] do
          assert upstream_error(pid, method, params) == %{
                   "code" => -32_600,
                   "message" => "invalid cursor: #{invalid}"
                 }
        end

        assert call(pid, "thread/items/list", item_query) == item_page
      end

      for {params, expected} <- snapshots do
        assert call(pid, "thread/turns/list", params) == expected
      end

      [{_, own}, {_, other}] = snapshots
      assert_rows("thread/turns/list", own["data"], turns)
      assert_rows("thread/turns/list", other["data"], foreign_turns)
      assert_no_execution(ctx, pid, 4)
      assert :ok = Session.close(pid)
    end
  end

  defp completed_history(ctx, pid, mode, texts \\ @texts) do
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => mode})

    rows =
      for text <- texts do
        turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
        events = TurnFixture.finish_turn(pid, id, turn)
        completed = item_events(events, "item/completed")
        assert Enum.map(completed, & &1["item"]["type"]) == ["userMessage", "agentMessage"]
        [user, agent] = completed

        assert user["item"]["content"] == [
                 %{"type" => "text", "text" => text, "text_elements" => []}
               ]

        assert agent["item"]["text"] == @answer

        entries =
          Enum.map(completed, fn event ->
            item = event["item"]
            assert is_binary(item["id"])
            assert event["threadId"] == id
            assert event["turnId"] == turn

            assert [began] =
                     Enum.filter(
                       item_events(events, "item/started"),
                       &(&1["item"]["id"] == item["id"])
                     )

            assert began["threadId"] == id
            assert began["turnId"] == turn
            started = Map.fetch!(began, "startedAtMs")
            ended = Map.fetch!(event, "completedAtMs")
            assert is_integer(started) and started > 0
            assert is_integer(ended) and ended >= started

            %{
              "turnId" => turn,
              "item" => item,
              "startedAtMs" => started,
              "completedAtMs" => ended
            }
          end)

        {%{id: turn, text: text}, entries}
      end

    turns = Enum.map(rows, &elem(&1, 0))
    items = Enum.flat_map(rows, &elem(&1, 1))

    # Existing synchronous native history read is the persistence barrier.
    history = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})
    assert_rows("thread/turns/list", history["thread"]["turns"], turns)
    {id, turns, items}
  end

  defp qualify_pages(pid, method, query, ascending) do
    Enum.flat_map(["asc", "desc"], fn direction ->
      ordered = if direction == "asc", do: ascending, else: Enum.reverse(ascending)
      params = Map.put(query, "sortDirection", direction)
      forward = walk_pages(pid, method, params, ordered)
      reverse_direction = if direction == "asc", do: "desc", else: "asc"

      reverse =
        forward
        |> Enum.with_index()
        |> Enum.flat_map(fn {{_method, _params, page}, index} ->
          # Backwards cursor includes the first row of its issuing page. The
          # whole preceding prefix is enumerated, not merely an overlap subset.
          prefix = ordered |> Enum.take(index * 2 + 1) |> Enum.reverse()

          back =
            Map.merge(query, %{
              "sortDirection" => reverse_direction,
              "cursor" => Map.fetch!(page, "backwardsCursor")
            })

          walk_pages(pid, method, back, prefix)
        end)

      forward ++ reverse
    end)
  end

  defp walk_pages(pid, method, query, expected) do
    chunks = Enum.chunk_every(expected, 2)

    {_query, calls} =
      chunks
      |> Enum.with_index()
      |> Enum.reduce({query, []}, fn {rows, index}, {params, calls} ->
        page = call(pid, method, params)
        assert_rows(method, Map.fetch!(page, "data"), rows)
        assert is_binary(Map.fetch!(page, "backwardsCursor"))
        next = Map.fetch!(page, "nextCursor")

        if index == length(chunks) - 1,
          do: assert(next == nil),
          else: assert(is_binary(next))

        {Map.put(params, "cursor", next), calls ++ [{method, params, page}]}
      end)

    calls
  end

  defp assert_rows("thread/items/list", actual, expected), do: assert(actual == expected)

  defp assert_rows("thread/turns/list", actual, expected) do
    assert Enum.map(actual, & &1["id"]) == Enum.map(expected, & &1.id)

    for {turn, wanted} <- Enum.zip(actual, expected) do
      assert turn["status"] == "completed"
      assert Enum.map(turn["items"], & &1["type"]) == ["userMessage", "agentMessage"]
      [user, agent] = turn["items"]
      assert Enum.any?(user["content"], &(&1["type"] == "text" and &1["text"] == wanted.text))
      assert agent["text"] == @answer
    end
  end

  defp cold_replay(ctx, pid, calls, count) do
    assert_no_execution(ctx, pid, count)
    process_id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)
    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process_id
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    for {method, params, expected} <- calls do
      assert call(cold, method, params) == expected
    end

    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_no_execution(ctx, cold, count)
    assert :ok = Session.close(cold)
  end

  defp item_events(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp assert_no_execution(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp start(ctx) do
    fixture = ctx.fixture

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
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
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
               %{"name" => "samgita_history_cursor_semantics", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
