defmodule SamgitaCodexDriver.NativeExecSourceValuesTest do
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
  @needle "Owned genuine Exec source discovery 163 λ"
  @exec_prompt "CLI producer: " <> @needle
  @control_prompt "Driver control: " <> @needle
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary Exec source fixture instructions."
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144
  @projection ~w(id source preview cwd modelProvider path historyMode turns)

  # Exec reads piped stdin even with a positional prompt. Replace only the
  # child's stdin with EOF, leaving stdio_owner.py's distinct control pipe intact.
  # execv retains this owned child's PID/process group; there is no extra child.
  @exec_launcher """
  import json, os, pathlib, sys
  record, executable, arguments = sys.argv[1], sys.argv[2], sys.argv[2:]
  pathlib.Path(record).write_text(json.dumps({
      "pid": os.getpid(), "executable": executable, "argv": arguments,
  }))
  with open(os.devnull, "rb") as empty:
      os.dup2(empty.fileno(), 0)
  os.execv(executable, arguments)
  """

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

        if ledger.count < 128 and size <= 262_144 and ledger.bytes + size <= 1_048_576 do
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
        "samgita-exec-source-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
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

  test "genuine CLI Exec and driver vscode sources retain positive list and search filters through cold discovery",
       ctx do
    cli = produce_exec(ctx)
    assert length(requests(ctx)) == 1
    exec_identity = provider_identity(ctx, 1, @exec_prompt)
    assert exec_identity.thread == cli.thread

    # The producer's canonical first metadata is observed before any app-server
    # reader starts; no fabricated SessionMeta/SQLite or attribution rewrite.
    exec_path = only_rollout(ctx)

    exec_source =
      canonical(ctx, exec_path, cli.thread, exec_identity.turn, "exec", @exec_prompt, 1)

    producer = start(ctx)
    producer_native = native_id(ctx, producer)
    exec = history(ctx, producer, exec_source)
    control = produce_control(ctx, producer)
    assert exec.id != control.id and exec.turn != control.turn and exec.path != control.path
    assert length(requests(ctx)) == 2
    close(producer, producer_native)

    # Native shutdown is allowed to finish the producer. The frozen discovery
    # baseline starts only after both actual producers are normally closed.
    rows =
      for row <- [exec, control] do
        observed = canonical(ctx, row.path, row.id, row.turn, row.source, row.text, row.index)
        assert observed.user === row.user
        assert observed.assistant === row.assistant
        assert observed.completed_user === row.completed_user
        assert observed.completed_assistant === row.completed_assistant
        assert observed.environment_context === row.environment_context
        Map.merge(row, %{bytes: observed.bytes})
      end

    [frozen_exec, _control] = rows
    assert frozen_exec.bytes === exec_source.bytes
    journal = bounded_file(ctx.fixture.requests)
    artifacts = %{cli.output_path => cli.bytes, cli.record_path => cli.record_bytes}
    assert_retained(ctx, rows, journal, artifacts)

    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    assert_unloaded(ctx, warm)
    matrix(ctx, warm, rows)
    assert_unloaded(ctx, warm)
    assert_histories(ctx, warm, rows)
    assert_idle(ctx, warm)
    assert_retained(ctx, rows, journal, artifacts)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native in [producer_native, warm_native, cli.native]
    assert_unloaded(ctx, cold)

    # First content queries in replacement native process are source-filter
    # discovery, before full history paging, resume or any new turn.
    matrix(ctx, cold, rows)
    assert_unloaded(ctx, cold)
    assert_histories(ctx, cold, rows)
    assert_idle(ctx, cold)
    assert_retained(ctx, rows, journal, artifacts)
    close(cold, cold_native)
    assert_retained(ctx, rows, journal, artifacts)
    assert length(requests(ctx)) == 2
    assert hash(File.read!(ctx.binary)) == @binary_sha
    assert_wire_inventory(ctx)
  end

  defp produce_exec(ctx) do
    record_path = Path.join(ctx.root, "exec-owned-process.json")

    native_args =
      NativeLaunchFixture.ordinary_args([
        "exec",
        "--json",
        "--skip-git-repo-check",
        "--color",
        "never",
        @exec_prompt
      ])

    assert {:ok, connection} =
             Stdio.open(
               executable: System.find_executable("python3"),
               args: ["-B", "-c", @exec_launcher, record_path, ctx.binary | native_args],
               cwd: ctx.fixture.workspace,
               inherit_env: [],
               env: environment(ctx),
               max_message_bytes: @max_line_bytes
             )

    on_exit(fn -> assert :ok = Stdio.close(connection) end)

    collected =
      try do
        collect_exec(connection, [], <<>>, now() + 20_000)
      after
        assert :ok = Stdio.close(connection)
      end

    assert :atomics.get(connection.owner.completion, 1) == 1
    assert Port.info(connection.port) == nil
    record_bytes = bounded_file(record_path)
    assert byte_size(record_bytes) <= 4096
    record = JSON.decode!(record_bytes)
    native = Map.fetch!(record, "pid")
    assert is_integer(native) and native > 0
    assert Map.fetch!(record, "executable") === ctx.binary
    assert Map.fetch!(record, "argv") === [ctx.binary | native_args]
    assert_gone(native)
    records = Enum.map(collected.lines, &JSON.decode!/1)
    assert Enum.all?(records, &is_map/1)

    assert [%{"type" => "thread.started", "thread_id" => thread}] =
             of_type(records, "thread.started")

    assert is_binary(thread) and thread != ""
    assert of_type(records, "turn.started") == [%{"type" => "turn.started"}]
    assert [%{"type" => "turn.completed", "usage" => usage}] = of_type(records, "turn.completed")
    assert is_map(usage)
    assert of_type(records, "error") == [] and of_type(records, "turn.failed") == []

    messages =
      for %{"type" => "item.completed", "item" => %{"type" => "agent_message"} = item} <- records,
          do: item

    assert [%{"id" => item_id, "type" => "agent_message", "text" => @answer}] = messages
    assert is_binary(item_id) and item_id != ""
    assert hd(records)["type"] == "thread.started"
    assert List.last(records)["type"] == "turn.completed"
    assert collected.bytes === Enum.join(collected.lines, "\n") <> "\n"
    output_path = Path.join(ctx.root, "exec-stdout.jsonl")
    File.write!(output_path, collected.bytes, [:exclusive])
    assert bounded_file(output_path) === collected.bytes

    %{
      thread: thread,
      native: native,
      output_path: output_path,
      bytes: collected.bytes,
      record_path: record_path,
      record_bytes: record_bytes
    }
  end

  defp collect_exec(state, lines, bytes, until) do
    port = state.port
    remaining = max(until - now(), 0)
    assert remaining > 0, "Owned native Exec deadline"

    receive do
      {^port, {:data, data}} = message ->
        bytes = bytes <> data
        assert byte_size(bytes) <= 1_048_576
        assert {:ok, events, next} = Stdio.handle_info(message, state)
        incoming = for {:message, encoded} <- events, do: encoded
        assert length(incoming) == length(events)
        lines = lines ++ incoming
        assert length(lines) <= 128
        collect_exec(next, lines, bytes, until)

      {^port, {:exit_status, _}} = message ->
        assert {:ok, [{:closed, closed}], next} = Stdio.handle_info(message, state)
        assert closed === %{"exit_status" => 0, "partial_message" => false}
        assert next.buffer === <<>>
        %{lines: lines, bytes: bytes}
    after
      remaining -> flunk("Owned native Exec deadline")
    end
  end

  defp of_type(records, type), do: Enum.filter(records, &(&1["type"] == type))

  defp only_rollout(ctx) do
    paths = Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl"))
    assert [path] = paths
    path
  end

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
    identity = provider_identity(ctx, 2, @control_prompt)
    assert identity === %{thread: id, turn: turn}

    # Paging actual full persisted turns is the native durability observation;
    # includeTurns:true is deliberately never used for paginated history.
    path = Map.fetch!(initial, "path")
    source = %{id: id, turn: turn, source: "vscode", text: @control_prompt, index: 2, path: path}
    stored = history(ctx, pid, source)
    canonical = canonical(ctx, path, id, turn, "vscode", @control_prompt, 2)
    assert stored.user === canonical.user
    assert stored.assistant === canonical.assistant
    stored
  end

  defp history(ctx, pid, source) do
    metadata =
      call(ctx, pid, "thread/read", %{"threadId" => source.id, "includeTurns" => false})["thread"]

    expected = %{
      "id" => source.id,
      "source" => source.source,
      "preview" => source.text,
      "cwd" => ctx.fixture.workspace,
      "modelProvider" => "fixture",
      "path" => source.path,
      "historyMode" => "paginated",
      "turns" => []
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
    assert [turn] = Map.fetch!(page, "data")
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

    # Paginated APIs project durable ItemCompleted TurnItems. Native user input
    # creates that item's UUID separately from the raw ResponseItem's msg_ ID.
    assert user["id"] === raw.completed_user["id"]
    refute user["id"] === raw.user["id"]
    assert assistant["id"] === raw.completed_assistant["id"]
    assert assistant["id"] === raw.assistant["id"]
    Map.merge(raw, %{projection: expected, items: [user, assistant]})
  end

  defp canonical(ctx, path, id, turn, source, text, index) do
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    bytes = bounded_file(path)
    records = jsonl(bytes)
    assert [%{"type" => "session_meta", "payload" => first} | _] = records
    assert Map.fetch!(first, "id") === id
    assert Map.fetch!(first, "source") === source
    assert Map.fetch!(first, "thread_source") === "user"
    assert Map.fetch!(first, "history_mode") === "paginated"
    assert Map.fetch!(first, "cwd") === ctx.fixture.workspace
    assert Map.fetch!(first, "model_provider") === "fixture"
    assert Map.fetch!(first, "cli_version") === "0.163.0"

    payloads = for %{"type" => "response_item", "payload" => payload} <- records, do: payload

    # Native initial context is a separate classified user-role message. Keep
    # it intact and require the single actual user prompt after it; its opaque
    # environment text is not a policy or permission behavior oracle.
    assert [environment_context, user] = Enum.filter(payloads, &(&1["role"] == "user"))

    assert %{"type" => "message", "content" => [%{"type" => "input_text", "text" => context}]} =
             environment_context

    assert is_binary(context) and context != ""
    assert is_binary(environment_context["id"]) and environment_context["id"] != ""

    assert get_in(environment_context, [@metadata, "content_item_kinds"]) ===
             ["environments.environment_context"]

    assert get_in(environment_context, [@metadata, "turn_id"]) === turn
    assert user["content"] === [%{"type" => "input_text", "text" => text}]
    assert is_binary(user["id"]) and user["id"] != ""
    refute user["id"] == environment_context["id"]
    assert get_in(user, [@metadata, "content_item_kinds"]) === ["user.text"]
    assert get_in(user, [@metadata, "turn_id"]) === turn
    assert [assistant] = Enum.filter(payloads, &(&1["role"] == "assistant"))
    assert Map.fetch!(assistant, "id") === "fixture-message-#{index}"
    assert assistant["content"] === [%{"type" => "output_text", "text" => @answer}]
    assert get_in(assistant, [@metadata, "turn_id"]) === turn
    event_payloads = for %{"type" => "event_msg", "payload" => event} <- records, do: event
    assert [%{"turn_id" => ^turn}] = of_type(event_payloads, "task_started")
    assert [completed] = of_type(event_payloads, "task_complete")
    assert Map.fetch!(completed, "turn_id") === turn
    assert Map.fetch!(completed, "last_agent_message") === @answer
    assert Map.get(completed, "error") === nil

    assert [user_event, assistant_event] = of_type(event_payloads, "item_completed")

    for event <- [user_event, assistant_event] do
      assert Map.fetch!(event, "thread_id") === id
      assert Map.fetch!(event, "turn_id") === turn
      assert is_integer(event["started_at_ms"]) and event["started_at_ms"] > 0
      assert event["completed_at_ms"] >= event["started_at_ms"]
    end

    completed_user = Map.fetch!(user_event, "item")
    completed_assistant = Map.fetch!(assistant_event, "item")

    assert %{"type" => "UserMessage", "content" => [%{"type" => "text", "text" => ^text}]} =
             completed_user

    assert is_binary(completed_user["id"]) and completed_user["id"] != ""
    refute completed_user["id"] === user["id"]

    assert %{"type" => "AgentMessage", "content" => [%{"type" => "Text", "text" => @answer}]} =
             completed_assistant

    assert completed_assistant["id"] === assistant["id"]

    %{
      id: id,
      turn: turn,
      source: source,
      text: text,
      index: index,
      path: path,
      bytes: bytes,
      user: user,
      completed_user: completed_user,
      completed_assistant: completed_assistant,
      environment_context: environment_context,
      assistant: assistant
    }
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

    assert Enum.any?(request["input"], fn item ->
             item["role"] == "developer" and
               item["content"] === [%{"type" => "input_text", "text" => @instructions}]
           end)

    %{thread: thread, turn: turn}
  end

  defp matrix(ctx, pid, rows) do
    for method <- ["thread/list", "thread/search"],
        kinds <- [["exec"], ["vscode"], ["exec", "vscode"]] do
      base =
        if method == "thread/list",
          do: %{"limit" => 100, "useStateDbOnly" => true},
          else: %{"limit" => 100, "searchTerm" => @needle}

      expected = Enum.filter(rows, &(&1.source in kinds))
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
        assert Map.take(thread, @projection) === original.projection
      end

      assert_snippets(method, data, expected)
      assert length(requests(ctx)) == 2
    end
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
      assert observed.completed_user === row.completed_user
      assert observed.completed_assistant === row.completed_assistant
      assert observed.environment_context === row.environment_context
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
    assert remaining > 0, "Owned native vscode control deadline"

    receive do
      {:codex_driver, ^pid, :events_available} -> complete_turn(pid, thread, turn, events, until)
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary control event gap")
    after
      remaining -> flunk("Owned native vscode control deadline")
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
    id = "owned-exec-source-#{System.unique_integer([:positive, :monotonic])}"
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

    for method <- ["thread/list", "thread/search"] do
      queries = Enum.filter(outgoing, &(&1["method"] == method))
      assert length(queries) == 6

      for kinds <- [["exec"], ["vscode"], ["exec", "vscode"]] do
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
               %{"name" => "owned_exec_source_values", "version" => "0.1.0"},
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

  defp assert_retained(ctx, rows, journal, artifacts) do
    assert bounded_file(ctx.fixture.requests) === journal
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    for {path, bytes} <- artifacts, do: assert(bounded_file(path) === bytes)
    for row <- rows, do: assert(bounded_file(row.path) === row.bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
