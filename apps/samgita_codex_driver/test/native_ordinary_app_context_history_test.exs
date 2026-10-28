defmodule SamgitaCodexDriver.NativeOrdinaryAppContextHistoryTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @script_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @call "owned-app-context-call-532"
  @input "Owned ordinary persisted Apps context λ🙂"
  @answer "Owned inventory metadata recorded λ"
  @uri "ui://owned/inventory-panel.html"
  @arguments %{"query" => "ordinary lamps λ", "link_id" => "owned-link-532"}

  # Owner2626 is the physical notification reference, separate from response5585.
  @notification_context_root_sha "8e719512bc26bb3871fcf7b378b79abf912d82787609c0ad418b71f179d0883f"
  @notification_context_node_sha "eb1116157e85c6093e153f4b64842af82e7b2bebe4c31f945228de36b1f29eb8"
  @notification_context_node_bytes """
  {
    "$ref": "#/definitions/McpToolCallAppContext"
  }
  """

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
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 128, else: 768
      message_limit = if direction == :out, do: 4096, else: 131_072
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 4_194_304 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
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
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-app-context-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-app-context")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)

    paths = [
      @script,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "models.json"),
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex"),
      schema_path("ClientRequest.json"),
      schema_path("ServerNotification.json"),
      schema_path("v2/ThreadItemsReadResponse.json")
    ]

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native Apps metadata preserves its complete selected item across first cold read and resume",
       ctx do
    warm = start(ctx)
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    thread_map =
      call(ctx, warm.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]

    thread = Map.fetch!(thread_map, "id")
    assert_id(thread)
    assert ModelFixture.requests(ctx.fixture) === []
    before_ms = System.system_time(:millisecond)
    began = System.monotonic_time(:millisecond)

    turn =
      call(ctx, warm.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert_id(turn)
    events = collect(warm.pid, thread, turn, [], began + 20_000)
    after_ms = System.system_time(:millisecond)
    elapsed = System.monotonic_time(:millisecond) - began
    refute Enum.any?(events, &(&1.kind == :server_request))

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/completed",
               do: event.wire["params"]
             )

    started = item_event(ctx, events, "item/started", thread, turn)
    completed = item_event(ctx, events, "item/completed", thread, turn)
    start_ms = Map.fetch!(started.wire["params"], "startedAtMs")
    end_ms = Map.fetch!(completed.wire["params"], "completedAtMs")
    duration = Map.fetch!(completed.wire["params"]["item"], "durationMs")
    assert is_integer(start_ms) and is_integer(end_ms)
    assert before_ms <= start_ms and start_ms <= end_ms and end_ms <= after_ms
    assert is_integer(duration) and duration >= 0 and duration <= elapsed
    expected_item = expected_item(duration)

    assert [agent] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]["item"]
             )

    assert agent === %{
             "id" => "owned-app-context-final-532",
             "type" => "agentMessage",
             "text" => @answer,
             "phase" => nil,
             "memoryCitation" => nil,
             "delivery" => nil,
             "questions" => nil
           }

    assert completed.wire["params"] === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => expected_item,
             "completedAtMs" => end_ms
           }

    assert started.wire["params"] === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" =>
               Map.merge(expected_item, %{
                 "status" => "inProgress",
                 "result" => nil,
                 "durationMs" => nil
               }),
             "startedAtMs" => start_ms
           }

    assert started.sequence < completed.sequence

    expected = %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => expected_item,
          "startedAtMs" => start_ms,
          "completedAtMs" => end_ms
        }
      ]
    }

    assert_provider(ctx, thread, turn)
    # This native metadata read is only the durable-store barrier; it never
    # supplies the independent semantic item expected above.
    saved =
      call(ctx, warm.pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["turns"] === []
    path = Map.fetch!(saved, "path")

    assert is_binary(path) and
             String.starts_with?(Path.expand(path), ctx.fixture.codex_home <> "/")

    rollout = snapshot(path)
    assert_durable_item(rollout.bytes, expected_item, thread, turn, start_ms, end_ms)
    request_bytes = snapshot(ctx.fixture.requests)
    params = %{"threadId" => thread, "turnId" => turn, "itemIds" => [@call]}
    mixed = %{params | "itemIds" => ["owned-absent-app-context", @call, @call]}
    assert selection(ctx, warm.pid, params) === expected
    assert selection(ctx, warm.pid, mixed) === expected

    assert selection(ctx, warm.pid, %{params | "itemIds" => ["owned-absent-app-context"]}) === %{
             "data" => []
           }

    assert_controls(ctx, thread, turn, request_bytes)
    assert_idle(warm.pid)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    assert snapshot(path) === rollout
    assert_controls(ctx, thread, turn, request_bytes)

    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    # First cold content operation is the actual selective read. No resume,
    # thread/read or model turn can prime this response.
    assert selection(ctx, cold.pid, mixed) === expected
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert snapshot(path) === rollout
    assert selection(ctx, cold.pid, params) === expected
    assert_controls(ctx, thread, turn, request_bytes)

    resumed =
      call(ctx, cold.pid, "thread/resume", %{"threadId" => thread, "excludeTurns" => true})

    assert resumed["thread"]["id"] === thread and resumed["thread"]["turns"] === []
    assert selection(ctx, cold.pid, mixed) === expected

    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert_controls(ctx, thread, turn, request_bytes)
    assert_idle(cold.pid)
    close(cold)
    resumed_rollout = snapshot(path)
    assert byte_size(resumed_rollout.bytes) >= byte_size(rollout.bytes)
    assert binary_part(resumed_rollout.bytes, 0, byte_size(rollout.bytes)) === rollout.bytes
    assert_durable_item(resumed_rollout.bytes, expected_item, thread, turn, start_ms, end_ms)
    assert_controls(ctx, thread, turn, request_bytes)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    close_provider(ctx)
    assert_controls(ctx, thread, turn, request_bytes)
  end

  defp expected_item(duration),
    do: %{
      "id" => @call,
      "type" => "mcpToolCall",
      "server" => "codex_apps",
      "tool" => "owned_inventory_lookup",
      "arguments" => @arguments,
      "status" => "completed",
      "appContext" => %{
        "connectorId" => "owned_inventory",
        "linkId" => "owned-link-532",
        "resourceUri" => @uri,
        "appName" => "owned_inventory",
        "actionName" => "owned_inventory_lookup"
      },
      "mcpAppResourceUri" => @uri,
      "mcpAppUi" => nil,
      "pluginId" => nil,
      "readOnlyHint" => true,
      "error" => nil,
      "durationMs" => duration,
      "result" => %{
        "_meta" => nil,
        "content" => [%{"type" => "text", "text" => "Owned inventory result β🙂"}],
        "structuredContent" => %{"items" => ["lamp-532"], "source" => "owned_inventory"}
      }
    }

  defp selection(ctx, pid, params) do
    result = call(ctx, pid, "thread/items/read", params)
    assert :ok = Schema.validate(schema("v2/ThreadItemsReadResponse.json"), result, max_depth: 64)
    result
  end

  defp item_event(ctx, events, method, thread, turn) do
    assert [event] =
             Enum.filter(
               events,
               &(&1.wire["method"] == method and
                   &1.wire["params"]["threadId"] == thread and &1.wire["params"]["turnId"] == turn and
                   &1.wire["params"]["item"]["id"] == @call)
             )

    assert [original] = Enum.filter(Agent.get(ctx.capture, & &1.in), &(&1.wire === event.wire))
    assert JSON.decode!(original.encoded) === event.wire
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 64)
    assert decoded === event.wire
    assert :ok = Schema.validate(schema("ServerNotification.json"), decoded, max_depth: 64)
    assert_notification_context_binding(decoded)
    event
  end

  defp assert_notification_context_binding(original) do
    bytes =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/stable/ServerNotification.json")
      |> File.read!()

    assert hash(bytes) === @notification_context_root_sha
    document = JSON.decode!(bytes)

    node =
      document
      |> Map.fetch!("definitions")
      |> Map.fetch!("ThreadItem")
      |> Map.fetch!("oneOf")
      |> Enum.fetch!(8)
      |> Map.fetch!("properties")
      |> Map.fetch!("appContext")
      |> Map.fetch!("anyOf")
      |> Enum.fetch!(0)

    assert hash(@notification_context_node_bytes) === @notification_context_node_sha
    assert JSON.decode!(@notification_context_node_bytes) === node

    actual =
      original
      |> Map.fetch!("params")
      |> Map.fetch!("item")
      |> Map.fetch!("appContext")

    # Complete literal context equality and independent MCP/provider oracles
    # remain in the owning test; this selects their original notification value.
    assert is_map(actual)

    assert :ok =
             Schema.validate(
               Map.put(node, "definitions", Map.fetch!(document, "definitions")),
               actual,
               max_depth: 64
             )
  end

  defp assert_durable_item(bytes, expected_item, thread, turn, start_ms, end_ms) do
    rows = String.split(bytes, "\n", trim: true)
    assert length(rows) <= 128
    rows = Enum.map(rows, &JSON.decode!/1)

    assert [event] =
             for(
               row <- rows,
               row["type"] == "event_msg",
               row["payload"]["type"] == "item_completed",
               row["payload"]["item"]["id"] == @call,
               do: row["payload"]
             )

    item = event["item"]
    # Core serializes the tagged item flat with camelCase metadata. Only its
    # generated sub-millisecond duration is read, bounded, and cross-checked
    # against the independently prescribed public item duration above.
    assert %{"secs" => seconds, "nanos" => nanos} = native_duration = Map.fetch!(item, "duration")
    assert is_integer(seconds) and seconds >= 0 and seconds <= 20
    assert is_integer(nanos) and nanos >= 0 and nanos < 1_000_000_000
    assert seconds * 1000 + div(nanos, 1_000_000) === expected_item["durationMs"]

    assert event === %{
             "type" => "item_completed",
             "thread_id" => thread,
             "turn_id" => turn,
             "started_at_ms" => start_ms,
             "completed_at_ms" => end_ms,
             "item" => %{
               "type" => "McpToolCall",
               "id" => @call,
               "server" => "codex_apps",
               "tool" => "owned_inventory_lookup",
               "arguments" => @arguments,
               "connectorId" => "owned_inventory",
               "linkId" => "owned-link-532",
               "appName" => "owned_inventory",
               "actionName" => "owned_inventory_lookup",
               "mcpAppResourceUri" => @uri,
               "readOnlyHint" => true,
               "status" => "completed",
               "duration" => native_duration,
               "result" => %{
                 "isError" => false,
                 "content" => [%{"type" => "text", "text" => "Owned inventory result β🙂"}],
                 "structuredContent" => %{"items" => ["lamp-532"], "source" => "owned_inventory"}
               }
             }
           }
  end

  defp assert_provider(ctx, thread, turn) do
    assert [first, second] = ModelFixture.requests(ctx.fixture)

    for request <- [first, second] do
      assert request["model"] === "mock-model"

      assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
               JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

      assert [@input] ===
               for(
                 item <- request["input"],
                 item["role"] == "user",
                 part <- Map.get(item, "content", []),
                 part["text"] == @input,
                 do: part["text"]
               )
    end

    assert [] === Enum.filter(first["input"], &(&1["type"] == "function_call_output"))

    assert [%{"call_id" => @call}] =
             Enum.filter(second["input"], &(&1["type"] == "function_call_output"))

    assert length(rows(ctx, "tool_call")) === 1

    assert rows(ctx, "tool_call") === [
             %{
               "event" => "tool_call",
               "call_id" => @call,
               "tool" => "owned_inventory_lookup",
               "arguments" => @arguments,
               "thread_id" => thread
             }
           ]

    assert rows(ctx, "model") === [
             %{"event" => "model", "sequence" => 1, "output_call_ids" => []},
             %{"event" => "model", "sequence" => 2, "output_call_ids" => [@call]}
           ]
  end

  defp assert_controls(ctx, thread, turn, requests) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert snapshot(ctx.fixture.requests) === requests
    assert_provider(ctx, thread, turn)
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
    assert rows(ctx, "unexpected_mcp") === []
  end

  defp rows(ctx, type) do
    path = Path.join(ctx.root, "ordinary-app-context-journal.json")
    data = snapshot(path).bytes |> JSON.decode!()
    assert length(data["events"]) <= 256
    Enum.filter(data["events"], &(&1["event"] == type))
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_app_context", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp collect(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         events,
         &(&1.wire["method"] == "turn/completed" and
             &1.wire["params"]["threadId"] == thread and &1.wire["params"]["turn"]["id"] == turn)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "Owned ordinary Apps turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary Apps event gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert {:ok, []} = Session.drain(pid, 256)
  end

  defp close(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    assert [%{"pid" => native}] = rows(ctx, "fixture_started")
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    refute File.exists?("/proc/#{native}")
    assert [%{"pid" => ^native}] = rows(ctx, "fixture_closed")
  end

  defp assert_inventory(ledger) do
    warm =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/start turn/start thread/read thread/items/read thread/items/read thread/items/read)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/items/read thread/loaded/list thread/items/read thread/resume thread/items/read thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 18 and length(Enum.uniq(ids)) === 18
    assert length(replies) === 18
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 2_097_152
    bytes = File.read!(path)
    assert byte_size(bytes) <= 2_097_152
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp assert_id(value), do: assert(is_binary(value) and byte_size(value) > 0)
  defp request_id, do: "owned-app-context-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
