defmodule SamgitaCodexDriver.NativeSuppliedNullImageDetailHistoryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ImageFixture,
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
  @script Path.expand(
            "../../../scripts/codex/supplied_null_image_detail_history_fixture.py",
            __DIR__
          )
  @original_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @original_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @source_answer "Deterministic local fixture answer"
  @answer "Owned imported null image detail consumed 163"
  @result "Owned genuine dynamic image output 163"
  @file_id "file-owned-null-image-detail-163"
  @metadata "internal_chat_message_metadata_passthrough"
  @effect "owned-null-image-tool-effect-once-163\n"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Owned null-image history lookup",
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

    assert hash(binary) == @binary_sha
    assert hash(@original_script) == @original_sha
    root = owned_root()
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, if(tags.profile == :user, do: "assistant", else: "dynamic_tool"))
      after
        restore_script(previous)
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    ctx = %{binary: binary, root: root, fixture: fixture, profile: tags.profile}

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image"],
      "use_responses_lite" => false,
      "supports_image_detail_original" => false
    })

    paths = [
      @script,
      @original_script,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "turn-models.json")
    ]

    Map.put(ctx, :unchanged, Enum.map(paths, &{&1, File.read!(&1)}))
  end

  for profile <- [:user, :tool] do
    @tag profile: profile
    test "native #{profile} image detail client-null is consumed after cold import", ctx do
      source = start(ctx)
      source_native = native_process(source)
      source_id = TurnFixture.thread(ctx, source, source_options(ctx))
      began = System.system_time(:microsecond) / 1_000_000
      turn = TurnFixture.start_turn(source, source_id, source_input(ctx))
      source_events = complete_source(ctx, source, source_id, turn)
      assert_completed(source_events, source_id, turn)
      assert_answer(source_events, source_id, turn, @source_answer)
      assert_idle(source)
      source_path = read_thread(source, source_id)["path"]
      ended = System.system_time(:microsecond) / 1_000_000
      source_requests = requests(ctx)
      assert length(source_requests) == source_budget(ctx)
      assert :ok = Session.close(source)
      assert_gone(source_native)

      # The native source owns all records. Only a submitted clone changes;
      # the real source rollout is never rewritten or copied as a fake producer.
      {source_bytes, payloads} = rollout(ctx, source_path)
      history = captured_history(ctx, payloads, turn, began, ended)
      assert_source_provider(ctx, source_requests, history)
      {submitted, expected} = null_detail(ctx, history)
      assert byte_size(JSON.encode!(submitted)) <= 1_048_576
      cold = start(ctx)
      cold_native = native_process(cold)
      refute cold_native == source_native
      assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
      imported = import_history(ctx, cold, source_id, submitted)
      imported_id = imported["id"]
      assert is_binary(imported_id) and imported_id != "" and imported_id != source_id
      assert imported["preview"] == marker(ctx)
      assert imported["status"] === %{"type" => "idle"}
      imported_path = read_thread(cold, imported_id)["path"]
      refute imported_path == source_path
      assert_import(ctx, imported_path, expected)
      assert {:ok, import_events} = Session.drain(cold, 256)
      assert_event_bounds(import_events)
      assert Session.status(cold).buffered_events == 0
      assert_no_dispatch(import_events)
      refute Enum.any?(import_events, &(&1.wire["method"] == "turn/started"))
      assert_idle(cold)
      assert requests(ctx) === source_requests
      assert_retained(ctx, source_path, source_bytes)

      followup_turn = TurnFixture.start_turn(cold, imported_id, text(followup(ctx)))
      followup_events = collect(cold, imported_id, followup_turn, [], now() + 20_000)
      assert_completed(followup_events, imported_id, followup_turn)
      assert_answer(followup_events, imported_id, followup_turn, @answer)
      assert_no_dispatch(followup_events)
      assert_idle(cold)
      assert [consumed] = requests(ctx) -- source_requests
      assert requests(ctx) === source_requests ++ [consumed]
      assert_provider_history(consumed, expected)
      assert_followup_provider(ctx, consumed)
      assert_import(ctx, imported_path, expected)
      assert_retained(ctx, source_path, source_bytes)
      assert :ok = Session.close(cold)
      assert_gone(cold_native)
      assert_import(ctx, imported_path, expected)
      assert requests(ctx) === source_requests ++ [consumed]
      assert_retained(ctx, source_path, source_bytes)
    end
  end

  defp owned_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-null-image-history-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp restore_script(nil), do: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
  defp restore_script(previous), do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous)

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp marker(%{profile: :user}), do: "Owned source user image detail null 163"
  defp marker(%{profile: :tool}), do: "Owned source dynamic image detail null 163"
  defp followup(%{profile: :user}), do: "Owned continuation consumes user image null detail 163"

  defp followup(%{profile: :tool}),
    do: "Owned continuation consumes dynamic image null detail 163"

  defp source_budget(%{profile: :user}), do: 1
  defp source_budget(%{profile: :tool}), do: 2
  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]
  defp image_url, do: ImageFixture.data_url(ImageFixture.png(2, 2))

  defp source_options(ctx) do
    base = %{
      "historyMode" => "legacy",
      "approvalPolicy" => "never",
      "sandbox" => "danger-full-access"
    }

    if ctx.profile == :tool, do: Map.put(base, "dynamicTools", [@lookup]), else: base
  end

  defp source_input(%{profile: :user} = ctx),
    do: text(marker(ctx)) ++ [%{"type" => "image", "fileId" => @file_id, "detail" => "low"}]

  defp source_input(ctx), do: text(marker(ctx))

  defp raw_content(%{profile: :user} = ctx),
    do: [
      raw_text(marker(ctx)),
      %{"type" => "input_image", "file_id" => @file_id, "detail" => "low"}
    ]

  defp raw_content(ctx), do: [raw_text(marker(ctx))]
  defp raw_text(value), do: %{"type" => "input_text", "text" => value}

  defp complete_source(%{profile: :user}, source, thread, turn) do
    events = collect(source, thread, turn, [], now() + 20_000)
    assert_no_dispatch(events)
    events
  end

  defp complete_source(ctx, source, thread, turn) do
    {tool, events} = await_tool(source, [], now() + 10_000)

    assert tool.wire["params"] === %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert [_first] = requests(ctx)
    effect = effect_path(ctx)
    refute File.exists?(effect)
    File.write!(effect, @effect, [:append])

    assert :ok =
             Session.respond(
               source,
               tool.handle,
               {:ok,
                %{
                  "success" => true,
                  "contentItems" => [
                    %{"type" => "inputText", "text" => @result},
                    %{"type" => "inputImage", "imageUrl" => image_url()}
                  ]
                }}
             )

    events = collect(source, thread, turn, events, now() + 20_000)
    assert [^tool] = dynamic_calls(events)
    events
  end

  defp captured_history(ctx, payloads, turn, began, ended) do
    history = Enum.filter(payloads, &source_item?(&1, ctx))
    assert length(history) == if(ctx.profile == :user, do: 2, else: 4)
    [user | rest] = history
    assert_source_user(ctx, user, turn, began, ended)
    assert_source_assistant(List.last(rest), source_budget(ctx), turn)
    assert_tool_history(ctx, rest, turn, began, ended)
    ids = Enum.map(history, &Map.fetch!(&1, "id"))
    assert length(Enum.uniq(ids)) == length(history)
    history
  end

  defp source_item?(%{"type" => "message", "role" => "user"} = item, ctx),
    do: item["content"] === raw_content(ctx)

  defp source_item?(%{"type" => "message", "role" => "assistant"} = item, ctx),
    do: item["id"] == "fixture-message-#{source_budget(ctx)}"

  defp source_item?(%{"type" => type} = item, %{profile: :tool})
       when type in ["function_call", "function_call_output"],
       do: item["call_id"] == "fixture-call-1"

  defp source_item?(_item, _ctx), do: false

  defp assert_source_user(ctx, user, turn, began, ended) do
    id = assert_native_id(user, "msg_")
    created = assert_created(user, began, ended)
    kinds = if ctx.profile == :user, do: ["user.text", "user.image"], else: ["user.text"]

    assert user === %{
             "type" => "message",
             "id" => id,
             "role" => "user",
             "content" => raw_content(ctx),
             @metadata => %{
               "turn_id" => turn,
               "create_time" => created,
               "content_item_kinds" => kinds
             }
           }
  end

  defp assert_source_assistant(assistant, index, turn) do
    # Native persistence preserves this original NON-prefixed provider ID.
    assert assistant === %{
             "type" => "message",
             "id" => "fixture-message-#{index}",
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @source_answer}],
             @metadata => %{"turn_id" => turn, "content_item_kinds" => ["unknown"]}
           }
  end

  defp assert_tool_history(%{profile: :user}, [_assistant], _turn, _began, _ended), do: :ok

  defp assert_tool_history(
         %{profile: :tool},
         [invocation, output, _assistant],
         turn,
         began,
         ended
       ) do
    assert_source_call(invocation, turn)
    id = assert_native_id(output, "fco_")
    created = assert_created(output, began, ended)

    assert output === %{
             "type" => "function_call_output",
             "id" => id,
             "call_id" => "fixture-call-1",
             "output" => [
               raw_text(@result),
               %{
                 "type" => "input_image",
                 "image_url" => image_url(),
                 "detail" => "high"
               }
             ],
             @metadata => %{"turn_id" => turn, "create_time" => created}
           }

    assert_png(output["output"] |> Enum.at(1))
  end

  defp assert_source_call(invocation, turn) do
    id = assert_native_id(invocation, "fc_")

    assert invocation === %{
             "type" => "function_call",
             "id" => id,
             "call_id" => "fixture-call-1",
             "name" => "fixture_lookup",
             "arguments" => ~s({"key": "synthetic"}),
             @metadata => %{"turn_id" => turn}
           }
  end

  defp assert_native_id(item, prefix) do
    id = Map.fetch!(item, "id")
    assert is_binary(id) and String.starts_with?(id, prefix) and byte_size(id) > byte_size(prefix)
    id
  end

  defp assert_created(item, began, ended) do
    created = Map.fetch!(Map.fetch!(item, @metadata), "create_time")
    assert is_number(created) and created > 0 and created >= began and created <= ended
    created
  end

  defp assert_png(image) do
    assert Map.fetch!(image, "image_url") === image_url()
    expected_bytes = ImageFixture.png(2, 2)
    assert {^expected_bytes, {2, 2}} = ImageFixture.decode_png!(image["image_url"])
  end

  defp null_detail(%{profile: :user}, [user, assistant] = original) do
    [text, image] = Map.fetch!(user, "content")
    assert image === %{"type" => "input_image", "file_id" => @file_id, "detail" => "low"}
    {submitted_image, expected_image} = null_image(image)
    submitted = [Map.put(user, "content", [text, submitted_image]), assistant]
    expected = [Map.put(user, "content", [text, expected_image]), assistant]
    assert [Map.put(user, "content", [text, image]), assistant] === original
    assert submitted !== original and submitted !== expected
    {submitted, expected}
  end

  defp null_detail(%{profile: :tool}, [user, invocation, output, assistant] = original) do
    [text, image] = Map.fetch!(output, "output")
    assert image === %{"type" => "input_image", "image_url" => image_url(), "detail" => "high"}
    {submitted_image, expected_image} = null_image(image)
    submitted = [user, invocation, Map.put(output, "output", [text, submitted_image]), assistant]
    expected = [user, invocation, Map.put(output, "output", [text, expected_image]), assistant]
    assert [user, invocation, Map.put(output, "output", [text, image]), assistant] === original
    assert submitted !== original and submitted !== expected
    {submitted, expected}
  end

  defp null_image(image) do
    submitted = Map.put(image, "detail", nil)
    expected = Map.delete(image, "detail")
    assert Map.has_key?(submitted, "detail")
    assert Map.fetch!(submitted, "detail") === nil
    assert Map.delete(submitted, "detail") === expected
    refute Map.has_key?(expected, "detail")
    {submitted, expected}
  end

  defp assert_source_provider(ctx, [first | rest], history) do
    assert_provider_history(first, [hd(history)])

    case ctx.profile do
      :user ->
        assert rest === []

      :tool ->
        assert [continuation] = rest
        assert_provider_history(continuation, Enum.take(history, 3))
        assert File.read!(effect_path(ctx)) === @effect
    end
  end

  defp provider_copy(item) do
    # client.rs1007–1025 removes passthrough for custom providers;1092–1096
    # independently drops non-prefixed IDs. Durable maps keep both unchanged.
    copy = Map.delete(item, @metadata)
    if prefixed_id?(item["id"]), do: copy, else: Map.delete(copy, "id")
  end

  defp prefixed_id?(id) do
    case String.split(id, "_", parts: 2) do
      [prefix, suffix] -> prefix != "" and suffix != ""
      _ -> false
    end
  end

  defp assert_provider_history(request, history) do
    input = Map.fetch!(request, "input")
    expected = Enum.map(history, &provider_copy/1)
    selected = Enum.filter(input, &provider_item?(&1, expected))
    assert selected === expected

    for item <- expected do
      assert Enum.count(input, &(&1 === item)) == 1
    end
  end

  defp provider_item?(item, expected) do
    Enum.any?(expected, fn original ->
      if original["type"] == "message" do
        item["type"] == "message" and item["role"] == original["role"] and
          item["content"] === original["content"]
      else
        item["type"] == original["type"] and item["call_id"] == original["call_id"]
      end
    end)
  end

  defp assert_followup_provider(ctx, request) do
    assert request["model"] == "mock-model"
    input = Map.fetch!(request, "input")
    followup = [raw_text(followup(ctx))]
    assert Enum.count(input, &(&1["role"] == "user" and &1["content"] === followup)) == 1
    assert [assistant] = Enum.filter(input, &(&1["role"] == "assistant"))
    refute Map.has_key?(assistant, "id")
    assert assistant["content"] === [%{"type" => "output_text", "text" => @source_answer}]
    assert_null_provider_image(ctx, input)
    metadata = request["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["history_initialization"] == "supplied_history"
  end

  defp assert_null_provider_image(%{profile: :user}, input) do
    assert [user] = Enum.filter(input, &(&1["role"] == "user" and length(&1["content"]) == 2))
    assert Enum.at(user["content"], 1) === %{"type" => "input_image", "file_id" => @file_id}
  end

  defp assert_null_provider_image(%{profile: :tool}, input) do
    assert [output] = Enum.filter(input, &(&1["type"] == "function_call_output"))
    assert [text, image] = output["output"]
    assert text === raw_text(@result)
    assert image === %{"type" => "input_image", "image_url" => image_url()}
    assert_png(image)
  end

  defp import_history(ctx, cold, source_id, submitted) do
    call(cold, "thread/resume", %{
      "threadId" => source_id,
      "history" => submitted,
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "approvalPolicy" => "never",
      "sandbox" => "danger-full-access"
    })["thread"]
  end

  defp assert_import(ctx, path, expected) do
    {_bytes, payloads} = rollout(ctx, path)
    ids = Enum.map(expected, &Map.fetch!(&1, "id"))
    assert Enum.filter(payloads, &(&1["id"] in ids)) === expected
    for item <- expected, do: assert(Enum.count(payloads, &(&1 === item)) == 1)
  end

  defp assert_retained(ctx, source_path, source_bytes) do
    assert File.read!(source_path) === source_bytes
    for {path, bytes} <- ctx.unchanged, do: assert(File.read!(path) === bytes)
    assert_effect(ctx)
  end

  defp assert_effect(%{profile: :user} = ctx) do
    refute File.exists?(effect_path(ctx))
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp assert_effect(%{profile: :tool} = ctx) do
    assert File.read!(effect_path(ctx)) === @effect
    assert File.ls!(ctx.fixture.workspace) === [Path.basename(effect_path(ctx))]
  end

  defp effect_path(ctx), do: Path.join(ctx.fixture.workspace, "owned-null-image-effect.log")

  defp rollout(ctx, path) do
    assert is_binary(path)
    expanded = Path.expand(path)
    assert String.starts_with?(expanded, Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(expanded)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(expanded)
    assert byte_size(bytes) == size
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048
    rows = Enum.map(lines, &decode_row/1)
    refute Enum.any?(rows, &(&1["type"] == "compacted"))
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    assert payloads != []
    {bytes, payloads}
  end

  defp decode_row(line) do
    assert byte_size(line) <= @max_line_bytes
    JSON.decode!(line)
  end

  defp requests(ctx) do
    assert %{type: :regular, size: size} = File.stat!(ctx.fixture.requests)
    assert size <= @max_file_bytes
    ModelFixture.requests(ctx.fixture)
  end

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp collect(pid, thread, turn, events, deadline) do
    events = drain(pid, events)

    if completed?(events, thread, turn) do
      events
    else
      wait_events(pid, deadline)
      collect(pid, thread, turn, events, deadline)
    end
  end

  defp await_tool(pid, events, deadline) do
    events = drain(pid, events)

    case dynamic_calls(events) do
      [tool] ->
        {tool, events}

      [] ->
        wait_events(pid, deadline)
        await_tool(pid, events, deadline)

      _ ->
        flunk("Expected exactly one native image dynamic call")
    end
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert_event_bounds(events)
    events
  end

  defp assert_event_bounds(events) do
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
  end

  defp wait_events(pid, deadline) do
    assert now() < deadline, "Null-image history event deadline"
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected null-image history event gap")
    after
      10 -> :ok
    end
  end

  defp completed?(events, thread, turn), do: completed_turns(events, thread, turn) != []

  defp completed_turns(events, thread, turn) do
    events
    |> Enum.filter(&(&1.wire["method"] == "turn/completed"))
    |> Enum.map(& &1.wire["params"])
    |> Enum.filter(&(&1["threadId"] == thread and &1["turn"]["id"] == turn))
  end

  defp assert_completed(events, thread, turn) do
    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             completed_turns(events, thread, turn)
  end

  defp assert_answer(events, thread, turn, answer) do
    matches =
      events
      |> Enum.filter(&(&1.wire["method"] == "item/completed"))
      |> Enum.map(& &1.wire["params"])
      |> Enum.filter(&answer_item?(&1, thread, turn))

    assert [
             %{
               "threadId" => ^thread,
               "turnId" => ^turn,
               "item" => %{"type" => "agentMessage", "text" => ^answer}
             }
           ] = matches
  end

  defp answer_item?(params, thread, turn),
    do:
      params["threadId"] == thread and params["turnId"] == turn and
        params["item"]["type"] == "agentMessage"

  defp dynamic_calls(events),
    do: Enum.filter(events, &(&1.wire["method"] == "item/tool/call"))

  defp assert_no_dispatch(events) do
    assert dynamic_calls(events) === []
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned null-image history process #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
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
               %{"name" => "samgita_supplied_null_image_detail", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
