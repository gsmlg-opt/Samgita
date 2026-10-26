defmodule SamgitaCodexDriver.NativeReviewSourceValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @needle "Owned genuine Review source discovery 163 λ"
  @review_prompt "Review this inert fixture text: " <> @needle
  @control_prompt "Driver control: " <> @needle
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary Review source control instructions."
  @review_source %{"subagent" => "review"}
  @review_public_source %{"subAgent" => "review"}
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144
  @projection ~w(id source preview cwd modelProvider path historyMode turns sessionId parentThreadId forkedFromId threadSource)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 1024 and size <= 262_144 and ledger.bytes + size <= 8_388_608 do
          entry = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    binary = Path.expand(binary)
    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-review-source-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture}

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(fixture.bin, "rg"))
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    sources = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    assert requests(ctx) == []
    Map.put(ctx, :inputs, Map.new(sources, &{&1, bounded_file(&1)}))
  end

  test "genuine inline Custom Review child keeps exact positive source discovery through cold reads",
       ctx do
    producer = start(ctx)
    producer_native = native_id(ctx, producer)
    parent = produce_control(ctx, producer)
    ctx = Map.put(ctx, :parent, parent.id)
    assert length(requests(ctx)) == 1

    response =
      call(ctx, producer, "review/start", %{
        "threadId" => parent.id,
        "target" => %{"type" => "custom", "instructions" => @review_prompt},
        "delivery" => "inline"
      })

    # Inline response identifies the parent review turn, never the internal
    # delegate. That separate native identity comes from the second real request.
    assert response["reviewThreadId"] === parent.id
    review_turn = response["turn"]["id"]
    assert is_binary(review_turn) and review_turn != "" and review_turn != parent.turn
    events = complete_turn(producer, parent.id, review_turn, [], now() + 20_000)
    assert_review_lifecycle(events, parent.id, review_turn)
    child_identity = provider_identity(ctx, 2, @review_prompt)
    refute child_identity.thread == parent.id
    refute child_identity.turn in [parent.turn, review_turn]
    child_metadata = child_identity.metadata
    assert child_metadata["parent_thread_id"] === parent.id
    assert child_metadata["parent_turn_id"] === review_turn

    child_path = await_rollout(ctx, child_identity.thread, child_identity.turn, now() + 5_000)

    child = %{
      id: child_identity.thread,
      turn: child_identity.turn,
      source: @review_source,
      text: @review_prompt,
      path: child_path,
      index: 2
    }

    # Readiness polls actual completed native pages plus durable canonical
    # events; parent completion alone is not a child shutdown/flush barrier.
    await_items(
      ctx,
      producer,
      child.id,
      child.turn,
      ["userMessage", "agentMessage"],
      now() + 5_000
    )

    await_rollout(ctx, parent.id, review_turn, now() + 5_000)

    await_items(
      ctx,
      producer,
      parent.id,
      review_turn,
      ["enteredReviewMode", "exitedReviewMode"],
      now() + 5_000
    )

    child = history(ctx, producer, child)
    assert child.root_turn_id === Map.get(child_metadata, "root_turn_id")
    parent = history(ctx, producer, parent)
    assert_parent_review(parent, review_turn)
    close(producer, producer_native)

    # Freeze only after the owned producer and native delegate writers finish.
    # Canonical IDs/content come from real persistence, never generated rows.
    rows =
      for row <- [child, parent] do
        raw = canonical(ctx, row.path, row.id, row.turn, row.source, row.text, row.index)
        assert raw.user === row.user
        assert raw.assistant === row.assistant
        assert raw.environment_context === row.environment_context
        assert raw.event_user === row.event_user
        assert raw.event_assistant === row.event_assistant
        Map.merge(row, %{bytes: raw.bytes})
      end

    assert length(requests(ctx)) == 2
    journal = bounded_file(ctx.fixture.requests)
    assert_retained(ctx, rows, journal)

    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    assert_unloaded(ctx, warm)
    matrix(ctx, warm, rows)
    assert_unloaded(ctx, warm)
    assert_histories(ctx, warm, rows)
    assert_idle(ctx, warm)
    assert_retained(ctx, rows, journal)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native in [producer_native, warm_native]
    assert_unloaded(ctx, cold)
    # Discovery is the first content query, before paging/resume/hydration.
    matrix(ctx, cold, rows)
    assert_unloaded(ctx, cold)
    assert_histories(ctx, cold, rows)
    assert_idle(ctx, cold)
    assert_retained(ctx, rows, journal)
    close(cold, cold_native)
    assert_retained(ctx, rows, journal)
    assert length(requests(ctx)) == 2
    assert hash(File.read!(ctx.binary)) == @binary_sha
    assert_wire_inventory(ctx)
  end

  defp of_type(records, type), do: Enum.filter(records, &(&1["type"] == type))

  defp produce_control(ctx, pid) do
    initial =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated",
        "threadSource" => "user",
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never"
      })["thread"]

    id = Map.fetch!(initial, "id")
    assert is_binary(id) and id != ""
    assert Map.fetch!(initial, "source") === "vscode"
    assert Map.fetch!(initial, "historyMode") === "paginated"

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => id,
        "input" => [%{"type" => "text", "text" => @control_prompt}]
      })["turn"]["id"]

    assert is_binary(turn) and turn != ""
    events = complete_turn(pid, id, turn, [], now() + 20_000)
    assert_control_items(events, id, turn)
    identity = provider_identity(ctx, 1, @control_prompt)
    assert identity.thread === id and identity.turn === turn

    # Paging actual full persisted turns is the native durability observation;
    # includeTurns:true is deliberately never used for paginated history.
    path = Map.fetch!(initial, "path")
    source = %{id: id, turn: turn, source: "vscode", text: @control_prompt, index: 1, path: path}
    await_rollout(ctx, id, turn, now() + 5_000)
    await_items(ctx, pid, id, turn, ["userMessage", "agentMessage"], now() + 5_000)
    stored = history(ctx, pid, source)
    canonical = canonical(ctx, path, id, turn, "vscode", @control_prompt, 1)
    assert stored.user === canonical.user
    assert stored.assistant === canonical.assistant
    stored
  end

  defp history(ctx, pid, source) do
    metadata =
      call(ctx, pid, "thread/read", %{"threadId" => source.id, "includeTurns" => false})["thread"]

    expected = %{
      "id" => source.id,
      "source" =>
        if(source.source == @review_source, do: @review_public_source, else: source.source),
      "preview" => source.text,
      "cwd" => ctx.fixture.workspace,
      "modelProvider" => "fixture",
      "path" => source.path,
      "historyMode" => "paginated",
      "turns" => [],
      # Stored API views in this pin initialize sessionId from the thread ID;
      # canonical child SessionMeta independently retains the root session ID.
      "sessionId" => source.id,
      "parentThreadId" => if(source.source == @review_source, do: ctx.parent, else: nil),
      "forkedFromId" => nil,
      "threadSource" => if(source.source == @review_source, do: "subagent", else: "user")
    }

    assert Map.take(metadata, @projection) === expected

    page =
      call(ctx, pid, "thread/turns/list", %{
        "threadId" => source.id,
        "itemsView" => "full",
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert Map.fetch!(page, "nextCursor") === nil
    turns = Map.fetch!(page, "data")
    assert is_list(turns) and length(turns) in 1..4
    assert [turn] = Enum.filter(turns, &(&1["id"] == source.turn))
    if source.source == @review_source, do: assert(length(turns) == 1)
    assert Map.fetch!(turn, "id") === source.turn
    assert Map.fetch!(turn, "status") === "completed"
    assert Map.fetch!(turn, "error") === nil
    assert Map.fetch!(turn, "itemsView") === "full"
    assert [user, assistant] = Map.fetch!(turn, "items")
    assert Map.fetch!(user, "type") === "userMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => source.text}
           ]

    assert %{"type" => "agentMessage", "text" => @answer} = assistant
    assert is_binary(user["id"]) and user["id"] != ""
    assert is_binary(assistant["id"]) and assistant["id"] != ""
    refute user["id"] == assistant["id"]

    items =
      call(ctx, pid, "thread/items/list", %{
        "threadId" => source.id,
        "turnId" => source.turn,
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert Map.fetch!(items, "nextCursor") === nil
    assert Enum.map(items["data"], &Map.fetch!(&1, "turnId")) === [source.turn, source.turn]
    assert Enum.map(items["data"], &Map.fetch!(&1, "item")) === [user, assistant]

    raw =
      canonical(
        ctx,
        source.path,
        source.id,
        source.turn,
        source.source,
        source.text,
        source.index
      )

    # Paginated APIs project durable ItemCompleted TurnItems; raw ResponseItem
    # IDs are not the oracle for the UserMessage representation.
    assert user["id"] === raw.event_user["id"]
    assert assistant["id"] === raw.event_assistant["id"]
    Map.merge(raw, %{projection: expected, items: [user, assistant], turns: turns})
  end

  defp canonical(ctx, path, id, turn, source, text, index) do
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    bytes = bounded_file(path)
    records = jsonl(bytes)
    assert [%{"type" => "session_meta", "payload" => first} | _] = records
    assert_session_metadata(ctx, first, id, source)

    payloads =
      for %{"type" => "response_item", "payload" => payload} <- records,
          get_in(payload, [@metadata, "turn_id"]) == turn,
          do: payload

    assert [user] =
             Enum.filter(payloads, fn payload ->
               payload["role"] == "user" and
                 payload["content"] == [%{"type" => "input_text", "text" => text}]
             end)

    assert is_binary(user["id"]) and user["id"] != ""
    assert get_in(user, [@metadata, "content_item_kinds"]) === ["user.text"]
    environment_context = environment_context(payloads, user["id"])
    assert [assistant] = Enum.filter(payloads, &(&1["role"] == "assistant"))
    assert assistant["id"] === "fixture-message-#{index}"
    assert assistant["content"] === [%{"type" => "output_text", "text" => @answer}]

    events = for %{"type" => "event_msg", "payload" => event} <- records, do: event
    assert [started] = Enum.filter(of_type(events, "task_started"), &(&1["turn_id"] == turn))
    assert [completed] = Enum.filter(of_type(events, "task_complete"), &(&1["turn_id"] == turn))
    assert completed["last_agent_message"] === @answer and Map.get(completed, "error") === nil

    items =
      for %{"type" => "item_completed", "turn_id" => ^turn, "item" => item} <- events,
          do: item

    assert [event_user, event_assistant] = items
    assert event_user["type"] === "UserMessage"

    assert Enum.map(event_user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => text}
           ]

    assert event_assistant["type"] === "AgentMessage"
    assert event_assistant["content"] === [%{"type" => "Text", "text" => @answer}]
    assert event_assistant["id"] === "fixture-message-#{index}"
    for item <- items, do: assert(is_binary(item["id"]) and item["id"] != "")
    refute event_user["id"] == event_assistant["id"]

    %{
      id: id,
      turn: turn,
      source: source,
      text: text,
      index: index,
      path: path,
      bytes: bytes,
      user: user,
      assistant: assistant,
      environment_context: environment_context,
      event_user: event_user,
      event_assistant: event_assistant,
      root_turn_id: Map.get(started, "root_turn_id")
    }
  end

  defp assert_session_metadata(ctx, first, id, source) do
    assert first["id"] === id and first["source"] === source
    assert first["history_mode"] === "paginated"
    assert first["cwd"] === ctx.fixture.workspace
    assert first["model_provider"] === "fixture" and first["cli_version"] === "0.163.0"
    assert Map.get(first, "forked_from_id") === nil

    if source == @review_source do
      assert first["thread_source"] === "subagent"
      assert first["parent_thread_id"] === ctx.parent
      assert first["session_id"] === ctx.parent
    else
      assert first["thread_source"] === "user"
      assert first["session_id"] === id
      assert Map.get(first, "parent_thread_id") === nil
    end
  end

  defp environment_context(payloads, user_id) do
    # Keep native environment context as its own opaque classified record.
    # Its content is retained without inspecting policy or permission details.
    assert [environment_context] =
             Enum.filter(payloads, fn payload ->
               payload["role"] == "user" and
                 get_in(payload, [@metadata, "content_item_kinds"]) == [
                   "environments.environment_context"
                 ]
             end)

    assert [%{"type" => "input_text", "text" => environment_text}] =
             environment_context["content"]

    assert is_binary(environment_text) and environment_text != ""
    assert is_binary(environment_context["id"]) and environment_context["id"] != ""
    refute environment_context["id"] == user_id
    environment_context
  end

  defp await_rollout(ctx, thread, turn, until) do
    paths = Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl"))
    assert length(paths) <= 2

    found = Enum.find(paths, &rollout_complete?(&1, thread, turn))

    if found do
      found
    else
      wait_readiness(until)
      await_rollout(ctx, thread, turn, until)
    end
  end

  defp rollout_complete?(path, thread, turn) do
    # A native writer may still append between stat/read. This bounded live
    # readiness read does not pretend to freeze an in-progress file.
    bytes = File.read!(path)
    assert byte_size(bytes) <= @max_file_bytes

    records =
      if byte_size(bytes) > 0 and String.ends_with?(bytes, "\n"), do: jsonl(bytes), else: []

    case records do
      [%{"type" => "session_meta", "payload" => %{"id" => ^thread}} | _] ->
        Enum.any?(records, fn record ->
          record["type"] == "event_msg" and record["payload"]["type"] == "task_complete" and
            record["payload"]["turn_id"] == turn
        end)

      _ ->
        false
    end
  end

  defp await_items(ctx, pid, thread, turn, required, until) do
    page =
      call(ctx, pid, "thread/turns/list", %{
        "threadId" => thread,
        "itemsView" => "full",
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert page["nextCursor"] === nil
    turns = Map.fetch!(page, "data")
    assert is_list(turns) and length(turns) <= 4
    found = Enum.find(turns, &(&1["id"] == turn))
    types = if found, do: Enum.map(found["items"], & &1["type"]), else: []

    if found && found["status"] == "completed" && Enum.all?(required, &(&1 in types)) do
      assert found["error"] === nil
      :ok
    else
      wait_readiness(until)
      await_items(ctx, pid, thread, turn, required, until)
    end
  end

  defp wait_readiness(until) do
    assert now() < until, "Owned Review durable native readiness deadline"
    Process.sleep(25)
  end

  defp jsonl(bytes) do
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048

    Enum.map(lines, fn line ->
      assert byte_size(line) <= @max_line_bytes
      JSON.decode!(line)
    end)
  end

  defp provider_identity(ctx, count, text) do
    journal = requests(ctx)
    assert length(journal) == count
    request = Enum.at(journal, count - 1)
    assert Map.fetch!(request, "model") === "mock-model"

    assert %{"thread_id" => thread, "turn_id" => turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert is_binary(thread) and thread != ""
    assert is_binary(turn) and turn != ""

    assert Enum.count(request["input"], fn item ->
             item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => text}]
           end) == 1

    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    %{thread: thread, turn: turn, metadata: metadata}
  end

  defp matrix(ctx, pid, rows) do
    for method <- ["thread/list", "thread/search"],
        kinds <- [["subAgentReview"], ["vscode"], ["subAgentReview", "vscode"]] do
      base =
        if method == "thread/list",
          do: %{"limit" => 100, "useStateDbOnly" => true},
          else: %{"limit" => 100, "searchTerm" => @needle}

      expected = Enum.filter(rows, &(source_kind(&1.source) in kinds))
      result = call(ctx, pid, method, Map.put(base, "sourceKinds", kinds))
      data = Map.fetch!(result, "data")
      threads = if method == "thread/search", do: Enum.map(data, & &1["thread"]), else: data
      ids = Enum.map(threads, &Map.fetch!(&1, "id"))
      assert length(ids) == length(expected)
      assert length(Enum.uniq(ids)) == length(ids)
      assert MapSet.new(ids) == MapSet.new(Enum.map(expected, & &1.id))
      assert Map.fetch!(result, "nextCursor") === nil

      for thread <- threads do
        original = Enum.find(expected, &(&1.id == thread["id"]))
        assert Map.take(thread, @projection) === discovery_projection(original)
      end

      assert_snippets(method, data, expected)
      assert length(requests(ctx)) == 2
    end
  end

  # These unloaded DB list/search views use a different pinned native path:
  # rollout state_db supplies an empty parent map, and the rollout-item helper
  # sets thread_source=None. Retain and assert both nulls; thread/read and the
  # canonical/provider ancestry above independently retain the actual lineage.
  defp discovery_projection(row) do
    Map.merge(row.projection, %{"parentThreadId" => nil, "threadSource" => nil})
  end

  defp assert_snippets("thread/search", data, expected) do
    for result <- data do
      original = Enum.find(expected, &(&1.id == result["thread"]["id"]))
      assert Map.fetch!(result, "snippet") === original.text
    end
  end

  defp assert_snippets("thread/list", _data, _expected), do: :ok

  defp assert_histories(ctx, pid, rows) do
    for row <- rows do
      observed = history(ctx, pid, row)
      assert observed.items === row.items
      assert observed.user === row.user
      assert observed.assistant === row.assistant
      assert observed.environment_context === row.environment_context
      assert observed.event_user === row.event_user
      assert observed.event_assistant === row.event_assistant
      assert observed.turns === row.turns
      assert observed.bytes === row.bytes
    end

    assert_unloaded(ctx, pid)
  end

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_event_bounds(events)
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    completed =
      TurnFixture.notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if completed do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               completed

      events
    else
      await_control(pid, thread, turn, events, until)
    end
  end

  defp await_control(pid, thread, turn, events, until) do
    remaining = max(until - now(), 0)
    assert remaining > 0, "Owned native turn deadline"

    receive do
      {:codex_driver, ^pid, :events_available} -> complete_turn(pid, thread, turn, events, until)
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary producer event gap")
    after
      remaining -> flunk("Owned native turn deadline")
    end
  end

  defp assert_control_items(events, thread, turn) do
    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == thread,
          event.wire["params"]["turnId"] == turn,
          do: event.wire["params"]["item"]

    assert [user, assistant] = items
    assert user["type"] === "userMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => @control_prompt}
           ]

    assert %{"type" => "agentMessage", "text" => @answer} = assistant
  end

  defp source_kind(@review_source), do: "subAgentReview"
  defp source_kind("vscode"), do: "vscode"

  defp assert_review_lifecycle(events, parent, turn) do
    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == parent,
          event.wire["params"]["turnId"] == turn,
          do: event.wire["params"]["item"]

    assert [entered] = Enum.filter(items, &(&1["type"] == "enteredReviewMode"))
    assert [exited] = Enum.filter(items, &(&1["type"] == "exitedReviewMode"))
    assert entered["review"] === @review_prompt
    assert exited["review"] === @answer
    assert is_binary(entered["id"]) and is_binary(exited["id"])
    refute entered["id"] == exited["id"]
    # The pin explicitly lacks a parent review TurnStarted. No invented
    # lifecycle symmetry, public delegate thread/started or inference is required.
  end

  defp assert_parent_review(parent, turn) do
    assert [review] = Enum.filter(parent.turns, &(&1["id"] == turn))
    assert review["status"] === "completed" and review["error"] === nil
    assert [entered] = Enum.filter(review["items"], &(&1["type"] == "enteredReviewMode"))
    assert [exited] = Enum.filter(review["items"], &(&1["type"] == "exitedReviewMode"))
    assert entered["review"] === @review_prompt and exited["review"] === @answer
  end

  defp assert_unloaded(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert_event_bounds(events)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert length(requests(ctx)) == 2
  end

  defp assert_event_bounds(events) do
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
  end

  defp call(ctx, pid, method, params) do
    id = "owned-review-source-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    records = Agent.get(ctx.capture, &Enum.reverse(&1.records))
    assert [sent, received] = Enum.filter(records, &(&1.wire["id"] == id))
    assert sent.direction == :out and received.direction == :in
    assert sent.wire === wire and received.wire === response
    assert JSON.decode!(sent.encoded) === wire
    assert JSON.decode!(received.encoded) === response
    result
  end

  defp assert_wire_inventory(ctx) do
    records = Agent.get(ctx.capture, &Enum.reverse(&1.records))
    outgoing = for %{direction: :out, wire: wire} <- records, do: wire
    assert Enum.count(outgoing, &(&1["method"] == "thread/start")) == 1
    assert Enum.count(outgoing, &(&1["method"] == "turn/start")) == 1
    assert Enum.count(outgoing, &(&1["method"] == "review/start")) == 1

    for method <- ["thread/list", "thread/search"] do
      queries = Enum.filter(outgoing, &(&1["method"] == method))
      assert length(queries) == 6

      for kinds <- [["subAgentReview"], ["vscode"], ["subAgentReview", "vscode"]] do
        assert Enum.count(queries, &(&1["params"]["sourceKinds"] == kinds)) == 2
      end
    end

    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: environment(ctx),
                    max_message_bytes: @max_line_bytes
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_review_source_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp environment(ctx) do
    %{
      "HOME" => ctx.fixture.home,
      "CODEX_HOME" => ctx.fixture.codex_home,
      "TMPDIR" => Path.join(ctx.root, "tmp"),
      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off"
    }
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    assert_gone(native)
  end

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned native #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) == size
    bytes
  end

  defp requests(ctx) do
    journal = JSON.decode!(bounded_file(ctx.fixture.requests))
    assert is_list(journal) and length(journal) <= 2
    journal
  end

  defp assert_retained(ctx, rows, journal) do
    assert bounded_file(ctx.fixture.requests) === journal
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    for row <- rows, do: assert(bounded_file(row.path) === row.bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
