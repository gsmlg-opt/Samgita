defmodule SamgitaCodexDriver.NativeThreadSourceFilterValuesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @needle "Owned explicit current source-kind filter 163 λ"
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary source-filter fixture instructions."
  @metadata "internal_chat_message_metadata_passthrough"
  @kinds [
    "cli",
    "exec",
    "appServer",
    "subAgentReview",
    "subAgentCompact",
    "subAgentOther",
    "unknown"
  ]
  @captured ["thread/start", "turn/start", "thread/list", "thread/search"]
  @projection ["id", "source", "preview", "cwd", "modelProvider", "path", "historyMode", "turns"]
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

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

      if wire["method"] in ["thread/start", "turn/start", "thread/list", "thread/search"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 64 and byte_size(encoded) <= 4096 do
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

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-source-filters-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
    capture = start_supervised!({Agent, fn -> [] end})
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

    paths = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.put(ctx, :inputs, Map.new(paths, &{&1, snapshot(&1)}))
  end

  test "current source-kind filter literals exclude real vscode rows and preserve mixed OR across cold discovery",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    rows = for index <- 1..2, do: source(ctx, warm, index)
    assert length(Enum.uniq(Enum.map(rows, & &1.id))) == 2
    assert length(Enum.uniq(Enum.map(rows, & &1.turn))) == 2
    assert length(Enum.uniq(Enum.map(rows, & &1.path))) == 2
    journal = snapshot(ctx.fixture.requests)
    assert length(requests(ctx)) == 2

    # The independent source-backed projection fixes actual native IDs/paths
    # against literal source/content/cwd/provider values. This is not positive
    # producer evidence for any of the seven absent source kinds.
    expected = Map.new(rows, &{&1.id, &1.projection})
    snippets = Map.new(rows, &{&1.id, &1.text})
    matrix(ctx, warm, expected, snippets)
    assert_idle(ctx, warm)
    assert_retained(ctx, rows, journal)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # First content queries in this process are discovery filters, before any
    # full-history read/resume. They must use persisted real source records.
    matrix(ctx, cold, expected, snippets)
    assert call(ctx, cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_idle(ctx, cold)
    assert_retained(ctx, rows, journal)
    close(cold, cold_native)
    assert_retained(ctx, rows, journal)
    assert length(requests(ctx)) == 2
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 64
    assert Enum.count(frames, &(&1["method"] == "thread/start")) == 2
    assert Enum.count(frames, &(&1["method"] == "turn/start")) == 2
    assert Enum.count(frames, &(&1["method"] == "thread/list")) == 30
    assert Enum.count(frames, &(&1["method"] == "thread/search")) == 30
    assert byte_size(JSON.encode!(frames)) <= 262_144
  end

  defp matrix(ctx, pid, expected, snippets) do
    for method <- ["thread/list", "thread/search"] do
      base =
        if method == "thread/list",
          do: %{"limit" => 100, "useStateDbOnly" => true},
          else: %{"limit" => 100, "searchTerm" => @needle}

      assert_page(method, call(ctx, pid, method, base), expected, snippets)

      for kind <- @kinds do
        excluded = call(ctx, pid, method, Map.put(base, "sourceKinds", [kind]))
        assert Map.fetch!(excluded, "data") === []
        assert Map.fetch!(excluded, "nextCursor") === nil
        assert Map.fetch!(excluded, "backwardsCursor") === nil
        mixed = call(ctx, pid, method, Map.put(base, "sourceKinds", [kind, "vscode"]))
        assert_page(method, mixed, expected, snippets)
        assert length(requests(ctx)) == 2
      end
    end
  end

  defp assert_page(method, page, expected, snippets) do
    rows = Map.fetch!(page, "data")
    assert length(rows) == map_size(expected)

    threads =
      if method == "thread/search", do: Enum.map(rows, &Map.fetch!(&1, "thread")), else: rows

    ids = Enum.map(threads, &Map.fetch!(&1, "id"))
    assert length(Enum.uniq(ids)) == length(ids)
    assert MapSet.new(ids) == MapSet.new(Map.keys(expected))
    assert Map.fetch!(page, "nextCursor") === nil

    for thread <- threads do
      assert Map.take(thread, @projection) === Map.fetch!(expected, Map.fetch!(thread, "id"))
    end

    if method == "thread/search" do
      for row <- rows do
        assert Map.fetch!(row, "snippet") === Map.fetch!(snippets, row["thread"]["id"])
      end
    end
  end

  defp source(ctx, pid, index) do
    initial =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "legacy",
        "ephemeral" => false,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]

    id = Map.fetch!(initial, "id")
    assert is_binary(id) and id != ""
    assert Map.fetch!(initial, "source") === "vscode"
    text = "#{index}: " <> @needle
    began = System.system_time(:microsecond) / 1_000_000

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => id,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

    assert is_binary(turn) and turn != ""
    events = complete_turn(pid, id, turn, [], now() + 20_000)
    ended = System.system_time(:microsecond) / 1_000_000
    assert_answer(events, id, turn)
    assert_no_work(events)
    assert_provider(ctx, id, turn, text, index)

    # Synchronous full read is the producer's durability barrier; turn/completed
    # alone does not establish the source file or the native search projection.
    saved = call(ctx, pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert %{"id" => ^id, "source" => "vscode", "historyMode" => "legacy"} = saved

    assert [
             %{
               "id" => ^turn,
               "status" => "completed",
               "error" => nil,
               "items" => [user_item, agent_item]
             }
           ] = saved["turns"]

    assert Map.fetch!(user_item, "type") == "userMessage"

    assert Enum.map(user_item["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => text}
           ]

    assert %{"type" => "agentMessage", "text" => @answer} = agent_item
    path = Map.fetch!(saved, "path")
    {bytes, records} = rollout(ctx, path)
    metadata = for %{"type" => "session_meta", "payload" => payload} <- records, do: payload
    assert metadata != []

    for meta <- metadata do
      assert Map.fetch!(meta, "id") === id
      assert Map.fetch!(meta, "source") === "vscode"
      assert Map.fetch!(meta, "cwd") === ctx.fixture.workspace
    end

    assert_source_items(records, id, turn, text, index, began, ended)

    projection = %{
      "id" => id,
      "source" => "vscode",
      "preview" => text,
      "cwd" => ctx.fixture.workspace,
      "modelProvider" => "fixture",
      "path" => path,
      "historyMode" => "legacy",
      "turns" => []
    }

    %{id: id, turn: turn, text: text, path: path, bytes: bytes, projection: projection}
  end

  defp assert_source_items(records, _thread, turn, text, index, began, ended) do
    items = for %{"type" => "response_item", "payload" => payload} <- records, do: payload

    assert [user] =
             Enum.filter(
               items,
               &(&1["role"] == "user" and
                   &1["content"] === [%{"type" => "input_text", "text" => text}])
             )

    id = Map.fetch!(user, "id")
    created = get_in(user, [@metadata, "create_time"])
    assert is_binary(id) and id != ""
    assert is_number(created) and created >= began and created <= ended

    assert user === %{
             "type" => "message",
             "id" => id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => text}],
             @metadata => %{
               "turn_id" => turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }

    assert [assistant] = Enum.filter(items, &(&1["id"] == "fixture-message-#{index}"))

    assert assistant === %{
             "type" => "message",
             "id" => "fixture-message-#{index}",
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @answer}],
             @metadata => %{"turn_id" => turn, "content_item_kinds" => ["unknown"]}
           }

    refute Enum.any?(records, &(&1["type"] == "compacted"))

    refute Enum.any?(
             items,
             &(&1["type"] in [
                 "function_call",
                 "function_call_output",
                 "custom_tool_call",
                 "custom_tool_call_output",
                 "local_shell_call",
                 "compaction",
                 "compaction_trigger"
               ])
           )
  end

  defp assert_provider(ctx, thread, turn, text, count) do
    journal = requests(ctx)
    assert length(journal) == count
    request = List.last(journal)
    assert Map.fetch!(request, "model") === "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    assert Enum.count(
             request["input"],
             &(&1["role"] == "user" and
                 &1["content"] === [%{"type" => "input_text", "text" => text}])
           ) == 1
  end

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_event_bounds(events)
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    terminal = notification(events, "turn/completed", thread, turn)

    if terminal do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               terminal

      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
               notification(events, "turn/started", thread, turn)

      assert Enum.count(
               events,
               &(&1.wire["method"] == "turn/completed" and
                   get_in(&1.wire, ["params", "threadId"]) == thread and
                   get_in(&1.wire, ["params", "turn", "id"]) == turn)
             ) == 1

      events
    else
      assert now() < until, "Native source-filter turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          complete_turn(pid, thread, turn, events, until)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected source-filter event gap")
      after
        max(until - now(), 0) -> flunk("Native source-filter turn deadline")
      end
    end
  end

  defp notification(events, method, thread, turn),
    do:
      TurnFixture.notification(
        events,
        method,
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp assert_answer(events, thread, turn) do
    completed =
      for event <- events,
          event.wire["method"] == "item/completed",
          get_in(event.wire, ["params", "threadId"]) == thread,
          get_in(event.wire, ["params", "turnId"]) == turn,
          get_in(event.wire, ["params", "item", "type"]) == "agentMessage",
          do: event.wire["params"]["item"]

    assert [%{"id" => id, "type" => "agentMessage", "text" => @answer}] = completed

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"id" => ^id, "type" => "agentMessage"}
           } =
             TurnFixture.notification(
               events,
               "item/started",
               &(&1["threadId"] == thread and &1["turnId"] == turn and &1["item"]["id"] == id)
             )
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert_event_bounds(events)
    assert_no_work(events)

    refute Enum.any?(
             events,
             &(String.starts_with?(&1.wire["method"] || "", "turn/") or
                 String.starts_with?(&1.wire["method"] || "", "item/"))
           )

    assert length(requests(ctx)) == 2
  end

  defp assert_no_work(events) do
    assert Enum.filter(events, &(&1.kind == :server_request)) === []

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ["error", "thread/compacted"] or
               get_in(event.wire, ["params", "item", "type"]) in [
                 "commandExecution",
                 "fileChange",
                 "mcpToolCall",
                 "dynamicToolCall",
                 "webSearch",
                 "imageGeneration",
                 "contextCompaction"
               ]
           end)
  end

  defp assert_event_bounds(events) do
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-source-filter-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [actual] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

  defp start(ctx) do
    f = ctx.fixture

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
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":/usr/bin:/bin",
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
               %{"name" => "owned_source_filter_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp rollout(ctx, path) do
    assert is_binary(path)
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    bytes = bounded_file(path)
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048

    records =
      Enum.map(lines, fn line ->
        assert byte_size(line) <= @max_line_bytes
        JSON.decode!(line)
      end)

    {bytes, records}
  end

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.lstat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) == size
    bytes
  end

  defp snapshot(path), do: bounded_file(path)

  defp requests(ctx) do
    journal = JSON.decode!(bounded_file(ctx.fixture.requests))
    assert is_list(journal) and length(journal) <= 2
    journal
  end

  defp assert_retained(ctx, rows, journal) do
    assert snapshot(ctx.fixture.requests) === journal
    for {path, bytes} <- ctx.inputs, do: assert(snapshot(path) === bytes)
    for row <- rows, do: assert(snapshot(row.path) === row.bytes)
    assert File.ls!(ctx.fixture.workspace) === []
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
      assert remaining > 0, "Owned source-filter native #{native} survived cleanup"
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

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
