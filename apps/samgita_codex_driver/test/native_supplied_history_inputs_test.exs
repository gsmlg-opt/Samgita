defmodule SamgitaCodexDriver.NativeSuppliedHistoryInputsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @marker "Owned genuine supplied-history media 163"
  @followup "Owned continuation after supplied history 163"
  @answer "Deterministic local fixture answer"
  @file_id "file-owned-history-import-163"
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 96, 0,
         0, 0, 4, 0, 1, 246, 23, 56, 85, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  @wav <<82, 73, 70, 70, 38, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
         64, 31, 0, 0, 128, 62, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 2, 0, 0, 0, 0, 0>>
  @image "data:image/png;base64," <> Base.encode64(@png)
  @audio "data:audio/wav;base64," <> Base.encode64(@wav)
  @raw_content [
    %{"type" => "input_text", "text" => @marker},
    %{"type" => "input_image", "image_url" => @image, "detail" => "auto"},
    %{"type" => "input_image", "file_id" => @file_id, "detail" => "low"},
    %{"type" => "input_audio", "audio_url" => @audio}
  ]
  @assistant_content [%{"type" => "output_text", "text" => @answer}]
  @max_rollout_bytes 4_194_304
  @max_line_bytes 262_144
  @tool_marker "Owned genuine supplied-history dynamic tool 163"
  @tool_followup "Owned continuation consumes the completed tool 163"
  @tool_arguments ~s({"key": "synthetic"})
  @tool_output "Owned supplied-history tool result λ🙂"
  @tool_effect "owned-dynamic-effect-once-163\n"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Fixed owned supplied-history lookup",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert binary_hash(binary) == @binary_sha

    # Select the existing normal provider fixture even if a previous profile has
    # configured an alternate script. Restore the environment immediately.
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        if tags[:dynamic_history], do: dynamic_fixture(binary), else: TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image", "audio"],
      "supports_image_detail_original" => true
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n"
    )

    File.mkdir!(Path.join(ctx.root, "tmp"))

    Map.put(ctx, :unchanged_files, [
      {config, File.read!(config)},
      {Path.join(ctx.fixture.codex_home, "turn-models.json"),
       File.read!(Path.join(ctx.fixture.codex_home, "turn-models.json"))},
      {@script, File.read!(@script)}
    ])
  end

  test "unstable native history import preserves genuine raw media and message metadata", ctx do
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy"
      })

    started = System.system_time(:microsecond) / 1_000_000

    source_turn =
      TurnFixture.start_turn(source, source_id, [
        %{"type" => "text", "text" => @marker, "text_elements" => []},
        %{"type" => "image", "url" => @image, "detail" => "auto"},
        %{"type" => "image", "fileId" => @file_id, "detail" => "low"},
        %{"type" => "audio", "url" => @audio}
      ])

    finish_turn(source, source_id, source_turn)
    saved_source = read_thread(source, source_id)
    source_path = Map.fetch!(saved_source, "path")
    assert Map.fetch!(saved_source, "id") == source_id
    finished = System.system_time(:microsecond) / 1_000_000
    assert [first_request] = requests(ctx)
    assert_idle(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    {source_bytes, source_payloads} = rollout(ctx, source_path)
    [user, assistant] = captured_history(source_payloads)
    assert_message(user, "user", @raw_content, source_turn, started, finished)
    assert_message(assistant, "assistant", @assistant_content, source_turn, started, finished)
    assert Map.fetch!(assistant, "id") == "fixture-message-1"
    refute Map.fetch!(user, "id") == Map.fetch!(assistant, "id")
    history = [user, assistant]

    # The only raw ResponseItem client input in the pin is explicitly unstable
    # thread/resume.history. These are native-created payloads, never fabricated
    # rollout records or manually completed schema maps.
    cold = start(ctx)
    cold_process = native_process(cold)
    refute cold_process == source_process
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}

    resumed =
      call(cold, "thread/resume", %{
        "threadId" => source_id,
        "history" => history,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]

    imported_id = Map.fetch!(resumed, "id")
    assert is_binary(imported_id) and imported_id != ""
    refute imported_id == source_id
    assert Map.fetch!(resumed, "preview") == @marker
    assert Map.fetch!(resumed, "status") == %{"type" => "idle"}

    saved_import = read_thread(cold, imported_id)
    imported_path = Map.fetch!(saved_import, "path")
    refute imported_path == source_path
    assert_imported_history(ctx, imported_path, history)
    assert requests(ctx) == [first_request]
    assert File.read!(source_path) === source_bytes

    next_turn =
      TurnFixture.start_turn(cold, imported_id, [
        %{"type" => "text", "text" => @followup, "text_elements" => []}
      ])

    finish_turn(cold, imported_id, next_turn)
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^first_request, continued] = requests(ctx)
    assert_provider_history(continued)
    assert_imported_history(ctx, imported_path, history)
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
    assert_idle(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)

    # Closing the importing native must also preserve the original source file.
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
  end

  @tag dynamic_history: true
  test "unstable native import consumes genuine dynamic-tool history without repeating its effect",
       ctx do
    effects = Path.join(ctx.fixture.workspace, "owned-supplied-history-effects.log")
    refute File.exists?(effects)
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy",
        "dynamicTools" => [@lookup]
      })

    began = System.system_time(:microsecond) / 1_000_000

    source_turn =
      TurnFixture.start_turn(source, source_id, [
        %{"type" => "text", "text" => @tool_marker, "text_elements" => []}
      ])

    {tool, events} = await_dynamic_tool(source, [], System.monotonic_time(:millisecond) + 10_000)

    assert tool.wire["params"] === %{
             "threadId" => source_id,
             "turnId" => source_turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert [first_request] = requests(ctx)
    refute File.exists?(effects)

    # This one real client-tool dispatch owns the effect. Imported transcript
    # data must never invoke this handler or append the effect a second time.
    File.write!(effects, @tool_effect, [:append])

    assert :ok =
             Session.respond(
               source,
               tool.handle,
               {:ok,
                %{
                  "success" => true,
                  "contentItems" => [%{"type" => "inputText", "text" => @tool_output}]
                }}
             )

    events = collect(source, source_turn, events, System.monotonic_time(:millisecond) + 20_000)
    assert_turn_completed(events, source_id, source_turn)
    assert [^tool] = dynamic_calls(events)
    saved = read_thread(source, source_id)
    source_path = Map.fetch!(saved, "path")
    ended = System.system_time(:microsecond) / 1_000_000
    assert [^first_request, source_continuation] = requests(ctx)
    assert_tool_provider(source_continuation, false)
    assert File.read!(effects) === @tool_effect
    assert_idle(source)
    assert %{interactions: 0} = Session.status(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    {source_bytes, payloads} = rollout(ctx, source_path)
    history = captured_dynamic_history(payloads)
    assert_dynamic_payloads(history, source_turn, began, ended)
    assert length(Enum.uniq(Enum.map(history, &Map.fetch!(&1, "id")))) == 4

    cold = start(ctx)
    cold_process = native_process(cold)
    refute cold_process == source_process
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    imported =
      call(cold, "thread/resume", %{
        "threadId" => source_id,
        "history" => history,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]

    imported_id = Map.fetch!(imported, "id")
    assert is_binary(imported_id) and imported_id != "" and imported_id != source_id
    assert Map.fetch!(imported, "preview") == @tool_marker
    assert Map.fetch!(imported, "status") === %{"type" => "idle"}
    imported_path = Map.fetch!(read_thread(cold, imported_id), "path")
    refute imported_path == source_path
    assert_dynamic_import(ctx, imported_path, history)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert Session.status(cold).buffered_events == 0
    assert dynamic_calls(import_events) == []
    assert requests(ctx) === [first_request, source_continuation]
    assert File.read!(effects) === @tool_effect
    assert File.read!(source_path) === source_bytes

    followup_turn =
      TurnFixture.start_turn(cold, imported_id, [
        %{"type" => "text", "text" => @tool_followup, "text_elements" => []}
      ])

    followup_events =
      collect(cold, followup_turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert_turn_completed(followup_events, imported_id, followup_turn)
    assert dynamic_calls(followup_events) == []
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^first_request, ^source_continuation, followup] = requests(ctx)
    assert_tool_provider(followup, true)

    metadata =
      followup
      |> Map.fetch!("client_metadata")
      |> Map.fetch!("x-codex-turn-metadata")
      |> JSON.decode!()

    assert Map.fetch!(metadata, "history_initialization") == "supplied_history"
    assert_dynamic_import(ctx, imported_path, history)
    assert File.read!(effects) === @tool_effect
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
    assert_idle(cold)
    assert %{interactions: 0} = Session.status(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)
    assert File.read!(effects) === @tool_effect
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
  end

  defp dynamic_fixture(binary) do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-dynamic-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = ModelFixture.start(root, "dynamic_tool")
    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  defp await_dynamic_tool(pid, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    case dynamic_calls(events) do
      [tool] ->
        {tool, events}

      [] ->
        assert System.monotonic_time(:millisecond) < deadline, "Supplied-history tool deadline"
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected supplied-history tool gap")
        after
          10 -> :ok
        end

        await_dynamic_tool(pid, events, deadline)

      _ ->
        flunk("Expected exactly one native dynamic-tool call")
    end
  end

  defp dynamic_calls(events),
    do: Enum.filter(events, &(&1.wire["method"] == "item/tool/call"))

  defp assert_turn_completed(events, thread, turn) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
  end

  defp captured_dynamic_history(payloads) do
    selected =
      Enum.filter(payloads, fn item ->
        case item["type"] do
          "message" ->
            (item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @tool_marker}]) or
              (item["role"] == "assistant" and item["id"] == "fixture-message-2")

          type when type in ["function_call", "function_call_output"] ->
            item["call_id"] == "fixture-call-1"

          _ ->
            false
        end
      end)

    assert [
             %{"type" => "message", "role" => "user"},
             %{"type" => "function_call"},
             %{"type" => "function_call_output"},
             %{"type" => "message", "role" => "assistant"}
           ] = selected

    selected
  end

  defp assert_dynamic_payloads([user, invocation, output, assistant], turn, began, ended) do
    user_metadata = Map.fetch!(user, "internal_chat_message_metadata_passthrough")
    user_created = Map.fetch!(user_metadata, "create_time")
    assert is_number(user_created) and user_created >= began and user_created <= ended

    assert user_metadata === %{
             "turn_id" => turn,
             "create_time" => user_created,
             "content_item_kinds" => ["user.text"]
           }

    assert user["content"] === [%{"type" => "input_text", "text" => @tool_marker}]
    assert is_binary(Map.fetch!(user, "id")) and byte_size(user["id"]) > 0
    call_id = Map.fetch!(invocation, "id")
    assert is_binary(call_id) and String.starts_with?(call_id, "fc_")

    assert invocation === %{
             "type" => "function_call",
             "id" => call_id,
             "call_id" => "fixture-call-1",
             "name" => "fixture_lookup",
             "arguments" => @tool_arguments,
             "internal_chat_message_metadata_passthrough" => %{"turn_id" => turn}
           }

    output_id = Map.fetch!(output, "id")
    assert is_binary(output_id) and String.starts_with?(output_id, "fco_")
    output_metadata = Map.fetch!(output, "internal_chat_message_metadata_passthrough")
    output_created = Map.fetch!(output_metadata, "create_time")
    assert is_number(output_created) and output_created >= began and output_created <= ended

    assert output === %{
             "type" => "function_call_output",
             "id" => output_id,
             "call_id" => "fixture-call-1",
             "output" => @tool_output,
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => output_created
             }
           }

    assert Map.fetch!(assistant, "id") == "fixture-message-2"
    assert_message(assistant, "assistant", @assistant_content, turn, began, ended)
  end

  defp assert_dynamic_import(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_dynamic_history(payloads) === history
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
  end

  defp assert_tool_provider(request, followup?) do
    input = Map.fetch!(request, "input")
    assert [invocation] = Enum.filter(input, &(&1["type"] == "function_call"))
    call_id = Map.fetch!(invocation, "id")

    assert invocation === %{
             "type" => "function_call",
             "id" => call_id,
             "call_id" => "fixture-call-1",
             "name" => "fixture_lookup",
             "arguments" => @tool_arguments
           }

    assert [output] = Enum.filter(input, &(&1["type"] == "function_call_output"))
    output_id = Map.fetch!(output, "id")

    assert output === %{
             "type" => "function_call_output",
             "id" => output_id,
             "call_id" => "fixture-call-1",
             "output" => @tool_output
           }

    assert Enum.count(input, fn item ->
             item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @tool_marker}]
           end) == 1

    if followup? do
      assert Enum.count(input, fn item ->
               item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @tool_followup}]
             end) == 1

      assert Enum.count(input, fn item ->
               item["role"] == "assistant" and item["content"] === @assistant_content
             end) == 1
    end
  end

  defp captured_history(payloads) do
    assert [user] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "user" and
                 Enum.any?(Map.get(item, "content", []), fn part ->
                   part == %{"type" => "input_text", "text" => @marker}
                 end)
             end)

    assert [assistant] =
             Enum.filter(payloads, fn item ->
               item["type"] == "message" and item["role"] == "assistant" and
                 item["id"] == "fixture-message-1"
             end)

    [user, assistant]
  end

  defp assert_message(item, role, content, turn, started, finished) do
    assert Map.fetch!(item, "type") == "message"
    assert Map.fetch!(item, "role") == role
    assert Map.fetch!(item, "content") === content
    assert is_binary(Map.fetch!(item, "id")) and byte_size(item["id"]) > 0
    metadata = Map.fetch!(item, "internal_chat_message_metadata_passthrough")
    assert is_map(metadata)
    assert Map.fetch!(metadata, "turn_id") == turn

    case role do
      "user" ->
        created = Map.fetch!(metadata, "create_time")
        assert is_number(created) and created >= started and created <= finished

        assert metadata === %{
                 "turn_id" => turn,
                 "create_time" => created,
                 "content_item_kinds" => ["user.text", "user.image", "user.image", "user.audio"]
               }

      "assistant" ->
        # models.rs:set_create_time_if_missing stamps Message only for user or
        # developer roles. Native assistant metadata has no creation timestamp;
        # annotated_content.rs classifies the provider's untyped text as unknown.
        assert metadata === %{"turn_id" => turn, "content_item_kinds" => ["unknown"]}
        refute Map.has_key?(metadata, "create_time")
    end
  end

  defp assert_imported_history(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_history(payloads) === history

    for item <- history do
      assert Enum.count(payloads, &(&1["id"] == item["id"])) == 1
      assert Enum.count(payloads, &(&1 === item)) == 1
    end
  end

  defp assert_provider_history(request) do
    # The pin strips passthrough metadata from non-OpenAI provider copies
    # (core/src/client.rs), so provider content and persisted metadata have
    # distinct oracles. Do not expect the provider copy to echo whole raw maps.
    input = Map.fetch!(request, "input")
    assert Enum.count(input, &(&1["role"] == "user" and &1["content"] === @raw_content)) == 1

    assert Enum.count(
             input,
             &(&1["role"] == "assistant" and &1["content"] === @assistant_content)
           ) == 1

    assert Enum.count(input, fn item ->
             item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @followup}]
           end) == 1

    metadata =
      request
      |> Map.fetch!("client_metadata")
      |> Map.fetch!("x-codex-turn-metadata")
      |> JSON.decode!()

    assert Map.fetch!(metadata, "history_initialization") == "supplied_history"
  end

  defp rollout(ctx, path) do
    assert is_binary(path)
    expanded = Path.expand(path)
    assert String.starts_with?(expanded, Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(expanded)
    assert size > 0 and size <= @max_rollout_bytes
    bytes = File.read!(expanded)
    assert byte_size(bytes) == size
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048

    payloads =
      for line <- lines,
          _ = assert(byte_size(line) <= @max_line_bytes),
          row = JSON.decode!(line),
          row["type"] == "response_item",
          do: Map.fetch!(row, "payload")

    assert payloads != []
    {bytes, payloads}
  end

  defp requests(ctx) do
    assert File.stat!(ctx.fixture.requests).size <= @max_rollout_bytes
    ModelFixture.requests(ctx.fixture)
  end

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp finish_turn(pid, thread, turn) do
    events = collect(pid, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
  end

  defp collect(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    if TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "Supplied-history turn deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected supplied-history event gap")
      after
        10 -> :ok
      end

      collect(pid, turn, events, deadline)
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
  end

  defp assert_unchanged(ctx) do
    for {path, bytes} <- ctx.unchanged_files, do: assert(File.read!(path) === bytes)
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert binary_hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp binary_hash(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned supplied-history process #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        max_events: 256,
        max_event_bytes: 1_048_576,
        max_message_bytes: 1_048_576,
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
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
               %{"name" => "samgita_supplied_history_inputs", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
