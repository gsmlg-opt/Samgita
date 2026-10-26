defmodule SamgitaCodexDriver.NativeSuppliedLocalShellHistoryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand(
            "../../../scripts/codex/supplied_local_shell_history_fixture.py",
            __DIR__
          )
  @script_sha "f79e843b2a33cd2154b038f249fe1daa21909ad50c13e9490077e1e5e031cf64"
  @in_progress_script Path.expand(
                        "../../../scripts/codex/supplied_in_progress_local_shell_history_fixture.py",
                        __DIR__
                      )
  @in_progress_sha "32ce3a38c1f6b72abde6b0db02b21242af60ebda6be72c952fa454945d8f7850"
  @original_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @original_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @marker "Owned generic current local-shell history 163 λ"
  @followup "Owned continuation consumes current local-shell history 163 λ"
  @command ["owned-inert-current-history-data-163"]
  @source_answer "Owned source local-shell evidence completed λ"
  @answer "Owned imported local-shell evidence consumed λ"
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(binary) == @binary_sha
    assert hash(@script) == @script_sha
    assert hash(@in_progress_script) == @in_progress_sha
    assert hash(@original_script) == @original_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-local-shell-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    shell_status = Map.get(tags, :shell_status, "incomplete")
    script = if shell_status == "in_progress", do: @in_progress_script, else: @script
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", script)

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

    ctx = %{binary: binary, fixture: fixture, root: root, shell_status: shell_status}
    TurnFixture.configure_model(ctx, %{})

    unchanged =
      Enum.map(
        [
          @script,
          @in_progress_script,
          @original_script,
          Path.join(fixture.codex_home, "config.toml"),
          Path.join(fixture.codex_home, "turn-models.json")
        ],
        fn path -> {path, File.read!(path)} end
      )

    Map.put(ctx, :unchanged, unchanged)
  end

  for null_metadata <- [false, true] do
    @tag null_metadata: null_metadata
    test "generic current local-shell item survives cold supplied history, client_null=#{null_metadata}",
         ctx do
      assert_history_journey(ctx)
    end
  end

  @tag null_metadata: false, shell_status: "in_progress"
  test "generic current in_progress local-shell data survives native raw output and cold supplied history",
       ctx do
    assert_history_journey(ctx)
  end

  defp assert_history_journey(ctx) do
    source = TurnFixture.start(ctx)
    source_native = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "historyMode" => "legacy",
        "experimentalRawEvents" => true,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    began = System.system_time(:microsecond) / 1_000_000
    source_turn = TurnFixture.start_turn(source, source_id, text(@marker))
    source_events = collect(source, &terminal(&1, source_turn), [], now() + 20_000)
    assert_completed(source_events, source_id, source_turn)
    assert_answer(source_events, source_id, source_turn, @source_answer)
    assert [first] = requests(ctx)
    assert_no_work(ctx, source, source_events)
    source_path = read_thread(source, source_id)["path"]
    ended = System.system_time(:microsecond) / 1_000_000
    assert :ok = Session.close(source)
    assert_gone(source_native)

    # Generic current Responses decoding, not legacy shell execution/emission
    # or call/output pairing. Only actual native payload maps transfer.
    {source_bytes, rows} = rollout(ctx, source_path)
    history = captured_history(rows, source_turn, began, ended, ctx.shell_status)
    [user, shell] = history
    assert_raw_shell(source_events, source_id, source_turn, shell)

    {submitted, expected_history} =
      if ctx.null_metadata do
        # Deliberate current client input; do not label this unchanged native
        # history or evidence that the native source emitted explicit null.
        modified = Map.put(shell, @metadata, nil)
        assert Map.has_key?(modified, @metadata)
        assert Map.fetch!(modified, @metadata) === nil
        assert Map.delete(modified, @metadata) === Map.delete(shell, @metadata)
        {[user, modified], [user, Map.delete(shell, @metadata)]}
      else
        {history, history}
      end

    if ctx.null_metadata, do: assert(submitted !== history), else: assert(submitted === history)
    assert byte_size(JSON.encode!(submitted)) <= 1_048_576
    cold = TurnFixture.start(ctx)
    cold_native = native_process(cold)
    refute cold_native == source_native
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # The raw input is explicitly unstable upstream. Exclude the distinct
    # rollout envelope/harness sidecar; never synthesize native history rows.
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
    refute imported_path == source_path
    assert_import(ctx, imported_path, expected_history)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert length(import_events) <= 256
    assert byte_size(JSON.encode!(Enum.map(import_events, & &1.wire))) <= 1_048_576
    assert Session.status(cold).buffered_events == 0
    assert_no_work(ctx, cold, import_events)
    refute Enum.any?(import_events, &(&1.wire["method"] == "turn/started"))
    assert requests(ctx) === [first]
    assert_retained(ctx, source_path, source_bytes)

    followup_turn = TurnFixture.start_turn(cold, imported_id, text(@followup))
    followup = collect(cold, &terminal(&1, followup_turn), [], now() + 20_000)
    assert_completed(followup, imported_id, followup_turn)
    assert_answer(followup, imported_id, followup_turn, @answer)
    assert_no_work(ctx, cold, followup)
    assert [^first, consumed] = requests(ctx)
    assert_provider(consumed, shell, ctx.shell_status)
    assert read_thread(cold, imported_id)["path"] == imported_path
    assert_import(ctx, imported_path, expected_history)
    assert_retained(ctx, source_path, source_bytes)
    assert :ok = Session.close(cold)
    assert_gone(cold_native)
    assert_import(ctx, imported_path, expected_history)
    assert requests(ctx) === [first, consumed]
    assert_retained(ctx, source_path, source_bytes)
  end

  defp captured_history(rows, source_turn, began, ended, expected_status) do
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item

    assert [user] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @marker}]
             end)

    assert [shell] = Enum.filter(payloads, &(&1["type"] == "local_shell_call"))
    selected = Enum.filter(payloads, &(&1 === user or &1 === shell))
    assert selected === [user, shell]
    assert_source_user(user, source_turn, began, ended)
    assert_source_local_shell(shell, source_turn, user["id"], expected_status)
    refute Enum.any?(rows, &(&1["type"] == "compacted"))
    refute Enum.any?(payloads, &(&1["type"] == "function_call_output"))
    selected
  end

  defp assert_source_user(user, source_turn, began, ended) do
    user_id = Map.fetch!(user, "id")
    assert is_binary(user_id) and byte_size(user_id) > 0
    created = user[@metadata]["create_time"]
    assert is_number(created) and created >= began and created <= ended

    assert user === %{
             "type" => "message",
             "id" => user_id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => @marker}],
             @metadata => %{
               "turn_id" => source_turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }
  end

  defp assert_source_local_shell(shell, source_turn, user_id, expected_status) do
    shell_id = Map.fetch!(shell, "id")
    assert is_binary(shell_id) and String.starts_with?(shell_id, "lsh_")
    assert byte_size(shell_id) > 4 and shell_id != user_id

    assert shell ===
             Map.put(canonical_shell(shell_id, expected_status), @metadata, %{
               "turn_id" => source_turn
             })
  end

  defp assert_raw_shell(events, thread, turn, shell) do
    selected =
      for event <- events,
          event.wire["method"] == "rawResponseItem/completed",
          get_in(event.wire, ["params", "item", "type"]) == "local_shell_call",
          do: event.wire["params"]

    assert selected === [%{"threadId" => thread, "turnId" => turn, "item" => shell}]
  end

  defp assert_import(ctx, path, history) do
    {_bytes, rows} = rollout(ctx, path)
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert length(Enum.uniq(ids)) == 2
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history

    assert Enum.filter(payloads, &(&1["type"] == "local_shell_call")) ===
             [List.last(history)]

    refute Enum.any?(rows, &(&1["type"] == "compacted"))

    refute Enum.any?(
             payloads,
             &(&1["type"] in ["compaction", "compaction_trigger", "function_call_output"])
           )
  end

  defp assert_provider(request, shell, expected_status) do
    input = request["input"]

    assert Enum.filter(input, &(&1["type"] == "local_shell_call")) ===
             [Map.delete(shell, @metadata)]

    assert Map.delete(shell, @metadata) ===
             canonical_shell(Map.fetch!(shell, "id"), expected_status)

    assert Enum.filter(input, &(&1["type"] == "function_call_output")) === []

    for marker <- [@marker, @followup] do
      assert Enum.count(input, fn item ->
               item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => marker}]
             end) == 1
    end

    metadata = request["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["history_initialization"] == "supplied_history"
  end

  # Independent pinned serde oracle. The provider omits ID/call ID/metadata;
  # stock native supplies the lsh_ identity and canonical optional-field nulls.
  defp canonical_shell(id) do
    %{
      "type" => "local_shell_call",
      "id" => id,
      "call_id" => nil,
      "status" => "incomplete",
      "action" => %{
        "type" => "exec",
        "command" => @command,
        "timeout_ms" => nil,
        "working_directory" => nil,
        "env" => nil,
        "user" => nil
      }
    }
  end

  # Keep the original complete incomplete oracle; the new current profile changes
  # only the independently prescribed status. Never infer it from observed data.
  defp canonical_shell(id, "incomplete"), do: canonical_shell(id)

  defp canonical_shell(id, "in_progress"),
    do: Map.put(canonical_shell(id), "status", "in_progress")

  defp collect(pid, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "Native supplied-local-shell event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, events, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected supplied-local-shell gap")
      after
        max(deadline - now(), 0) -> flunk("Native supplied-local-shell event deadline")
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

  defp assert_no_work(ctx, pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Enum.filter(events, &(&1.kind == :server_request)) === []

    refute Enum.any?(events, fn event ->
             event.wire["method"] == "thread/compacted" or
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
    assert length(rows) <= 2
    rows
  end

  defp assert_retained(ctx, source_path, source_bytes) do
    assert File.read!(source_path) === source_bytes
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
      assert remaining > 0, "Owned supplied-local-shell native #{native} survived cleanup"
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
