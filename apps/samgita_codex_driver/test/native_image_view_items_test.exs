defmodule SamgitaCodexDriver.NativeImageViewItemsTest do
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
  import TurnFixture, only: [call: 3, thread: 3, start_turn: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/image_view_fixture.py", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @call_id "owned-view-image-call-1"
  @relative_image "owned-image.png"
  @canary "OWNED_IMAGE_VIEW_UNCHANGED_CANARY\n"
  @answer "Owned local image read finished"

  setup context do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert file_hash(binary) == @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-image-view-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, Map.get(context, :image_view_scenario, "image_view"))
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Native guardians registered later close/reap before provider/root teardown.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    assert ModelFixture.requests(fixture) == []
    File.mkdir!(Path.join(root, "tmp"))
    png = ImageFixture.png(2, 2)
    image_path = Path.join(fixture.workspace, @relative_image)
    File.write!(image_path, png, [:exclusive])
    File.write!(Path.join(fixture.workspace, "canary.txt"), @canary, [:exclusive])
    ctx = %{binary: binary, root: root, fixture: fixture, png: png, image_path: image_path}

    TurnFixture.configure_model(ctx, %{
      "input_modalities" => ["text", "image"],
      "use_responses_lite" => false
    })

    ctx
  end

  test "native local image view survives first cold selective history after source removal",
       ctx do
    # The semantic oracle is complete before native observation. PNG dimensions,
    # CRCs and all RGB(17,34,51) pixels are checked independently by ImageFixture.
    expected = %{"id" => @call_id, "type" => "imageView", "path" => ctx.image_path}
    assert ctx.image_path == Path.join(ctx.fixture.workspace, @relative_image)
    assert {source_png, {2, 2}} = ImageFixture.decode_png!(ImageFixture.data_url(ctx.png))
    assert source_png === ctx.png
    source_hash = file_hash(ctx.image_path)
    assert_present_files(ctx, source_hash)

    warm = start(ctx)
    warm_instance = Session.status(warm).instance_id
    %{connection: warm_connection} = :sys.get_state(warm)
    warm_native_pid = assert_native(warm)
    id = thread(ctx, warm, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []
    before_ms = System.system_time(:millisecond)

    turn =
      start_turn(warm, id, [
        %{"type" => "text", "text" => "Read only the owned synthetic local PNG"}
      ])

    events = collect(warm, turn, [], System.monotonic_time(:millisecond) + 15_000)
    after_ms = System.system_time(:millisecond)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    # Exactly one native call lifecycle; no callback, shell or approval executes.
    started = image_notification(events, "item/started")
    completed = image_notification(events, "item/completed")
    started_at_ms = Map.fetch!(started, "startedAtMs")
    completed_at_ms = Map.fetch!(completed, "completedAtMs")
    assert is_integer(started_at_ms) and is_integer(completed_at_ms)
    assert before_ms <= started_at_ms and started_at_ms <= completed_at_ms
    assert completed_at_ms <= after_ms

    assert started === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected,
             "startedAtMs" => started_at_ms
           }

    assert completed === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completed_at_ms
           }

    assert [@answer] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]["item"]["text"]
             )

    assert Session.interaction_outcomes(warm) == []
    assert_idle(warm)
    requests = assert_provider(ctx)
    assert_present_files(ctx, source_hash)

    # Only the warm producer gets a thread/read store barrier.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(warm, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [@call_id]}

    expected_direct = %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => expected,
          "startedAtMs" => started_at_ms,
          "completedAtMs" => completed_at_ms
        }
      ]
    }

    warm_response = call(warm, "thread/items/read", query)
    assert warm_response === expected_direct
    assert_selection(warm, query, expected_direct)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_present_files(ctx, source_hash)
    assert_no_execution_events(warm)
    close_owned(warm)
    assert_gone(warm_native_pid)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_present_files(ctx, source_hash)

    # Fixture mutation only, after confirmed native shutdown: this exact PNG was
    # created above with exclusive mode. History must not reread or recreate it.
    assert Path.dirname(ctx.image_path) == ctx.fixture.workspace
    assert File.lstat!(ctx.image_path).type == :regular
    assert File.read!(ctx.image_path) === ctx.png
    assert :ok = File.rm(ctx.image_path)
    assert_removed_files(ctx)

    cold = start(ctx)
    refute cold == warm
    refute Session.status(cold).instance_id == warm_instance
    %{connection: cold_connection} = :sys.get_state(cold)
    refute cold_connection.port == warm_connection.port
    cold_native_pid = assert_native(cold)
    refute cold_native_pid == warm_native_pid
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_removed_files(ctx)

    # First content read in a distinct pinned native process. No resume,
    # thread/read hydration or turn can hide a re-execution/read dependency.
    cold_response = call(cold, "thread/items/read", query)
    assert cold_response === expected_direct
    assert cold_response === warm_response
    assert_selection(cold, query, expected_direct)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_removed_files(ctx)
    assert_no_execution_events(cold)
    assert_idle(cold)
    close_owned(cold)
    assert_gone(cold_native_pid)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_removed_files(ctx)
  end

  @tag image_view_scenario: "image_view_invalid"
  test "native invalid image returns exact text without a live or persisted imageView", ctx do
    invalid = "OWNED_NOT_AN_IMAGE\n"

    File.write!(Path.join(ctx.fixture.workspace, "owned-invalid-image.png"), invalid, [:exclusive])

    assert_rejected_view(
      ctx,
      "owned-view-image-invalid-call-1",
      %{"path" => "owned-invalid-image.png"},
      "unable to process image: invalid or unsupported image data",
      %{"owned-invalid-image.png" => invalid}
    )
  end

  @tag image_view_scenario: "image_view_low_detail"
  test "native unsupported detail returns exact text without a live or persisted imageView",
       ctx do
    assert_rejected_view(
      ctx,
      "owned-view-image-low-detail-call-1",
      %{"path" => @relative_image, "detail" => "low"},
      "view_image.detail only supports " <>
        "`high` or `original`; omit `detail` for default high resized behavior, got `low`"
    )
  end

  defp assert_rejected_view(ctx, call_id, arguments, error, extra_files \\ %{}) do
    assert {_png, {2, 2}} = ImageFixture.decode_png!(ImageFixture.data_url(ctx.png))
    assert_rejected_files(ctx, extra_files)
    warm = start(ctx)
    warm_instance = Session.status(warm).instance_id
    %{connection: warm_connection} = :sys.get_state(warm)
    warm_native_pid = assert_native(warm)
    id = thread(ctx, warm, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []

    turn =
      start_turn(warm, id, [
        %{"type" => "text", "text" => "Inspect only the owned synthetic image fixture"}
      ])

    events = collect(warm, turn, [], System.monotonic_time(:millisecond) + 15_000)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ["item/started", "item/completed"] and
               event.wire["params"]["item"]["type"] == "imageView"
           end)

    assert [@answer] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]["item"]["text"]
             )

    assert Session.interaction_outcomes(warm) == []
    assert_idle(warm)
    requests = assert_rejected_provider(ctx, call_id, arguments, error)
    assert_rejected_files(ctx, extra_files)

    # Failed calls emit no imageView item. Do not invent a failure ThreadItem.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(warm, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [call_id]}
    assert call(warm, "thread/items/read", query) === %{"data" => []}
    assert_selection(warm, query, %{"data" => []}, call_id)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_rejected_files(ctx, extra_files)
    assert_no_execution_events(warm)
    close_owned(warm)
    assert_gone(warm_native_pid)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_rejected_files(ctx, extra_files)

    cold = start(ctx)
    refute cold == warm
    refute Session.status(cold).instance_id == warm_instance
    %{connection: cold_connection} = :sys.get_state(cold)
    refute cold_connection.port == warm_connection.port
    cold_native_pid = assert_native(cold)
    refute cold_native_pid == warm_native_pid
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_rejected_files(ctx, extra_files)

    # First content read: no resume, thread/read hydration or new turn.
    assert call(cold, "thread/items/read", query) === %{"data" => []}
    assert_selection(cold, query, %{"data" => []}, call_id)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_rejected_files(ctx, extra_files)
    assert_no_execution_events(cold)
    assert Session.interaction_outcomes(cold) == []
    assert_idle(cold)
    close_owned(cold)
    assert_gone(cold_native_pid)
    assert ModelFixture.requests(ctx.fixture) === requests
    assert_rejected_files(ctx, extra_files)
  end

  defp assert_rejected_provider(ctx, call_id, arguments, error) do
    assert [first, continued] = requests = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"

    assert [_view_image] =
             Enum.filter(
               first["tools"],
               &(&1["type"] == "function" and &1["name"] == "view_image")
             )

    assert calls(first) == []
    assert outputs(first) == []
    assert images(first["input"]) == []
    assert [view_call] = calls(continued)
    assert view_call["name"] == "view_image"
    assert view_call["call_id"] == call_id
    assert JSON.decode!(view_call["arguments"]) === arguments
    assert [output] = outputs(continued)
    output_id = Map.fetch!(output, "id")
    assert is_binary(output_id) and output_id != call_id

    assert Regex.match?(
             ~r/^fco_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
             output_id
           )

    # success=false is internal metadata; the native wire output is plain text.
    assert output === %{
             "type" => "function_call_output",
             "id" => output_id,
             "call_id" => call_id,
             "output" => error
           }

    assert images(continued["input"]) == []
    requests
  end

  defp assert_rejected_files(ctx, extra_files) do
    expected = Map.merge(%{@relative_image => ctx.png, "canary.txt" => @canary}, extra_files)
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == Enum.sort(Map.keys(expected))

    for {name, bytes} <- expected do
      path = Path.join(ctx.fixture.workspace, name)
      assert File.lstat!(path).type == :regular
      assert File.read!(path) === bytes
      assert file_hash(path) == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    end
  end

  defp assert_provider(ctx) do
    assert [first, continued] = requests = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"

    assert [_view_image] =
             Enum.filter(
               first["tools"],
               &(&1["type"] == "function" and &1["name"] == "view_image")
             )

    assert calls(first) == []
    assert outputs(first) == []
    assert images(first["input"]) == []
    assert [view_call] = calls(continued)
    assert view_call["name"] == "view_image"
    assert view_call["call_id"] == @call_id
    assert JSON.decode!(view_call["arguments"]) === %{"path" => @relative_image}
    assert [output] = outputs(continued)

    assert [%{"type" => "input_image", "image_url" => url, "detail" => "high"} = image] =
             output["output"]

    assert image === %{"type" => "input_image", "image_url" => url, "detail" => "high"}

    # The native session stamps a separate durable Responses item identity:
    # session/mod.rs:3543-3552 and response_item_id.rs:20-25 use fco + UUIDv7.
    output_id = Map.fetch!(output, "id")
    assert is_binary(output_id) and output_id != @call_id

    assert Regex.match?(
             ~r/^fco_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
             output_id
           )

    assert output === %{
             "type" => "function_call_output",
             "id" => output_id,
             "call_id" => @call_id,
             "output" => [image]
           }

    # The native decoder/encoder may change PNG encoding. Check independent
    # CRCs, dimensions and every pixel instead of recycling observed image bytes.
    assert {_encoded_png, {2, 2}} = ImageFixture.decode_png!(url)
    assert images(continued["input"]) === [image]
    requests
  end

  defp calls(request),
    do: Enum.filter(request["input"], &(&1["type"] == "function_call"))

  defp outputs(request),
    do: Enum.filter(request["input"], &(&1["type"] == "function_call_output"))

  defp images(%{"type" => "input_image"} = image), do: [image]
  defp images(value) when is_map(value), do: value |> Map.values() |> Enum.flat_map(&images/1)
  defp images(value) when is_list(value), do: Enum.flat_map(value, &images/1)
  defp images(_value), do: []

  defp assert_present_files(ctx, source_hash) do
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["canary.txt", @relative_image]
    assert File.lstat!(ctx.image_path).type == :regular
    assert File.read!(ctx.image_path) === ctx.png
    assert file_hash(ctx.image_path) == source_hash
    assert File.read!(Path.join(ctx.fixture.workspace, "canary.txt")) === @canary
  end

  defp assert_removed_files(ctx) do
    refute File.exists?(ctx.image_path)
    assert File.ls!(ctx.fixture.workspace) == ["canary.txt"]
    assert File.read!(Path.join(ctx.fixture.workspace, "canary.txt")) === @canary
  end

  defp image_notification(events, method) do
    assert [params] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["type"] == "imageView",
               do: event.wire["params"]
             )

    params
  end

  defp assert_selection(pid, query, expected, call_id \\ @call_id) do
    assert call(
             pid,
             "thread/items/read",
             Map.put(query, "itemIds", [call_id, call_id, "owned-absent-item"])
           ) === expected

    assert call(pid, "thread/items/read", Map.put(query, "itemIds", ["owned-absent-item"])) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", Map.put(query, "turnId", "owned-absent-turn")) ===
             %{"data" => []}
  end

  defp collect(pid, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)

    refute Enum.any?(incoming, &(&1.kind == :server_request)),
           "Unexpected interaction: the owned image view requires no approval or callback"

    events = events ++ incoming

    if notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, turn, events, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected image-view event gap")
      after
        remaining -> flunk("Native image-view deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_no_execution_events(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "item/started",
               "item/completed",
               "turn/started",
               "turn/completed"
             ]
           end)
  end

  defp assert_native(pid) do
    native_pid = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native_pid) and native_pid > 0
    assert file_hash("/proc/#{native_pid}/exe") == @binary_sha256
    native_pid
  end

  defp file_hash(path),
    do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

  defp assert_gone(native_pid, remaining \\ 100) do
    if File.exists?("/proc/#{native_pid}") do
      assert remaining > 0, "Owned native process #{native_pid} survived cleanup"
      Process.sleep(10)
      assert_gone(native_pid, remaining - 1)
    else
      :ok
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "samgita_native_image_view", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
  end
end
