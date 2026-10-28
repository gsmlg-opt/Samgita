defmodule SamgitaCodexDriver.NativeOrdinaryBackgroundTerminalsTest do
  @moduledoc """
  Paired ordinary native lifecycle for physical request-ID owners 1289 and 1299.
  """
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_background_terminals_fixture.py", __DIR__)
  @script_sha "b149a92976fedfd1f7989f11dfe7111767bf57ecb161b060505e5be4a575d299"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "ServerNotification.json" =>
      "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1",
    "v2/ThreadBackgroundTerminalsCleanParams.json" =>
      "e07820971c6e4ef8ee1ca5565a6eb78b04a96e001a5828e136b8aca927096a51",
    "v2/ThreadBackgroundTerminalsCleanResponse.json" =>
      "a594a65b4eb1ddf4613e868e382d7cda24daaa09b86de919fbece99e75b55478",
    "v2/ThreadBackgroundTerminalsTerminateParams.json" =>
      "4af4973b4e965228e7c6ffdff341c22c227c26bc48d4b44a8696993869b64103",
    "v2/ThreadBackgroundTerminalsTerminateResponse.json" =>
      "1f5dfb3fdd3c1fef2ef9b9b2c26eb2f2c7346cdf695d4ca291ede076050d1bc7",
    "v2/ThreadBackgroundTerminalsListParams.json" =>
      "7ac232410d59afd308dca04f8c0b08f20fa6e87f00bd0d3b5892b7ce8b31d2ee",
    "v2/ThreadBackgroundTerminalsListResponse.json" =>
      "b56b1cbcb1d60079ee9f9caaeef29cad869a25b4a6d356566f7c9f672faa7bf4"
  }
  @id_node_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_node_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @list "thread/backgroundTerminals/list"
  @clean "thread/backgroundTerminals/clean"
  @terminate "thread/backgroundTerminals/terminate"
  @clean_id "owned-background-clean-1289"
  @terminate_id 1_299_001
  @prompt "Owned ordinary background terminals only"
  @answer "Owned ordinary background terminals launched."

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
          case record(next.capture, :out, encoded) do
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
          case record_events(next.capture, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(capture, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(capture, :in, encoded) do
            :ok -> {:cont, :ok}
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8_192, else: 65_536

        if length(ledger.frames) < 256 and size <= limit and ledger.bytes + size <= 2_097_152 do
          frame = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}
          {:ok, %{frames: ledger.frames ++ [frame], bytes: ledger.bytes + size}}
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

    for {relative, expected} <- @schemas,
        do: assert(hash(File.read!(schema_path(relative))) === expected)

    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-background-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.cp!(@script, Path.join(root, "bin/reader.py"))
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    profile = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      python: python,
      binary: Path.expand(binary),
      capture: capture
    }

    peer = start_peer(profile)
    frozen = inputs(profile)
    native = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(native.pid).generation)
    %{profile: profile, peer: peer, native: native, frozen: frozen}
  end

  test "targeted native termination preserves the other live session and clean stops that remaining session",
       ctx do
    profile = ctx.profile
    pid = ctx.native.pid
    deadline = now() + 30_000

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated",
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })["thread"]["id"]

    assert_uuid(thread)

    turn =
      call(profile, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @prompt}]
      })["turn"]["id"]

    assert_uuid(turn)

    events =
      await_events(profile, pid, [], deadline, fn events ->
        Enum.any?(notices(events, "turn/completed"), &(&1.wire["params"]["turn"]["id"] === turn))
      end)

    state = assert_model_exchanges(profile)
    a = state["readers"]["a"]
    b = state["readers"]["b"]
    assert a["pid"] !== b["pid"] and a["processId"] !== b["processId"]
    assert_readers(profile, state)
    assert Enum.filter(notices(events, "item/completed"), &command_item?/1) === []
    assert_terminals(profile, pid, thread, [a, b])

    # A response confirms the request result, while the original command item's
    # actual completion and independent pidfd observation establish the effect.
    boundary = length(frames(profile))

    assert call(
             profile,
             pid,
             @terminate,
             %{"threadId" => thread, "processId" => a["processId"]},
             @terminate_id
           ) === %{"terminated" => true}

    assert_physical_owner(profile, @terminate, 43, @terminate_id)
    events = await_completion(profile, pid, events, thread, turn, a, deadline)
    assert_later_completion(profile, "a", boundary)

    assert observe(ctx.peer.port, "a", true, deadline) === %{
             "name" => "a",
             "pid" => a["pid"],
             "exited" => true
           }

    assert observe(ctx.peer.port, "b", false, deadline) === %{
             "name" => "b",
             "pid" => b["pid"],
             "exited" => false
           }

    assert_terminals(profile, pid, thread, [b])
    assert_readers(profile, state)

    boundary = length(frames(profile))
    # The clean ACK is only a submitted core op. Never treat {} or an empty
    # terminal list as evidence of process termination or child reaping.
    assert call(profile, pid, @clean, %{"threadId" => thread}, @clean_id) === %{}
    assert_physical_owner(profile, @clean, 41, @clean_id)
    events = await_completion(profile, pid, events, thread, turn, b, deadline)
    assert_later_completion(profile, "b", boundary)

    assert observe(ctx.peer.port, "b", true, deadline) === %{
             "name" => "b",
             "pid" => b["pid"],
             "exited" => true
           }

    assert_terminals(profile, pid, thread, [])
    assert_lifecycle(profile, events, thread, turn, a, b)
    assert_inventory(profile)
    assert_controls(profile, a, b)
    assert inputs(profile) === ctx.frozen
    assert_model_exchanges(profile)
    assert Session.status(pid).phase === :ready
    assert Session.status(pid).pending === 0
    assert Session.uncertain_operations(pid) === []
    assert now() < deadline
    close_native(ctx.native)
    # Native-owner close waits on its owned process group. pidfd readiness alone
    # proves exit, whereas exact /proc absence after close also proves reaping.
    for reader <- [a, b], do: refute(File.exists?("/proc/#{reader["pid"]}"))
    assert_readers(profile, state)
    final_bytes = File.read!(Path.join(profile.root, "peer.json"))
    close_transport(ctx.peer.transport, ctx.peer.identity)
    assert read_json(profile, "peer-closed.json") === %{"pidfds" => 0, "serverClosed" => true}
    assert File.read!(Path.join(profile.root, "peer.json")) === final_bytes
    assert inputs(profile) === ctx.frozen
    assert_inventory(profile)
  end

  defp assert_physical_owner(profile, method, index, id) do
    assert [sent] =
             Enum.filter(
               frames(profile),
               &(&1.direction === :out and &1.wire["method"] === method)
             )

    assert sent.wire["id"] === id
    assert byte_size(sent.encoded) <= 8_192
    document = schema("ClientRequest.json")
    variants = Map.fetch!(document, "oneOf")

    assert [selected] =
             Enum.filter(
               variants,
               &(get_in(&1, ["properties", "method", "enum"]) === [method])
             )

    assert selected === Enum.at(variants, index)
    node = selected |> Map.fetch!("properties") |> Map.fetch!("id")
    assert node === %{"$ref" => "#/definitions/RequestId"}
    assert JSON.decode!(@id_node_bytes) === node
    assert hash(@id_node_bytes) === @id_node_sha
    definitions = Map.fetch!(document, "definitions")

    assert Map.fetch!(definitions, "RequestId") === %{
             "anyOf" => [
               %{"type" => "string"},
               %{"format" => "int64", "type" => "integer"}
             ]
           }

    assert :ok = Schema.validate(Map.put(node, "definitions", definitions), sent.wire["id"])

    assert :ok =
             Schema.validate(Map.put(selected, "definitions", definitions), sent.wire,
               max_depth: 32
             )

    assert :ok = Schema.validate(document, sent.wire, max_depth: 32)
  end

  defp assert_terminals(profile, pid, thread, readers) do
    result = call(profile, pid, @list, %{"threadId" => thread})
    assert :ok = Schema.validate(schema("v2/ThreadBackgroundTerminalsListResponse.json"), result)
    assert result["nextCursor"] === nil

    expected =
      readers
      |> Enum.sort_by(&String.to_integer(&1["processId"]))
      |> Enum.map(fn reader ->
        %{
          "itemId" => "owned-background-" <> reader["name"],
          "processId" => reader["processId"],
          "command" => command(profile, reader["name"]),
          "cwd" => profile.workspace
        }
      end)

    assert Enum.map(result["data"], &Map.take(&1, ~w(itemId processId command cwd))) === expected
  end

  defp await_completion(profile, pid, events, thread, turn, reader, deadline) do
    id = "owned-background-" <> reader["name"]

    await_events(profile, pid, events, deadline, fn events ->
      Enum.any?(notices(events, "item/completed"), fn event ->
        params = event.wire["params"]

        params["threadId"] === thread and params["turnId"] === turn and
          params["item"]["id"] === id and params["item"]["processId"] === reader["processId"]
      end)
    end)
  end

  defp await_events(profile, pid, events, deadline, predicate) do
    remaining = deadline - now()
    assert remaining > 0, "Owned background native notification deadline"
    # Drain the complete bounded queue before waiting for its empty-to-nonempty
    # edge; a partial drain could otherwise retain events without a fresh edge.
    assert {:ok, fresh} = Session.drain(pid, 256)
    events = events ++ fresh

    assert length(events) <= 256 and
             byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert read_json(profile, "peer.json")["errors"] === []

    if predicate.(events) do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} ->
          await_events(profile, pid, events, deadline, predicate)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Owned background native event gap")
      after
        remaining -> flunk("Owned background native notification deadline")
      end
    end
  end

  defp assert_later_completion(profile, name, boundary) do
    indexed = Enum.with_index(frames(profile), 1)

    assert [{original, index}] =
             Enum.filter(indexed, fn {frame, _index} ->
               frame.direction === :in and frame.wire["method"] === "item/completed" and
                 get_in(frame.wire, ["params", "item", "id"]) === "owned-background-" <> name
             end)

    assert index > boundary
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 32)
    assert decoded === original.wire
  end

  defp assert_lifecycle(profile, events, thread, turn, a, b) do
    for reader <- [a, b] do
      id = "owned-background-" <> reader["name"]

      assert [start] =
               Enum.filter(
                 notices(events, "item/started"),
                 &(&1.wire["params"]["item"]["id"] === id)
               )

      assert [finish] =
               Enum.filter(
                 notices(events, "item/completed"),
                 &(&1.wire["params"]["item"]["id"] === id)
               )

      assert start.sequence < finish.sequence

      for event <- [start, finish] do
        assert event.generation === profile.generation
        assert event.wire["params"]["threadId"] === thread
        assert event.wire["params"]["turnId"] === turn
        assert :ok = Schema.validate(schema("ServerNotification.json"), event.wire, max_depth: 32)
      end

      item = finish.wire["params"]["item"]
      assert item["type"] === "commandExecution" and item["processId"] === reader["processId"]
      assert item["cwd"] === profile.workspace

      assert item["command"] ===
               Path.join(profile.root, "bin/sh") <>
                 " -c '" <> command(profile, reader["name"]) <> "'"

      assert item["status"] !== "inProgress"
      assert item["aggregatedOutput"] === ready(reader["name"])
      assert is_integer(item["durationMs"]) and item["durationMs"] >= 0
    end

    assert [completion] = notices(events, "turn/completed")
    assert completion.wire["params"]["turn"]["id"] === turn
    assert completion.wire["params"]["turn"]["status"] === "completed"

    assert [answer] =
             Enum.filter(
               notices(events, "item/completed"),
               &(&1.wire["params"]["item"]["type"] === "agentMessage")
             )

    assert answer.wire["params"]["item"]["text"] === @answer
  end

  defp assert_readers(profile, state) do
    assert File.ls!(profile.workspace) === []

    for name <- ~w(a b) do
      reader = state["readers"][name]

      assert read_json(profile, "reader-#{name}-started.json") ===
               Map.take(reader, ~w(pid name cwd))

      refute File.exists?(Path.join(profile.root, "reader-#{name}-unexpected.json"))
    end
  end

  defp assert_model_exchanges(profile) do
    state = read_json(profile, "peer.json")
    assert state["errors"] === []
    assert [one, two, three] = state["requests"]
    assert Enum.map([one, two, three], & &1["index"]) === [1, 2, 3]

    for request <- [one, two, three] do
      bytes = Base.decode64!(request["bodyBase64"])
      assert byte_size(bytes) <= 262_144
      native_input = JSON.decode!(bytes)["input"]

      actual_outputs =
        native_input
        |> Enum.filter(&(&1["type"] === "function_call_output"))
        |> Enum.map(&Map.take(&1, ~w(type call_id output)))

      assert actual_outputs === request["toolOutputs"]

      assert Enum.filter(native_input, &(&1["role"] === "user"))
             |> Enum.flat_map(& &1["content"])
             |> Enum.filter(&(&1["type"] === "input_text" and &1["text"] === @prompt))
             |> length() === 1
    end

    assert one["toolOutputs"] === []
    assert [initial] = two["toolOutputs"]
    assert [^initial, final] = three["toolOutputs"]

    for {output, name} <- [{initial, "a"}, {final, "b"}] do
      assert output["call_id"] === "owned-background-" <> name
      assert String.ends_with?(output["output"], "Output:\n" <> ready(name))

      assert Regex.scan(
               ~r/^Process running with session ID ([1-9][0-9]*)$/m,
               output["output"],
               capture: :all_but_first
             ) === [[state["readers"][name]["processId"]]]
    end

    assert length(state["emitted"]) === 3

    for {emission, index} <- Enum.with_index(state["emitted"], 1),
        do: assert_model_emission(profile, emission, index)

    state
  end

  defp assert_model_emission(profile, emission, index) do
    events = emission["events"]
    assert [created, output, completed] = events

    assert created === %{
             "type" => "response.created",
             "response" => %{"id" => "owned-background-response-#{index}"}
           }

    assert output["type"] === "response.output_item.done"
    assert completed["type"] === "response.completed"
    # JSON map key order is not the oracle; the original emitted SSE bytes
    # are decoded independently and compared to the recorded semantic events.
    bytes = Base.decode64!(emission["bodyBase64"])
    assert byte_size(bytes) <= 65_536

    decoded =
      bytes
      |> String.split("\n\n", trim: true)
      |> Enum.map(&decode_model_frame/1)

    assert decoded === events

    if index < 3 do
      name = if index == 1, do: "a", else: "b"

      assert Map.take(output["item"], ~w(type name call_id)) === %{
               "type" => "function_call",
               "name" => "exec_command",
               "call_id" => "owned-background-" <> name
             }

      assert JSON.decode!(output["item"]["arguments"]) === exec_args(profile, name)
    else
      assert output["item"] === %{
               "type" => "message",
               "role" => "assistant",
               "id" => "owned-background-answer",
               "content" => [%{"type" => "output_text", "text" => @answer}]
             }
    end
  end

  defp decode_model_frame(frame) do
    assert [event_line, "data: " <> data] = String.split(frame, "\n")
    event = JSON.decode!(data)
    assert event_line === "event: " <> event["type"]
    event
  end

  defp assert_controls(profile, a, b) do
    state = read_json(profile, "peer.json")
    assert state["requestCount"] === 6

    assert state["controls"] === [
             %{
               "input" => %{"name" => "a", "waitExit" => true},
               "result" => %{"name" => "a", "pid" => a["pid"], "exited" => true}
             },
             %{
               "input" => %{"name" => "b", "waitExit" => false},
               "result" => %{"name" => "b", "pid" => b["pid"], "exited" => false}
             },
             %{
               "input" => %{"name" => "b", "waitExit" => true},
               "result" => %{"name" => "b", "pid" => b["pid"], "exited" => true}
             }
           ]
  end

  defp assert_inventory(profile) do
    outgoing = for frame <- frames(profile), frame.direction === :out, do: frame.wire["method"]

    assert outgoing === [
             "initialize",
             "initialized",
             "server/diagnostics",
             "thread/start",
             "turn/start",
             @list,
             @terminate,
             @list,
             @clean,
             @list
           ]
  end

  defp observe(port, name, wait_exit, deadline) do
    remaining = min(deadline - now(), 6_000)
    assert remaining > 0

    assert {:ok, socket} =
             :gen_tcp.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, send_timeout: remaining, send_timeout_close: true],
               remaining
             )

    try do
      body = JSON.encode!(%{"name" => name, "waitExit" => wait_exit})

      request =
        "POST /fixture/observe HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
          body

      assert :ok = :gen_tcp.send(socket, request)
      response = read_control(socket, <<>>, min(deadline, now() + 6_000))
      assert [header, result] = String.split(response, "\r\n\r\n", parts: 2)
      assert String.starts_with?(header, "HTTP/1.1 200 OK\r\n")
      assert String.contains?(header, "\r\nContent-Length: #{byte_size(result)}\r\n")
      JSON.decode!(result)
    after
      assert :ok = :gen_tcp.close(socket)
    end
  end

  defp read_control(socket, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0, "Owned pidfd observation deadline"

    case :gen_tcp.recv(socket, 0, remaining) do
      {:ok, chunk} ->
        assert byte_size(bytes) + byte_size(chunk) <= 8_192
        read_control(socket, bytes <> chunk, deadline)

      {:error, :closed} ->
        bytes

      other ->
        flunk("Owned pidfd observation failed: #{inspect(other)}")
    end
  end

  defp start_peer(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [@script, "--root", profile.root],
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 8_192
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = peer_startup(transport.port, <<>>, now() + 5_000)
    assert is_integer(startup["pid"]) and startup["pid"] > 0
    :atomics.put(identity, 1, startup["pid"])
    assert hash(File.read!(profile.python)) === hash(File.read!("/proc/#{startup["pid"]}/exe"))
    assert is_integer(startup["port"]) and startup["port"] in 1..65_535
    assert startup["execArgs"] === Map.new(~w(a b), &{&1, exec_args(profile, &1)})
    %{transport: transport, identity: identity, port: startup["port"]}
  end

  defp peer_startup(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0, "Owned background peer startup deadline"
    assert byte_size(bytes) <= 8_192

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected owned background peer startup output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} -> peer_startup(port, bytes <> chunk, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned background peer startup exit #{status}")
        after
          remaining -> flunk("Owned background peer startup deadline")
        end
    end
  end

  defp start_native(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: profile.capture,
                    executable: profile.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: profile.workspace,
                    inherit_env: [],
                    env: environment(profile),
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity}

    on_exit(fn ->
      close_native(native)
      assert_readers_stopped(profile)
    end)

    info = %{"name" => "owned_ordinary_background", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      profile,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native_pid = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native_pid) and native_pid > 0
    :atomics.put(identity, 1, native_pid)
    assert hash(File.read!("/proc/#{native_pid}/exe")) === @binary_sha
    native
  end

  defp assert_readers_stopped(profile) do
    for name <- ~w(a b) do
      marker = Path.join(profile.root, "reader-#{name}-started.json")

      if File.exists?(marker),
        do: refute(File.exists?("/proc/#{JSON.decode!(File.read!(marker))["pid"]}"))
    end
  end

  defp call(profile, pid, method, params, id \\ nil) do
    id = id || request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    assert :ok = Schema.validate_result(:server_response, method, result)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(frames(profile), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp command(profile, name) do
    "exec " <>
      Enum.map_join(
        [
          profile.python,
          Path.join(profile.root, "bin/reader.py"),
          "--reader",
          "--root",
          profile.root,
          "--name",
          name
        ],
        " ",
        &shell_quote/1
      )
  end

  defp shell_quote(text) do
    if Regex.match?(~r/\A[-a-zA-Z0-9_\/.]+\z/, text),
      do: text,
      else: "'" <> String.replace(text, "'", ~s('"'"')) <> "'"
  end

  defp exec_args(profile, name),
    do: %{
      "cmd" => command(profile, name),
      "workdir" => profile.workspace,
      "shell" => Path.join(profile.root, "bin/sh"),
      "login" => false,
      "tty" => true,
      "yield_time_ms" => 1_000,
      "max_output_tokens" => 512
    }

  defp environment(profile),
    do: %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "SHELL" => Path.join(profile.root, "bin/sh"),
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }

  defp inputs(profile) do
    paths =
      Enum.map(
        ~w(codex/config.toml codex/models.json bin/reader.py bin/sh),
        &Path.join(profile.root, &1)
      ) ++ [@script] ++ Enum.map(Map.keys(@schemas), &schema_path/1)

    Map.new(paths, &{&1, File.read!(&1)})
  end

  defp frames(profile), do: Agent.get(profile.capture, & &1.frames)
  defp ready(name), do: "owned-background-#{name}-ready\n"
  defp command_item?(event), do: event.wire["params"]["item"]["type"] === "commandExecution"
  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] === method))

  defp read_json(profile, relative) do
    bytes = File.read!(Path.join(profile.root, relative))
    assert byte_size(bytes) <= 2_097_152
    JSON.decode!(bytes)
  end

  defp schema(relative), do: schema_path(relative) |> File.read!() |> JSON.decode!()

  defp schema_path(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)

  defp request_id, do: "owned-background-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp assert_uuid(id),
    do:
      assert(
        is_binary(id) and
          Regex.match?(
            ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
            id
          )
      )

  defp close_native(native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    close_transport(native.connection, native.identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    os_pid = :atomics.get(identity, 1)
    if os_pid > 0, do: refute(File.exists?("/proc/#{os_pid}"))
  end
end
