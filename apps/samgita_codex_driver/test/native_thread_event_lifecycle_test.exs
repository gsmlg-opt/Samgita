defmodule SamgitaCodexDriver.NativeThreadEventLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing "00000000-0000-4000-8000-000000000000"
  @script Path.expand("../../../scripts/codex/thread_event_fixture.py", __DIR__)

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    if tags[:unload_immediately] do
      config = Path.join(ctx.fixture.codex_home, "config.toml")
      File.write!(config, "thread_unload_delay_secs = 0\n" <> File.read!(config))
    end

    ctx
  end

  test "thread start emits its identified idle summary without inference", ctx do
    pid = start(ctx)
    response = call(pid, "thread/start", thread_params(ctx))
    thread = response["thread"]
    id = thread["id"]

    events =
      await(pid, fn events -> notice(events, "thread/started", &(&1["thread"]["id"] == id)) end)

    assert notice(events, "thread/started")["thread"] == thread
    assert thread["cwd"] == ctx.fixture.workspace
    assert thread["modelProvider"] == "fixture"
    assert thread["ephemeral"] == false
    assert thread["status"] == %{"type" => "idle"}
    assert thread["turns"] == []
    assert is_binary(id) and id != ""
    assert is_integer(thread["createdAt"]) and thread["createdAt"] > 0
    assert is_integer(thread["updatedAt"]) and thread["updatedAt"] >= thread["createdAt"]
    assert response["cwd"] == ctx.fixture.workspace
    assert response["model"] == "mock-model"
    assert response["modelProvider"] == "fixture"
    assert ModelFixture.requests(ctx.fixture) == []
    assert_idle(pid)
  end

  test "native streaming retains event identities order timing usage and terminal summary", ctx do
    pid = start(ctx)
    {id, _started} = thread(ctx, pid)
    turn = start_turn(pid, id, "Owned event sequence")
    events = finish(pid, id, turn)
    text = expected_text(ctx, id)
    assert_stream(events, id, turn, text)

    assert statuses(events, id) == [
             %{"type" => "active", "activeFlags" => []},
             %{"type" => "idle"}
           ]

    assert index(events, "thread/status/changed", &(&1["status"]["type"] == "active")) <
             index(events, "turn/started")

    assert index(events, "thread/status/changed", &(&1["status"]["type"] == "idle")) <
             index(events, "turn/completed")

    started = notice(events, "turn/started")["turn"]
    completed = notice(events, "turn/completed")["turn"]
    assert started["status"] == "inProgress"
    assert started["items"] == []
    assert started["itemsView"] == "notLoaded"
    assert started["error"] == nil
    assert completed["status"] == "completed"
    assert completed["error"] == nil
    assert completed["itemsView"] == "summary"
    assert [%{"type" => "agentMessage", "text" => ^text}] = completed["items"]
    assert is_integer(started["startedAt"]) and started["startedAt"] > 0
    assert completed["startedAt"] == started["startedAt"]
    assert is_integer(completed["completedAt"])
    assert completed["completedAt"] >= started["startedAt"]
    assert is_integer(completed["durationMs"]) and completed["durationMs"] >= 0

    usage = notice(events, "thread/tokenUsage/updated", &(&1["turnId"] == turn))
    assert usage["threadId"] == id

    expected = %{
      "inputTokens" => 7,
      "cachedInputTokens" => 3,
      "cacheWriteInputTokens" => 0,
      "outputTokens" => 11,
      "reasoningOutputTokens" => 2,
      "totalTokens" => 18
    }

    assert usage["tokenUsage"]["last"] == expected
    assert usage["tokenUsage"]["total"] == expected
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_idle(pid)
  end

  test "two native threads retain separate item delta status and terminal associations", ctx do
    pid = start(ctx)
    {first, _events} = thread(ctx, pid)
    {second, _events} = thread(ctx, pid)
    one = start_turn(pid, first, "Owned first thread")
    two = start_turn(pid, second, "Owned second thread")

    events =
      await(pid, fn events ->
        not is_nil(terminal(events, first, one)) and not is_nil(terminal(events, second, two))
      end)

    assert_stream(events, first, one, expected_text(ctx, first))
    assert_stream(events, second, two, expected_text(ctx, second))
    refute expected_text(ctx, first) == expected_text(ctx, second)

    assert Enum.uniq(Enum.map(notices(events, "turn/completed"), & &1["threadId"])) |> Enum.sort() ==
             Enum.sort([first, second])

    for {id, turn} <- [{first, one}, {second, two}] do
      assert statuses(events, id) == [
               %{"type" => "active", "activeFlags" => []},
               %{"type" => "idle"}
             ]

      read = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
      assert [%{"id" => ^turn, "items" => items}] = read["turns"]
      assert Enum.find(items, &(&1["type"] == "agentMessage"))["text"] == expected_text(ctx, id)
    end

    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_idle(pid)
  end

  test "normalized name notices persist while rejected metadata commands cannot fabricate success",
       ctx do
    pid = start(ctx)
    {id, _events} = thread(ctx, pid)
    turn = start_turn(pid, id, "Owned persisted naming")
    finish(pid, id, turn)
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => "  Owned é🙂  "}) == %{}

    first =
      await(pid, fn events ->
        notice(events, "thread/name/updated", &(&1["threadName"] == "Owned é🙂"))
      end)

    assert notice(first, "thread/name/updated") == %{"threadId" => id, "threadName" => "Owned é🙂"}

    for {method, params} <- [
          {"thread/name/set", %{"threadId" => id, "name" => " \n "}},
          {"thread/name/set", %{"threadId" => @missing, "name" => "Rejected"}},
          {"thread/archive", %{"threadId" => @missing}},
          {"thread/unarchive", %{"threadId" => @missing}},
          {"thread/delete", %{"threadId" => @missing}}
        ] do
      assert upstream_error(pid, method, params)["code"] < 0
    end

    # A successful serial name command is a concrete observation barrier.
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => "Owned after errors"}) ==
             %{}

    after_errors =
      await(pid, fn events ->
        notice(events, "thread/name/updated", &(&1["threadName"] == "Owned after errors"))
      end)

    assert notices(after_errors, "thread/name/updated") == [
             %{"threadId" => id, "threadName" => "Owned after errors"}
           ]

    for method <- ["thread/archived", "thread/unarchived", "thread/deleted"] do
      assert notices(after_errors, method) == []
    end

    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["name"] == "Owned after errors"
    requests = ModelFixture.requests(ctx.fixture)
    assert :ok = Session.close(pid)
    cold = start(ctx)

    assert call(cold, "thread/read", %{"threadId" => id})["thread"]["name"] ==
             "Owned after errors"

    assert ModelFixture.requests(ctx.fixture) == requests
    assert_idle(cold)
  end

  test "archive unarchive and deletion emit exact identities after their distinct transitions",
       ctx do
    pid = start(ctx)
    {id, _events} = thread(ctx, pid)
    turn = start_turn(pid, id, "Owned event persistence")
    finish(pid, id, turn)
    assert call(pid, "thread/archive", %{"threadId" => id}) == %{}

    archived =
      await(pid, fn events -> notice(events, "thread/archived", &(&1["threadId"] == id)) end)

    assert notices(archived, "thread/archived") == [%{"threadId" => id}]
    restored = call(pid, "thread/unarchive", %{"threadId" => id})["thread"]
    assert restored["id"] == id

    unarchived =
      await(pid, fn events -> notice(events, "thread/unarchived", &(&1["threadId"] == id)) end)

    assert notices(unarchived, "thread/unarchived") == [%{"threadId" => id}]
    assert call(pid, "thread/delete", %{"threadId" => id}) == %{}

    deleted =
      await(pid, fn events -> notice(events, "thread/deleted", &(&1["threadId"] == id)) end)

    assert notices(deleted, "thread/deleted") == [%{"threadId" => id}]
    assert upstream_error(pid, "thread/read", %{"threadId" => id})["message"] =~ id
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_idle(pid)
  end

  @tag unload_immediately: true
  test "configured idle eviction emits closed independently of unsubscribe acknowledgement",
       ctx do
    pid = start(ctx)
    {id, _events} = thread(ctx, pid)
    turn = start_turn(pid, id, "Owned unload lifecycle")
    finish(pid, id, turn)
    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{"status" => "unsubscribed"}
    events = await(pid, fn events -> notice(events, "thread/closed", &(&1["threadId"] == id)) end)
    assert notices(events, "thread/closed") == [%{"threadId" => id}]

    assert %{"threadId" => id, "status" => %{"type" => "notLoaded"}} in notices(
             events,
             "thread/status/changed"
           )

    refute id in call(pid, "thread/loaded/list", %{})["data"]
    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{"status" => "notLoaded"}

    assert call(pid, "thread/unsubscribe", %{"threadId" => @missing}) == %{
             "status" => "notLoaded"
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_idle(pid)
  end

  test "cold resume restores state and usage without replaying old lifecycle or running inference",
       ctx do
    pid = start(ctx)
    {id, _events} = thread(ctx, pid)
    turn = start_turn(pid, id, "Owned recovered history")
    original_events = finish(pid, id, turn)
    text = expected_text(ctx, id)
    assert_stream(original_events, id, turn, text)
    requests = ModelFixture.requests(ctx.fixture)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    resumed = call(cold, "thread/resume", %{"threadId" => id})["thread"]
    assert resumed["id"] == id

    assert call(cold, "thread/name/set", %{"threadId" => id, "name" => "Owned recovery barrier"}) ==
             %{}

    events =
      await(cold, fn events ->
        notice(events, "thread/name/updated", &(&1["threadName"] == "Owned recovery barrier"))
      end)

    assert [%{"id" => ^turn}] = resumed["turns"]

    assert notice(events, "thread/tokenUsage/updated", &(&1["turnId"] == turn))["tokenUsage"] ==
             notice(original_events, "thread/tokenUsage/updated", &(&1["turnId"] == turn))[
               "tokenUsage"
             ]

    for method <- [
          "thread/started",
          "turn/started",
          "turn/completed",
          "item/started",
          "item/completed",
          "item/agentMessage/delta"
        ] do
      assert notices(events, method) == []
    end

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             call(cold, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert Enum.find(items, &(&1["type"] == "agentMessage"))["text"] == text
    assert ModelFixture.requests(ctx.fixture) == requests
    assert_idle(cold)
  end

  test "exact opt out suppresses only its named notices and does not persist into another initialization",
       ctx do
    muted = start(ctx, ["item/agentMessage/delta"])
    {id, _events} = thread(ctx, muted)
    first = start_turn(muted, id, "Owned muted streaming")
    muted_events = finish(muted, id, first)
    assert notices(muted_events, "item/agentMessage/delta") == []

    assert notice(muted_events, "item/completed", &(&1["item"]["type"] == "agentMessage"))["item"][
             "text"
           ] ==
             expected_text(ctx, id)

    assert notice(muted_events, "turn/started")["threadId"] == id
    assert :ok = Session.close(muted)

    # The prefix is deliberately not the exact wire method.
    prefix = start(ctx, ["item/agentMessage"])
    call(prefix, "thread/resume", %{"threadId" => id})
    second = start_turn(prefix, id, "Owned exact-name control")
    events = finish(prefix, id, second)
    assert_stream(events, id, second, expected_text(ctx, id))
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_idle(prefix)
  end

  defp start(ctx, opt_out \\ []) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off",
               "NO_COLOR" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_thread_event_fixture", "version" => "0.1.0"},
               %{"experimentalApi" => true, "optOutNotificationMethods" => opt_out}
             )

    pid
  end

  defp thread_params(ctx) do
    %{
      "cwd" => ctx.fixture.workspace,
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false
    }
  end

  defp thread(ctx, pid) do
    id = call(pid, "thread/start", thread_params(ctx))["thread"]["id"]

    events =
      await(pid, fn events -> notice(events, "thread/started", &(&1["thread"]["id"] == id)) end)

    {id, events}
  end

  defp start_turn(pid, id, text) do
    TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
  end

  defp finish(pid, id, turn), do: await(pid, &terminal(&1, id, turn))

  defp terminal(events, id, turn) do
    notice(events, "turn/completed", &(&1["threadId"] == id and &1["turn"]["id"] == turn))
  end

  defp expected_text(ctx, id) do
    {_request, index} =
      ctx.fixture
      |> ModelFixture.requests()
      |> Enum.with_index(1)
      |> Enum.filter(fn {request, _} ->
        metadata = request["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
        metadata["thread_id"] == id
      end)
      |> List.last()

    "Owned stream #{index} é🙂\nDone."
  end

  defp assert_stream(events, id, turn, text) do
    started =
      notice(
        events,
        "item/started",
        &(&1["threadId"] == id and &1["turnId"] == turn and
            &1["item"]["type"] == "agentMessage")
      )

    completed =
      notice(
        events,
        "item/completed",
        &(&1["threadId"] == id and &1["turnId"] == turn and
            &1["item"]["type"] == "agentMessage")
      )

    item = completed["item"]["id"]
    assert started["item"]["id"] == item
    deltas = notices(events, "item/agentMessage/delta") |> Enum.filter(&(&1["turnId"] == turn))
    assert Enum.all?(deltas, &(&1["threadId"] == id and &1["itemId"] == item))
    assert Enum.map_join(deltas, & &1["delta"]) == text
    assert length(deltas) == 5

    assert Enum.map(deltas, & &1["delta"]) == [
             "Owned stream ",
             Enum.at(String.split(text, " "), 2),
             " é",
             "🙂",
             "\nDone."
           ]

    assert completed["item"]["text"] == text
    assert is_integer(started["startedAtMs"]) and started["startedAtMs"] > 0
    assert is_integer(completed["completedAtMs"])
    assert completed["completedAtMs"] >= started["startedAtMs"]
    assert_stream_order(events, id, turn, item)
  end

  defp assert_stream_order(events, id, turn, item) do
    scoped =
      Enum.filter(events, fn event ->
        params = event.wire["params"] || %{}

        params["threadId"] == id and
          (params["turnId"] == turn or params["turn"]["id"] == turn)
      end)

    assert index(scoped, "turn/started") <
             index(scoped, "item/started", &(&1["item"]["id"] == item))

    assert index(scoped, "item/started", &(&1["item"]["id"] == item)) <
             index(scoped, "item/agentMessage/delta")

    assert index(scoped, "item/agentMessage/delta", fn _ -> true end, :last) <
             index(scoped, "item/completed", &(&1["item"]["id"] == item))

    assert index(scoped, "item/completed", &(&1["item"]["id"] == item)) <
             index(scoped, "turn/completed")
  end

  defp statuses(events, id) do
    notices(events, "thread/status/changed")
    |> Enum.filter(&(&1["threadId"] == id))
    |> Enum.map(& &1["status"])
  end

  defp index(events, method, predicate \\ fn _ -> true end, position \\ :first) do
    indices =
      for {event, i} <- Enum.with_index(events),
          event.wire["method"] == method and predicate.(event.wire["params"]),
          do: i

    result = if position == :last, do: List.last(indices), else: List.first(indices)
    assert is_integer(result), "Missing ordered #{method}"
    result
  end

  defp notices(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp notice(events, method, predicate \\ fn _ -> true end) do
    Enum.find(notices(events, method), predicate)
  end

  defp await(pid, predicate, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch

    if predicate.(events) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Native event deadline: #{inspect(events)}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native event gap")
      after
        20 -> :ok
      end

      await(pid, predicate, events, deadline)
    end
  end

  defp assert_idle(pid),
    do: assert(%{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid))
end
