defmodule SamgitaCodexDriver.NativeTextSpanHistoryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  test "native persisted user spans retain UTF-8 byte ranges and distinct placeholders", ctx do
    pid = start(ctx)
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    text = "é🙂xλ"
    assert byte_size(text) == 9
    assert String.length(text) == 4

    elements = [
      %{"byteRange" => %{"start" => 0, "end" => 2}, "placeholder" => "accent λ"},
      %{"byteRange" => %{"start" => 2, "end" => 6}},
      %{"byteRange" => %{"start" => 6, "end" => 7}, "placeholder" => nil},
      %{"byteRange" => %{"start" => 7, "end" => 9}, "placeholder" => ""}
    ]

    assert Enum.map(elements, fn element ->
             %{"start" => first, "end" => last} = element["byteRange"]
             binary_part(text, first, last - first)
           end) == ["é", "🙂", "x", "λ"]

    # Input omission and explicit null are distinct requests. Native output
    # canonicalizes both to null while preserving nonempty and empty strings.
    refute Map.has_key?(Enum.at(elements, 1), "placeholder")
    assert Map.fetch!(Enum.at(elements, 2), "placeholder") == nil
    assert Map.fetch!(Enum.at(elements, 3), "placeholder") == ""
    input = %{"type" => "text", "text" => text, "text_elements" => elements}

    expected =
      Map.put(input, "text_elements", Enum.map(elements, &Map.put_new(&1, "placeholder", nil)))

    client_id = "owned-span-client-λ"

    turn =
      TurnFixture.start_turn(pid, id, [input], %{"clientUserMessageId" => client_id})

    events = TurnFixture.finish_turn(pid, id, turn)
    completed = user_event(events, "item/completed")
    item_id = completed["item"]["id"]
    assert is_binary(item_id)

    wanted_item = %{
      "type" => "userMessage",
      "id" => item_id,
      "clientId" => client_id,
      "content" => [expected]
    }

    for method <- ["item/started", "item/completed"] do
      event = user_event(events, method)
      assert event["threadId"] == id
      assert event["turnId"] == turn
      assert event["item"] == wanted_item
    end

    entry = persisted_entry(events, turn, wanted_item)
    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [item_id]}
    assert_history_user(pid, id, turn, wanted_item)
    assert call(pid, "thread/items/read", query) == %{"data" => [entry]}
    [request] = ModelFixture.requests(ctx.fixture)
    assert %{"type" => "input_text", "text" => text} in TurnFixture.provider_content(ctx.fixture)
    refute JSON.encode!(request) =~ "text_elements"
    assert_idle(pid)

    process_id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)
    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process_id
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_history_user(cold, id, turn, wanted_item)
    assert call(cold, "thread/items/read", query) == %{"data" => [entry]}
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == [request]
    assert_idle(cold)
    assert :ok = Session.close(cold)
  end

  test "native malformed span types preserve existing history and do not sample again", ctx do
    pid = start(ctx)
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => "Owned span baseline"}])
    events = TurnFixture.finish_turn(pid, id, turn)
    user = user_event(events, "item/completed")["item"]
    assert_history_user(pid, id, turn, user)
    history_query = %{"threadId" => id, "includeTurns" => true}
    history = call(pid, "thread/read", history_query)
    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [user["id"]]}
    original = call(pid, "thread/items/read", query)
    assert original == %{"data" => [persisted_entry(events, turn, user)]}
    [request] = ModelFixture.requests(ctx.fixture)

    for malformed <- [
          nil,
          [%{"byteRange" => nil}],
          [%{"byteRange" => %{"start" => 0}}],
          [%{"byteRange" => %{"start" => -1, "end" => 1}}],
          [%{"byteRange" => %{"start" => 0, "end" => "one"}}],
          [%{"byteRange" => %{"start" => 0, "end" => 1}, "placeholder" => 42}]
        ] do
      error =
        upstream_error(
          pid,
          "turn/start",
          %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => "x", "text_elements" => malformed}]
          },
          validation: :wire
        )

      assert error["code"] == -32_600
      assert error["message"] =~ "Invalid request"
      assert call(pid, "thread/read", history_query) == history
      assert call(pid, "thread/items/read", query) == original
      assert ModelFixture.requests(ctx.fixture) == [request]
      assert_idle(pid)
    end

    assert :ok = Session.close(pid)
  end

  defp assert_history_user(pid, id, turn, item) do
    read = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             read["thread"]["turns"]

    assert [actual] = Enum.filter(items, &(&1["type"] == "userMessage"))
    assert actual == item
  end

  defp persisted_entry(events, turn, item) do
    began = user_event(events, "item/started")
    ended = user_event(events, "item/completed")
    started = Map.fetch!(began, "startedAtMs")
    completed = Map.fetch!(ended, "completedAtMs")
    assert is_integer(started) and started > 0
    assert is_integer(completed) and completed >= started
    %{"turnId" => turn, "item" => item, "startedAtMs" => started, "completedAtMs" => completed}
  end

  defp user_event(events, method) do
    assert [event] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["type"] == "userMessage",
               do: event.wire["params"]
             )

    event
  end

  defp assert_idle(pid) do
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
               %{"name" => "samgita_text_span_history", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
