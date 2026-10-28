defmodule SamgitaCodexDriver.NativeActiveInjectedHistoryLifecycleTest do
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
  # Three authored oracles: request, prepared durable history, fixture-provider input.
  @items [
    %{
      "type" => "message",
      "id" => "msg_v510_active_first_λ",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => "First queued active context λ🙂"}],
      "internal_chat_message_metadata_passthrough" => %{
        "turn_id" => "owned-active-injection-source-v510"
      }
    },
    %{
      "type" => "message",
      "id" => "msg_v510_active_second_雪",
      "role" => "assistant",
      "content" => [
        %{"type" => "output_text", "text" => "Second queued active context 雪🙂\nKeep FIFO."}
      ],
      "internal_chat_message_metadata_passthrough" => %{
        "turn_id" => "owned-active-injection-source-v510"
      }
    }
  ]
  @durable_items [
    %{
      "type" => "message",
      "id" => "msg_v510_active_first_λ",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => "First queued active context λ🙂"}],
      "internal_chat_message_metadata_passthrough" => %{
        "turn_id" => "owned-active-injection-source-v510",
        "content_item_kinds" => ["unknown"]
      }
    },
    %{
      "type" => "message",
      "id" => "msg_v510_active_second_雪",
      "role" => "assistant",
      "content" => [
        %{"type" => "output_text", "text" => "Second queued active context 雪🙂\nKeep FIFO."}
      ],
      "internal_chat_message_metadata_passthrough" => %{
        "turn_id" => "owned-active-injection-source-v510",
        "content_item_kinds" => ["unknown"]
      }
    }
  ]
  @provider_items [
    %{
      "type" => "message",
      "id" => "msg_v510_active_first_λ",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => "First queued active context λ🙂"}]
    },
    %{
      "type" => "message",
      "id" => "msg_v510_active_second_雪",
      "role" => "assistant",
      "content" => [
        %{"type" => "output_text", "text" => "Second queued active context 雪🙂\nKeep FIFO."}
      ]
    }
  ]
  @input "Hold a synthetic lookup before queued active context β🙂"
  @fresh_input "Explicit fresh turn after interrupted queued context γ🙂"
  @answer "Deterministic local fixture answer"
  @output "Synthetic lookup completed"
  @tool_result %{
    "success" => true,
    "contentItems" => [%{"type" => "inputText", "text" => "Synthetic lookup completed"}]
  }
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
        "owned-active-injection-#{System.unique_integer([:positive, :monotonic])}"
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

  test "active injections become durable FIFO context only after the held tool replies", ctx do
    held = held_turn(ctx)
    events = inject_while_held(ctx, held)

    assert :ok = Session.respond(held.session.pid, held.tool.handle, {:ok, @tool_result})

    assert [%{handle: handle, status: :sent_unconfirmed} = outcome] =
             Session.interaction_outcomes(held.session.pid)

    assert handle === held.tool.handle
    assert_tool_response(ctx, held)

    events = await_turn(held.session, held.turn, events, now() + 5000)
    assert_completed_turn(events, held.thread, held.turn)
    assert [held.tool] === Enum.filter(events, &(&1.kind === :server_request))
    assert_successful_tool(events, held)
    assert [first, continued] = ModelFixture.requests(ctx.fixture)
    assert first === held.first
    input = provider_input(continued)
    assert_selected(input, @provider_items)
    assert_fifo_after_output(input)
    original = assert_durable_items(held.path)
    assert_idle(held.session.pid)
    # Local write and terminal observation do not invent a remote response ACK.
    assert Session.interaction_outcomes(held.session.pid) === [outcome]
    assert_inputs(ctx)
    close_native(held.session)

    assert ModelFixture.requests(ctx.fixture) === [first, continued]
    assert assert_durable_items(held.path) === original
    assert_capture(ctx, :continued)
    assert_inputs(ctx)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  test "interrupt discards active queued items across confirmed shutdown and cold resume", ctx do
    held = held_turn(ctx)
    events = inject_while_held(ctx, held)
    original_rows = original_history_rows(held.path)

    assert call(
             ctx,
             held.session,
             "turn/interrupt",
             %{
               "threadId" => held.thread,
               "turnId" => held.turn
             },
             "owned-active-interrupt-v510"
           ) === %{}

    events = await_turn(held.session, held.turn, events, now() + 5000)
    assert_interrupted_turn(events, held.thread, held.turn)
    assert [held.tool] === Enum.filter(events, &(&1.kind === :server_request))
    assert ModelFixture.requests(ctx.fixture) === [held.first]
    assert_absent(durable_payloads(held.path))
    assert original_history_rows(held.path) === original_rows
    assert_idle(held.session.pid)
    assert Session.interaction_outcomes(held.session.pid) === []
    close_native(held.session)
    assert_absent(durable_payloads(held.path))
    assert original_history_rows(held.path) === original_rows
    prefix = captured(ctx)

    cold = start_native(ctx, 2)
    refute cold.pid === held.session.pid
    refute cold.native === held.session.native
    assert call(ctx, cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    resumed = call(ctx, cold, "thread/resume", %{"threadId" => held.thread})["thread"]
    assert resumed["id"] === held.thread and resumed["path"] === held.path
    assert ModelFixture.requests(ctx.fixture) === [held.first]
    assert_absent(durable_payloads(held.path))
    assert original_history_rows(held.path) === original_rows
    cold_events = drain(cold, [])
    assert_no_turn(cold_events)
    assert_idle(cold.pid)

    turn =
      call(ctx, cold, "turn/start", %{
        "threadId" => held.thread,
        "input" => [%{"type" => "text", "text" => @fresh_input}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0 and turn !== held.turn
    cold_events = await_turn(cold, turn, cold_events, now() + 5000)
    assert_completed_turn(cold_events, held.thread, turn)
    assert Enum.filter(cold_events, &(&1.kind === :server_request)) === []
    assert [first, fresh] = ModelFixture.requests(ctx.fixture)
    assert first === held.first
    input = provider_input(fresh)
    assert_absent(input)
    {original_user, original_call} = assert_original_items(input)

    assert [original_user, original_call] ===
             Enum.map(original_rows, fn row ->
               Map.delete(row["payload"], "internal_chat_message_metadata_passthrough")
             end)

    assert [user] =
             Enum.filter(
               input,
               &(&1["role"] === "user" and
                   &1["content"] === [%{"type" => "input_text", "text" => @fresh_input}])
             )

    assert is_binary(user["id"]) and byte_size(user["id"]) > 0
    assert_absent(durable_payloads(held.path))
    assert original_history_rows(held.path) === original_rows
    assert_idle(cold.pid)
    assert Session.interaction_outcomes(cold.pid) === []
    assert_inputs(ctx)
    close_native(cold)

    assert ModelFixture.requests(ctx.fixture) === [first, fresh]
    assert_absent(durable_payloads(held.path))
    assert original_history_rows(held.path) === original_rows
    assert Enum.take(captured(ctx), length(prefix)) === prefix
    assert_capture(ctx, :interrupted)
    assert_inputs(ctx)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp held_turn(ctx) do
    session = start_native(ctx, 1)

    created =
      call(ctx, session, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "dynamicTools" => [@lookup]
      })["thread"]

    thread = Map.fetch!(created, "id")
    path = Map.fetch!(created, "path")
    assert is_binary(thread) and byte_size(thread) > 0
    assert is_binary(path) and String.starts_with?(path, ctx.fixture.codex_home <> "/")
    assert ModelFixture.requests(ctx.fixture) === []

    turn =
      call(ctx, session, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0

    events =
      await_events(session, [], now() + 5000, fn events ->
        Enum.any?(events, &(&1.kind === :server_request))
      end)

    assert [tool] = Enum.filter(events, &(&1.kind === :server_request))
    assert tool.wire["method"] === "item/tool/call"
    assert is_integer(tool.wire["id"])
    assert tool.handle.id === tool.wire["id"]
    assert tool.handle.generation === session.generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] === %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert :ok = Schema.validate(protocol_schema("ServerRequest.json"), tool.wire, max_depth: 32)

    assert :ok =
             Schema.validate(protocol_schema("DynamicToolCallParams.json"), tool.wire["params"])

    assert [original] =
             Enum.filter(captured(ctx), fn entry ->
               entry.connection === session.index and entry.direction === :in and
                 entry.wire["method"] === "item/tool/call"
             end)

    assert original.wire === tool.wire
    assert JSON.decode!(original.encoded) === tool.wire
    assert tool.wire["id"] >= 0

    assert original.wire === %{
             "id" => tool.handle.id,
             "method" => "item/tool/call",
             "params" => tool.wire["params"]
           }

    envelope_schema = protocol_schema("ServerRequest.json")

    dynamic_envelope =
      envelope_schema["oneOf"]
      |> Enum.at(5)
      |> Map.put("definitions", envelope_schema["definitions"])

    assert :ok = Schema.validate(dynamic_envelope, original.wire, max_depth: 32)

    assert [first] = ModelFixture.requests(ctx.fixture)
    assert_absent(provider_input(first))
    assert_absent(durable_payloads(path))

    %{
      session: session,
      thread: thread,
      turn: turn,
      path: path,
      tool: tool,
      events: events,
      first: first
    }
  end

  defp inject_while_held(ctx, held) do
    Enum.zip(@items, ["owned-active-first-v510-λ", "owned-active-second-v510-雪"])
    |> Enum.reduce(held.events, fn {item, id}, events ->
      params = %{"threadId" => held.thread, "items" => [item]}
      wire = %{"id" => id, "method" => "thread/inject_items", "params" => params}
      result = call(ctx, held.session, wire["method"], params, id)
      assert result === %{}
      assert_injection_contract(wire, result)
      # Real ACK under an unresolved callback means queued, not durable acceptance.
      assert_absent(durable_payloads(held.path))
      assert ModelFixture.requests(ctx.fixture) === [held.first]
      events = drain(held.session, events)
      assert [held.tool] === Enum.filter(events, &(&1.kind === :server_request))
      refute Enum.any?(events, &(&1.wire["method"] === "turn/completed"))

      assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0, gap: nil} =
               Session.status(held.session.pid)

      assert Session.interaction_outcomes(held.session.pid) === []
      events
    end)
  end

  defp assert_tool_response(ctx, held) do
    assert [sent] =
             Enum.filter(captured(ctx), fn entry ->
               entry.connection === held.session.index and entry.direction === :out and
                 entry.wire["id"] === held.tool.wire["id"] and
                 not Map.has_key?(entry.wire, "method")
             end)

    wire = %{"id" => held.tool.wire["id"], "result" => @tool_result}
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert :ok = Schema.validate(protocol_schema("JSONRPCResponse.json"), sent.wire)

    assert :ok =
             Schema.validate(protocol_schema("DynamicToolCallResponse.json"), sent.wire["result"])
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

    id = "owned-active-injection-initialize-#{index}"
    info = %{"name" => "owned_active_injected_history", "version" => "0.1.0"}

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
    id = id || "owned-active-injection-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request(session.pid, method, params, id: id, timeout_ms: 5000)

    assert_exchange(ctx, session, %{"id" => id, "method" => method, "params" => params}, response)
    result
  end

  defp assert_exchange(ctx, session, wire, response) do
    entries = Enum.filter(captured(ctx), &(&1.connection === session.index))

    assert [sent] =
             Enum.filter(
               entries,
               &(&1.direction === :out and &1.wire["id"] === wire["id"] and
                   Map.has_key?(&1.wire, "method"))
             )

    assert [received] =
             Enum.filter(
               entries,
               &(&1.direction === :in and &1.wire["id"] === wire["id"] and
                   not Map.has_key?(&1.wire, "method"))
             )

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

  defp durable_rows(path) do
    assert File.stat!(path).size <= 1_048_576
    rows = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert length(rows) <= 128
    rows
  end

  defp durable_payloads(path) do
    path
    |> durable_rows()
    |> Enum.filter(&(&1["type"] === "response_item"))
    |> Enum.map(&Map.fetch!(&1, "payload"))
  end

  # Identify retained history using authored input/call identity before retaining
  # full original rows (including native IDs, metadata and timestamps) unchanged.
  defp original_history_rows(path) do
    rows = Enum.filter(durable_rows(path), &(&1["type"] === "response_item"))
    payloads = Enum.map(rows, & &1["payload"])
    {user, call} = assert_original_items(payloads)
    assert [user_row] = Enum.filter(rows, &(&1["payload"] === user))
    assert [call_row] = Enum.filter(rows, &(&1["payload"] === call))
    assert Enum.find_index(rows, &(&1 === user_row)) < Enum.find_index(rows, &(&1 === call_row))
    [user_row, call_row]
  end

  defp assert_original_items(items) do
    assert [user] =
             Enum.filter(items, fn item ->
               item["type"] === "message" and item["role"] === "user" and
                 item["content"] === [%{"type" => "input_text", "text" => @input}]
             end)

    assert [call] =
             Enum.filter(items, fn item ->
               item["type"] === "function_call" and item["call_id"] === "fixture-call-1"
             end)

    assert is_binary(user["id"]) and String.starts_with?(user["id"], "msg_")
    assert is_binary(call["id"]) and String.starts_with?(call["id"], "fc_")
    assert call["name"] === "fixture_lookup"
    assert is_binary(call["arguments"])
    assert JSON.decode!(call["arguments"]) === %{"key" => "synthetic"}
    assert Enum.find_index(items, &(&1 === user)) < Enum.find_index(items, &(&1 === call))
    {user, call}
  end

  defp selected_by_id(items),
    do: Enum.filter(items, &(&1["id"] in ["msg_v510_active_first_λ", "msg_v510_active_second_雪"]))

  defp selected_by_text(items) do
    Enum.filter(items, fn item ->
      content = Map.get(item, "content", [])

      is_list(content) and
        Enum.any?(content, fn part ->
          part["text"] in [
            "First queued active context λ🙂",
            "Second queued active context 雪🙂\nKeep FIFO."
          ]
        end)
    end)
  end

  defp assert_absent(items) do
    assert selected_by_id(items) === []
    assert selected_by_text(items) === []
  end

  defp assert_selected(items, expected) do
    assert selected_by_id(items) === expected
    assert selected_by_text(items) === expected
  end

  defp assert_durable_items(path) do
    rows = durable_rows(path)
    payloads = rows |> Enum.filter(&(&1["type"] === "response_item")) |> Enum.map(& &1["payload"])
    assert_selected(payloads, @durable_items)
    assert_fifo_after_output(payloads)
    second = Enum.find_index(payloads, &(&1["id"] === "msg_v510_active_second_雪"))

    assert [answer] =
             Enum.filter(payloads, fn item ->
               item["type"] === "message" and item["role"] === "assistant" and
                 item["content"] === [%{"type" => "output_text", "text" => @answer}]
             end)

    assert second < Enum.find_index(payloads, &(&1 === answer))

    Enum.filter(
      rows,
      &(get_in(&1, ["payload", "id"]) in ["msg_v510_active_first_λ", "msg_v510_active_second_雪"])
    )
  end

  defp provider_input(request) do
    assert request["model"] === "mock-model"
    assert byte_size(JSON.encode!(request)) <= 1_048_576
    input = Map.fetch!(request, "input")
    assert is_list(input) and length(input) <= 128
    input
  end

  defp assert_fifo_after_output(items) do
    assert [output] =
             Enum.filter(
               items,
               &(&1["type"] === "function_call_output" and
                   &1["call_id"] === "fixture-call-1")
             )

    assert output["output"] === @output
    tool = Enum.find_index(items, &(&1 === output))
    first = Enum.find_index(items, &(&1["id"] === "msg_v510_active_first_λ"))
    second = Enum.find_index(items, &(&1["id"] === "msg_v510_active_second_雪"))
    assert Enum.all?([tool, first, second], &is_integer/1)
    assert tool < first and first < second
  end

  defp await_turn(session, turn, events, deadline) do
    await_events(session, events, deadline, fn events ->
      Enum.any?(events, fn event ->
        event.wire["method"] === "turn/completed" and
          get_in(event.wire, ["params", "turn", "id"]) === turn
      end)
    end)
  end

  defp await_events(session, events, deadline, predicate) do
    events = drain(session, events)

    if predicate.(events) do
      events
    else
      remaining = deadline - now()
      assert remaining > 0, "Native active injected-history event deadline"

      receive do
        {:codex_driver, pid, :events_available} when pid === session.pid -> :ok
        {:codex_driver, pid, {:gap, _}} when pid === session.pid -> flunk("Native event gap")
      after
        remaining -> flunk("Native active injected-history event deadline")
      end

      await_events(session, events, deadline, predicate)
    end
  end

  defp drain(session, events) do
    assert {:ok, fresh} = Session.drain(session.pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 128
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= 1_048_576

    assert Enum.all?(combined, fn event ->
             event.generation === session.generation and
               (event.kind === :notification or
                  (event.kind === :server_request and event.wire["method"] === "item/tool/call"))
           end)

    assert Enum.count(combined, &(&1.kind === :server_request)) <= 1
    refute Enum.any?(combined, &(&1.wire["method"] in ["error", "warning"]))
    sequences = Enum.map(combined, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
    combined
  end

  defp assert_no_turn(events) do
    refute Enum.any?(events, &(&1.wire["method"] in ["turn/started", "turn/completed"]))
  end

  defp assert_terminal_turn(events, thread, turn, status) do
    assert [started] = Enum.filter(events, &(&1.wire["method"] === "turn/started"))
    assert get_in(started.wire, ["params", "threadId"]) === thread
    assert get_in(started.wire, ["params", "turn", "id"]) === turn
    assert [completed] = Enum.filter(events, &(&1.wire["method"] === "turn/completed"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => ^status}} =
             completed.wire["params"]

    assert started.sequence < completed.sequence
    {started, completed}
  end

  defp assert_completed_turn(events, thread, turn) do
    {started, completed} = assert_terminal_turn(events, thread, turn, "completed")

    assert [answer] =
             Enum.filter(events, fn event ->
               event.wire["method"] === "item/completed" and
                 get_in(event.wire, ["params", "item", "type"]) === "agentMessage"
             end)

    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"text" => @answer}} =
             answer.wire["params"]

    assert started.sequence < answer.sequence and answer.sequence < completed.sequence
  end

  defp assert_interrupted_turn(events, thread, turn) do
    assert_terminal_turn(events, thread, turn, "interrupted")

    refute Enum.any?(events, fn event ->
             event.wire["method"] === "item/completed" and
               get_in(event.wire, ["params", "item", "type"]) === "agentMessage"
           end)
  end

  defp assert_successful_tool(events, held) do
    assert [started] =
             Enum.filter(
               events,
               &(&1.wire["method"] === "item/started" and
                   get_in(&1.wire, ["params", "item", "type"]) === "dynamicToolCall")
             )

    assert [completed] =
             Enum.filter(
               events,
               &(&1.wire["method"] === "item/completed" and
                   get_in(&1.wire, ["params", "item", "type"]) === "dynamicToolCall")
             )

    assert %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => %{
               "id" => "fixture-call-1",
               "tool" => "fixture_lookup",
               "status" => "completed",
               "success" => true,
               "contentItems" => content
             }
           } = completed.wire["params"]

    assert thread === held.thread and turn === held.turn
    assert content === @tool_result["contentItems"]
    assert get_in(started.wire, ["params", "item", "status"]) === "inProgress"
    assert started.sequence < held.tool.sequence and held.tool.sequence < completed.sequence
  end

  defp assert_capture(ctx, outcome) do
    entries = captured(ctx)
    assert length(entries) <= 128
    assert Enum.reduce(entries, 0, &(byte_size(&1.encoded) + &2)) <= 1_048_576
    count = if outcome === :continued, do: 1, else: 2
    assert length(Agent.get(ctx.capture, & &1.connections)) === count

    for entry <- entries do
      limit = if entry.direction === :out, do: 4096, else: 65_536
      assert byte_size(entry.encoded) <= limit
      assert entry.connection in 1..count
      assert {:ok, decoded} = Wire.decode(entry.encoded, max_depth: 32)
      assert decoded === entry.wire
      assert {:ok, reencoded} = Wire.encode(decoded, max_depth: 32)
      assert JSON.decode!(reencoded) === entry.wire
    end

    for index <- 1..count do
      assert_connection_capture(Enum.filter(entries, &(&1.connection === index)), index, outcome)
    end
  end

  defp assert_connection_capture(selected, index, outcome) do
    out = Enum.filter(selected, &(&1.direction === :out))

    requests =
      Enum.filter(out, &(Map.has_key?(&1.wire, "id") and Map.has_key?(&1.wire, "method")))

    responses =
      Enum.filter(
        selected,
        &(&1.direction === :in and Map.has_key?(&1.wire, "id") and
            not Map.has_key?(&1.wire, "method"))
      )

    assert Enum.map(requests, & &1.wire["id"]) === Enum.map(responses, & &1.wire["id"])
    assert Enum.map(out, & &1.wire["method"]) === expected_methods(index, outcome)

    native_requests =
      Enum.filter(
        selected,
        &(&1.direction === :in and Map.has_key?(&1.wire, "id") and
            Map.has_key?(&1.wire, "method"))
      )

    if index === 1,
      do: assert(length(native_requests) === 1),
      else: assert(native_requests === [])

    replies =
      Enum.filter(out, &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method")))

    if outcome === :continued, do: assert(length(replies) === 1), else: assert(replies === [])
  end

  defp expected_methods(1, outcome) do
    ~w(initialize initialized server/diagnostics thread/start turn/start thread/inject_items thread/inject_items) ++
      if(outcome === :continued, do: [nil], else: ["turn/interrupt"])
  end

  defp expected_methods(2, :interrupted),
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
