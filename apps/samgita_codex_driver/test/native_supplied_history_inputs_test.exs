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

  @search_script Path.expand(
                   "../../../scripts/codex/supplied_tool_search_history_fixture.py",
                   __DIR__
                 )
  @exposure_script Path.expand("../../../scripts/codex/dynamic_tool_exposure_fixture.py", __DIR__)
  @search_marker "Owned genuine supplied-history tool-search 163"
  @search_followup "Owned continuation consumes completed tool-search evidence 163"
  @search_answer "Owned exposure completed λ"
  @search_followup_answer "Owned imported tool-search evidence consumed λ"
  @search_output "Owned synthetic record result λ"
  @search_effect "owned-tool-search-effect-once-163\n"
  @search_arguments ~s({"key": "owned exposure λ", "count": 7, "nested": {"enabled": true, "labels": ["α", "β"]}})
  @search_argument_map %{
    "key" => "owned exposure λ",
    "count" => 7,
    "nested" => %{"enabled" => true, "labels" => ["α", "β"]}
  }
  @search_schema %{
    "type" => "object",
    "properties" => %{
      "key" => %{"type" => "string"},
      "count" => %{"type" => "integer"},
      "nested" => %{
        "type" => "object",
        "properties" => %{
          "enabled" => %{"type" => "boolean"},
          "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["enabled", "labels"],
        "additionalProperties" => false
      }
    },
    "required" => ["key", "count", "nested"],
    "additionalProperties" => false
  }
  @search_namespace %{
    "type" => "namespace",
    "name" => "owned_catalog",
    "description" => "Owned canonical catalog description β",
    "tools" => [
      %{
        "type" => "function",
        "name" => "quasar_lookup_824",
        "description" => "quasar_lookup_824 retrieves the owned synthetic record λ",
        "inputSchema" => @search_schema,
        "deferLoading" => true
      }
    ]
  }
  @search_provider_namespace %{
    "type" => "namespace",
    "name" => "owned_catalog",
    "description" => "Owned canonical catalog description β",
    "tools" => [
      %{
        "type" => "function",
        "name" => "quasar_lookup_824",
        "description" => "quasar_lookup_824 retrieves the owned synthetic record λ",
        "strict" => false,
        "parameters" => @search_schema,
        "defer_loading" => true
      }
    ]
  }

  @custom_script Path.expand("../../../scripts/codex/supplied_custom_history_fixture.py", __DIR__)
  @custom_marker "Owned genuine supplied-history custom patch 163"
  @custom_followup "Owned continuation consumes completed custom patch evidence 163"
  @custom_answer "Owned custom patch completed λ🙂"
  @custom_followup_answer "Owned imported custom patch evidence consumed λ🙂"
  @custom_patch "*** Begin Patch\n*** Update File: owned-notice.txt\n@@\n-owned before\n+owned after λ🙂\n*** End Patch\n"

  @reasoning_script Path.expand(
                      "../../../scripts/codex/reasoning_item_events_fixture.py",
                      __DIR__
                    )
  @reasoning_marker "Owned genuine supplied-history reasoning 163"
  @reasoning_followup "Owned continuation consumes supplied reasoning evidence 163"
  @reasoning_answer "Owned source reasoning completed λ🙂"
  @reasoning_followup_answer "Owned imported reasoning evidence consumed λ🙂"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert binary_hash(binary) == @binary_sha

    # Select the existing normal provider fixture even if a previous profile has
    # configured an alternate script. Restore the environment immediately.
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    selected_script = history_script(tags)
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", selected_script)

    ctx =
      try do
        history_fixture(binary, tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    model = %{
      "input_modalities" => ["text", "image", "audio"],
      "supports_image_detail_original" => true
    }

    model = history_model(model, tags)

    TurnFixture.configure_model(ctx, model)

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n"
    )

    File.mkdir!(Path.join(ctx.root, "tmp"))

    unchanged_files = [
      {config, File.read!(config)},
      {Path.join(ctx.fixture.codex_home, "turn-models.json"),
       File.read!(Path.join(ctx.fixture.codex_home, "turn-models.json"))},
      {@script, File.read!(@script)}
    ]

    unchanged_files =
      unchanged_files ++ Enum.map(history_source_paths(tags), &{&1, File.read!(&1)})

    Map.put(ctx, :unchanged_files, unchanged_files)
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

    assert_null_history_inputs(
      ctx,
      source_id,
      source_path,
      source_bytes,
      history,
      [{0, "internal_chat_message_metadata_passthrough"}, {1, "phase"}],
      []
    )

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

    assert_null_history_inputs(
      ctx,
      source_id,
      source_path,
      source_bytes,
      history,
      [
        {1, "internal_chat_message_metadata_passthrough"},
        {2, "internal_chat_message_metadata_passthrough"}
      ],
      [effects]
    )

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

  @tag search_history: true
  test "unstable native import consumes genuine completed client tool-search history once", ctx do
    effects = Path.join(ctx.fixture.workspace, "owned-supplied-search-effects.log")
    refute File.exists?(effects)
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy",
        "dynamicTools" => [@search_namespace]
      })

    began = System.system_time(:microsecond) / 1_000_000

    source_turn =
      TurnFixture.start_turn(source, source_id, [
        %{"type" => "text", "text" => @search_marker, "text_elements" => []}
      ])

    {tool, events} = await_dynamic_tool(source, [], System.monotonic_time(:millisecond) + 10_000)

    assert tool.wire["params"] === %{
             "threadId" => source_id,
             "turnId" => source_turn,
             "callId" => "owned-exposure-call",
             "namespace" => "owned_catalog",
             "tool" => "quasar_lookup_824",
             "arguments" => @search_argument_map
           }

    assert [initial, searched] = requests(ctx)
    assert Enum.any?(initial["tools"], &(&1["type"] == "tool_search"))
    assert_search_provider(searched, false, false)
    refute File.exists?(effects)

    # Only this genuine client-tool callback performs the owned effect. The
    # native client search itself is local BM25, not another client callback.
    File.write!(effects, @search_effect, [:append])

    assert :ok =
             Session.respond(
               source,
               tool.handle,
               {:ok,
                %{
                  "success" => true,
                  "contentItems" => [%{"type" => "inputText", "text" => @search_output}]
                }}
             )

    events = collect(source, source_turn, events, System.monotonic_time(:millisecond) + 20_000)
    assert_turn_completed(events, source_id, source_turn)
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    assert_search_answer(events, source_turn, @search_answer)
    source_path = Map.fetch!(read_thread(source, source_id), "path")
    ended = System.system_time(:microsecond) / 1_000_000
    assert [^initial, ^searched, completed] = requests(ctx)
    assert_search_provider(completed, true, false)
    assert File.read!(effects) === @search_effect
    assert_idle(source)
    assert %{interactions: 0} = Session.status(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    {source_bytes, payloads} = rollout(ctx, source_path)
    history = captured_search_history(payloads)
    assert_search_payloads(history, source_turn, began, ended)
    assert length(Enum.uniq(Enum.map(history, &Map.fetch!(&1, "id")))) == 6

    assert_null_history_inputs(
      ctx,
      source_id,
      source_path,
      source_bytes,
      history,
      [
        {1, "internal_chat_message_metadata_passthrough"},
        {2, "internal_chat_message_metadata_passthrough"}
      ],
      [effects]
    )

    cold = start(ctx)
    cold_process = native_process(cold)
    refute cold_process == source_process
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # The pin marks this input "[UNSTABLE] FOR CODEX CLOUD - DO NOT USE".
    # Complete ResponseItems are imported untouched. They do not carry SessionMeta
    # and cannot restore the original dynamic registration. The followup below
    # consumes completed evidence only; it does not claim callable continuity.
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
    assert Map.fetch!(imported, "preview") == @search_marker
    assert Map.fetch!(imported, "status") === %{"type" => "idle"}
    imported_path = Map.fetch!(read_thread(cold, imported_id), "path")
    refute imported_path == source_path
    assert_search_import(ctx, imported_path, history)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert Session.status(cold).buffered_events == 0
    assert Enum.filter(import_events, &(&1.kind == :server_request)) == []
    assert requests(ctx) === [initial, searched, completed]
    assert File.read!(effects) === @search_effect
    assert File.read!(source_path) === source_bytes

    followup_turn =
      TurnFixture.start_turn(cold, imported_id, [
        %{"type" => "text", "text" => @search_followup, "text_elements" => []}
      ])

    followup_events =
      collect(cold, followup_turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert_turn_completed(followup_events, imported_id, followup_turn)
    assert Enum.filter(followup_events, &(&1.kind == :server_request)) == []
    assert_search_answer(followup_events, followup_turn, @search_followup_answer)
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^initial, ^searched, ^completed, followup] = requests(ctx)
    assert_search_provider(followup, true, true)

    metadata =
      followup
      |> Map.fetch!("client_metadata")
      |> Map.fetch!("x-codex-turn-metadata")
      |> JSON.decode!()

    assert Map.fetch!(metadata, "history_initialization") == "supplied_history"

    # The imported transcript does not restore an executable owned namespace.
    refute Enum.any?(followup["tools"], fn tool ->
             tool["name"] in ["owned_catalog", "quasar_lookup_824"] or
               Enum.any?(Map.get(tool, "tools", []), &(&1["name"] == "quasar_lookup_824"))
           end)

    assert_search_import(ctx, imported_path, history)
    {_bytes, imported_payloads} = rollout(ctx, imported_path)

    assert [%{"content" => [%{"type" => "output_text", "text" => @search_followup_answer}]}] =
             Enum.filter(
               imported_payloads,
               &(&1["id"] == "owned-supplied-search-followup-answer")
             )

    assert File.read!(effects) === @search_effect
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
    assert_idle(cold)
    assert %{interactions: 0} = Session.status(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)
    assert File.read!(effects) === @search_effect
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
  end

  @tag custom_history: true
  test "unstable native import consumes genuine custom patch history without repeating its effect",
       ctx do
    target = Path.join(ctx.fixture.workspace, "owned-notice.txt")
    File.write!(target, "owned before\n")
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      call(source, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "legacy",
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]["id"]

    assert is_binary(source_id) and byte_size(source_id) > 0
    began = System.system_time(:microsecond) / 1_000_000
    source_turn = custom_turn(source, source_id, @custom_marker)
    events = collect(source, source_turn, [], System.monotonic_time(:millisecond) + 20_000)
    assert_turn_completed(events, source_id, source_turn)
    assert_custom_answer(events, source_turn, @custom_answer)

    assert [%{"item" => %{"type" => "fileChange", "status" => "completed"}}] =
             custom_file_changes(events, "item/completed")

    assert length(custom_file_changes(events, "item/started")) == 1
    assert Enum.filter(events, &(&1.kind == :server_request)) == []
    source_path = Map.fetch!(read_thread(source, source_id), "path")
    ended = System.system_time(:microsecond) / 1_000_000
    assert [initial, completed] = requests(ctx)
    assert_custom_provider(completed, false, began, ended)
    assert File.read!(target) === "owned after λ🙂\n"
    effect_inode = File.stat!(target).inode
    [effect_snapshot] = custom_effect_snapshots(ctx)
    assert effect_snapshot["inode"] == effect_inode
    assert_idle(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    {source_bytes, payloads} = rollout(ctx, source_path)
    history = captured_custom_history(payloads)
    assert_custom_payloads(history, source_turn, began, ended)
    assert length(Enum.uniq(Enum.map(history, &Map.fetch!(&1, "id")))) == 4

    assert_null_history_inputs(
      ctx,
      source_id,
      source_path,
      source_bytes,
      history,
      [
        {1, "internal_chat_message_metadata_passthrough"},
        {2, "internal_chat_message_metadata_passthrough"}
      ],
      [target, Path.join(ctx.root, "custom-effect-snapshots.json")]
    )

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
    assert Map.fetch!(imported, "preview") == @custom_marker
    assert Map.fetch!(imported, "status") === %{"type" => "idle"}
    imported_path = Map.fetch!(read_thread(cold, imported_id), "path")
    refute imported_path == source_path
    assert_custom_import(ctx, imported_path, history)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert Session.status(cold).buffered_events == 0
    assert_custom_no_work(import_events)
    assert requests(ctx) === [initial, completed]
    assert custom_effect_snapshots(ctx) === [effect_snapshot]
    assert_custom_retained(ctx, target, effect_inode, source_path, source_bytes)

    followup_turn = custom_turn(cold, imported_id, @custom_followup)
    followup = collect(cold, followup_turn, [], System.monotonic_time(:millisecond) + 20_000)
    assert_turn_completed(followup, imported_id, followup_turn)
    assert_custom_answer(followup, followup_turn, @custom_followup_answer)
    assert_custom_no_work(followup)
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^initial, ^completed, continuation] = requests(ctx)
    assert_custom_provider(continuation, true, began, ended)
    assert custom_effect_snapshots(ctx) === [effect_snapshot, effect_snapshot]
    assert_custom_import(ctx, imported_path, history)
    assert_custom_retained(ctx, target, effect_inode, source_path, source_bytes)
    assert_idle(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)
    assert_custom_retained(ctx, target, effect_inode, source_path, source_bytes)
    assert requests(ctx) === [initial, completed, continuation]
  end

  @tag reasoning_history: true
  test "unstable native import consumes genuine reasoning history without generating it again",
       ctx do
    source = start(ctx)
    source_process = native_process(source)

    source_id =
      TurnFixture.thread(ctx, source, %{
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy"
      })

    began = System.system_time(:microsecond) / 1_000_000
    source_turn = custom_turn(source, source_id, @reasoning_marker)
    events = collect(source, source_turn, [], System.monotonic_time(:millisecond) + 20_000)
    ended = System.system_time(:microsecond) / 1_000_000
    assert_turn_completed(events, source_id, source_turn)
    assert_reasoning_live(events, source_id, source_turn, began, ended)
    assert_custom_answer(events, source_turn, @reasoning_answer)
    assert_custom_no_work(events)
    source_path = Map.fetch!(read_thread(source, source_id), "path")
    assert [initial] = requests(ctx)
    assert Enum.filter(initial["input"], &(&1["type"] == "reasoning")) == []
    assert_idle(source)
    assert :ok = Session.close(source)
    assert_gone(source_process)

    # Capture real native ResponseItems before using the unstable input API.
    # The Python producer emits only ordinary Responses events, never history.
    {source_bytes, payloads} = rollout(ctx, source_path)
    history = captured_reasoning_history(payloads)
    assert_reasoning_payloads(history, source_turn, began, ended)
    assert length(Enum.uniq(Enum.map(history, &Map.fetch!(&1, "id")))) == 3
    assert_reasoning_retained(ctx, source_path, source_bytes)

    # Explicit-null CLIENT inputs: one Reasoning metadata field and one genuine
    # user Message metadata field. Keep the existing two-import invariant.
    assert_null_history_inputs(
      ctx,
      source_id,
      source_path,
      source_bytes,
      history,
      [
        {1, "internal_chat_message_metadata_passthrough"},
        {0, "internal_chat_message_metadata_passthrough"}
      ],
      []
    )

    assert requests(ctx) === [initial]
    assert_reasoning_retained(ctx, source_path, source_bytes)
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
    assert Map.fetch!(imported, "preview") == @reasoning_marker
    assert Map.fetch!(imported, "status") === %{"type" => "idle"}
    imported_path = Map.fetch!(read_thread(cold, imported_id), "path")
    refute imported_path == source_path
    assert_reasoning_import(ctx, imported_path, history)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert Session.status(cold).buffered_events == 0
    assert_custom_no_work(import_events)
    assert_reasoning_not_generated(import_events)
    refute Enum.any?(import_events, &(&1.wire["method"] == "turn/started"))
    assert requests(ctx) === [initial]
    assert_reasoning_retained(ctx, source_path, source_bytes)

    followup_turn = custom_turn(cold, imported_id, @reasoning_followup)
    followup = collect(cold, followup_turn, [], System.monotonic_time(:millisecond) + 20_000)
    assert_turn_completed(followup, imported_id, followup_turn)
    assert_custom_answer(followup, followup_turn, @reasoning_followup_answer)
    assert_custom_no_work(followup)
    assert_reasoning_not_generated(followup)
    assert Map.fetch!(read_thread(cold, imported_id), "id") == imported_id
    assert [^initial, continuation] = requests(ctx)
    assert_reasoning_provider(continuation)
    assert_reasoning_import(ctx, imported_path, history)
    assert_reasoning_retained(ctx, source_path, source_bytes)
    assert_idle(cold)
    assert %{interactions: 0} = Session.status(cold)
    assert :ok = Session.close(cold)
    assert_gone(cold_process)
    assert_reasoning_retained(ctx, source_path, source_bytes)
    assert requests(ctx) === [initial, continuation]
  end

  defp reasoning_fixture(binary) do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-reasoning-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = ModelFixture.start(root, "reasoning_history")
    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  defp reasoning_summary do
    [
      %{"type" => "summary_text", "text" => "Owned summary λ🙂"},
      %{"type" => "summary_text", "text" => "Owned second summary"}
    ]
  end

  defp reasoning_content do
    [
      %{"type" => "reasoning_text", "text" => "Owned raw α🙂"},
      %{"type" => "text", "text" => ""},
      %{"type" => "text", "text" => "Owned text alternative"}
    ]
  end

  defp reasoning_params(events, method) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["item"]["type"] == "reasoning",
        do: event.wire["params"]
  end

  defp assert_reasoning_live(events, thread, turn, began, ended) do
    item = %{
      "type" => "reasoning",
      "id" => "owned-reasoning-populated",
      "summary" => ["Owned summary λ🙂", "Owned second summary"],
      "content" => ["Owned raw α🙂", "", "Owned text alternative"]
    }

    assert [started] = reasoning_params(events, "item/started")
    assert [completed] = reasoning_params(events, "item/completed")
    started_at = Map.fetch!(started, "startedAtMs")
    completed_at = Map.fetch!(completed, "completedAtMs")
    assert is_integer(started_at) and is_integer(completed_at)
    assert trunc(began * 1_000) <= started_at
    assert started_at <= completed_at and completed_at <= trunc(ended * 1_000)

    assert started === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => item,
             "startedAtMs" => started_at
           }

    assert completed === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => item,
             "completedAtMs" => completed_at
           }

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          event.wire["params"]["item"]["type"] == "reasoning",
          do: event.wire["method"]

    assert order === ["item/started", "item/completed"]
  end

  defp assert_reasoning_not_generated(events) do
    assert reasoning_params(events, "item/started") == []
    assert reasoning_params(events, "item/completed") == []
  end

  defp captured_reasoning_history(payloads) do
    selected =
      Enum.filter(payloads, fn item ->
        item["type"] == "reasoning" or
          (item["type"] == "message" and item["role"] == "user" and
             item["content"] === [%{"type" => "input_text", "text" => @reasoning_marker}]) or
          (item["type"] == "message" and item["id"] == "owned-reasoning-source-answer")
      end)

    assert [
             %{"type" => "message", "role" => "user"},
             %{"type" => "reasoning"},
             %{"type" => "message", "role" => "assistant"}
           ] = selected

    selected
  end

  defp assert_reasoning_payloads([user, reasoning, assistant], turn, began, ended) do
    user_id = Map.fetch!(user, "id")
    assert_custom_native_id(user_id, "msg")
    created = custom_created(user, began, ended)

    assert user === %{
             "type" => "message",
             "id" => user_id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => @reasoning_marker}],
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }

    assert reasoning === %{
             "type" => "reasoning",
             "id" => "owned-reasoning-populated",
             "summary" => reasoning_summary(),
             "content" => reasoning_content(),
             "encrypted_content" => nil,
             "internal_chat_message_metadata_passthrough" => %{"turn_id" => turn}
           }

    assert assistant === %{
             "type" => "message",
             "id" => "owned-reasoning-source-answer",
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @reasoning_answer}],
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "content_item_kinds" => ["unknown"]
             }
           }
  end

  defp assert_reasoning_import(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_reasoning_history(payloads) === history
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
  end

  defp assert_reasoning_provider(request) do
    input = Map.fetch!(request, "input")

    # Non-OpenAI request copies lose metadata; IDs without an underscore are
    # removed (client.rs:1007-1009,1092-1095). Durable originals above retain both.
    assert Enum.filter(input, &(&1["type"] == "reasoning")) === [
             %{
               "type" => "reasoning",
               "summary" => reasoning_summary(),
               "content" => reasoning_content(),
               "encrypted_content" => nil
             }
           ]

    assert_custom_provider_message(input, "user", @reasoning_marker)
    assert_custom_provider_message(input, "assistant", @reasoning_answer)
    assert_custom_provider_message(input, "user", @reasoning_followup)
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    assert Map.fetch!(metadata, "history_initialization") == "supplied_history"
  end

  defp assert_reasoning_retained(ctx, source_path, source_bytes) do
    assert File.read!(source_path) === source_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert_unchanged(ctx)
  end

  defp custom_fixture(binary) do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-custom-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = ModelFixture.start(root, "custom_history")
    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  defp custom_turn(pid, thread, text) do
    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text, "text_elements" => []}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    turn
  end

  defp custom_file_changes(events, method) do
    events
    |> Enum.filter(&(&1.wire["method"] == method))
    |> Enum.map(&Map.fetch!(&1.wire, "params"))
    |> Enum.filter(&(&1["item"]["type"] == "fileChange"))
  end

  defp assert_custom_no_work(events) do
    assert custom_file_changes(events, "item/started") == []
    assert custom_file_changes(events, "item/completed") == []
    assert Enum.filter(events, &(&1.kind == :server_request)) == []
  end

  defp assert_custom_answer(events, turn, text) do
    answers =
      for event <- events,
          event.wire["method"] == "item/completed",
          params = event.wire["params"],
          params["turnId"] == turn,
          params["item"]["type"] == "agentMessage",
          do: params["item"]["text"]

    assert answers === [text]
  end

  defp custom_effect_snapshots(ctx) do
    path = Path.join(ctx.root, "custom-effect-snapshots.json")
    assert File.stat!(path).size <= 4_096
    JSON.decode!(File.read!(path))
  end

  defp assert_custom_retained(ctx, target, inode, source_path, source_bytes) do
    assert File.read!(target) === "owned after λ🙂\n"
    assert File.stat!(target).inode == inode
    assert File.read!(source_path) === source_bytes
    assert_unchanged(ctx)
  end

  defp captured_custom_history(payloads) do
    selected = Enum.filter(payloads, &custom_history_item?/1)

    assert [
             %{"role" => "user"},
             %{"type" => "custom_tool_call"},
             %{"type" => "custom_tool_call_output"},
             %{"role" => "assistant"}
           ] = selected

    selected
  end

  defp custom_history_item?(%{"type" => "message", "role" => "user", "content" => content}),
    do: content === [%{"type" => "input_text", "text" => @custom_marker}]

  defp custom_history_item?(%{"type" => "message", "id" => "owned-custom-source-answer"}),
    do: true

  defp custom_history_item?(%{"type" => kind, "call_id" => "owned-patch-call"})
       when kind in ["custom_tool_call", "custom_tool_call_output"],
       do: true

  defp custom_history_item?(_), do: false

  defp assert_custom_payloads([user, invocation, output, assistant], turn, began, ended) do
    user_id = Map.fetch!(user, "id")
    assert_custom_native_id(user_id, "msg")
    created = custom_created(user, began, ended)

    assert user === %{
             "type" => "message",
             "id" => user_id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => @custom_marker}],
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }

    assert invocation ===
             Map.put(custom_call(), "internal_chat_message_metadata_passthrough", %{
               "turn_id" => turn
             })

    assert_custom_output(output, turn, began, ended)

    assert assistant === %{
             "type" => "message",
             "id" => "owned-custom-source-answer",
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @custom_answer}],
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "content_item_kinds" => ["unknown"]
             }
           }
  end

  defp custom_call do
    %{
      "type" => "custom_tool_call",
      "id" => "owned-patch-item",
      "call_id" => "owned-patch-call",
      "name" => "apply_patch",
      "input" => @custom_patch
    }
  end

  defp custom_created(item, began, ended) do
    created =
      Map.fetch!(Map.fetch!(item, "internal_chat_message_metadata_passthrough"), "create_time")

    assert is_number(created) and created >= began and created <= ended
    created
  end

  defp assert_custom_native_id(id, prefix) do
    assert is_binary(id)

    pattern =
      "\\A" <> prefix <> "_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z"

    assert Regex.match?(Regex.compile!(pattern), id)
  end

  defp assert_custom_output(output, turn, began, ended) do
    id = Map.fetch!(output, "id")
    assert_custom_native_id(id, "ctco")
    created = custom_created(output, began, ended)
    text = Map.fetch!(output, "output")
    assert_custom_output_text(text, began, ended)

    assert output === %{
             "type" => "custom_tool_call_output",
             "id" => id,
             "call_id" => "owned-patch-call",
             "output" => text,
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => created
             }
           }
  end

  defp assert_custom_output_text(text, began, ended) do
    assert is_binary(text)

    assert [_, duration] =
             Regex.run(
               ~r/\AExit code: 0\nWall time: ([0-9]+(?:\.[0-9]+)?) seconds\nOutput:\nSuccess\. Updated the following files:\nM owned-notice\.txt\n\z/u,
               text
             )

    assert {seconds, ""} = Float.parse(duration)
    assert seconds >= 0 and seconds <= ended - began + 0.1
  end

  defp assert_custom_import(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_custom_history(payloads) === history
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
  end

  defp assert_custom_provider(request, followup?, began, ended) do
    input = Map.fetch!(request, "input")

    assert Enum.filter(input, &(&1["type"] == "custom_tool_call")) === [
             Map.delete(custom_call(), "id")
           ]

    assert [output] = Enum.filter(input, &(&1["type"] == "custom_tool_call_output"))
    assert_custom_native_id(Map.fetch!(output, "id"), "ctco")
    text = Map.fetch!(output, "output")
    assert_custom_output_text(text, began, ended)

    assert output === %{
             "type" => "custom_tool_call_output",
             "id" => output["id"],
             "call_id" => "owned-patch-call",
             "output" => text
           }

    assert_custom_provider_message(input, "user", @custom_marker)

    if followup? do
      assert_custom_provider_message(input, "user", @custom_followup)
      assert_custom_provider_message(input, "assistant", @custom_answer)
      metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
      assert Map.fetch!(metadata, "history_initialization") == "supplied_history"
    end
  end

  defp assert_custom_provider_message(input, role, text) do
    type = if role == "user", do: "input_text", else: "output_text"

    assert Enum.count(
             input,
             &(&1["role"] == role and
                 &1["content"] === [%{"type" => type, "text" => text}])
           ) == 1
  end

  defp history_script(%{reasoning_history: true}), do: @reasoning_script
  defp history_script(%{custom_history: true}), do: @custom_script
  defp history_script(%{search_history: true}), do: @search_script
  defp history_script(_), do: @script

  defp history_fixture(binary, %{reasoning_history: true}), do: reasoning_fixture(binary)
  defp history_fixture(binary, %{custom_history: true}), do: custom_fixture(binary)
  defp history_fixture(binary, %{search_history: true}), do: search_fixture(binary)
  defp history_fixture(binary, %{dynamic_history: true}), do: dynamic_fixture(binary)
  defp history_fixture(_binary, tags), do: TurnFixture.setup(tags)

  defp history_model(model, %{custom_history: true}),
    do: Map.put(model, "apply_patch_tool_type", "freeform")

  defp history_model(model, %{search_history: true}),
    do: Map.put(model, "supports_search_tool", true)

  defp history_model(model, _), do: model

  defp history_source_paths(%{reasoning_history: true}), do: [@reasoning_script]
  defp history_source_paths(%{custom_history: true}), do: [@custom_script]
  defp history_source_paths(%{search_history: true}), do: [@search_script, @exposure_script]
  defp history_source_paths(_), do: []

  # These are intentionally modified CLIENT inputs, not native-null emissions
  # or unchanged-history preservation. Each request changes exactly one field
  # on one genuinely captured ResponseItem; serde None omits that field durably.
  defp assert_null_history_inputs(
         ctx,
         source_id,
         source_path,
         source_bytes,
         history,
         selections,
         paths
       ) do
    assert length(selections) == 2
    before_requests = requests(ctx)
    retained = Map.new(paths, &{&1, null_retained_file(&1)})
    pid = start(ctx)
    native = native_process(pid)
    assert call(pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    imports =
      Enum.reduce(selections, {[], []}, fn {index, key}, {ids, import_paths} ->
        original = Enum.fetch!(history, index)
        assert_null_source_field(original, key)
        submitted = List.update_at(history, index, &Map.put(&1, key, nil))
        expected = List.update_at(history, index, &Map.delete(&1, key))
        assert Map.has_key?(Enum.fetch!(submitted, index), key)
        assert Map.fetch!(Enum.fetch!(submitted, index), key) === nil
        refute Map.has_key?(Enum.fetch!(expected, index), key)
        assert submitted !== expected

        imported =
          call(pid, "thread/resume", %{
            "threadId" => source_id,
            "history" => submitted,
            "model" => "mock-model",
            "modelProvider" => "fixture",
            "cwd" => ctx.fixture.workspace,
            "approvalPolicy" => "never",
            "sandbox" => "danger-full-access"
          })["thread"]

        id = Map.fetch!(imported, "id")
        assert is_binary(id) and id != "" and id != source_id
        refute id in ids
        assert Map.fetch!(imported, "status") === %{"type" => "idle"}
        path = Map.fetch!(read_thread(pid, id), "path")
        refute path == source_path or path in import_paths
        assert_null_persistence(ctx, path, expected, index, key)
        assert {:ok, events} = Session.drain(pid, 256)
        assert Session.status(pid).buffered_events == 0
        assert_custom_no_work(events)
        refute Enum.any?(events, &(&1.wire["method"] == "turn/started"))
        assert requests(ctx) === before_requests
        assert File.read!(source_path) === source_bytes

        for {retained_path, value} <- retained,
            do: assert(null_retained_file(retained_path) === value)

        assert_unchanged(ctx)
        assert_idle(pid)
        {[id | ids], [path | import_paths]}
      end)

    assert {[_second_id, _first_id], [_second_path, _first_path]} = imports
    assert :ok = Session.close(pid)
    assert_gone(native)
    assert requests(ctx) === before_requests
    assert File.read!(source_path) === source_bytes
    for {path, value} <- retained, do: assert(null_retained_file(path) === value)
    assert_unchanged(ctx)
  end

  defp assert_null_source_field(original, "internal_chat_message_metadata_passthrough") do
    assert is_map(Map.fetch!(original, "internal_chat_message_metadata_passthrough"))
  end

  defp assert_null_source_field(original, "phase") do
    assert original["type"] == "message" and original["role"] == "assistant"
    # This producer has no phase. Explicit null is a distinct legal client input
    # which normalizes to the same omitted field; it is not a native phase claim.
    refute Map.has_key?(original, "phase")
  end

  defp assert_null_persistence(ctx, path, expected, changed_index, key) do
    {_bytes, payloads} = rollout(ctx, path)
    ids = Enum.map(expected, &Map.fetch!(&1, "id"))
    selected = Enum.filter(payloads, &(&1["id"] in ids))
    assert selected === expected
    assert length(Enum.uniq(ids)) == length(ids)
    assert length(selected) == length(ids)
    refute Map.has_key?(Enum.fetch!(selected, changed_index), key)
    assert Enum.map(selected, &Map.fetch!(&1, "id")) === ids
  end

  defp null_retained_file(path) do
    stat = File.stat!(path, time: :posix)
    assert stat.type == :regular
    {File.read!(path), stat.inode, stat.size, stat.mtime, stat.ctime}
  end

  defp search_fixture(binary) do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-supplied-search-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = ModelFixture.start(root, "namespace_deferred")
    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  defp assert_search_answer(events, turn, text) do
    assert %{"turnId" => ^turn, "item" => %{"type" => "agentMessage", "text" => ^text}} =
             TurnFixture.notification(
               events,
               "item/completed",
               &(&1["turnId"] == turn and &1["item"]["type"] == "agentMessage")
             )
  end

  defp captured_search_history(payloads) do
    selected =
      Enum.filter(payloads, fn item ->
        case item["type"] do
          "message" ->
            (item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @search_marker}]) or
              (item["role"] == "assistant" and item["id"] == "owned-exposure-answer")

          type when type in ["tool_search_call", "tool_search_output"] ->
            item["call_id"] == "owned-exposure-search"

          type when type in ["function_call", "function_call_output"] ->
            item["call_id"] == "owned-exposure-call"

          _ ->
            false
        end
      end)

    assert [
             %{"type" => "message", "role" => "user"},
             %{"type" => "tool_search_call"},
             %{"type" => "tool_search_output"},
             %{"type" => "function_call"},
             %{"type" => "function_call_output"},
             %{"type" => "message", "role" => "assistant"}
           ] = selected

    selected
  end

  defp assert_search_payloads(
         [user, search, found, invocation, output, assistant],
         turn,
         began,
         ended
       ) do
    user_metadata = Map.fetch!(user, "internal_chat_message_metadata_passthrough")
    created = Map.fetch!(user_metadata, "create_time")
    assert is_number(created) and created >= began and created <= ended
    assert is_binary(Map.fetch!(user, "id")) and byte_size(user["id"]) > 0

    assert user_metadata === %{
             "turn_id" => turn,
             "create_time" => created,
             "content_item_kinds" => ["user.text"]
           }

    assert_search_pair(search, found, turn, began, ended)
    assert_search_function(invocation, output, turn, began, ended)
    assert Map.fetch!(assistant, "id") == "owned-exposure-answer"

    assert_message(
      assistant,
      "assistant",
      [%{"type" => "output_text", "text" => @search_answer}],
      turn,
      began,
      ended
    )
  end

  defp assert_search_pair(search, found, turn, began, ended) do
    search_id = Map.fetch!(search, "id")
    assert is_binary(search_id) and String.starts_with?(search_id, "tsc_")

    assert search === %{
             "type" => "tool_search_call",
             "id" => search_id,
             "call_id" => "owned-exposure-search",
             "execution" => "client",
             "arguments" => %{"query" => "quasar_lookup_824", "limit" => 1},
             "internal_chat_message_metadata_passthrough" => %{"turn_id" => turn}
           }

    found_id = Map.fetch!(found, "id")
    assert is_binary(found_id) and String.starts_with?(found_id, "tso_")
    found_metadata = Map.fetch!(found, "internal_chat_message_metadata_passthrough")
    found_created = Map.fetch!(found_metadata, "create_time")
    assert is_number(found_created) and found_created >= began and found_created <= ended

    assert found === %{
             "type" => "tool_search_output",
             "id" => found_id,
             "call_id" => "owned-exposure-search",
             "status" => "completed",
             "execution" => "client",
             "tools" => [@search_provider_namespace],
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => found_created
             }
           }
  end

  defp assert_search_function(invocation, output, turn, began, ended) do
    call_id = Map.fetch!(invocation, "id")
    assert is_binary(call_id) and String.starts_with?(call_id, "fc_")

    assert invocation === %{
             "type" => "function_call",
             "id" => call_id,
             "call_id" => "owned-exposure-call",
             "namespace" => "owned_catalog",
             "name" => "quasar_lookup_824",
             "arguments" => @search_arguments,
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
             "call_id" => "owned-exposure-call",
             "output" => @search_output,
             "internal_chat_message_metadata_passthrough" => %{
               "turn_id" => turn,
               "create_time" => output_created
             }
           }
  end

  defp assert_search_import(ctx, path, history) do
    {_bytes, payloads} = rollout(ctx, path)
    assert captured_search_history(payloads) === history
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
  end

  defp assert_search_provider(request, completed?, followup?) do
    input = Map.fetch!(request, "input")
    assert [search] = Enum.filter(input, &(&1["type"] == "tool_search_call"))

    assert Map.delete(search, "id") === %{
             "type" => "tool_search_call",
             "call_id" => "owned-exposure-search",
             "execution" => "client",
             "arguments" => %{"query" => "quasar_lookup_824", "limit" => 1}
           }

    assert [found] = Enum.filter(input, &(&1["type"] == "tool_search_output"))

    assert Map.delete(found, "id") === %{
             "type" => "tool_search_output",
             "call_id" => "owned-exposure-search",
             "status" => "completed",
             "execution" => "client",
             "tools" => [@search_provider_namespace]
           }

    assert Enum.count(input, fn item ->
             item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => @search_marker}]
           end) == 1

    if completed? do
      assert [invocation] = Enum.filter(input, &(&1["type"] == "function_call"))

      assert Map.delete(invocation, "id") === %{
               "type" => "function_call",
               "call_id" => "owned-exposure-call",
               "namespace" => "owned_catalog",
               "name" => "quasar_lookup_824",
               "arguments" => @search_arguments
             }

      assert [output] = Enum.filter(input, &(&1["type"] == "function_call_output"))

      assert Map.delete(output, "id") === %{
               "type" => "function_call_output",
               "call_id" => "owned-exposure-call",
               "output" => @search_output
             }
    end

    if followup? do
      assert Enum.count(input, fn item ->
               item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @search_followup}]
             end) == 1

      assert Enum.count(input, fn item ->
               item["role"] == "assistant" and
                 item["content"] === [%{"type" => "output_text", "text" => @search_answer}]
             end) == 1
    end
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
