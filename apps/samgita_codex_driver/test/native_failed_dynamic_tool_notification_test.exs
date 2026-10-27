defmodule SamgitaCodexDriver.NativeFailedDynamicToolNotificationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, configure_model: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @input "Owned live failed dynamic-tool item λ🙂"
  @output "Owned synthetic lookup failure: missing record β🙂\nPreserve this result."
  @content [%{"type" => "inputText", "text" => @output}]
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
    def send(state, encoded), do: Stdio.send(state, encoded)

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &capture_item(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    # Preserve selected native JSONL before Session decoding or projection.
    defp capture_item({:message, encoded}, :ok, capture) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ["item/started", "item/completed"] and
           get_in(wire, ["params", "item", "type"]) == "dynamicToolCall" do
        case Agent.get_and_update(capture, &append(&1, encoded, wire)) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      else
        {:cont, :ok}
      end
    end

    defp capture_item(_event, :ok, _capture), do: {:cont, :ok}

    defp append(ledger, encoded, wire) do
      size = byte_size(encoded)

      if ledger.count < 128 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
        record = %{encoded: encoded, wire: wire, ordinal: ledger.count + 1}

        {:ok,
         %{
           count: ledger.count + 1,
           bytes: ledger.bytes + size,
           records: [record | ledger.records]
         }}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

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
    assert hash(File.read!(@script)) == @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-failed-dynamic-item-#{System.unique_integer([:positive, :monotonic])}"
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

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    File.write!(fixture.requests, "[]")
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture}
    configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")
    Map.merge(ctx, %{config: config, config_bytes: File.read!(config)})
  end

  test "native failed tool notification preserves the result and completes the overall turn",
       ctx do
    {pid, connection} = start_native(ctx)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha

    thread =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "dynamicTools" => [@lookup]
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    assert ModelFixture.requests(ctx.fixture) == []
    generation = Session.status(pid).generation
    native_lower = System.system_time(:millisecond)
    began_at = System.monotonic_time(:millisecond)

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    {tool, events} = await_tool(pid, [], began_at + 15_000)
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert tool.wire["method"] == "item/tool/call"
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok, %{"success" => false, "contentItems" => @content}}
             )

    events = await_turn(pid, turn, events, System.monotonic_time(:millisecond) + 20_000)
    elapsed = System.monotonic_time(:millisecond) - began_at
    native_upper = System.system_time(:millisecond)
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    started = item_event(events, "item/started", "dynamicToolCall")
    completed = item_event(events, "item/completed", "dynamicToolCall")
    start_time = Map.fetch!(started.wire["params"], "startedAtMs")
    completion_time = Map.fetch!(completed.wire["params"], "completedAtMs")
    duration = Map.fetch!(completed.wire["params"]["item"], "durationMs")
    assert is_integer(start_time) and start_time > 0
    assert is_integer(completion_time) and completion_time >= start_time
    assert is_integer(duration) and duration >= 0 and duration <= elapsed
    assert native_lower <= start_time and completion_time <= native_upper

    expected = %{
      "type" => "dynamicToolCall",
      "id" => "fixture-call-1",
      "namespace" => nil,
      "tool" => "fixture_lookup",
      "arguments" => %{"key" => "synthetic"},
      "status" => "failed",
      "contentItems" => @content,
      "success" => false,
      "durationMs" => duration
    }

    assert completed.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completion_time
           }

    assert started.wire["params"] == %{
             "threadId" => thread,
             "turnId" => turn,
             "item" =>
               Map.merge(expected, %{
                 "status" => "inProgress",
                 "contentItems" => nil,
                 "success" => nil,
                 "durationMs" => nil
               }),
             "startedAtMs" => start_time
           }

    expected_started =
      Map.merge(expected, %{
        "status" => "inProgress",
        "contentItems" => nil,
        "success" => nil,
        "durationMs" => nil
      })

    originals =
      assert_original_items(
        ctx,
        [
          {started, "item/started",
           %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => expected_started,
             "startedAtMs" => start_time
           }},
          {completed, "item/completed",
           %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completion_time
           }}
        ],
        %{generation: generation, lower: native_lower, upper: native_upper}
      )

    # Validate the actual native envelope against its root export, not a
    # fabricated item or a sibling persisted-history response contract.
    schema =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/stable/ServerNotification.json")
      |> File.read!()
      |> JSON.decode!()

    assert completed.kind == :notification
    assert :ok = Schema.validate(schema, completed.wire, max_depth: 32)
    assert {:ok, encoded} = Wire.encode(completed.wire, max_depth: 32)
    assert {:ok, preserved} = Wire.decode(encoded, max_depth: 32)
    assert preserved === completed.wire
    assert started.sequence < completed.sequence

    assistant = item_event(events, "item/completed", "agentMessage").wire["params"]
    assert assistant["threadId"] == thread and assistant["turnId"] == turn
    assert assistant["item"]["text"] == @answer
    assert is_binary(assistant["item"]["id"])

    assert [finished] = Enum.filter(events, &(&1.wire["method"] == "turn/completed"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             finished.wire["params"]

    assert completed.sequence < finished.sequence
    assert [first, continued] = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"
    assert Enum.filter(first["input"], &(&1["type"] == "function_call_output")) == []

    assert [output] =
             Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

    assert output["call_id"] == "fixture-call-1"
    assert output["output"] == @output

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === generation
    assert File.ls!(ctx.fixture.workspace) == []
    assert File.read!(ctx.config) == ctx.config_bytes
    assert hash(File.read!(@script)) == @script_sha
    assert captured_items(ctx) === originals
    assert :ok = StdioSessionFixture.close(pid, connection)
    refute File.exists?("/proc/#{native}")
    assert captured_items(ctx) === originals
    assert ModelFixture.requests(ctx.fixture) == [first, continued]
  end

  defp assert_original_items(ctx, prescribed, %{
         generation: generation,
         lower: lower,
         upper: upper
       }) do
    originals = captured_items(ctx)
    assert length(originals) === 2
    assert Enum.map(originals, & &1.ordinal) === [1, 2]

    assert Enum.map(originals, & &1.wire) ===
             Enum.map(prescribed, fn {event, _, _} -> event.wire end)

    canonical = notification_schema()

    for {original, {event, method, params}} <- Enum.zip(originals, prescribed) do
      emitted = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted) and lower <= emitted and emitted <= upper
      assert event.kind === :notification and event.generation === generation
      expected = %{"method" => method, "params" => params, "emittedAtMs" => emitted}
      assert event.wire === expected
      assert original.wire === expected
      assert JSON.decode!(original.encoded) === expected
      assert {:ok, preserved} = Wire.decode(original.encoded, max_depth: 32)
      assert preserved === expected
      assert :ok = Schema.validate(canonical, original.wire, max_depth: 32)
    end

    originals
  end

  defp captured_items(ctx), do: Agent.get(ctx.capture, &Enum.reverse(&1.records))

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp await_tool(pid, events, deadline) do
    events = collect(pid, events)
    refute Enum.any?(events, &(&1.wire["method"] == "turn/completed"))

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] ->
        {tool, events}

      [] ->
        wait_events(pid, deadline)
        await_tool(pid, events, deadline)

      _ ->
        flunk("Additional native tool interaction")
    end
  end

  defp await_turn(pid, turn, events, deadline) do
    events = collect(pid, events)

    if Enum.any?(events, fn event ->
         event.wire["method"] == "turn/completed" and
           get_in(event.wire, ["params", "turn", "id"]) == turn
       end) do
      events
    else
      wait_events(pid, deadline)
      await_turn(pid, turn, events, deadline)
    end
  end

  defp collect(pid, events) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert length(Enum.uniq_by(events, & &1.wire["method"])) <= 32
    assert Enum.all?(events, &(&1.generation == generation))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.sort(Enum.uniq(sequences))
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))

    assert Enum.all?(events, fn event ->
             event.kind == :notification or
               (event.kind == :server_request and event.wire["method"] == "item/tool/call")
           end)

    assert Enum.count(events, &(&1.kind == :server_request)) <= 1
    events
  end

  defp wait_events(pid, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Native failed dynamic-tool event deadline"

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native event gap")
    after
      remaining -> flunk("Native failed dynamic-tool event deadline")
    end
  end

  defp item_event(events, method, type) do
    assert [event] =
             Enum.filter(events, fn event ->
               event.wire["method"] == method and
                 get_in(event.wire, ["params", "item", "type"]) == type
             end)

    event
  end

  defp start_native(ctx) do
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
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    connection = :sys.get_state(pid).connection

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(connection.owner.completion, 1) == 1
      assert Port.info(connection.port) == nil
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_failed_dynamic_item", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "optOutNotificationMethods" => ["remoteControl/status/changed"]
               }
             )

    {pid, connection}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
