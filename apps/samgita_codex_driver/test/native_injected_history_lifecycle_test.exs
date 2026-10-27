defmodule SamgitaCodexDriver.NativeInjectedHistoryLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [configure_model: 2]

  @moduletag :real_codex
  @moduletag timeout: 30_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @metadata "internal_chat_message_metadata_passthrough"
  @source_turn "owned-injection-source-turn-v508"
  @items [
    %{
      "type" => "message",
      "id" => "msg_v508_first_λ",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => "First durable injected context λ🙂"}],
      @metadata => %{"turn_id" => @source_turn}
    },
    %{
      "type" => "message",
      "id" => "msg_v508_second_雪",
      "role" => "assistant",
      "content" => [
        %{"type" => "output_text", "text" => "Second durable injected context 雪🙂\nKeep order."}
      ],
      @metadata => %{"turn_id" => @source_turn}
    }
  ]
  # Native text preparation annotates each unclassified content element while
  # preserving the supplied turn ID. Keep this separate from the request oracle.
  @durable_items Enum.map(@items, &put_in(&1, [@metadata, "content_item_kinds"], ["unknown"]))
  @input "Continue from both durable injected contexts β🙂"
  @answer "Deterministic local fixture answer"
  @inject_id "owned-idle-injection-v508-λ🙂"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, connection} <- Stdio.open(Keyword.delete(opts, :capture)) do
        index =
          Agent.get_and_update(capture, fn ledger ->
            index = length(ledger.connections) + 1
            {index, %{ledger | connections: ledger.connections ++ [connection]}}
          end)

        {:ok, Map.merge(connection, %{capture: capture, index: index})}
      end
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
          case Enum.reduce_while(events, :ok, &capture_event(&1, &2, next)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp capture_event({:message, encoded}, :ok, state) do
      case record(state, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp capture_event(_event, :ok, _state), do: {:cont, :ok}

    # Keep original bytes before the Session decodes or projects native messages.
    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 4096, else: 65_536

        if ledger.count < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
          entry = %{direction: direction, encoded: encoded, connection: state.index}

          {:ok,
           %{
             ledger
             | count: ledger.count + 1,
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

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-idle-injection-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
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

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) === 1
      assert Port.info(fixture.port) === nil
    end)

    File.write!(fixture.requests, "[]")

    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: [], connections: []} end})

    ctx = %{binary: Path.expand(binary), root: root, fixture: fixture, capture: capture}
    configure_model(ctx, %{})

    frozen =
      Map.new(
        [
          Path.join(fixture.codex_home, "config.toml"),
          Path.join(fixture.codex_home, "turn-models.json"),
          @script,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex")
        ],
        &{&1, File.read!(&1)}
      )

    Map.put(ctx, :frozen, frozen)
  end

  test "idle injection persists before its ACK and survives an actual cold continuation", ctx do
    warm = start_native(ctx, 1)

    created =
      call(ctx, warm, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false
      })["thread"]

    thread = Map.fetch!(created, "id")
    assert is_binary(thread) and byte_size(thread) > 0
    path = Map.fetch!(created, "path")
    assert is_binary(path) and String.starts_with?(path, ctx.fixture.codex_home <> "/")
    assert ModelFixture.requests(ctx.fixture) === []
    assert_idle(warm.pid)

    params = %{"threadId" => thread, "items" => @items}
    wire = %{"id" => @inject_id, "method" => "thread/inject_items", "params" => params}
    result = call(ctx, warm, wire["method"], params, @inject_id)
    assert result === %{}
    assert_injection_contract(wire, result)

    # This idle API awaits its checkpoint. Inspect actual disk bytes immediately
    # after the ACK, before requesting another turn or closing the native process.
    original = assert_durable_items(path)
    warm_events = drain(warm, [])
    assert_no_turn(warm_events)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_idle(warm.pid)
    assert_inputs(ctx)

    close_native(warm)
    assert ModelFixture.requests(ctx.fixture) === []
    assert assert_durable_items(path) === original
    prefix = captured(ctx)

    cold = start_native(ctx, 2)
    refute cold.pid === warm.pid
    refute cold.native === warm.native

    assert call(ctx, cold, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    resumed = call(ctx, cold, "thread/resume", %{"threadId" => thread})["thread"]
    assert resumed["id"] === thread and resumed["path"] === path
    assert ModelFixture.requests(ctx.fixture) === []
    assert assert_durable_items(path) === original
    cold_events = drain(cold, [])
    assert_no_turn(cold_events)
    assert_idle(cold.pid)

    turn =
      call(ctx, cold, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = await_turn(cold, turn, cold_events, now() + 5000)
    assert_completed_turn(events, thread, turn)
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert_provider_input(request)
    assert assert_durable_items(path) === original
    assert_idle(cold.pid)
    assert_inputs(ctx)
    close_native(cold)

    assert ModelFixture.requests(ctx.fixture) === [request]
    assert assert_durable_items(path) === original
    assert Enum.take(captured(ctx), length(prefix)) === prefix
    assert_capture(ctx)
    assert_inputs(ctx)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp start_native(ctx, index) do
    assert {:ok, pid} =
             Session.start_link(
               request_timeout_ms: 5000,
               max_events: 128,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    connections = Agent.get(ctx.capture, & &1.connections)
    assert length(connections) === index
    connection = Enum.at(connections, index - 1)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_native(%{pid: pid, connection: connection, identity: identity}) end)

    id = "owned-injection-initialize-#{index}"
    info = %{"name" => "owned_idle_injected_history", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5000)

    session = %{pid: pid, connection: connection, identity: identity, index: index}

    assert_exchange(
      ctx,
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = call(ctx, session, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    Map.merge(session, %{native: native, generation: Session.status(pid).generation})
  end

  defp call(ctx, session, method, params, id \\ nil) do
    id = id || "owned-injection-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request(session.pid, method, params, id: id, timeout_ms: 5000)

    assert_exchange(ctx, session, %{"id" => id, "method" => method, "params" => params}, response)
    result
  end

  defp assert_exchange(ctx, session, wire, response) do
    entries = Enum.filter(captured(ctx), &(&1.connection === session.index))

    assert [sent] =
             Enum.filter(entries, &(&1.direction === :out and &1.wire["id"] === wire["id"]))

    assert [received] =
             Enum.filter(entries, &(&1.direction === :in and &1.wire["id"] === wire["id"]))

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
    assert :ok = Schema.validate(protocol_schema("ClientRequest.json"), wire, max_depth: 32)
    assert :ok = Schema.validate(protocol_schema("JSONRPCResponse.json"), response, max_depth: 32)
  end

  defp assert_injection_contract(wire, result) do
    schema = protocol_schema("ClientRequest.json")

    assert Enum.at(schema["oneOf"], 65) === %{
             "description" =>
               "Append raw Responses API items to the thread history without starting a user turn.",
             "properties" => %{
               "id" => %{"$ref" => "#/definitions/RequestId"},
               "method" => %{
                 "enum" => ["thread/inject_items"],
                 "title" => "Thread/injectItemsRequestMethod",
                 "type" => "string"
               },
               "params" => %{"$ref" => "#/definitions/ThreadInjectItemsParams"}
             },
             "required" => ["id", "method", "params"],
             "title" => "Thread/injectItemsRequest",
             "type" => "object"
           }

    assert :ok = Schema.validate(schema, wire, max_depth: 32)
    assert :ok = Schema.validate(protocol_schema("v2/ThreadInjectItemsResponse.json"), result)
    assert {:ok, encoded} = Wire.encode(wire, max_depth: 32)
    assert {:ok, preserved} = Wire.decode(encoded, max_depth: 32)
    assert preserved === wire
  end

  defp assert_durable_items(path) do
    assert File.stat!(path).size <= 1_048_576

    rows =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert length(rows) <= 128
    ids = Enum.map(@items, & &1["id"])

    selected =
      Enum.filter(rows, fn row ->
        row["type"] === "response_item" and get_in(row, ["payload", "id"]) in ids
      end)

    assert Enum.map(selected, & &1["payload"]) === @durable_items
    assert length(selected) === 2
    selected
  end

  defp assert_provider_input(request) do
    assert request["model"] === "mock-model"
    assert byte_size(JSON.encode!(request)) <= 1_048_576
    input = Map.fetch!(request, "input")
    assert is_list(input) and length(input) <= 128
    ids = Enum.map(@items, & &1["id"])
    expected = Enum.map(@items, &Map.delete(&1, @metadata))
    assert Enum.filter(input, &(&1["id"] in ids)) === expected

    texts = Enum.flat_map(@items, fn item -> Enum.map(item["content"], & &1["text"]) end)

    assert Enum.filter(input, fn item ->
             Enum.any?(Map.get(item, "content", []), &(&1["text"] in texts))
           end) === expected

    assert [user] =
             Enum.filter(input, fn item ->
               item["role"] === "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @input}]
             end)

    assert is_binary(user["id"]) and byte_size(user["id"]) > 0

    assert Map.delete(user, "id") === %{
             "type" => "message",
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => @input}]
           }

    first = Enum.find_index(input, &(&1["id"] === hd(ids)))
    second = Enum.find_index(input, &(&1["id"] === List.last(ids)))
    current = Enum.find_index(input, &(&1 === user))
    assert Enum.all?([first, second, current], &is_integer/1)
    assert first < second and second < current
  end

  defp await_turn(session, turn, events, deadline) do
    events = drain(session, events)

    if Enum.any?(events, fn event ->
         event.wire["method"] === "turn/completed" and
           get_in(event.wire, ["params", "turn", "id"]) === turn
       end) do
      events
    else
      remaining = deadline - now()
      assert remaining > 0, "Native cold injected-history turn deadline"

      receive do
        {:codex_driver, pid, :events_available} when pid === session.pid -> :ok
        {:codex_driver, pid, {:gap, _}} when pid === session.pid -> flunk("Native event gap")
      after
        remaining -> flunk("Native cold injected-history turn deadline")
      end

      await_turn(session, turn, events, deadline)
    end
  end

  defp drain(session, events) do
    assert {:ok, fresh} = Session.drain(session.pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 128
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= 1_048_576

    assert Enum.all?(
             combined,
             &(&1.generation === session.generation and &1.kind === :notification)
           )

    refute Enum.any?(combined, &(&1.wire["method"] in ["error", "warning"]))
    sequences = Enum.map(combined, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
    combined
  end

  defp assert_no_turn(events) do
    refute Enum.any?(events, &(&1.wire["method"] in ["turn/started", "turn/completed"]))
  end

  defp assert_completed_turn(events, thread, turn) do
    assert [started] = Enum.filter(events, &(&1.wire["method"] === "turn/started"))
    assert get_in(started.wire, ["params", "threadId"]) === thread
    assert get_in(started.wire, ["params", "turn", "id"]) === turn
    assert [completed] = Enum.filter(events, &(&1.wire["method"] === "turn/completed"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             completed.wire["params"]

    assert started.sequence < completed.sequence

    assert [answer] =
             Enum.filter(events, fn event ->
               event.wire["method"] === "item/completed" and
                 get_in(event.wire, ["params", "item", "type"]) === "agentMessage"
             end)

    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"text" => @answer}} =
             answer.wire["params"]

    assert started.sequence < answer.sequence and answer.sequence < completed.sequence
  end

  defp assert_capture(ctx) do
    entries = captured(ctx)
    assert length(entries) <= 128
    assert Enum.reduce(entries, 0, &(byte_size(&1.encoded) + &2)) <= 1_048_576

    for entry <- entries do
      limit = if entry.direction === :out, do: 4096, else: 65_536
      assert byte_size(entry.encoded) <= limit
      assert entry.connection in [1, 2]
      assert {:ok, decoded} = Wire.decode(entry.encoded, max_depth: 32)
      assert decoded === entry.wire
      assert {:ok, reencoded} = Wire.encode(decoded, max_depth: 32)
      assert JSON.decode!(reencoded) === entry.wire
    end

    assert length(Agent.get(ctx.capture, & &1.connections)) === 2

    for index <- [1, 2] do
      selected = Enum.filter(entries, &(&1.connection === index))
      out = Enum.filter(selected, &(&1.direction === :out))
      requests = Enum.filter(out, &Map.has_key?(&1.wire, "id"))
      responses = Enum.filter(selected, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
      assert Enum.map(requests, & &1.wire["id"]) === Enum.map(responses, & &1.wire["id"])
      assert Enum.map(out, & &1.wire["method"]) === expected_methods(index)
    end
  end

  defp expected_methods(1),
    do: ~w(initialize initialized server/diagnostics thread/start thread/inject_items)

  defp expected_methods(2),
    do: ~w(initialize initialized server/diagnostics thread/loaded/list thread/resume turn/start)

  defp captured(ctx) do
    Agent.get(ctx.capture, &Enum.reverse(&1.records))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp assert_inputs(ctx) do
    for {path, bytes} <- ctx.frozen, do: assert(File.read!(path) === bytes)
    assert hash(File.read!(@script)) === @script_sha
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp close_native(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp protocol_schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
