defmodule SamgitaCodexDriver.NativePersistedToolOutputVariantsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ImageFixture, ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, thread: 3, start_turn: 3, finish_turn: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @answer "Deterministic local fixture answer"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Fixed synthetic lookup with an explicit client response",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  @standalone_name "owned_retained_content"
  @content_text "Owned retained content array λ🙂\nSecond synthetic line"
  @low_placeholder "image content omitted because detail 'low' is not supported; use 'high', 'original', or 'auto'"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-tool-output-variants-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "dynamic_tool")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Exit callbacks run in reverse registration order: native sessions first,
    # then confirmed provider shutdown, then deletion of the owned fixture root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture}

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image"],
      "use_responses_lite" => false
    })

    ctx
  end

  for {variant, namespace_mode} <- [
        {:text_only, :explicit_null},
        {:text_and_low_image, :omitted},
        {:text_and_high_image, :omitted}
      ] do
    @variant variant
    @namespace_mode namespace_mode
    test "retained #{@variant} output with #{@namespace_mode} namespace survives first cold selection",
         ctx do
      pid = start(ctx)
      %{connection: warm_connection} = :sys.get_state(pid)
      warm_instance = Session.status(pid).instance_id

      id =
        thread(ctx, pid, %{
          "historyMode" => "paginated",
          "dynamicTools" => [@lookup]
        })

      turn =
        start_turn(pid, id, [
          %{"type" => "text", "text" => "Owned retained array #{@variant}: λ🙂"}
        ])

      {tool, events} = await_tool(pid, [], System.monotonic_time(:millisecond) + 10_000)
      assert_pending(ctx, pid, id, turn, tool)

      text = %{"type" => "input_text", "text" => @content_text}
      # The small owned RGB image stays below the pin's high-detail budgets.
      # Its independent pixel/CRC oracle also checks the provider continuation.
      image_bytes = ImageFixture.png(2, 2)
      image_url = ImageFixture.data_url(image_bytes)

      content =
        case @variant do
          :text_only ->
            [text]

          :text_and_low_image ->
            [text, %{"type" => "input_image", "image_url" => image_url, "detail" => "low"}]

          :text_and_high_image ->
            [text, %{"type" => "input_image", "image_url" => image_url, "detail" => "high"}]
        end

      standalone = %{
        "name" => @standalone_name,
        "output" => content,
        "retain" => true
      }

      # Both input forms deserialize to None in the pin. Public ThreadItem emits
      # null, while the provider ResponseItem skips its absent namespace member.
      standalone =
        case @namespace_mode do
          :explicit_null ->
            with_null = Map.put(standalone, "namespace", nil)
            assert Map.fetch(with_null, "namespace") == {:ok, nil}
            with_null

          :omitted ->
            assert Map.fetch(standalone, "namespace") == :error
            standalone
        end

      assert TurnFixture.start_turn(pid, id, [], %{"toolOutput" => standalone}) == turn
      assert_pending(ctx, pid, id, turn, tool)
      assert Session.interaction_outcomes(pid) == []
      assert File.ls!(ctx.fixture.workspace) == []
      tool_result = "Owned fixed lookup completion λ🙂"

      # Injection does not resolve the original dynamic-tool interaction.
      assert :ok =
               Session.respond(
                 pid,
                 tool.handle,
                 {:ok,
                  %{
                    "success" => true,
                    "contentItems" => [%{"type" => "inputText", "text" => tool_result}]
                  }}
               )

      events = events ++ finish_turn(pid, id, turn)
      assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
      assert_turn(events, id, turn)
      started = item_event(events, "item/started", "functionCallOutput")
      completed = item_event(events, "item/completed", "functionCallOutput")
      item_id = started["item"]["id"]
      assert is_binary(item_id) and item_id != ""
      began = started["startedAtMs"]
      ended = completed["completedAtMs"]
      assert is_integer(began) and began > 0
      assert is_integer(ended) and ended >= began

      # Every payload field comes from prescribed caller input. Only native
      # identity and canonical timestamps are observed, never a history payload.
      expected_item = %{
        "type" => "functionCallOutput",
        "id" => item_id,
        "name" => @standalone_name,
        "namespace" => nil,
        "output" => content
      }

      assert started == %{
               "threadId" => id,
               "turnId" => turn,
               "item" => expected_item,
               "startedAtMs" => began
             }

      assert completed == %{
               "threadId" => id,
               "turnId" => turn,
               "item" => expected_item,
               "completedAtMs" => ended
             }

      requests = ModelFixture.requests(ctx.fixture)
      assert [first, continued] = requests
      assert first["model"] == "mock-model" and continued["model"] == "mock-model"
      refute Enum.any?(first["input"], &(&1["type"] == "function_call_output"))

      assert [captured] =
               Enum.filter(
                 continued["input"],
                 &(&1["type"] == "function_call_output" and &1["name"] == @standalone_name)
               )

      # The public item preserves caller input. Provider preparation separately
      # replaces unsupported low detail with this exact pinned placeholder.
      provider_content =
        if @variant == :text_and_low_image,
          do: [text, %{"type" => "input_text", "text" => @low_placeholder}],
          else: content

      # Exact provider shape independently proves preparation and namespace
      # omission; copying a historical/native item cannot satisfy this oracle.
      assert captured == %{
               "type" => "function_call_output",
               "id" => item_id,
               "name" => @standalone_name,
               "output" => provider_content
             }

      if @variant == :text_and_high_image do
        assert [^text, image] = captured["output"]
        assert {^image_bytes, {2, 2}} = ImageFixture.decode_png!(image["image_url"])
      end

      assert [lookup_output] =
               Enum.filter(
                 continued["input"],
                 &(&1["type"] == "function_call_output" and &1["call_id"] == "fixture-call-1")
               )

      assert lookup_output["output"] == tool_result
      assert length(Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))) == 2
      assert item_event(events, "item/completed", "agentMessage")["item"]["text"] == @answer
      assert_idle(pid)
      assert Session.uncertain_operations(pid) == []
      assert File.ls!(ctx.fixture.workspace) == []

      # Persist the canonical producer projection without taking expected data
      # from thread/read. First cold content access below is selective only.
      hydrated = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})
      assert hydrated["thread"]["id"] == id
      assert hydrated["thread"]["historyMode"] == "paginated"

      query = %{"threadId" => id, "turnId" => turn, "itemIds" => [item_id]}

      expected_entry = %{
        "turnId" => turn,
        "item" => expected_item,
        "startedAtMs" => began,
        "completedAtMs" => ended
      }

      assert_selected = fn client ->
        assert call(client, "thread/items/read", query) == %{"data" => [expected_entry]}

        assert call(client, "thread/items/read", %{
                 query
                 | "itemIds" => ["owned-absent-array-item", item_id, item_id]
               }) == %{"data" => [expected_entry]}

        assert call(client, "thread/items/read", %{
                 query
                 | "itemIds" => ["owned-absent-array-item"]
               }) == %{"data" => []}

        assert call(client, "thread/items/read", %{
                 query
                 | "turnId" => "owned-absent-array-turn"
               }) == %{"data" => []}

        assert ModelFixture.requests(ctx.fixture) == requests
        assert File.ls!(ctx.fixture.workspace) == []
        assert_idle(client)
        assert %{gap: nil} = Session.status(client)
        assert Session.uncertain_operations(client) == []
      end

      assert_selected.(pid)
      warm_native = call(pid, "server/diagnostics", %{})["process"]["id"]
      assert :ok = StdioSessionFixture.close(pid, warm_connection)
      refute File.exists?("/proc/#{warm_native}")
      cold = start(ctx)
      %{connection: cold_connection} = :sys.get_state(cold)
      assert Session.status(cold).instance_id != warm_instance
      cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
      refute cold_native == warm_native
      assert call(cold, "thread/loaded/list", %{})["data"] == []

      # First thread-content operation in the distinct, unhydrated native process.
      assert_selected.(cold)
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert {:ok, remaining} = Session.drain(cold)
      refute Enum.any?(remaining, &(&1.kind == :server_request))
      refute Enum.any?(remaining, &(&1.wire["method"] in ["turn/started", "turn/completed"]))
      assert :ok = StdioSessionFixture.close(cold, cold_connection)
      refute File.exists?("/proc/#{cold_native}")
      assert ModelFixture.requests(ctx.fixture) == requests
      assert File.ls!(ctx.fixture.workspace) == []
    end
  end

  defp item_events(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp item_event(events, method, type) do
    assert [event] = Enum.filter(item_events(events, method), &(&1["item"]["type"] == type))
    event
  end

  defp assert_turn(events, id, turn) do
    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == id
      assert params["turn"]["id"] == turn
    end
  end

  defp await_tool(pid, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    refute Enum.any?(events, &(&1.wire["method"] == "turn/completed"))

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] ->
        {tool, events}

      [] ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {:codex_driver, ^pid, :events_available} ->
            await_tool(pid, events, deadline)

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected event gap awaiting fixed native tool")
        after
          remaining -> flunk("Fixed native tool deadline")
        end

      _ ->
        flunk("Unexpected additional native interaction")
    end
  end

  defp assert_pending(ctx, pid, id, turn, tool) do
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert tool.kind == :server_request
    assert tool.wire["method"] == "item/tool/call"
    assert is_integer(tool.wire["id"]) or is_binary(tool.wire["id"])
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => id,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }
  end

  defp assert_idle(pid),
    do: assert(%{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid))

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
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
               %{"name" => "samgita_persisted_tool_output_variants", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
