defmodule SamgitaCodexDriver.NativeSuppliedAgentMessageHistoryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/supplied_agent_message_history_fixture.py", __DIR__)
  @original_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @original_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @source_script Path.expand("support/native_subagent_activity_fixture.py", __DIR__)
  @source_sha "4575d44a3fe71aab346f1b455d4ffc235f23e55b2aa1bdede17745f0f5f59851"
  @marker "OWNED_ACTIVITY_ROOT_V39"
  @child_marker "OWNED_ACTIVITY_CHILD_V39"
  @child_path "/root/activity_child"
  @child_answer "Owned activity child done"
  @source_answer "Owned activity root done"
  @spawn "owned-v39-spawn-activity"
  @wait "owned-v39-wait-activity"
  @followup "Owned continuation consumes supplied AgentMessage history 163 λ"
  @answer "Owned imported AgentMessage evidence consumed λ"
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(binary) == @binary_sha
    assert hash(@original_script) == @original_sha
    assert hash(@source_script) == @source_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-agent-message-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    ctx = %{binary: binary, fixture: fixture, root: root}

    TurnFixture.configure_model(ctx, %{
      "multi_agent_version" => "v2",
      "supported_reasoning_levels" => [
        %{"effort" => "medium", "description" => "Owned synthetic medium effort"}
      ],
      "default_reasoning_level" => "medium"
    })

    unchanged =
      Enum.map(
        [
          @script,
          @original_script,
          @source_script,
          Path.join(fixture.codex_home, "config.toml"),
          Path.join(fixture.codex_home, "turn-models.json")
        ],
        fn path -> {path, File.read!(path)} end
      )

    Map.put(ctx, :unchanged, unchanged)
  end

  for null_metadata <- [false, true] do
    @tag null_metadata: null_metadata
    test "native AgentMessage survives cold supplied history, client_null=#{null_metadata}",
         ctx do
      source = start(ctx)
      source_native = native_process(source)

      source_id =
        TurnFixture.thread(ctx, source, %{
          "historyMode" => "legacy",
          "approvalPolicy" => "never",
          "sandbox" => "danger-full-access"
        })

      began = System.system_time(:microsecond) / 1_000_000

      source_turn =
        TurnFixture.start_turn(source, source_id, text(@marker), %{"effort" => "medium"})

      source_events = collect(source, &terminal(&1, source_turn), [], now() + 20_000)
      assert_completed(source_events, source_id, source_turn)
      assert_answer(source_events, source_id, source_turn, @source_answer)
      source_requests = requests(ctx)
      assert length(source_requests) == 4
      assert_observed(ctx, false)
      assert_no_work(ctx, source, source_events)

      # Independent native reads establish the actual one child and its terminal
      # turn. The provider supplies only model replies, not child/history records.
      assert [child] = children(source, source_id)
      child_id = child["id"]
      assert is_binary(child_id) and child_id != "" and child_id != source_id
      assert child["parentThreadId"] == source_id
      child_thread = read_thread(source, child_id)
      assert [%{"id" => child_turn, "status" => "completed"}] = child_thread["turns"]
      assert is_binary(child_turn) and child_turn != ""
      child_source_path = child_thread["path"]
      source_path = read_thread(source, source_id)["path"]
      ended = System.system_time(:microsecond) / 1_000_000
      assert :ok = Session.close(source)
      assert_gone(source_native)

      # Capture real native maps only after the source and child have stopped.
      # The communication metadata sidecar is separate and is not imported.
      {source_bytes, rows} = rollout(ctx, source_path)
      {child_bytes, _child_rows} = rollout(ctx, child_source_path)
      ctx = Map.put(ctx, :source_files, [{child_source_path, child_bytes}])
      history = captured_history(rows, source_turn, began, ended)
      [user, message] = history
      assert_source_requests(source_requests, message)

      {submitted, expected_history} =
        if ctx.null_metadata do
          modified = Map.put(message, @metadata, nil)
          assert Map.has_key?(modified, @metadata)
          assert Map.fetch!(modified, @metadata) === nil
          assert Map.delete(modified, @metadata) === Map.delete(message, @metadata)
          {[user, modified], [user, Map.delete(message, @metadata)]}
        else
          {history, history}
        end

      if ctx.null_metadata, do: assert(submitted !== history), else: assert(submitted === history)
      assert byte_size(JSON.encode!(submitted)) <= 1_048_576
      cold = start(ctx)
      cold_native = native_process(cold)
      refute cold_native == source_native
      assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

      # Raw history is explicitly unstable upstream. It does not restore a child,
      # dispatch the historical message or recreate the source collaboration.
      imported =
        call(cold, "thread/resume", %{
          "threadId" => source_id,
          "history" => submitted,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.fixture.workspace,
          "approvalPolicy" => "never",
          "sandbox" => "danger-full-access"
        })["thread"]

      imported_id = imported["id"]
      assert is_binary(imported_id) and imported_id != "" and imported_id != source_id
      assert imported["preview"] == @marker
      assert imported["status"] === %{"type" => "idle"}
      imported_path = read_thread(cold, imported_id)["path"]
      refute imported_path in [source_path, child_source_path]
      assert_import(ctx, imported_path, expected_history)
      assert children(cold, imported_id) === []

      assert call(cold, "thread/loaded/list", %{}) === %{
               "data" => [imported_id],
               "nextCursor" => nil
             }

      assert {:ok, import_events} = Session.drain(cold, 256)
      assert length(import_events) <= 256
      assert byte_size(JSON.encode!(Enum.map(import_events, & &1.wire))) <= 1_048_576
      assert Session.status(cold).buffered_events == 0
      assert_no_work(ctx, cold, import_events)
      refute Enum.any?(import_events, &(&1.wire["method"] == "turn/started"))
      assert requests(ctx) === source_requests
      assert_observed(ctx, false)
      assert_retained(ctx, source_path, source_bytes)

      followup_turn =
        TurnFixture.start_turn(cold, imported_id, text(@followup), %{"effort" => "medium"})

      followup = collect(cold, &terminal(&1, followup_turn), [], now() + 20_000)
      assert_completed(followup, imported_id, followup_turn)
      assert_answer(followup, imported_id, followup_turn, @answer)
      assert_no_work(ctx, cold, followup)

      refute Enum.any?(followup, fn event ->
               get_in(event.wire, ["params", "item", "type"]) in [
                 "subAgentActivity",
                 "collabAgentToolCall",
                 "dynamicToolCall"
               ]
             end)

      assert [consumed] = requests(ctx) -- source_requests
      assert requests(ctx) === source_requests ++ [consumed]
      assert_provider(consumed, message)
      assert_observed(ctx, true)
      assert children(cold, imported_id) === []

      assert call(cold, "thread/loaded/list", %{}) === %{
               "data" => [imported_id],
               "nextCursor" => nil
             }

      assert read_thread(cold, imported_id)["path"] == imported_path
      assert_import(ctx, imported_path, expected_history)
      assert_retained(ctx, source_path, source_bytes)
      assert :ok = Session.close(cold)
      assert_gone(cold_native)
      assert_import(ctx, imported_path, expected_history)
      assert requests(ctx) === source_requests ++ [consumed]
      assert_observed(ctx, true)
      assert_retained(ctx, source_path, source_bytes)
    end
  end

  defp captured_history(rows, source_turn, began, ended) do
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item

    assert [user] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @marker}]
             end)

    assert [message] = Enum.filter(payloads, &(&1["type"] == "agent_message"))
    selected = Enum.filter(payloads, &(&1 === user or &1 === message))
    assert selected === [user, message]
    assert_source_user(user, source_turn, began, ended)
    assert_source_message(message, source_turn, began, ended)
    refute user["id"] == message["id"]
    refute Enum.any?(rows, &(&1["type"] == "compacted"))
    selected
  end

  defp assert_source_user(user, source_turn, began, ended) do
    user_id = Map.fetch!(user, "id")
    assert is_binary(user_id) and byte_size(user_id) > 0
    user_created = user[@metadata]["create_time"]
    assert is_number(user_created) and user_created >= began and user_created <= ended

    assert user === %{
             "type" => "message",
             "id" => user_id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => @marker}],
             @metadata => %{
               "turn_id" => source_turn,
               "create_time" => user_created,
               "content_item_kinds" => ["user.text"]
             }
           }
  end

  defp assert_source_message(message, source_turn, began, ended) do
    id = Map.fetch!(message, "id")
    assert is_binary(id) and String.starts_with?(id, "amsg_") and byte_size(id) > 5
    created = message[@metadata]["create_time"]
    assert is_number(created) and created > 0 and created >= began and created <= ended

    assert message ===
             Map.merge(provider_message(id), %{
               @metadata => %{"turn_id" => source_turn, "create_time" => created}
             })
  end

  defp assert_import(ctx, path, history) do
    {_bytes, rows} = rollout(ctx, path)
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert length(Enum.uniq(ids)) == 2
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
    assert Enum.filter(payloads, &user_marker?([&1], @marker)) === [hd(history)]
    assert Enum.filter(payloads, &(&1["type"] == "agent_message")) === [List.last(history)]

    refute Enum.any?(payloads, fn item ->
             item["type"] in [
               "function_call",
               "function_call_output",
               "custom_tool_call",
               "custom_tool_call_output",
               "tool_search_call",
               "tool_search_output",
               "local_shell_call"
             ]
           end)

    refute Enum.any?(rows, &(&1["type"] in ["compacted", "inter_agent_communication_metadata"]))
  end

  defp assert_source_requests(requests, message) do
    root_requests = Enum.filter(requests, &user_marker?(&1["input"], @marker))
    assert length(root_requests) == 3
    assert [child] = requests -- root_requests
    assert child["model"] == "mock-model"

    assert [incoming] = Enum.filter(child["input"], &(&1["type"] == "agent_message"))
    assert incoming["author"] == "/root"
    assert incoming["recipient"] == @child_path

    assert incoming["content"] === [
             %{
               "type" => "input_text",
               "text" =>
                 "Message Type: NEW_TASK\nTask name: /root/activity_child\nSender: /root\nPayload:\n" <>
                   @child_marker
             }
           ]

    outputs =
      for request <- root_requests,
          item <- request["input"],
          item["type"] == "function_call_output",
          do: {item["call_id"], JSON.decode!(item["output"])}

    assert Enum.uniq(outputs) |> Enum.sort() ===
             Enum.sort([
               {@spawn, %{"task_name" => @child_path}},
               {@wait, %{"message" => "Wait completed.", "timed_out" => false}}
             ])

    assert Enum.filter(List.last(root_requests)["input"], &(&1["type"] == "agent_message")) ===
             [Map.delete(message, @metadata)]

    for request <- requests do
      assert request["model"] == "mock-model"
      assert request["reasoning"]["effort"] == "medium"
    end
  end

  defp assert_provider(request, message) do
    input = request["input"]

    assert Enum.filter(input, &(&1["type"] == "agent_message")) ===
             [Map.delete(message, @metadata)]

    assert Map.delete(message, @metadata) === provider_message(message["id"])

    for marker <- [@marker, @followup] do
      assert Enum.count(input, &user_marker?([&1], marker)) == 1
    end

    metadata = request["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["history_initialization"] == "supplied_history"
  end

  defp provider_message(id) do
    %{
      "type" => "agent_message",
      "id" => id,
      "author" => @child_path,
      "recipient" => "/root",
      "content" => [
        %{
          "type" => "input_text",
          "text" =>
            "Message Type: FINAL_ANSWER\nTask name: /root\nSender: /root/activity_child\nPayload:\n" <>
              @child_answer
        }
      ]
    }
  end

  defp user_marker?(items, marker),
    do:
      Enum.any?(items, fn item ->
        item["role"] == "user" and
          item["content"] === [%{"type" => "input_text", "text" => marker}]
      end)

  defp assert_observed(ctx, followup?) do
    path = Path.join(ctx.root, "activity-observed.json")
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size <= @max_file_bytes
    responses = ["spawn", "wait", "child_final", "root_final"]
    expected = if followup?, do: responses ++ ["import_followup"], else: responses

    assert path |> File.read!() |> JSON.decode!() === %{
             "root_requests" => 3,
             "child_requests" => 1,
             "responses" => expected,
             "errors" => []
           }
  end

  defp children(pid, root) do
    assert %{"data" => data, "nextCursor" => nil} =
             call(pid, "thread/list", %{
               "parentThreadId" => root,
               "sortKey" => "created_at",
               "limit" => 100,
               "useStateDbOnly" => true
             })

    assert is_list(data)
    data
  end

  defp assert_answer(events, thread, turn, answer) do
    completed =
      for %{
            wire: %{
              "method" => "item/completed",
              "params" =>
                %{
                  "threadId" => ^thread,
                  "turnId" => ^turn,
                  "item" => %{"type" => "agentMessage"}
                } = params
            }
          } <- events,
          do: params

    assert [
             %{
               "threadId" => ^thread,
               "turnId" => ^turn,
               "item" => %{"type" => "agentMessage", "text" => ^answer}
             }
           ] = completed
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "samgita_supplied_agent_message", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp collect(pid, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "Native supplied-AgentMessage event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, events, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected supplied-AgentMessage gap")
      after
        max(deadline - now(), 0) -> flunk("Native supplied-AgentMessage event deadline")
      end
    end
  end

  defp terminal(events, turn),
    do: notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp assert_completed(events, thread, turn) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             terminal(events, turn)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             notification(events, "turn/started", &(&1["turn"]["id"] == turn))

    assert [event] =
             Enum.filter(
               events,
               &(&1.wire["method"] == "turn/completed" and
                   get_in(&1.wire, ["params", "turn", "id"]) == turn)
             )

    assert event.wire["params"]["threadId"] == thread
  end

  defp assert_no_work(ctx, pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Enum.filter(events, &(&1.kind == :server_request)) === []
    assert File.ls!(ctx.fixture.workspace) === []
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
    assert length(rows) <= 5
    rows
  end

  defp assert_retained(ctx, source_path, source_bytes) do
    assert File.read!(source_path) === source_bytes
    for {path, bytes} <- ctx.source_files, do: assert(File.read!(path) === bytes)
    for {path, bytes} <- ctx.unchanged, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned supplied-AgentMessage native #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]
  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
