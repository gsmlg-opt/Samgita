defmodule SamgitaCodexDriver.NativeOrganizationLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @pinned "01984de2-8f74-7c91-a3b2-5c5e937cf318"
  @missing "00000000-0000-4000-8000-000000000000"

  setup tags do
    TurnFixture.setup(tags)
  end

  test "section identity pagination and appearance patch semantics persist across restart", ctx do
    pid = start(ctx)

    first =
      create(pid, "  Work λ  ", %{"appearance" => %{"icon" => "folder", "color" => "purple"}})

    second = create(pid, "Work λ")
    assert first["name"] == "Work λ"

    assert first["id"] =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    refute first["id"] == second["id"]
    page = call(pid, "threadSection/list", %{"limit" => 0})
    assert page["data"] == [%{"id" => @pinned, "name" => "Pinned", "appearance" => nil}]
    assert page["nextCursor"] == @pinned
    ordered = Enum.sort_by([first, second], & &1["id"])
    next = call(pid, "threadSection/list", %{"cursor" => page["nextCursor"], "limit" => 1})
    assert next["data"] == [hd(ordered)]
    assert next["nextCursor"] == hd(ordered)["id"]

    assert call(pid, "threadSection/list", %{"cursor" => next["nextCursor"], "limit" => 1}) == %{
             "data" => [List.last(ordered)],
             "nextCursor" => nil
           }

    preserved = rename(pid, first["id"], "  Preserved  ")
    assert preserved == %{first | "name" => "Preserved"}
    replacement = rename(pid, first["id"], "Replacement", %{"appearance" => %{"icon" => "star"}})
    assert replacement["appearance"] == %{"icon" => "star", "color" => nil}
    cleared = rename(pid, first["id"], "Final", %{"appearance" => nil})
    assert cleared == %{first | "name" => "Final", "appearance" => nil}
    expected = sections(pid)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert sections(cold) == expected
    assert ModelFixture.requests(ctx.fixture) == []
    assert_ready(cold)
  end

  test "invalid section edits preserve catalogue and appearance limits count UTF8 bytes", ctx do
    pid = start(ctx)

    valid =
      create(pid, "Valid", %{
        "appearance" => %{
          "icon" => String.duplicate("λ", 32),
          "color" => String.duplicate("x", 64)
        }
      })

    expected = sections(pid)

    for {method, params, message} <- [
          {"threadSection/create", %{"name" => " \t\n"}, "section name must not be empty"},
          {"threadSection/update", %{"sectionId" => valid["id"], "name" => " "},
           "section name must not be empty"},
          {"threadSection/update", %{"sectionId" => " ", "name" => "Work"},
           "sectionId must not be empty"},
          {"threadSection/delete", %{"sectionId" => " "}, "sectionId must not be empty"},
          {"threadSection/update", %{"sectionId" => @pinned, "name" => "Other"},
           "the built-in pinned section cannot be renamed"},
          {"threadSection/delete", %{"sectionId" => @pinned},
           "the built-in pinned section cannot be deleted"},
          {"threadSection/update", %{"sectionId" => @missing, "name" => "Missing"},
           "thread section not found: #{@missing}"},
          {"threadSection/delete", %{"sectionId" => @missing},
           "thread section not found: #{@missing}"}
        ] do
      assert upstream_error(pid, method, params) == %{"code" => -32_602, "message" => message}
      assert sections(pid) == expected
    end

    for method <- ["threadSection/create", "threadSection/update"],
        field <- ["icon", "color"],
        value <- [String.duplicate("x", 65), String.duplicate("λ", 33)] do
      params = %{"name" => "Rejected", "appearance" => %{field => value}}

      params =
        if method == "threadSection/update",
          do: Map.put(params, "sectionId", valid["id"]),
          else: params

      assert upstream_error(pid, method, params) == %{
               "code" => -32_602,
               "message" => "section appearance #{field} must not exceed 64 bytes"
             }

      assert sections(pid) == expected
    end

    assert ModelFixture.requests(ctx.fixture) == []
    assert_ready(pid)
  end

  test "server section ordering and entry times persist while invalid moves preserve membership",
       ctx do
    pid = start(ctx)
    section = create(pid, "Ordered")
    other = create(pid, "Other")
    {first, _, _} = materialize(ctx, pid)
    {second, _, _} = materialize(ctx, pid)
    {third, _, _} = materialize(ctx, pid)
    for id <- [first, second, third], do: move(pid, id, section["id"])
    initial = members(pid, section["id"])
    assert Enum.map(initial, & &1["id"]) == [first, second, third]
    first_entered = hd(initial)["sectionEnteredAt"]
    third_entered = List.last(initial)["sectionEnteredAt"]
    refute first_entered == nil or third_entered == nil
    move(pid, third, section["id"], first)
    move(pid, first, section["id"])
    assert Enum.map(members(pid, section["id"]), & &1["id"]) == [third, second, first]
    assert read(pid, first)["thread"]["sectionEnteredAt"] == first_entered
    assert read(pid, third)["thread"]["sectionEnteredAt"] == third_entered
    before = members(pid, section["id"])

    for {params, message} <- [
          {%{"threadId" => first, "sectionId" => section["id"], "beforeThreadId" => first},
           "thread #{first} cannot be moved before itself"},
          {%{"threadId" => first, "sectionId" => other["id"], "beforeThreadId" => second},
           "before thread #{second} is not in section #{other["id"]}"},
          {%{"threadId" => first, "sectionId" => "missing-section"},
           "section missing-section does not exist"},
          {%{"threadId" => first, "sectionId" => nil, "beforeThreadId" => second},
           "beforeThreadId requires a non-null sectionId"},
          {%{"threadId" => first, "sectionId" => " "}, "sectionId must not be empty"}
        ] do
      assert upstream_error(pid, "thread/section/move", params) == %{
               "code" => -32_600,
               "message" => message
             }

      assert members(pid, section["id"]) == before
    end

    move(pid, third, nil)
    assert read(pid, third)["thread"]["section"] == nil
    assert read(pid, third)["thread"]["sectionEnteredAt"] == nil
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert Enum.map(members(cold, section["id"]), & &1["id"]) == [second, first]
    assert read(cold, first)["thread"]["sectionEnteredAt"] == first_entered
    assert read(cold, third)["thread"]["section"] == nil
    assert call(cold, "thread/loaded/list")["data"] == []
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_ready(cold)
  end

  test "section rename projects to members and deletion clears active and archived membership",
       ctx do
    pid = start(ctx)
    section = create(pid, "Before")
    {active, _, _} = materialize(ctx, pid)
    {archived, _, _} = materialize(ctx, pid)
    for id <- [active, archived], do: move(pid, id, section["id"])
    assert call(pid, "thread/archive", %{"threadId" => archived}) == %{}

    renamed =
      rename(pid, section["id"], "After", %{
        "appearance" => %{"icon" => "folder", "color" => "blue"}
      })

    assert read(pid, active)["thread"]["section"] == renamed

    assert [archived_view] =
             call(pid, "thread/list", %{"archived" => true, "limit" => 20})["data"]

    assert archived_view["id"] == archived
    assert archived_view["section"] == renamed
    assert call(pid, "threadSection/delete", %{"sectionId" => section["id"]}) == %{}
    assert_unsectioned(read(pid, active)["thread"])
    restored = call(pid, "thread/unarchive", %{"threadId" => archived})["thread"]
    assert_unsectioned(restored)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    for id <- [active, archived], do: assert_unsectioned(read(cold, id)["thread"])
    refute Enum.any?(sections(cold), &(&1["id"] == section["id"]))
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_ready(cold)
  end

  test "terminal attention preserves earliest unread while reads cold resume and revert respect history",
       ctx do
    pid = start(ctx)
    {id, first_turn, first_events} = materialize(ctx, pid, %{"historyMode" => "paginated"})
    first = read(pid, id)["readState"]
    assert first["firstUnread"] == %{"type" => "turn", "turnId" => first_turn}
    assert read_notice(first_events, id, first)
    {second_turn, second_events} = turn(pid, id)
    refute second_turn == first_turn
    latest = read(pid, id)["readState"]
    assert latest["firstUnread"] == first["firstUnread"]
    refute latest["revision"] == first["revision"]
    assert read_notice(second_events, id, latest)
    assert read(pid, id)["readState"] == latest
    assert call(pid, "thread/list", %{"limit" => 20})["readStates"] == %{id => latest}
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["readState"] == latest
    assert call(cold, "thread/loaded/list")["data"] == []
    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert read(cold, id)["readState"] == latest
    assert {:ok, replay_events} = Session.drain(cold)
    refute notification(replay_events, "thread/readState/changed", fn _ -> true end)

    assert call(cold, "thread/revert", %{"threadId" => id, "beforeTurnId" => first_turn})[
             "thread"
           ]["id"] == id

    reverted = read(cold, id)["readState"]
    assert reverted["firstUnread"] == nil
    refute reverted["revision"] == latest["revision"]
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_ready(cold)
  end

  test "competing read-state actions apply one seen revision and return the committed winner on conflict",
       ctx do
    pid = start(ctx)
    {id, _, _} = materialize(ctx, pid)
    initial = read(pid, id)["readState"]

    tasks =
      for operation <- ["read", "unread"] do
        Task.async(fn ->
          Session.request(
            pid,
            "thread/readState/update",
            read_params(id, initial["revision"], operation)
          )
        end)
      end

    results = Task.await_many(tasks, 10_000)

    assert [{:ok, %{"result" => %{"readState" => winner}}}] =
             Enum.filter(results, &match?({:ok, _}, &1))

    assert [{:error, %Error{code: :upstream_error, wire: %{"error" => conflict}}}] =
             Enum.filter(results, &match?({:error, _}, &1))

    assert conflict == conflict(winner)
    refute winner["revision"] == initial["revision"]

    for operation <- ["read", "unread"] do
      assert upstream_error(
               pid,
               "thread/readState/update",
               read_params(id, initial["revision"], operation)
             ) == conflict(winner)

      assert read(pid, id)["readState"] == winner
    end

    assert {:ok, events} = Session.drain(pid)
    assert Enum.count(events, &(&1.wire["method"] == "thread/readState/changed")) == 1
    assert read_notice(events, id, winner)
    unread = mark(pid, id, winner, "unread")
    assert unread["firstUnread"] == %{"type" => "threadStart"}
    refute unread["revision"] == winner["revision"]
    read_state = mark(pid, id, unread, "read")
    assert read_state["firstUnread"] == nil
    refute read_state["revision"] == unread["revision"]
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert read(cold, id)["readState"] == read_state

    assert upstream_error(
             cold,
             "thread/readState/update",
             read_params(id, unread["revision"], "unread")
           ) == conflict(read_state)

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_ready(cold)
  end

  test "read-state mutation persists without a subscriber and resubscription restores native notices",
       ctx do
    pid = start(ctx)
    {id, _, _} = materialize(ctx, pid)
    state = read(pid, id)["readState"]
    read_state = mark(pid, id, state, "read")
    await(pid, &read_notice(&1, id, read_state))
    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{"status" => "unsubscribed"}
    unread = mark(pid, id, read_state, "unread")
    assert unread["firstUnread"] == %{"type" => "threadStart"}
    assert read(pid, id)["readState"] == unread
    assert {:ok, unsubscribed_events} = Session.drain(pid)
    refute read_notice(unsubscribed_events, id, unread)
    assert call(pid, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    assert read(pid, id)["readState"] == unread
    final = mark(pid, id, unread, "read")
    assert final["firstUnread"] == nil
    await(pid, &read_notice(&1, id, final))
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_ready(pid)
  end

  test "stable organization remains available while read-state gates and malformed inputs retain boundaries",
       ctx do
    for negotiation <- [:absent, false] do
      pid = start(ctx, negotiation)
      section = create(pid, "Stable")
      updated = rename(pid, section["id"], "Stable renamed")
      id = TurnFixture.thread(ctx, pid)
      move(pid, id, updated["id"])
      assert read(pid, id)["thread"]["section"] == updated
      params = read_params(id, "unseen", "unread")

      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(pid, "thread/readState/update", params)

      assert upstream_error(pid, "thread/readState/update", params, validation: :wire) == %{
               "code" => -32_600,
               "message" => "thread/readState/update requires experimentalApi capability"
             }

      assert call(pid, "threadSection/delete", %{"sectionId" => updated["id"]}) == %{}
      refute Enum.any?(sections(pid), &(&1["id"] == updated["id"]))
      assert :ok = Session.close(pid)
    end

    pid = start(ctx)
    ephemeral = TurnFixture.thread(ctx, pid, %{"ephemeral" => true})

    assert upstream_error(
             pid,
             "thread/readState/update",
             read_params(ephemeral, "unseen", "unread")
           ) == %{"code" => -32_600, "message" => "thread read state unavailable"}

    for {method, params} <- [
          {"threadSection/create", %{"name" => 42}},
          {"threadSection/list", %{"limit" => -1}},
          {"threadSection/update", %{"sectionId" => @pinned}},
          {"threadSection/delete", %{"sectionId" => nil}},
          {"thread/section/move", %{"threadId" => @missing}},
          {"thread/section/move", %{"threadId" => @missing, "sectionId" => 42}},
          {"thread/readState/update",
           %{
             "threadId" => @missing,
             "expectedRevision" => "x",
             "operation" => %{"type" => "invalid"}
           }},
          {"thread/readState/update",
           %{"threadId" => @missing, "operation" => %{"type" => "read"}}}
        ] do
      assert {:error, %Error{}} = Session.request(pid, method, params)
      error = upstream_error(pid, method, params, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request: ")
    end

    assert ModelFixture.requests(ctx.fixture) == []
    assert_ready(pid)
  end

  defp start(ctx, negotiation \\ true) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_organization_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp call(pid, method, params \\ %{}), do: TurnFixture.call(pid, method, params)

  defp upstream_error(pid, method, params, opts \\ []),
    do: TurnFixture.upstream_error(pid, method, params, opts)

  defp read(pid, id), do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})

  defp create(pid, name, extra \\ %{}),
    do: call(pid, "threadSection/create", Map.merge(%{"name" => name}, extra))["section"]

  defp rename(pid, id, name, extra \\ %{}),
    do:
      call(pid, "threadSection/update", Map.merge(%{"sectionId" => id, "name" => name}, extra))[
        "section"
      ]

  defp sections(pid), do: call(pid, "threadSection/list", %{"limit" => 100})["data"]

  defp move(pid, id, section, before \\ nil),
    do:
      assert(
        call(pid, "thread/section/move", %{
          "threadId" => id,
          "sectionId" => section,
          "beforeThreadId" => before
        }) == %{}
      )

  defp members(pid, section),
    do:
      call(pid, "thread/list", %{
        "sectionId" => section,
        "sortKey" => "section_position",
        "limit" => 100
      })["data"]

  defp assert_unsectioned(thread),
    do: assert(thread["section"] == nil and thread["sectionEnteredAt"] == nil)

  defp read_params(id, revision, operation),
    do: %{"threadId" => id, "expectedRevision" => revision, "operation" => %{"type" => operation}}

  defp mark(pid, id, state, operation),
    do:
      call(pid, "thread/readState/update", read_params(id, state["revision"], operation))[
        "readState"
      ]

  defp conflict(state),
    do: %{
      "code" => -32_600,
      "message" => "read state changed",
      "data" => %{"reason" => "readStateConflict", "readState" => state}
    }

  defp materialize(ctx, pid, extra \\ %{}) do
    id = TurnFixture.thread(ctx, pid, extra)
    {turn, events} = turn(pid, id)
    {id, turn, events}
  end

  defp turn(pid, id) do
    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Synthetic organization state"}
      ])

    {turn, TurnFixture.finish_turn(pid, id, turn)}
  end

  defp read_notice(events, id, state),
    do:
      notification(
        events,
        "thread/readState/changed",
        &(&1 == %{"threadId" => id, "readState" => state})
      )

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp await(pid, predicate),
    do: await(pid, predicate, [], System.monotonic_time(:millisecond) + 15_000)

  defp await(pid, predicate, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    cond do
      predicate.(acc) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native organization notification deadline: #{inspect(acc)}")

      true ->
        assert_ready(pid)

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Native organization gap: #{inspect(gap)}")
        after
          10 -> :ok
        end

        await(pid, predicate, acc, deadline)
    end
  end

  defp assert_ready(pid),
    do: assert(%{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid))
end
