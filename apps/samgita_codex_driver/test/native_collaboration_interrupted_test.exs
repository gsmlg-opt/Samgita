defmodule SamgitaCodexDriver.NativeCollaborationInterruptedTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/collaboration_interrupted_fixture.py", __DIR__)
  @script_sha "baccf44853bd7b0daf029f21e993bf6d3e7744fc3990554260b92d556b521a55"
  @provider_base Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_base_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @root "OWNED_V417_ROOT"
  @child "OWNED_V417_CHILD_HELD"
  @answer "Owned interrupted child closed."
  @spawn "owned-v417-spawn"
  @close "owned-v417-close"

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
        {:ok, next} -> record_sent(next, encoded)
        other -> other
      end
    end

    defp record_sent(state, encoded) do
      case record(state.capture, :out, encoded) do
        :ok -> {:ok, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} -> record_received(next, events)
        other -> other
      end
    end

    defp record_received(state, events) do
      case Enum.reduce_while(events, :ok, &record_event(&1, &2, state.capture)) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Original native JSONL payloads, before Session decoding or projection.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded}

        {:ok,
         %{count: ledger.count + 1, bytes: ledger.bytes + size, records: [entry | ledger.records]}}
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

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@provider_base)) === @provider_base_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-collaboration-interrupted-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      workspace: Path.join(root, "workspace"),
      capture: capture
    }

    provider = start_provider(profile)

    originals =
      Map.new(
        [
          @script,
          @provider_base,
          Path.join(root, "codex/config.toml"),
          Path.join(root, "codex/models.json")
        ],
        &{&1, File.read!(&1)}
      )

    %{profile: profile, provider: provider, originals: originals}
  end

  test "real interrupted child closes with exact live and warm first-cold persisted snapshots",
       ctx do
    assert_contracts()
    assert_frozen(ctx)
    {profile, session} = start_native(ctx.profile)
    instance = Session.status(session.pid).instance_id

    root =
      call(profile, session.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "historyMode" => "paginated",
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(root) and byte_size(root) > 0
    assert read_json(profile, "requests.json") === []
    lower = System.system_time(:millisecond)
    deadline = now() + 20_000

    turn =
      call(
        profile,
        session.pid,
        "turn/start",
        %{"threadId" => root, "input" => [%{"type" => "text", "text" => @root}]},
        remaining(deadline)
      )["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0

    {events, child, child_turn, child_started} =
      await_ready(profile, session.pid, root, turn, [], min(deadline, now() + 5_000))

    assert %{} ===
             call(
               profile,
               session.pid,
               "turn/interrupt",
               %{"threadId" => child, "turnId" => child_turn},
               remaining(deadline)
             )

    {events, child_finished} =
      await_terminal(
        profile,
        session.pid,
        child,
        child_turn,
        events,
        min(deadline, now() + 5_000),
        "interrupted"
      )

    assert child_finished.wire["params"]["turn"]["error"] === nil
    assert child_finished.wire["params"]["turn"]["items"] === []
    assert child_started.sequence < child_finished.sequence

    # Both original native observations precede this explicit owned fixture gate.
    [sent_interrupt] =
      Enum.filter(
        capture(profile),
        &(&1.direction == :out and &1.wire["method"] == "turn/interrupt")
      )

    interrupt_id = sent_interrupt.wire["id"]

    [ack] =
      Enum.filter(capture(profile), &(&1.direction == :in and &1.wire["id"] == interrupt_id))

    assert ack.wire === %{"id" => interrupt_id, "result" => %{}}
    assert JSON.decode!(ack.encoded) === ack.wire
    interruption_window = %{lower: lower, upper: System.system_time(:millisecond)}
    assert_native_notice(profile, child_started, interruption_window)
    assert_native_notice(profile, child_finished, interruption_window)
    assert read_json(profile, "provider-state.json")["root_responses"] === [@spawn]
    assert {:ok, _} = Stdio.send(ctx.provider.transport, "after-native-interrupted")

    {events, finished} =
      await_terminal(profile, session.pid, root, turn, events, deadline, "completed")

    upper = System.system_time(:millisecond)

    run = %{
      thread: root,
      turn: turn,
      events: events,
      lower: lower,
      upper: upper,
      finished: finished
    }

    assert finished.wire["params"]["turn"]["error"] === nil
    expected_item = close_item(root, child)

    started =
      assert_item(
        profile,
        run,
        "item/started",
        %{expected_item | "status" => "inProgress", "agentsStates" => %{}},
        "startedAtMs"
      )

    completed = assert_item(profile, run, "item/completed", expected_item, "completedAtMs")
    answer = assert_answer(profile, run, "owned-v417-answer", @answer)
    assert child_finished.sequence < started.sequence
    assert started.sequence < completed.sequence
    assert completed.sequence < answer.sequence and answer.sequence < finished.sequence

    assert_original_order(profile, [
      child_started,
      child_finished,
      started,
      completed,
      answer,
      finished
    ])

    assert length(matching(events, "turn/completed", child, child_turn)) === 1

    assert Enum.filter(events, &(get_in(&1.wire, ["params", "item", "id"]) == @close)) ===
             [started, completed]

    refute Enum.any?(events, fn event ->
             event.wire["params"]["threadId"] == child and
               get_in(event.wire, ["params", "item", "type"]) == "agentMessage"
           end)

    assert call(profile, session.pid, "thread/loaded/list", %{})["data"] === [root]
    assert_provider(profile, root, turn, child, child_turn)
    assert read_json(profile, "provider-events.json") === provider_events(child)

    entry = %{
      "turnId" => turn,
      "item" => expected_item,
      "startedAtMs" => started.wire["params"]["startedAtMs"],
      "completedAtMs" => completed.wire["params"]["completedAtMs"]
    }

    assert entry["startedAtMs"] <= entry["completedAtMs"]
    query = %{"threadId" => root, "turnId" => turn, "itemIds" => [@close]}
    assert_selection(profile, session.pid, query, entry)
    assert_ready(session.pid)
    assert Session.uncertain_operations(session.pid) === []
    close_native(session.pid, session.connection, session.identity)
    assert_final_ingress(profile, run)
    frozen = frozen_provider(profile)
    assert_frozen(ctx)

    {cold_profile, cold} = start_native(ctx.profile)
    assert :atomics.get(cold.identity, 1) !== :atomics.get(session.identity, 1)
    assert Session.status(cold.pid).instance_id !== instance
    assert call(cold_profile, cold.pid, "thread/loaded/list", %{})["data"] === []
    # This is the replacement process's first content operation, without resume.
    assert_selection(cold_profile, cold.pid, query, entry)
    assert call(cold_profile, cold.pid, "thread/loaded/list", %{})["data"] === []
    cold_events = drain(cold_profile, cold.pid, [])

    refute Enum.any?(
             cold_events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert frozen_provider(cold_profile) === frozen
    assert_provider(cold_profile, root, turn, child, child_turn)
    assert_frozen(ctx)
    assert_ready(cold.pid)
    assert Session.uncertain_operations(cold.pid) === []
    close_native(cold.pid, cold.connection, cold.identity)
    assert frozen_provider(cold_profile) === frozen
    assert_frozen(ctx)

    assert_outgoing(
      profile,
      ~w(initialize initialized server/diagnostics thread/start turn/start turn/interrupt thread/loaded/list thread/items/read),
      cold_profile.capture_start
    )

    assert_outgoing(
      cold_profile,
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/items/read thread/loaded/list)
    )

    close_transport(ctx.provider.transport, ctx.provider.identity)
    assert frozen_provider(cold_profile) === frozen
  end

  defp start_provider(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [@script, "--root", profile.root],
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 4096
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(profile.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    %{transport: transport, identity: identity}
  end

  defp provider_startup(port, buffer, deadline) do
    assert now() < deadline, "Owned provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned provider startup output")
      [_partial] -> provider_startup(port, buffer, deadline)
    end
  end

  defp start_native(profile) do
    start_index = Agent.get(profile.capture, & &1.count)
    profile = Map.put(profile, :capture_start, start_index)

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
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
    on_exit(fn -> close_native(pid, connection, identity) end)
    info = %{"name" => "owned_collaboration_interrupted", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert_exchange(profile, wire, response)
    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    profile = Map.put(profile, :generation, Session.status(pid).generation)
    {profile, %{pid: pid, connection: connection, identity: identity}}
  end

  defp environment(profile) do
    %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off"
    }
  end

  defp await_ready(profile, pid, root, turn, events, deadline) do
    assert now() < deadline, "Owned native child and HTTP readiness deadline"
    events = drain(profile, pid, events)
    state = read_json(profile, "provider-state.json")
    assert state["errors"] === []

    if state["child_held"] and state["root_held"] do
      {child, child_turn} = assert_ready_requests(profile, state, root, turn)

      case matching(events, "turn/started", child, child_turn) do
        [started] ->
          assert started.wire["params"]["turn"]["status"] === "inProgress"
          assert matching(events, "turn/completed", child, child_turn) === []

          assert Enum.filter(events, &(get_in(&1.wire, ["params", "item", "id"]) == @close)) ===
                   []

          {events, child, child_turn, started}

        [] ->
          wait_ready(profile, pid, root, turn, events, deadline)

        _ ->
          flunk("Duplicate native child turn start")
      end
    else
      wait_ready(profile, pid, root, turn, events, deadline)
    end
  end

  defp assert_ready_requests(profile, state, root, turn) do
    child = state["child_thread"]
    child_turn = state["child_turn"]
    assert is_binary(child) and child !== root
    assert is_binary(child_turn) and child_turn !== turn
    assert state["root_thread"] === root and state["root_turn"] === turn
    assert state["root_requests"] === 2 and state["child_requests"] === 1
    assert state["root_responses"] === [@spawn] and state["controls"] === []
    assert length(read_json(profile, "requests.json")) === 3
    assert_provider_requests(profile, root, turn, child, child_turn, 2)
    {child, child_turn}
  end

  defp wait_ready(profile, pid, root, turn, events, deadline) do
    assert now() < deadline, "Owned native child and HTTP readiness deadline"
    Process.sleep(10)
    await_ready(profile, pid, root, turn, events, deadline)
  end

  defp await_terminal(profile, pid, thread, turn, events, deadline, expected_status) do
    assert now() < deadline, "Owned native terminal deadline"
    events = drain(profile, pid, events)
    assert now() < deadline, "Owned native terminal deadline"

    case matching(events, "turn/completed", thread, turn) do
      [event] ->
        assert event.wire["params"]["turn"]["status"] === expected_status
        {events, event}

      [] ->
        assert now() < deadline, "Owned native terminal deadline"
        Process.sleep(10)
        await_terminal(profile, pid, thread, turn, events, deadline, expected_status)

      _ ->
        flunk("Duplicate native terminal event")
    end
  end

  defp drain(profile, pid, events) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert generation === profile.generation
    assert Enum.all?(events, &(&1.kind === :notification and &1.generation === generation))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
    refute Enum.any?(events, &(&1.wire["method"] == "error"))
    events
  end

  defp matching(events, method, thread, turn) do
    Enum.filter(events, fn event ->
      event.wire["method"] == method and event.wire["params"]["threadId"] == thread and
        get_in(event.wire, ["params", "turn", "id"]) == turn
    end)
  end

  defp close_item(root, child) do
    %{
      "id" => @close,
      "type" => "collabAgentToolCall",
      "tool" => "closeAgent",
      "status" => "completed",
      "senderThreadId" => root,
      "receiverThreadIds" => [child],
      "prompt" => nil,
      "model" => nil,
      "reasoningEffort" => nil,
      "agentsStates" => %{child => %{"status" => "interrupted", "message" => nil}}
    }
  end

  defp assert_contracts do
    for relative <- ["ServerNotification.json", "v2/ThreadItemsReadResponse.json"] do
      assert Enum.at(schema(relative)["definitions"]["CollabAgentStatus"]["enum"], 2) ===
               "interrupted"
    end
  end

  defp assert_selection(profile, pid, query, entry) do
    result = call(profile, pid, "thread/items/read", query)
    assert result === %{"data" => [entry]}
    assert :ok = Schema.validate(schema("v2/ThreadItemsReadResponse.json"), result, max_depth: 32)
  end

  defp assert_native_notice(profile, event, run) do
    assert event.generation === profile.generation and event.kind === :notification
    assert_time(event.wire["emittedAtMs"], run)
    assert :ok = Schema.validate(schema("ServerNotification.json"), event.wire, max_depth: 32)

    assert [original] =
             Enum.filter(capture(profile), &(&1.direction == :in and &1.wire === event.wire))

    assert JSON.decode!(original.encoded) === event.wire
  end

  defp assert_notice(profile, run, event, method, params) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert_time(emitted_at, run)
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire === %{"method" => method, "params" => params, "emittedAtMs" => emitted_at}
    schema = schema("ServerNotification.json")
    assert :ok = Schema.validate(schema, event.wire, max_depth: 32)
  end

  defp assert_item(profile, run, method, item, time_key) do
    [event] =
      Enum.filter(notices(run.events, method), &(&1.wire["params"]["item"]["id"] == item["id"]))

    time = Map.fetch!(event.wire["params"], time_key)
    assert_time(time, run)

    params = %{
      "threadId" => run.thread,
      "turnId" => run.turn,
      "item" => item,
      time_key => time
    }

    assert event.wire["params"] === params
    assert_notice(profile, run, event, method, params)

    originals =
      for record <- capture(profile),
          record.direction == :in,
          record.wire["method"] == method,
          get_in(record.wire, ["params", "item", "id"]) == item["id"],
          do: record

    assert [original] = originals
    assert original.wire === event.wire
    assert JSON.decode!(original.encoded) === event.wire
    event
  end

  defp assert_answer(profile, run, id, text) do
    [event] =
      Enum.filter(
        notices(run.events, "item/completed"),
        &(&1.wire["params"]["item"]["type"] == "agentMessage")
      )

    item = %{
      "type" => "agentMessage",
      "id" => id,
      "text" => text,
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

    assert_item(profile, run, "item/completed", item, "completedAtMs")
    assert event.sequence < run.finished.sequence
    event
  end

  defp assert_time(time, run),
    do: assert(is_integer(time) and run.lower <= time and time <= run.upper)

  defp assert_provider(profile, root, turn, child, child_turn) do
    assert_provider_requests(profile, root, turn, child, child_turn, 3)

    assert read_json(profile, "provider-state.json") === %{
             "root_requests" => 3,
             "child_requests" => 1,
             "root_responses" => [@spawn, @close, "root_final"],
             "root_thread" => root,
             "root_turn" => turn,
             "child_thread" => child,
             "child_turn" => child_turn,
             "child_held" => true,
             "root_held" => true,
             "controls" => ["after-native-interrupted"],
             "errors" => []
           }
  end

  defp assert_provider_requests(profile, root, turn, child, child_turn, root_count) do
    requests = read_json(profile, "requests.json")
    assert length(requests) === root_count + 1
    grouped = Enum.group_by(requests, &metadata(&1)["thread_id"])
    assert Enum.sort(Map.keys(grouped)) === Enum.sort([root, child])
    roots = Map.fetch!(grouped, root)
    assert length(roots) === root_count

    for {request, index} <- Enum.with_index(roots) do
      assert metadata(request)["turn_id"] === turn
      assert Enum.count(user_texts(request), &(&1 == @root)) === 1
      outputs = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))
      assert Enum.map(outputs, & &1["call_id"]) === Enum.take([@spawn, @close], index)

      if index >= 1 do
        assert JSON.decode!(hd(outputs)["output"])["agent_id"] === child
      end

      if index == 2 do
        assert JSON.decode!(List.last(outputs)["output"]) === %{
                 "previous_status" => "interrupted"
               }
      end
    end

    [child_request] = Map.fetch!(grouped, child)
    assert metadata(child_request)["turn_id"] === child_turn
    assert Enum.count(user_texts(child_request), &(&1 == @child)) === 1
    refute @root in user_texts(child_request)
    assert Enum.filter(child_request["input"], &(&1["type"] == "function_call_output")) === []

    for request <- requests do
      assert request["model"] === "mock-model"
      assert request["reasoning"]["effort"] === "low"
      assert byte_size(JSON.encode!(request)) <= 1_048_576
    end
  end

  defp metadata(request), do: JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

  defp user_texts(request) do
    for item <- request["input"],
        item["role"] == "user",
        part <- item["content"],
        part["type"] == "input_text",
        do: part["text"]
  end

  defp provider_events(child) do
    items = [
      %{
        "type" => "function_call",
        "namespace" => "multi_agent_v1",
        "name" => "spawn_agent",
        "call_id" => @spawn,
        "arguments" =>
          ~s({"message": "OWNED_V417_CHILD_HELD", "fork_context": false, "model": "mock-model", "reasoning_effort": "low"})
      },
      %{
        "type" => "function_call",
        "namespace" => "multi_agent_v1",
        "name" => "close_agent",
        "call_id" => @close,
        "arguments" => ~s({"target": "#{child}"})
      },
      %{
        "type" => "message",
        "role" => "assistant",
        "id" => "owned-v417-answer",
        "content" => [%{"type" => "output_text", "text" => @answer}]
      }
    ]

    for {item, step} <- Enum.with_index(items, 1) do
      id = "owned-v417-response-#{step}"

      [
        %{"type" => "response.created", "response" => %{"id" => id}},
        %{"type" => "response.output_item.done", "item" => item},
        %{
          "type" => "response.completed",
          "response" => %{
            "id" => id,
            "usage" => %{
              "input_tokens" => 0,
              "input_tokens_details" => nil,
              "output_tokens" => 0,
              "output_tokens_details" => nil,
              "total_tokens" => 0
            }
          }
        }
      ]
    end
  end

  defp assert_frozen(ctx) do
    assert File.ls!(ctx.profile.workspace) === []
    assert Enum.all?(ctx.originals, fn {path, bytes} -> File.read!(path) === bytes end)
  end

  defp frozen_provider(profile) do
    Map.new(~w(requests.json provider-state.json provider-events.json), fn name ->
      path = Path.join(profile.root, name)
      assert File.stat!(path).size <= 2_097_152
      {name, File.read!(path)}
    end)
  end

  defp read_json(profile, name) do
    path = Path.join(profile.root, name)
    assert File.stat!(path).size <= 2_097_152
    path |> File.read!() |> JSON.decode!()
  end

  defp assert_original_order(profile, events) do
    originals = Enum.filter(capture(profile), &(&1.direction == :in))
    Enum.reduce(events, originals, &consume_original/2)
  end

  defp consume_original(event, originals) do
    assert [original | remaining] = Enum.drop_while(originals, &(&1.wire !== event.wire))
    assert JSON.decode!(original.encoded) === event.wire
    remaining
  end

  defp assert_final_ingress(profile, run) do
    methods = ~w(turn/started turn/completed item/started item/completed)

    originals =
      for record <- capture(profile),
          record.direction == :in and record.wire["method"] in methods,
          do: record.wire

    selected = for event <- run.events, event.wire["method"] in methods, do: event.wire
    assert originals === selected
  end

  defp assert_outgoing(profile, expected, stop_index \\ nil) do
    records = capture(profile)

    records =
      if stop_index,
        do: Enum.take(records, stop_index - Map.get(profile, :capture_start, 0)),
        else: records

    assert for(record <- records, record.direction == :out, do: record.wire["method"]) ===
             expected
  end

  defp assert_ready(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp remaining(deadline) do
    value = deadline - now()
    assert value > 0, "Owned shared active-turn deadline"
    min(value, 5_000)
  end

  defp call(profile, pid, method, params, timeout_ms \\ 5_000) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: timeout_ms)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.drop(Map.get(profile, :capture_start, 0))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] == method))

  defp schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_native(pid, connection, identity) do
    assert :ok = StdioSessionFixture.close(pid, connection)
    close_transport(connection, identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id,
    do: "owned-v417-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
