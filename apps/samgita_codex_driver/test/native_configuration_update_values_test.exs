defmodule SamgitaCodexDriver.NativeConfigurationUpdateValuesTest do
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
  @script Path.expand("../../../scripts/codex/configuration_update_fixture.py", __DIR__)
  @script_sha "754f9c49e236707f4605a699ce230b0e772f3411016ddd23f161027164733d38"
  @original_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @original_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @markers Enum.map(1..4, &"Owned configuration turn #{&1} 163 λ")
  @followup "Owned raw configuration history continuation 163 λ"
  @answers Enum.map(1..5, &"Owned ordinary configuration answer #{&1} 163 λ")
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    @methods ["thread/start", "thread/resume", "thread/settings/update", "turn/start"]

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
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 1_048_576 do
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

    assert hash(binary) == @binary_sha
    assert hash(@script) == @script_sha
    assert hash(@original_script) == @original_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-config-update-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
    on_exit(fn -> close_provider(fixture) end)
    capture = start_supervised!({Agent, fn -> [] end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture}

    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" =>
        Enum.map(
          ["low", "medium", "high"],
          &%{"effort" => &1, "description" => "Synthetic #{&1}"}
        ),
      "supports_reasoning_effort_updates" => true,
      "use_responses_lite" => false
    })

    paths = [
      @script,
      @original_script,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "turn-models.json")
    ]

    Map.put(ctx, :unchanged, Enum.map(paths, &{&1, File.read!(&1)}))
  end

  test "native controls append only on selected changes and raw cold input keeps its own representation",
       ctx do
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

    runs =
      for index <- 1..4 do
        if index in [2, 4] do
          effort = if index == 2, do: "high", else: "low"

          assert request(ctx, source, "thread/settings/update", %{
                   "threadId" => source_thread,
                   "effort" => effort
                 }) === %{}

          await_settings(source, source_thread, effort, [], now() + 5_000)
          assert length(requests(ctx)) == index - 1
        end

        marker = Enum.at(@markers, index - 1)
        began = System.system_time(:microsecond) / 1_000_000

        turn =
          request(ctx, source, "turn/start", %{
            "threadId" => source_thread,
            "input" => text(marker)
          })["turn"]["id"]

        assert is_binary(turn) and turn != ""
        events = collect(source, source_thread, turn, [], now() + 20_000)
        ended = System.system_time(:microsecond) / 1_000_000
        assert_completed(events, source_thread, turn)
        assert_answer(events, source_thread, turn, Enum.at(@answers, index - 1))
        assert_no_dispatch(ctx, source, events)

        expected =
          if index == 3,
            do: [],
            else: [control(Enum.at(["medium", "high", "high", "low"], index - 1))]

        assert_raw_controls(events, source_thread, turn, expected)
        assert length(requests(ctx)) == index
        %{turn: turn, marker: marker, began: began, ended: ended}
      end

    assert length(Enum.uniq(Enum.map(runs, & &1.turn))) == 4
    source_path = read_thread(source, source_thread)["path"]
    assert :ok = Session.close(source)
    assert_gone(source_native)
    {source_bytes, source_rows} = rollout(ctx, source_path)
    history = capture_history(source_rows, runs)
    source_requests = requests(ctx)
    assert length(source_requests) == 4
    assert_source_requests(source_requests)
    assert byte_size(JSON.encode!(history)) <= 1_048_576

    # Only actual raw native payloads cross this API; no envelope or sidecar is supplied.
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

    assert imported["preview"] == hd(@markers)
    assert imported["status"] === %{"type" => "idle"}
    imported_path = read_thread(cold, imported_thread)["path"]
    refute imported_path == source_path
    assert_import(ctx, imported_path, history, false)
    assert {:ok, import_events} = Session.drain(cold, 256)
    assert_event_bounds(import_events)
    assert_no_dispatch(ctx, cold, import_events)
    refute Enum.any?(import_events, &(&1.wire["method"] == "turn/started"))
    assert requests(ctx) === source_requests
    assert_retained(ctx, source_path, source_bytes)

    followup_turn =
      request(ctx, cold, "turn/start", %{
        "threadId" => imported_thread,
        "input" => text(@followup)
      })["turn"]["id"]

    assert is_binary(followup_turn) and followup_turn not in Enum.map(runs, & &1.turn)
    followup = collect(cold, imported_thread, followup_turn, [], now() + 20_000)
    assert_completed(followup, imported_thread, followup_turn)
    assert_answer(followup, imported_thread, followup_turn, List.last(@answers))
    assert_no_dispatch(ctx, cold, followup)
    assert [consumed] = requests(ctx) -- source_requests
    assert requests(ctx) === source_requests ++ [consumed]
    assert_cold_request(consumed)
    assert_import(ctx, imported_path, history, followup_turn)
    assert_retained(ctx, source_path, source_bytes)
    assert :ok = Session.close(cold)
    assert_gone(cold_native)
    assert_import(ctx, imported_path, history, followup_turn)
    assert requests(ctx) === source_requests ++ [consumed]
    assert length(Agent.get(ctx.capture, & &1)) == 9
    assert_retained(ctx, source_path, source_bytes)
  end

  defp capture_history(rows, runs) do
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    controls = Enum.filter(rows, &(get_in(&1, ["payload", "type"]) == "configuration_update"))
    assert Enum.map(controls, & &1["payload"]) === Enum.map(["medium", "high", "low"], &control/1)

    for row <- controls do
      refute Map.has_key?(row, "ordinal")
      assert_control_row(row, row["payload"], :native)
    end

    expected =
      for {run, index} <- Enum.with_index(runs, 1), reduce: [] do
        acc ->
          assert [user] = Enum.filter(payloads, &user_marker?(&1, run.marker))
          assert_user(user, run)

          assert [assistant] =
                   Enum.filter(payloads, &(&1["id"] == "owned-config-answer-#{index}"))

          assert assistant === %{
                   "type" => "message",
                   "id" => "owned-config-answer-#{index}",
                   "role" => "assistant",
                   "content" => [
                     %{"type" => "output_text", "text" => Enum.at(@answers, index - 1)}
                   ],
                   @metadata => %{"turn_id" => run.turn, "content_item_kinds" => ["unknown"]}
                 }

          update =
            if index == 3,
              do: [],
              else: [control(Enum.at(["medium", "high", "high", "low"], index - 1))]

          acc ++ [user] ++ update ++ [assistant]
      end

    selected =
      Enum.filter(payloads, fn item ->
        item["type"] == "configuration_update" or
          Enum.any?(@markers, &user_marker?(item, &1)) or
          item["id"] in Enum.map(1..4, &"owned-config-answer-#{&1}")
      end)

    assert selected === expected
    assert length(selected) == 11
    ids = Enum.map(Enum.filter(selected, &(&1["type"] != "configuration_update")), & &1["id"])
    assert length(Enum.uniq(ids)) == 8

    refute Enum.any?(rows, &(&1["type"] == "compacted"))
    selected
  end

  defp assert_user(user, run) do
    id = Map.fetch!(user, "id")
    created = get_in(user, [@metadata, "create_time"])
    assert is_binary(id) and id != ""
    assert is_number(created) and created >= run.began and created <= run.ended

    assert user === %{
             "type" => "message",
             "id" => id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => run.marker}],
             @metadata => %{
               "turn_id" => run.turn,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }
  end

  defp assert_import(ctx, path, history, followup_turn) do
    {_bytes, rows} = rollout(ctx, path)
    payloads = for %{"type" => "response_item", "payload" => item} <- rows, do: item
    assert Enum.take(payloads, length(history)) === history
    controls = Enum.filter(rows, &(get_in(&1, ["payload", "type"]) == "configuration_update"))
    imported = Enum.take(controls, 3)
    assert Enum.map(imported, & &1["payload"]) === Enum.map(["medium", "high", "low"], &control/1)
    for row <- imported, do: assert_control_row(row, row["payload"], :imported)

    if followup_turn do
      assert [fresh] = Enum.drop(controls, 3)
      assert_control_row(fresh, control("medium"), :native)
      assert [user] = Enum.filter(payloads, &user_marker?(&1, @followup))
      assert get_in(user, [@metadata, "turn_id"]) == followup_turn
      assert [user, update, assistant] = Enum.drop(payloads, length(history)) |> Enum.take(-3)
      assert user_marker?(user, @followup)
      assert update === control("medium")
      assert assistant["id"] == "owned-config-answer-5"
      assert get_in(assistant, [@metadata, "turn_id"]) == followup_turn
    else
      assert controls === imported
      assert payloads === history
    end

    refute Enum.any?(rows, &(&1["type"] == "compacted"))
  end

  defp assert_control_row(row, payload, annotation) do
    timestamp = Map.fetch!(row, "timestamp")
    assert {:ok, _time, 0} = DateTime.from_iso8601(timestamp)
    expected = %{"timestamp" => timestamp, "type" => "response_item", "payload" => payload}

    expected =
      if Map.has_key?(row, "ordinal") do
        ordinal = Map.fetch!(row, "ordinal")
        assert is_integer(ordinal) and ordinal >= 0
        Map.put(expected, "ordinal", ordinal)
      else
        expected
      end

    expected =
      if annotation == :native do
        Map.put(expected, "metadata", %{
          "client_authored" => false,
          "harness_authored_configuration" => true
        })
      else
        expected
      end

    assert row === expected
  end

  defp assert_source_requests(requests) do
    expected = [["medium"], ["medium", "high"], ["medium", "high"], ["medium", "high", "low"]]

    for {request, efforts} <- Enum.zip(requests, expected) do
      assert request["model"] == "mock-model"
      assert get_in(request, ["reasoning", "effort"]) == "medium"

      assert Enum.filter(request["input"], &(&1["type"] == "configuration_update")) ===
               Enum.map(efforts, &control/1)
    end

    assert [key] = requests |> Enum.map(&Map.fetch!(&1, "prompt_cache_key")) |> Enum.uniq()
    assert is_binary(key) and key != ""
  end

  defp assert_cold_request(request) do
    assert request["model"] == "mock-model"
    assert get_in(request, ["reasoning", "effort"]) == "medium"

    assert Enum.filter(request["input"], &(&1["type"] == "configuration_update")) === [
             control("medium")
           ]

    for marker <- @markers ++ [@followup] do
      assert Enum.count(request["input"], &user_marker?(&1, marker)) == 1
    end
  end

  defp assert_raw_controls(events, thread, turn, controls) do
    selected =
      for event <- events,
          event.wire["method"] == "rawResponseItem/completed",
          get_in(event.wire, ["params", "item", "type"]) == "configuration_update",
          do: event.wire["params"]

    assert selected ===
             Enum.map(controls, &%{"threadId" => thread, "turnId" => turn, "item" => &1})
  end

  defp await_settings(pid, thread, effort, events, until) do
    events = drain(pid, events)

    if notification(events, "thread/settings/updated", fn params ->
         params["threadId"] == thread and params["threadSettings"]["effort"] == effort
       end) do
      :ok
    else
      wait(pid, until, "Native configuration settings deadline")
      await_settings(pid, thread, effort, events, until)
    end
  end

  defp collect(pid, thread, turn, events, until) do
    events = drain(pid, events)

    if terminal(events, thread, turn) do
      events
    else
      wait(pid, until, "Native configuration turn deadline")
      collect(pid, thread, turn, events, until)
    end
  end

  defp terminal(events, thread, turn),
    do:
      notification(
        events,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
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

    assert [%{"type" => "agentMessage", "text" => ^answer}] = selected
  end

  defp assert_no_dispatch(ctx, pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Enum.filter(events, &(&1.kind == :server_request)) === []
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_event_bounds(events)
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    events
  end

  defp assert_event_bounds(events) do
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
  end

  defp wait(pid, until, message) do
    assert now() < until, message

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native configuration gap")
    after
      max(until - now(), 0) -> flunk(message)
    end
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-config-#{System.unique_integer([:positive, :monotonic])}"

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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "owned_configuration_values", "version" => "0.1.0"},
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
      assert remaining > 0, "Owned configuration native #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp read_thread(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp control(effort),
    do: %{"type" => "configuration_update", "reasoning" => %{"effort" => effort}}

  defp user_marker?(item, marker),
    do:
      item["role"] == "user" and item["content"] === [%{"type" => "input_text", "text" => marker}]

  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]
  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
