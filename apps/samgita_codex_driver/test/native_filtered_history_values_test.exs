defmodule SamgitaCodexDriver.NativeFilteredHistoryValuesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/filtered_history_fixture.py", __DIR__)
  @script_sha "2a96fea0fd80ea61cff2c32a5dee7b2c3de420cd4f43131a71bccd20209c27b4"
  @original_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @original_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144
  @filtered ["compaction_trigger", "other", "compaction"]
  @tools [
    "function_call",
    "function_call_output",
    "custom_tool_call",
    "custom_tool_call_output",
    "tool_search_call",
    "tool_search_output",
    "local_shell_call"
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    @methods ["thread/start", "thread/resume", "thread/compact/start", "turn/start"]

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in @methods do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 8 and byte_size(encoded) <= 1_048_576 do
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
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(binary) == @binary_sha
    assert hash(@script) == @script_sha
    assert hash(@original_script) == @original_sha
    profile = profile(tags.profile)

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-filtered-history-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, profile.scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    capture = start_supervised!({Agent, fn -> [] end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture, profile: profile}
    TurnFixture.configure_model(ctx, %{})

    paths = [
      @script,
      @original_script,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "turn-models.json")
    ]

    Map.put(ctx, :unchanged, Enum.map(paths, &{&1, File.read!(&1)}))
  end

  @tag profile: :trigger
  test "native-produced backend trigger is accepted as current raw history and filtered", ctx do
    assert_filtered_journey(ctx)
  end

  @tag profile: :other
  test "current Other decoded by native is accepted as raw history and filtered", ctx do
    assert_filtered_journey(ctx)
  end

  defp assert_filtered_journey(ctx) do
    p = ctx.profile
    source = start(ctx)
    source_native = native_process(source)

    source_thread =
      request(ctx, source, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "legacy",
        "experimentalRawEvents" => true,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]["id"]

    assert is_binary(source_thread) and source_thread != ""
    assert requests(ctx) === []
    began = System.system_time(:microsecond) / 1_000_000

    source_turn =
      request(ctx, source, "turn/start", %{
        "threadId" => source_thread,
        "input" => text(p.marker)
      })["turn"]["id"]

    assert is_binary(source_turn) and source_turn != ""
    seed = collect(source, &terminal(&1, source_thread, source_turn), [], now() + 20_000)
    ended = System.system_time(:microsecond) / 1_000_000
    assert_completed(seed, source_thread, source_turn)
    assert_answer(seed, source_thread, source_turn, p.source_answer)
    assert_no_dispatch(ctx, source, seed)
    refute compaction_started(seed, source_thread)
    assert [first] = requests(ctx)
    assert_request_input(first, [p.marker])
    captured = capture_control(ctx, source, source_thread, source_turn, seed, first)
    assert captured === %{"type" => p.type}

    source_path = read_thread(source, source_thread)["path"]
    assert :ok = Session.close(source)
    assert_gone(source_native)
    {source_bytes, source_rows} = rollout(ctx, source_path)
    user = capture_user(source_rows, source_turn, p.marker, began, ended)
    source_payloads = payloads(source_rows)
    refute Enum.any?(source_payloads, &(&1["type"] in ["compaction_trigger", "other"]))
    source_requests = requests(ctx)
    assert length(source_requests) == p.source_count

    # Current raw input only: a genuine native user plus the whole captured
    # native control map, unchanged. The trigger is captured from a backend
    # request; Other from actual native raw output. Neither is durable history.
    history = [user, captured]
    assert byte_size(JSON.encode!(history)) <= 1_048_576
    cold = start(ctx)
    cold_native = native_process(cold)
    refute cold_native == source_native
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    imported =
      request(ctx, cold, "thread/resume", %{
        "threadId" => source_thread,
        "history" => history,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]

    imported_thread = imported["id"]

    assert is_binary(imported_thread) and imported_thread != "" and
             imported_thread != source_thread

    assert imported["preview"] == p.marker
    assert imported["status"] === %{"type" => "idle"}
    imported_path = read_thread(cold, imported_thread)["path"]
    refute imported_path == source_path
    assert_import(ctx, imported_path, user, nil)
    import_events = drain(cold, [])
    assert_no_dispatch(ctx, cold, import_events)
    refute Enum.any?(import_events, &(&1.wire["method"] in ["turn/started", "turn/completed"]))
    refute compaction_started(import_events, imported_thread)
    assert Session.status(cold).buffered_events == 0
    assert requests(ctx) === source_requests
    assert_retained(ctx, source_path, source_bytes)

    followup_turn =
      request(ctx, cold, "turn/start", %{
        "threadId" => imported_thread,
        "input" => text(p.followup)
      })["turn"]["id"]

    assert is_binary(followup_turn) and followup_turn != "" and followup_turn != source_turn
    followup = collect(cold, &terminal(&1, imported_thread, followup_turn), [], now() + 20_000)
    assert_completed(followup, imported_thread, followup_turn)
    assert_answer(followup, imported_thread, followup_turn, p.followup_answer)
    assert_no_dispatch(ctx, cold, followup)
    refute compaction_started(followup, imported_thread)
    assert [consumed] = Enum.drop(requests(ctx), p.source_count)
    assert requests(ctx) === source_requests ++ [consumed]
    assert_request_input(consumed, [p.marker, p.followup])
    metadata = consumed["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["history_initialization"] == "supplied_history"
    assert_import(ctx, imported_path, user, followup_turn)
    assert_retained(ctx, source_path, source_bytes)
    assert :ok = Session.close(cold)
    assert_gone(cold_native)
    assert_import(ctx, imported_path, user, followup_turn)
    assert requests(ctx) === source_requests ++ [consumed]
    frames = Agent.get(ctx.capture, & &1)

    expected_methods =
      ["thread/start", "turn/start"] ++
        if(p.type == "compaction_trigger", do: ["thread/compact/start"], else: []) ++
        ["thread/resume", "turn/start"]

    assert Enum.map(frames, & &1["method"]) === expected_methods
    assert length(frames) == p.frame_count
    assert_retained(ctx, source_path, source_bytes)
  end

  defp capture_control(%{profile: %{type: "other"}}, _source, thread, turn, events, _first) do
    raw =
      for event <- events,
          event.wire["method"] == "rawResponseItem/completed",
          get_in(event.wire, ["params", "item", "type"]) == "other",
          do: event.wire["params"]

    assert [%{"threadId" => ^thread, "turnId" => ^turn, "item" => item}] = raw
    assert raw === [%{"threadId" => thread, "turnId" => turn, "item" => %{"type" => "other"}}]
    assert item === %{"type" => "other"}
    item
  end

  defp capture_control(ctx, source, thread, source_turn, _seed, first) do
    assert request(ctx, source, "thread/compact/start", %{"threadId" => thread}) === %{}

    events =
      collect(
        source,
        fn events ->
          if item = compaction_started(events, thread),
            do: terminal(events, thread, item["turnId"])
        end,
        [],
        now() + 20_000
      )

    assert %{
             "threadId" => ^thread,
             "turnId" => turn,
             "item" => %{"id" => id, "type" => "contextCompaction"}
           } = compaction_started(events, thread)

    assert is_binary(turn) and turn != "" and turn != source_turn
    assert is_binary(id) and id != ""

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"id" => ^id, "type" => "contextCompaction"}
           } =
             notification(
               events,
               "item/completed",
               &(&1["threadId"] == thread and &1["item"]["id"] == id)
             )

    assert Enum.count(
             events,
             &(&1.wire["method"] == "item/completed" and
                 get_in(&1.wire, ["params", "threadId"]) == thread and
                 get_in(&1.wire, ["params", "turnId"]) == turn and
                 get_in(&1.wire, ["params", "item", "id"]) == id)
           ) == 1

    assert_completed(events, thread, turn)
    assert_no_dispatch(ctx, source, events)
    assert [^first, compact_request] = requests(ctx)
    assert compact_request["model"] == "mock-model"
    input = compact_request["input"]
    assert [captured] = Enum.filter(input, &(&1["type"] == "compaction_trigger"))
    assert captured === %{"type" => "compaction_trigger"}
    assert Enum.count(input, &user_marker?(&1, ctx.profile.marker)) == 1
    refute Enum.any?(input, &(&1["type"] in (["compaction", "other"] ++ @tools)))
    captured
  end

  defp capture_user(rows, turn, marker, began, ended) do
    assert [user] = Enum.filter(payloads(rows), &user_marker?(&1, marker))
    id = Map.fetch!(user, "id")
    created = get_in(user, [@metadata, "create_time"])
    assert is_binary(id) and id != ""
    assert is_number(created) and created >= began and created <= ended

    assert user === %{
             "type" => "message",
             "id" => id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => marker}],
             @metadata => %{
               "turn_id" => turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }

    user
  end

  defp assert_import(ctx, path, original, followup_turn) do
    {_bytes, rows} = rollout(ctx, path)
    items = payloads(rows)
    assert Enum.filter(items, &(&1["id"] == original["id"])) === [original]
    assert Enum.filter(items, &user_marker?(&1, ctx.profile.marker)) === [original]
    refute Enum.any?(items, &(&1["type"] in (@filtered ++ @tools)))
    refute Enum.any?(rows, &(&1["type"] == "compacted"))

    if followup_turn do
      assert [fresh] = Enum.filter(items, &user_marker?(&1, ctx.profile.followup))
      assert get_in(fresh, [@metadata, "turn_id"]) == followup_turn
      refute fresh["id"] == original["id"]

      assert [answer] =
               Enum.filter(
                 items,
                 &(&1["id"] == "owned-filtered-#{ctx.profile.scenario}-followup")
               )

      assert answer["content"] === [
               %{"type" => "output_text", "text" => ctx.profile.followup_answer}
             ]

      assert get_in(answer, [@metadata, "turn_id"]) == followup_turn
    else
      assert items === [original]
    end
  end

  defp assert_request_input(request, markers) do
    assert request["model"] == "mock-model"
    input = request["input"]
    assert is_list(input) and length(input) <= 256
    refute Enum.any?(input, &(&1["type"] in (@filtered ++ @tools)))
    for marker <- markers, do: assert(Enum.count(input, &user_marker?(&1, marker)) == 1)
  end

  defp collect(pid, done, events, until) do
    events = drain(pid, events)

    if done.(events) do
      events
    else
      assert now() < until, "Native filtered-history turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, done, events, until)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native filtered-history gap")
      after
        max(until - now(), 0) -> flunk("Native filtered-history turn deadline")
      end
    end
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    events
  end

  defp terminal(events, thread, turn),
    do:
      notification(
        events,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp compaction_started(events, thread),
    do:
      notification(
        events,
        "item/started",
        &(&1["threadId"] == thread and &1["item"]["type"] == "contextCompaction")
      )

  defp assert_completed(events, thread, turn) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             terminal(events, thread, turn)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             notification(
               events,
               "turn/started",
               &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
             )

    assert Enum.count(
             events,
             &(&1.wire["method"] == "turn/completed" and
                 get_in(&1.wire, ["params", "threadId"]) == thread and
                 get_in(&1.wire, ["params", "turn", "id"]) == turn)
           ) == 1
  end

  defp assert_answer(events, thread, turn, answer) do
    selected =
      for event <- events,
          event.wire["method"] == "item/completed",
          get_in(event.wire, ["params", "threadId"]) == thread,
          get_in(event.wire, ["params", "turnId"]) == turn,
          get_in(event.wire, ["params", "item", "type"]) == "agentMessage",
          do: event.wire["params"]["item"]

    assert [%{"id" => id, "type" => "agentMessage", "text" => ^answer}] = selected
    assert is_binary(id) and id != ""

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"id" => ^id, "type" => "agentMessage"}
           } =
             notification(
               events,
               "item/started",
               &(&1["threadId"] == thread and &1["turnId"] == turn and &1["item"]["id"] == id)
             )
  end

  defp assert_no_dispatch(ctx, pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Enum.filter(events, &(&1.kind == :server_request)) === []
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-filtered-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
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
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_filtered_history_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp rollout(ctx, path) do
    assert is_binary(path)
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) == size
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048

    rows =
      Enum.map(lines, fn line ->
        assert byte_size(line) <= @max_line_bytes
        JSON.decode!(line)
      end)

    {bytes, rows}
  end

  defp requests(ctx) do
    assert %{type: :regular, size: size} = File.stat!(ctx.fixture.requests)
    assert size <= @max_file_bytes
    rows = ModelFixture.requests(ctx.fixture)
    assert length(rows) <= ctx.profile.source_count + 1
    rows
  end

  defp assert_retained(ctx, source_path, source_bytes) do
    assert File.read!(source_path) === source_bytes
    for {path, bytes} <- ctx.unchanged, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned filtered-history native #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp profile(:trigger),
    do: %{
      type: "compaction_trigger",
      scenario: "compaction",
      source_count: 2,
      frame_count: 5,
      marker: "Owned current filtered trigger source 163 λ",
      followup: "Owned current filtered trigger continuation 163 λ",
      source_answer: "Owned trigger source ordinary answer 163 λ",
      followup_answer: "Owned trigger filtered continuation answer 163 λ"
    }

  defp profile(:other),
    do: %{
      type: "other",
      scenario: "assistant",
      source_count: 1,
      frame_count: 4,
      marker: "Owned current filtered Other source 163 λ",
      followup: "Owned current filtered Other continuation 163 λ",
      source_answer: "Owned Other source ordinary answer 163 λ",
      followup_answer: "Owned Other filtered continuation answer 163 λ"
    }

  defp payloads(rows), do: for(%{"type" => "response_item", "payload" => item} <- rows, do: item)

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp user_marker?(item, marker),
    do:
      item["role"] == "user" and item["content"] === [%{"type" => "input_text", "text" => marker}]

  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]
  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
