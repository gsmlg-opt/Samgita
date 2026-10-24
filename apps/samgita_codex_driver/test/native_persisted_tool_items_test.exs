defmodule SamgitaCodexDriver.NativePersistedToolItemsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, thread: 3, start_turn: 3, finish_turn: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @answer "Deterministic local fixture answer"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Fixed synthetic lookup with an explicit client response",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-persisted-tools-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "dynamic_tool")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Exit callbacks run in reverse registration order: native sessions first,
    # then confirmed provider shutdown, then deletion of the owned fixture root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  for success <- [true, false] do
    @success success
    test "persisted dynamic success=#{success} keeps exact items timestamps order and cold reads",
         ctx do
      pid = start(ctx)

      id =
        thread(ctx, pid, %{
          "historyMode" => "paginated",
          "dynamicTools" => [@lookup]
        })

      input = "Owned persisted dynamic result #{@success}: λ🙂"
      output = "Fixed synthetic tool result #{@success}: λ🙂"
      content = [%{"type" => "inputText", "text" => output}]
      turn = start_turn(pid, id, [%{"type" => "text", "text" => input}])
      {tool, events} = await_tool(pid, [], System.monotonic_time(:millisecond) + 10_000)
      assert_pending(ctx, pid, id, turn, tool)

      # Only the exact fixed native tool is answered, after all associations and
      # the generation-bound handle are checked. No generic approval is installed.
      assert :ok =
               Session.respond(
                 pid,
                 tool.handle,
                 {:ok,
                  %{
                    "success" => @success,
                    "contentItems" => content
                  }}
               )

      events = events ++ finish_turn(pid, id, turn)
      assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
      assert_turn(events, id, turn)

      for method <- ["item/started", "item/completed"] do
        assert Enum.map(item_events(events, method), & &1["item"]["type"]) ==
                 ["userMessage", "dynamicToolCall", "agentMessage"]
      end

      user = item_event(events, "item/completed", "userMessage")
      dynamic = item_event(events, "item/completed", "dynamicToolCall")
      assistant = item_event(events, "item/completed", "agentMessage")

      assert user["item"]["content"] == [
               %{"type" => "text", "text" => input, "text_elements" => []}
             ]

      assert assistant["item"]["text"] == @answer
      assert is_binary(user["item"]["id"])
      assert is_binary(assistant["item"]["id"])

      duration = dynamic["item"]["durationMs"]
      assert is_integer(duration) and duration >= 0

      expected_dynamic = %{
        "type" => "dynamicToolCall",
        "id" => "fixture-call-1",
        "namespace" => nil,
        "tool" => "fixture_lookup",
        "arguments" => %{"key" => "synthetic"},
        "status" => if(@success, do: "completed", else: "failed"),
        "contentItems" => content,
        "success" => @success,
        "durationMs" => duration
      }

      assert dynamic["item"] == expected_dynamic
      started = item_event(events, "item/started", "dynamicToolCall")

      assert started["item"] ==
               Map.merge(expected_dynamic, %{
                 "status" => "inProgress",
                 "contentItems" => nil,
                 "success" => nil,
                 "durationMs" => nil
               })

      expected =
        Enum.map([user, dynamic, assistant], fn event ->
          persisted_entry(events, id, turn, event)
        end)

      assert MapSet.size(MapSet.new(Enum.map(expected, & &1["item"]["id"]))) == 3
      requests = ModelFixture.requests(ctx.fixture)
      assert [first, continued] = requests
      assert first["model"] == "mock-model"
      assert continued["model"] == "mock-model"
      refute Enum.any?(first["input"], &(&1["type"] == "function_call_output"))

      assert [native_output] =
               Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

      assert native_output["call_id"] == "fixture-call-1"
      assert native_output["output"] == output
      assert_idle(pid)

      # This existing native read is the flush/project barrier. Do not poll the
      # history API or substitute a delay for producer/store readiness.
      hydrated = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})

      assert [%{"id" => ^turn, "status" => "completed", "items" => hydrated_items}] =
               hydrated["thread"]["turns"]

      assert hydrated_items == Enum.map(expected, & &1["item"])

      ids = Enum.map(expected, & &1["item"]["id"])
      [user_id, tool_id, assistant_id] = ids
      query = %{"threadId" => id, "turnId" => turn}
      selection = Map.put(query, "itemIds", [assistant_id, tool_id, tool_id, "owned-absent-item"])
      all = Map.put(query, "itemIds", Enum.reverse(ids))
      assert call(pid, "thread/items/read", all) == %{"data" => expected}
      assert call(pid, "thread/items/read", selection) == %{"data" => tl(expected)}

      assert call(pid, "thread/items/read", Map.put(query, "itemIds", [user_id])) ==
               %{"data" => [hd(expected)]}

      assert call(pid, "thread/items/read", Map.put(query, "itemIds", ["owned-absent-item"])) ==
               %{"data" => []}

      assert call(pid, "thread/items/read", Map.put(all, "turnId", "owned-absent-turn")) ==
               %{"data" => []}

      page_query = Map.merge(query, %{"limit" => 1, "sortDirection" => "asc"})
      assert pages(pid, page_query) == expected
      assert pages(pid, Map.put(page_query, "sortDirection", "desc")) == Enum.reverse(expected)
      first_page = call(pid, "thread/items/list", page_query)
      assert first_page["data"] == [hd(expected)]
      assert is_binary(first_page["nextCursor"])
      continuation = Map.put(page_query, "cursor", first_page["nextCursor"])
      second_page = call(pid, "thread/items/list", continuation)
      assert second_page["data"] == [Enum.at(expected, 1)]
      assert is_binary(second_page["nextCursor"])
      assert ModelFixture.requests(ctx.fixture) == requests

      native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
      assert :ok = Session.close(pid)
      cold = start(ctx)
      refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert call(cold, "thread/items/read", all) == %{"data" => expected}
      assert call(cold, "thread/items/read", selection) == %{"data" => tl(expected)}
      assert call(cold, "thread/items/list", page_query) == first_page
      assert call(cold, "thread/items/list", continuation) == second_page
      assert pages(cold, page_query) == expected
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert ModelFixture.requests(ctx.fixture) == requests
      assert_idle(cold)
      assert :ok = Session.close(cold)
    end
  end

  defp persisted_entry(events, id, turn, completed) do
    item = completed["item"]
    assert completed["threadId"] == id
    assert completed["turnId"] == turn
    started = Enum.filter(item_events(events, "item/started"), &(&1["item"]["id"] == item["id"]))
    assert [start] = started
    assert start["threadId"] == id
    assert start["turnId"] == turn
    began = Map.fetch!(start, "startedAtMs")
    ended = Map.fetch!(completed, "completedAtMs")
    assert is_integer(began) and began > 0
    assert is_integer(ended) and ended >= began

    %{"turnId" => turn, "item" => item, "startedAtMs" => began, "completedAtMs" => ended}
  end

  defp item_events(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp item_event(events, method, type) do
    assert [event] = Enum.filter(item_events(events, method), &(&1["item"]["type"] == type))
    event
  end

  defp assert_turn(events, id, turn) do
    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == id
      assert params["turn"]["id"] == turn
    end
  end

  defp pages(pid, query), do: pages(pid, query, [], MapSet.new())

  defp pages(pid, query, acc, seen) do
    page = call(pid, "thread/items/list", query)
    rows = page["data"]
    assert length(rows) <= 1
    assert length(acc) + length(rows) <= 3
    prior = MapSet.new(Enum.map(acc, & &1["item"]["id"]))
    current = MapSet.new(Enum.map(rows, & &1["item"]["id"]))
    assert MapSet.disjoint?(prior, current)

    case Map.fetch!(page, "nextCursor") do
      nil ->
        acc ++ rows

      cursor ->
        assert is_binary(cursor)
        assert rows != []
        refute MapSet.member?(seen, cursor)
        pages(pid, Map.put(query, "cursor", cursor), acc ++ rows, MapSet.put(seen, cursor))
    end
  end

  defp await_tool(pid, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    refute Enum.any?(events, &(&1.wire["method"] == "turn/completed"))

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] ->
        {tool, events}

      [] ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {:codex_driver, ^pid, :events_available} ->
            await_tool(pid, events, deadline)

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected event gap awaiting fixed native tool")
        after
          remaining -> flunk("Fixed native tool deadline")
        end

      _ ->
        flunk("Unexpected additional native interaction")
    end
  end

  defp assert_pending(ctx, pid, id, turn, tool) do
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert tool.kind == :server_request
    assert tool.wire["method"] == "item/tool/call"
    assert is_integer(tool.wire["id"]) or is_binary(tool.wire["id"])
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => id,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }
  end

  defp assert_idle(pid),
    do: assert(%{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid))

  defp start(ctx) do
    f = ctx.fixture

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
             Session.initialize(
               pid,
               %{"name" => "samgita_persisted_tool_items", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
