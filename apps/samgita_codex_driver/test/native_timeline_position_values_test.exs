defmodule SamgitaCodexDriver.NativeTimelinePositionValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed ordinary timeline position fixture instructions."
  @answer "Deterministic local fixture answer"
  @markers ["Owned timeline ordinal first λ", "Owned timeline ordinal second 🙂"]
  @captured_methods ["turn/start", "thread/timeline/list"]
  @error_script Path.expand("../../../scripts/codex/timeline_error_fixture.py", __DIR__)
  @error_message "Selected model is at capacity. Please try a different model."
  @terminal_error %{
    "message" => @error_message,
    "codexErrorInfo" => "serverOverloaded",
    "additionalDetails" => nil,
    "misalignment" => nil
  }
  @raw_error %{"message" => @error_message, "codex_error_info" => "server_overloaded"}

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

      if wire["method"] in ["turn/start", "thread/timeline/list"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
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
    ctx = setup_fixture(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      for path <- [config, Path.join(ctx.fixture.codex_home, "turn-models.json")], into: %{} do
        {path, snapshot(path)}
      end

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  defp setup_fixture(%{timeline_error: true} = tags) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @error_script)

    try do
      TurnFixture.setup(tags)
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  defp setup_fixture(tags), do: TurnFixture.setup(tags)

  test "ordinary timeline positions retain canonical rollout ordinals across pages and restart",
       ctx do
    assert File.ls!(ctx.fixture.workspace) == []
    first = start(ctx)
    first_native = native_id(ctx, first)

    thread =
      call(ctx, first, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    rows = Enum.map(@markers, &complete_turn(ctx, first, thread, &1))
    assert [first_provider, second_provider] = ModelFixture.requests(ctx.fixture)

    for {provider, row} <- Enum.zip([first_provider, second_provider], rows) do
      assert_provider(provider, thread, row)
    end

    # The public completed-history read is the retained persistence barrier.
    # Snapshot native canonical records before requesting any timeline values.
    saved = assert_history(ctx, first, thread, rows)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    rollout = snapshot(path)
    expected = raw_positions(rollout.bytes, thread, rows)
    assert length(expected) == 8
    journal = snapshot(ctx.fixture.requests)
    retained = Map.merge(ctx.inputs, %{path => rollout, ctx.fixture.requests => journal})

    query = %{"threadId" => thread, "limit" => 100}
    full = call(ctx, first, "thread/timeline/list", query)
    assert Map.fetch!(full, "nextCursor") === nil
    assert Map.fetch!(full, "activeRealtimeSessionAtPageStart") === nil
    assert_timeline(Map.fetch!(full, "data"), expected, rows)

    pages = page_one(ctx, first, thread, nil, Enum.reverse(expected), MapSet.new(), [])
    assert length(pages) == 8
    paged = pages |> Enum.reverse() |> Enum.flat_map(&Map.fetch!(&1.response, "data"))
    assert_timeline(paged, expected, rows)
    remaining = Enum.drop(pages, 4)
    assert length(remaining) == 4
    assert is_binary(hd(remaining).params["cursor"])
    assert_retained(ctx, first, retained)
    close(first, first_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == first_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    cold_saved = assert_history(ctx, cold, thread, rows)
    assert Map.fetch!(cold_saved, "path") == path
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []

    cold_full = call(ctx, cold, "thread/timeline/list", query)
    assert_timeline(Map.fetch!(cold_full, "data"), expected, rows)
    assert cold_full === full

    # Reuse each genuine opaque midstream continuation unchanged. No thread is
    # resumed and no inference is issued while reading the persisted positions.
    for page <- remaining do
      assert call(ctx, cold, "thread/timeline/list", page.params) === page.response
    end

    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert length(Agent.get(ctx.capture, & &1)) == 2 + 2 + length(pages) + length(remaining)
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    assert snapshot(path) === rollout
    assert snapshot(ctx.fixture.requests) === journal
  end

  @tag timeline_error: true
  test "failed and recovered timeline errors preserve native history across cold restart", ctx do
    first = start(ctx)
    first_native = native_id(ctx, first)

    thread =
      call(ctx, first, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    failed = failed_turn(ctx, first, thread)
    assert [failed_provider] = ModelFixture.requests(ctx.fixture)
    assert_provider(failed_provider, thread, failed)

    # Inspect the failed durable reader before any recovery request. A read ACK
    # alone cannot prove that the native projection persisted its terminal error.
    failed_saved = assert_history(ctx, first, thread, [failed])
    path = Map.fetch!(failed_saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    failed_bytes = snapshot(path)
    failed_expected = error_positions(failed_bytes.bytes, thread, [failed])
    query = %{"threadId" => thread, "limit" => 100}
    failed_timeline = call(ctx, first, "thread/timeline/list", query)
    assert_error_timeline(failed_timeline, failed_expected)
    assert snapshot(path) === failed_bytes
    assert ModelFixture.requests(ctx.fixture) == [failed_provider]

    recovered = complete_turn(ctx, first, thread, "Owned timeline explicit recovery 🙂")
    refute recovered.id == failed.id
    assert [^failed_provider, recovery_provider] = ModelFixture.requests(ctx.fixture)
    assert_provider(recovery_provider, thread, recovered)
    rows = [failed, recovered]
    saved = assert_history(ctx, first, thread, rows)
    assert Map.fetch!(saved, "path") == path
    rollout = snapshot(path)
    expected = error_positions(rollout.bytes, thread, rows)
    assert length(expected) == 2
    full = call(ctx, first, "thread/timeline/list", query)
    assert_error_timeline(full, expected)
    journal = snapshot(ctx.fixture.requests)
    retained = Map.merge(ctx.inputs, %{path => rollout, ctx.fixture.requests => journal})
    assert_retained(ctx, first, retained)
    close(first, first_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == first_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    cold_saved = assert_history(ctx, cold, thread, rows)
    assert Map.fetch!(cold_saved, "path") == path
    assert Map.fetch!(cold_saved, "turns") === Map.fetch!(saved, "turns")
    cold_timeline = call(ctx, cold, "thread/timeline/list", query)
    assert_error_timeline(cold_timeline, expected)
    assert cold_timeline === full
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert length(Agent.get(ctx.capture, & &1)) == 5
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    assert snapshot(path) === rollout
    assert snapshot(ctx.fixture.requests) === journal
  end

  defp failed_turn(ctx, pid, thread) do
    marker = "Owned timeline native overload λ"
    requested_at = System.system_time(:millisecond)

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect_turn(pid, thread, turn, [], deadline(20_000), "failed")
    finished_at = System.system_time(:millisecond)

    assert [
             %{
               "threadId" => ^thread,
               "turnId" => ^turn,
               "willRetry" => false,
               "error" => @terminal_error
             }
           ] = event_params(events, "error")

    assert [
             %{
               "threadId" => ^thread,
               "turn" => %{"id" => ^turn, "status" => "failed", "error" => @terminal_error}
             }
           ] = event_params(events, "turn/completed")

    assert [%{"threadId" => ^thread, "turnId" => ^turn, "item" => user}] =
             event_params(events, "item/completed")

    assert_user(user, marker)
    assert is_binary(user["id"]) and byte_size(user["id"]) > 0
    assert_user_identity(events, thread, turn, user, {requested_at, finished_at})
    assert Session.uncertain_operations(pid) == []

    %{
      id: turn,
      marker: marker,
      user: user["id"],
      assistant: nil,
      status: "failed",
      error: @terminal_error
    }
  end

  defp complete_turn(ctx, pid, thread, marker) do
    requested_at = System.system_time(:millisecond)

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect_turn(pid, thread, turn, [], deadline(20_000))
    finished_at = System.system_time(:millisecond)

    completed =
      for event <- events,
          event.wire["method"] == "item/completed",
          params = event.wire["params"],
          params["threadId"] == thread and params["turnId"] == turn,
          do: params["item"]

    assert [user, assistant] = completed
    assert_user(user, marker)
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
    assert is_binary(user["id"]) and is_binary(assistant["id"])
    refute user["id"] == assistant["id"]
    assert_user_identity(events, thread, turn, user, {requested_at, finished_at})
    %{id: turn, marker: marker, user: user["id"], assistant: assistant["id"]}
  end

  defp assert_user_identity(events, thread, turn, user, {requested_at, finished_at}) do
    id = Map.fetch!(user, "id")

    assert Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
             id
           )

    {created_at, ""} = id |> String.replace("-", "") |> String.slice(0, 12) |> Integer.parse(16)
    assert requested_at <= created_at and created_at <= finished_at
    refute id == turn

    lifecycle =
      Enum.filter(events, fn event ->
        event.wire["method"] in ["item/started", "item/completed"] and
          get_in(event.wire, ["params", "item", "type"]) == "userMessage"
      end)

    assert [started, completed] = lifecycle
    assert Enum.map(lifecycle, & &1.wire["method"]) == ["item/started", "item/completed"]
    assert started.sequence < completed.sequence

    for event <- lifecycle do
      assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => ^user} = event.wire["params"]
    end
  end

  defp assert_provider(provider, thread, row) do
    turn = row.id
    assert Map.fetch!(provider, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(provider["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } =
             hd(provider["input"])

    user_texts =
      for item <- provider["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == row.marker)) == 1
  end

  defp assert_history(ctx, pid, thread, rows) do
    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"
    turns = Map.fetch!(saved, "turns")
    assert length(turns) == length(rows)

    for {turn, row} <- Enum.zip(turns, rows) do
      assert Map.fetch!(turn, "id") == row.id
      assert Map.fetch!(turn, "status") == Map.get(row, :status, "completed")
      assert Map.fetch!(turn, "error") === Map.get(row, :error)
      assert_history_items(Map.fetch!(turn, "items"), row)
    end

    saved
  end

  defp assert_history_items([user], %{assistant: nil} = row) do
    assert Map.fetch!(user, "id") == row.user
    assert_user(user, row.marker)
  end

  defp assert_history_items([user, assistant], row) do
    assert Map.fetch!(user, "id") == row.user
    assert Map.fetch!(assistant, "id") == row.assistant
    assert_user(user, row.marker)
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
  end

  defp error_positions(bytes, thread, rows) do
    assert String.ends_with?(bytes, "\n")
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048
    records = Enum.map(lines, &JSON.decode!/1)

    Enum.map(rows, fn row ->
      user = raw_record(records, "item_completed", row.id, row.user)
      assert user["payload"]["thread_id"] == thread

      assert user["payload"]["item"]["content"] == [
               %{"type" => "text", "text" => row.marker, "text_elements" => []}
             ]

      finished = raw_record(records, "task_complete", row.id)
      payload = Map.fetch!(finished, "payload")

      if row.assistant do
        assistant = raw_record(records, "item_completed", row.id, row.assistant)
        assert assistant["payload"]["thread_id"] == thread

        assert assistant["payload"]["item"]["content"] == [
                 %{"type" => "Text", "text" => @answer}
               ]

        refute Map.has_key?(payload, "error")
      else
        assert Map.fetch!(payload, "error") === @raw_error
      end

      {ordinal(finished), row.id, Map.get(row, :status, "completed"), Map.get(row, :error)}
    end)
  end

  defp assert_error_timeline(response, expected) do
    assert Map.fetch!(response, "nextCursor") === nil
    assert Map.fetch!(response, "activeRealtimeSessionAtPageStart") === nil
    entries = Map.fetch!(response, "data")
    terminal = Enum.filter(entries, &(&1["type"] == "turnCompleted"))
    assert length(terminal) == length(expected)

    for {entry, {position, turn, status, error}} <- Enum.zip(terminal, expected) do
      assert Map.fetch!(entry, "position") === position
      assert Map.fetch!(entry, "turnId") == turn
      assert Map.fetch!(entry, "status") == status
      assert Map.fetch!(entry, "error") === error
    end
  end

  defp raw_positions(bytes, thread, rows) do
    assert String.ends_with?(bytes, "\n")
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048
    records = Enum.map(lines, &JSON.decode!/1)

    expected =
      Enum.flat_map(rows, fn row ->
        started = raw_record(records, "task_started", row.id)
        finished = raw_record(records, "task_complete", row.id)
        user = raw_record(records, "item_completed", row.id, row.user)
        assistant = raw_record(records, "item_completed", row.id, row.assistant)
        assert user["payload"]["thread_id"] == thread
        assert assistant["payload"]["thread_id"] == thread
        assert %{"type" => "UserMessage", "content" => content} = user["payload"]["item"]
        assert [%{"type" => "text", "text" => text}] = content
        assert text == row.marker

        assert %{"type" => "AgentMessage", "content" => [%{"type" => "Text", "text" => @answer}]} =
                 assistant["payload"]["item"]

        [
          {ordinal(started), "turnStarted", row.id, nil},
          {ordinal(user), "item", row.id, row.user},
          {ordinal(assistant), "item", row.id, row.assistant},
          {ordinal(finished), "turnCompleted", row.id, nil}
        ]
      end)

    positions = Enum.map(expected, &elem(&1, 0))
    assert positions == Enum.sort(positions)
    assert MapSet.size(MapSet.new(positions)) == 8
    expected
  end

  defp raw_record(records, type, turn, item \\ nil) do
    assert [record] =
             Enum.filter(records, fn record ->
               payload = record["payload"]

               record["type"] == "event_msg" and payload["type"] == type and
                 payload["turn_id"] == turn and (is_nil(item) or payload["item"]["id"] == item)
             end)

    record
  end

  defp ordinal(record) do
    position = Map.fetch!(record, "ordinal")
    assert is_integer(position) and position >= 0
    position
  end

  defp assert_timeline(entries, expected, rows) do
    assert Enum.map(entries, &entry_tuple/1) === expected

    for {row, [started, user, assistant, finished]} <-
          Enum.zip(rows, Enum.chunk_every(entries, 4)) do
      assert started["type"] == "turnStarted"
      assert finished["type"] == "turnCompleted"
      assert finished["status"] == "completed"
      assert_user(Map.fetch!(user, "item"), row.marker)
      assert %{"type" => "agentMessage", "text" => @answer} = Map.fetch!(assistant, "item")
    end
  end

  defp entry_tuple(entry) do
    position = Map.fetch!(entry, "position")
    assert is_integer(position) and position >= 0

    {position, Map.fetch!(entry, "type"), Map.fetch!(entry, "turnId"),
     get_in(entry, ["item", "id"])}
  end

  defp assert_user(user, marker) do
    assert %{"type" => "userMessage", "content" => content} = user
    assert [%{"type" => "text", "text" => ^marker}] = content
  end

  defp page_one(ctx, pid, thread, cursor, [wanted | rest], seen, pages) do
    assert length(pages) < 8
    params = %{"threadId" => thread, "limit" => 1}
    params = if is_nil(cursor), do: params, else: Map.put(params, "cursor", cursor)
    response = call(ctx, pid, "thread/timeline/list", params)
    assert [entry] = Map.fetch!(response, "data")
    assert entry_tuple(entry) === wanted
    pages = [%{params: params, response: response} | pages]
    next = Map.fetch!(response, "nextCursor")

    if rest == [] do
      assert next === nil
      Enum.reverse(pages)
    else
      assert is_binary(next) and byte_size(next) > 0
      refute MapSet.member?(seen, next)
      page_one(ctx, pid, thread, next, rest, MapSet.put(seen, next), pages)
    end
  end

  defp collect_turn(pid, thread, turn, events, until, expected_status \\ "completed") do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native timeline event buffer exceeded its count bound"
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during native timeline")
    after
      0 -> :ok
    end

    case notification(
           events,
           "turn/completed",
           &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
         ) do
      nil ->
        assert System.monotonic_time(:millisecond) < until, "native timeline turn deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during native timeline")
        after
          10 -> :ok
        end

        collect_turn(pid, thread, turn, events, until, expected_status)

      completed ->
        assert %{
                 "threadId" => ^thread,
                 "turn" => %{"id" => ^turn, "status" => ^expected_status}
               } =
                 completed

        events
    end
  end

  defp event_params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-timeline-position-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    captured = Agent.get(ctx.capture, &Enum.drop(&1, before))

    if method in @captured_methods do
      assert [%{encoded: encoded, wire: recorded}] = captured
      assert recorded === wire
      assert JSON.decode!(encoded) === wire
    else
      assert captured == []
    end

    result
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, expected} <- inputs, do: assert(snapshot(path) === expected)
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
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
               %{"name" => "owned_timeline_position_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
