defmodule SamgitaCodexDriver.ThreadSearchTimelineTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    TurnFixture.setup(tags)
  end

  test "content search preserves escaped Unicode literals through filters pagination and cold reads",
       ctx do
    pid = TurnFixture.start(ctx)
    literal = ~S(quoted "needle" \ path é🙂)

    rows =
      for prefix <- ["first", "second", "unrelated"] do
        id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
        text = if prefix == "unrelated", do: "no matching content", else: "#{prefix} #{literal}"
        complete(ctx, pid, id, text)
        {id, text}
      end

    expected = rows |> Enum.take(2) |> Map.new()
    params = %{"searchTerm" => literal, "sortKey" => "recency_at", "sortDirection" => "desc"}
    full = rpc(pid, "thread/search", params)
    assert length(full["data"]) == 2
    assert Map.new(search_rows(full["data"])) == expected
    assert full["nextCursor"] == nil
    assert is_binary(full["backwardsCursor"])
    assert Enum.all?(full["data"], &(&1["thread"]["source"] == "vscode"))

    paged = pages(pid, "thread/search", Map.put(params, "limit", 1))
    assert search_rows(paged) == search_rows(full["data"])
    assert length(Enum.uniq_by(paged, & &1["thread"]["id"])) == 2

    assert search_rows(
             rpc(pid, "thread/search", Map.put(params, "sourceKinds", ["vscode"]))["data"]
           ) == search_rows(full["data"])

    assert rpc(pid, "thread/search", Map.put(params, "sourceKinds", ["exec"]))["data"] == []
    [{archived, archived_text} | _] = rows
    assert rpc(pid, "thread/archive", %{"threadId" => archived}) == %{}

    assert search_rows(rpc(pid, "thread/search", params)["data"]) ==
             Enum.reject(search_rows(full["data"]), &(elem(&1, 0) == archived))

    archive_params = Map.put(params, "archived", true)

    assert search_rows(rpc(pid, "thread/search", archive_params)["data"]) == [
             {archived, archived_text}
           ]

    assert :ok = Session.close(pid)
    cold = TurnFixture.start(ctx)

    assert search_rows(rpc(cold, "thread/search", archive_params)["data"]) == [
             {archived, archived_text}
           ]

    assert Map.new(search_rows(rpc(cold, "thread/search", params)["data"])) ==
             Map.delete(expected, archived)

    assert_model_count(ctx, 3)
  end

  test "occurrence pages retain UTF16 ranges item identity and inclusive turn cursors across restart",
       ctx do
    pid = TurnFixture.start(ctx)
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    text = "😀 Needle needle NEEDLE"
    turn = complete(ctx, pid, id, text)
    params = %{"threadId" => id, "searchTerm" => "needle", "limit" => 1}
    first = rpc(pid, "thread/searchOccurrences", params)
    assert length(first["data"]) == 1
    assert is_binary(first["nextCursor"])
    full = pages(pid, "thread/searchOccurrences", params)
    assert length(full) == 3

    assert Enum.map(full, & &1["snippetMatchRange"]) == [
             %{"start" => 3, "end" => 9},
             %{"start" => 10, "end" => 16},
             %{"start" => 17, "end" => 23}
           ]

    for occurrence <- full do
      assert occurrence["turnId"] == turn.id
      assert occurrence["itemId"] == turn.user
      assert occurrence["snippet"] == text
      assert is_binary(occurrence["turnCursor"])

      page =
        rpc(pid, "thread/turns/list", %{
          "threadId" => id,
          "cursor" => occurrence["turnCursor"],
          "limit" => 1,
          "sortDirection" => "asc",
          "itemsView" => "full"
        })

      assert [%{"id" => turn_id, "items" => items}] = page["data"]
      assert turn_id == turn.id
      assert Enum.any?(items, &(&1["id"] == turn.user))
    end

    continuation = Map.put(params, "cursor", first["nextCursor"])
    expected = rpc(pid, "thread/searchOccurrences", continuation)
    assert :ok = Session.close(pid)
    cold = TurnFixture.start(ctx)
    assert rpc(cold, "thread/searchOccurrences", continuation) == expected
    assert pages(cold, "thread/searchOccurrences", params) == full
    assert_model_count(ctx, 1)
  end

  test "history cursors reject malformed cross-thread and cross-query reuse without changing state",
       ctx do
    pid = TurnFixture.start(ctx)
    first_id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    second_id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    complete(ctx, pid, first_id, "cursor needle needle")
    complete(ctx, pid, second_id, "second needle")
    params = %{"threadId" => first_id, "searchTerm" => "needle", "limit" => 0}
    first = rpc(pid, "thread/searchOccurrences", params)
    assert length(first["data"]) == 1
    cursor = first["nextCursor"]
    assert is_binary(cursor)

    for changes <- [
          %{"cursor" => "not-json"},
          %{"cursor" => cursor, "threadId" => second_id},
          %{"cursor" => cursor, "searchTerm" => "NEEDLE"}
        ] do
      supplied = changes["cursor"]

      assert rpc_error(pid, "thread/searchOccurrences", Map.merge(params, changes)) == %{
               "code" => -32_600,
               "message" => "invalid cursor: #{supplied}"
             }
    end

    assert rpc_error(pid, "thread/search", %{"searchTerm" => " \n "}) == %{
             "code" => -32_600,
             "message" => "thread/search requires a non-empty searchTerm"
           }

    assert rpc_error(pid, "thread/search", %{"searchTerm" => "needle", "cursor" => "bad"}) == %{
             "code" => -32_600,
             "message" => "invalid cursor: bad"
           }

    assert rpc_error(pid, "thread/searchOccurrences", Map.put(params, "searchTerm", " \n ")) == %{
             "code" => -32_600,
             "message" => "thread/searchOccurrences requires a non-empty searchTerm"
           }

    assert rpc(pid, "thread/searchOccurrences", Map.put(params, "searchTerm", "not-present")) ==
             %{
               "data" => [],
               "nextCursor" => nil
             }

    timeline = rpc(pid, "thread/timeline/list", %{"threadId" => first_id, "limit" => 1})
    assert is_binary(timeline["nextCursor"])

    assert rpc_error(pid, "thread/timeline/list", %{"threadId" => first_id, "cursor" => "bad"}) ==
             %{
               "code" => -32_600,
               "message" => "invalid thread timeline cursor"
             }

    assert rpc_error(pid, "thread/timeline/list", %{
             "threadId" => second_id,
             "cursor" => timeline["nextCursor"]
           }) == %{
             "code" => -32_600,
             "message" => "thread timeline cursor belongs to another thread"
           }

    assert rpc(pid, "thread/searchOccurrences", params) == first
    assert_model_count(ctx, 2)
  end

  test "timeline pages preserve ordinary item and turn boundaries and cold continuation", ctx do
    pid = TurnFixture.start(ctx)
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    turns = for text <- ["timeline first", "timeline second"], do: complete(ctx, pid, id, text)
    params = %{"threadId" => id, "limit" => 100}
    full = rpc(pid, "thread/timeline/list", params)
    assert full["nextCursor"] == nil
    assert full["activeRealtimeSessionAtPageStart"] == nil

    assert Enum.map(full["data"], & &1["type"]) ==
             List.duplicate(["turnStarted", "item", "item", "turnCompleted"], 2) |> List.flatten()

    for {turn, entries} <- Enum.zip(turns, Enum.chunk_every(full["data"], 4)) do
      assert Enum.all?(entries, &(&1["turnId"] == turn.id))
      [started, user, assistant, finished] = entries
      assert user["item"]["id"] == turn.user
      assert user["item"]["type"] == "userMessage"
      assert assistant["item"]["id"] == turn.assistant
      assert assistant["item"]["text"] == "Deterministic local fixture answer"
      assert finished["status"] == "completed"
      assert finished["error"] == nil
      assert is_integer(started["startedAt"])
      assert is_integer(finished["completedAt"])
      assert is_integer(finished["durationMs"]) and finished["durationMs"] >= 0
    end

    positions = Enum.map(full["data"], & &1["position"])
    assert positions == Enum.sort(positions)

    assert pages(pid, "thread/timeline/list", Map.put(params, "limit", 3), :prepend) ==
             full["data"]

    clamped = rpc(pid, "thread/timeline/list", Map.put(params, "limit", 0))
    assert clamped["data"] == [List.last(full["data"])]
    assert is_binary(clamped["nextCursor"])
    continuation = Map.merge(params, %{"limit" => 3, "cursor" => clamped["nextCursor"]})
    older = rpc(pid, "thread/timeline/list", continuation)
    assert :ok = Session.close(pid)
    cold = TurnFixture.start(ctx)
    assert rpc(cold, "thread/timeline/list", continuation) == older
    assert rpc(cold, "thread/timeline/list", params) == full
    assert_model_count(ctx, 2)
  end

  test "fork search and timeline preserve inherited prefixes after parent divergence and revert",
       ctx do
    pid = TurnFixture.start(ctx)
    parent = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    prefix = complete(ctx, pid, parent, "prefix needle")
    fork = rpc(pid, "thread/fork", %{"threadId" => parent, "lastTurnId" => prefix.id})["thread"]
    child = fork["id"]
    assert child != parent
    assert fork["forkedFromId"] == parent
    excluded = complete(ctx, pid, parent, "excluded parent needle")
    own = complete(ctx, pid, child, "child needle")
    params = %{"threadId" => child, "searchTerm" => "needle", "limit" => 1}
    occurrences = pages(pid, "thread/searchOccurrences", params)
    assert Enum.map(occurrences, & &1["turnId"]) == [prefix.id, own.id]
    assert Enum.map(occurrences, & &1["itemId"]) == [prefix.user, own.user]
    refute Enum.any?(occurrences, &String.contains?(&1["snippet"], "excluded parent"))
    timeline_params = %{"threadId" => child, "limit" => 100}
    timeline = rpc(pid, "thread/timeline/list", timeline_params)
    assert timeline["data"] |> Enum.map(& &1["turnId"]) |> Enum.uniq() == [prefix.id, own.id]
    refute Enum.any?(timeline["data"], &(&1["turnId"] == excluded.id))

    assert rpc(pid, "thread/revert", %{"threadId" => parent, "beforeTurnId" => excluded.id})[
             "thread"
           ]["id"] == parent

    assert pages(pid, "thread/searchOccurrences", params) == occurrences
    assert rpc(pid, "thread/timeline/list", timeline_params) == timeline
    remaining = pages(pid, "thread/searchOccurrences", Map.put(params, "threadId", parent))
    assert Enum.map(remaining, & &1["turnId"]) == [prefix.id]
    assert_model_count(ctx, 3)
  end

  test "experimental and storage boundaries reject unsupported reads while archived occurrences remain readable",
       ctx do
    disabled = TurnFixture.start(ctx, experimental: false)
    missing = "67e55044-10b1-426f-9247-bb680e5fe0c8"

    for {method, params} <- [
          {"thread/search", %{"searchTerm" => "needle"}},
          {"thread/searchOccurrences", %{"threadId" => missing, "searchTerm" => "needle"}},
          {"thread/timeline/list", %{"threadId" => missing}}
        ] do
      assert rpc_error(disabled, method, params, validation: :wire) == %{
               "code" => -32_600,
               "message" => "#{method} requires experimentalApi capability"
             }
    end

    assert_model_count(ctx, 0)
    assert :ok = Session.close(disabled)
    pid = TurnFixture.start(ctx)
    legacy = TurnFixture.thread(ctx, pid, %{"historyMode" => "legacy"})
    complete(ctx, pid, legacy, "legacy-boundary needle")

    for {method, extra} <- [
          {"thread/searchOccurrences", %{"searchTerm" => "needle"}},
          {"thread/timeline/list", %{}}
        ] do
      assert rpc_error(pid, method, Map.put(extra, "threadId", legacy)) == %{
               "code" => -32_601,
               "message" => "#{method} is not supported yet"
             }
    end

    assert [%{"thread" => %{"id" => ^legacy}, "snippet" => "legacy-boundary needle"}] =
             rpc(pid, "thread/search", %{"searchTerm" => "legacy-boundary"})["data"]

    archived = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    complete(ctx, pid, archived, "archived needle")
    params = %{"threadId" => archived, "searchTerm" => "needle"}
    before_archive = rpc(pid, "thread/searchOccurrences", params)
    assert length(before_archive["data"]) == 1
    assert rpc(pid, "thread/archive", %{"threadId" => archived}) == %{}
    assert rpc(pid, "thread/searchOccurrences", params) == before_archive

    assert rpc_error(pid, "thread/timeline/list", %{"threadId" => archived}) == %{
             "code" => -32_600,
             "message" => "thread #{archived} is archived"
           }

    assert_model_count(ctx, 2)
  end

  defp complete(ctx, pid, id, text) do
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, id, turn)

    user =
      TurnFixture.notification(events, "item/completed", &(&1["item"]["type"] == "userMessage"))

    assistant =
      TurnFixture.notification(events, "item/completed", &(&1["item"]["type"] == "agentMessage"))

    assert user["threadId"] == id and user["turnId"] == turn
    assert assistant["threadId"] == id and assistant["turnId"] == turn

    # Native includeTurns waits for persist_thread/write_and_project on paginated
    # history; legacy history uses load_history. This is a read/flush barrier,
    # not polling an index until a desired query happens to succeed.
    history = rpc(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert Enum.any?(history["turns"], &(&1["id"] == turn and &1["status"] == "completed"))
    assert is_list(ModelFixture.requests(ctx.fixture))
    %{id: turn, user: user["item"]["id"], assistant: assistant["item"]["id"]}
  end

  defp pages(pid, method, params, direction \\ :append) do
    walk_pages(pid, method, params, direction, [], MapSet.new(), 0)
  end

  defp walk_pages(pid, method, params, direction, acc, cursors, count) do
    assert count < 20, "native pagination must terminate within the bounded fixture history"
    page = rpc(pid, method, params)
    data = page["data"]
    assert is_list(data)
    acc = if direction == :prepend, do: data ++ acc, else: acc ++ data

    case page["nextCursor"] do
      nil ->
        acc

      cursor ->
        assert is_binary(cursor) and cursor != ""
        refute MapSet.member?(cursors, cursor), "native cursor must advance"

        walk_pages(
          pid,
          method,
          Map.put(params, "cursor", cursor),
          direction,
          acc,
          MapSet.put(cursors, cursor),
          count + 1
        )
    end
  end

  defp search_rows(rows), do: Enum.map(rows, &{&1["thread"]["id"], &1["snippet"]})

  defp rpc(pid, method, params) do
    id = "history-request-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    result
  end

  defp rpc_error(pid, method, params, opts \\ []) do
    id = System.unique_integer([:positive])

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request_native(
               pid,
               %{"id" => id, "method" => method, "params" => params},
               opts
             )

    error
  end

  defp assert_model_count(ctx, expected),
    do: assert(length(ModelFixture.requests(ctx.fixture)) == expected)
end
