defmodule SamgitaCodexDriver.NativeSubagentHookTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/subagent_hook_fixture.py", __DIR__)
  @script_sha "23580ce78bd11659e5062e6822b40dc904c04153c23a6c0dfd410a929e7e352c"
  @response_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @root_marker "OWNED_V495_HOOK_ROOT"
  @child_marker "OWNED_V495_HOOK_CHILD"
  @child_path "/root/hook_child"
  @spawn "owned-v495-spawn-hook-child"
  @wait "owned-v495-wait-hook-child"
  @child_answer "Owned V495 child hook answer"
  @root_answer "Owned V495 root hook answer"
  @status_message "Owned ordinary subagent hook λ🙂"
  @lifecycle ~w(turn/started hook/started hook/completed item/started item/completed turn/completed)

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

    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        record = %{direction: direction, encoded: encoded}

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

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha

    assert hash(File.read!(Path.join(Path.dirname(@script), "model_fixture.py"))) ===
             @response_sha

    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-subagent-hook-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
          Path.join(Path.dirname(@script), "model_fixture.py"),
          Path.join(root, "codex/models.json")
        ],
        &{&1, File.read!(&1)}
      )

    %{profile: profile, provider: provider, originals: originals}
  end

  test "native successful child emits original SubagentStart and SubagentStop pairs", ctx do
    assert Enum.slice(schema()["definitions"]["HookEventName"]["enum"], 8, 2) ===
             ["subagentStart", "subagentStop"]

    session = start_native(ctx.profile)
    profile = Map.put(ctx.profile, :generation, Session.status(session.pid).generation)
    configure_owned_hooks(profile, session.pid)
    configured = File.read!(Path.join(profile.root, "codex/config.toml"))
    assert read_json(profile, "requests.json") === []
    assert invocation_paths(profile) === []

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
    lower = System.system_time(:millisecond)
    deadline = now() + 20_000

    root_turn =
      call(profile, session.pid, "turn/start", %{
        "threadId" => root,
        "effort" => "medium",
        "input" => [%{"type" => "text", "text" => @root_marker}]
      })["turn"]["id"]

    events = await_ready(profile, session.pid, [], min(deadline, now() + 5_000))
    ready_upper = System.system_time(:millisecond)

    # Resolve the generated child UUID independently of hook/activity payloads.
    page =
      call(profile, session.pid, "thread/list", %{
        "parentThreadId" => root,
        "sortKey" => "created_at",
        "limit" => 100,
        "useStateDbOnly" => true
      })

    assert [child] = page["data"]
    assert page["nextCursor"] === nil
    child_id = child["id"]
    assert is_binary(child_id) and byte_size(child_id) > 0 and child_id != root
    assert child["parentThreadId"] === root and child["forkedFromId"] === nil
    assert child["cwd"] === profile.workspace and child["modelProvider"] === "fixture"
    assert %{"subAgent" => %{"thread_spawn" => child_source}} = child["source"]
    assert child_source["parent_thread_id"] === root and child_source["depth"] === 1
    assert child_source["agent_path"] === @child_path
    [child_request] = Enum.filter(read_json(profile, "requests.json"), &(&1["kind"] === "child"))
    assert child_request["thread_id"] === child_id
    child_turn = child_request["turn_id"]
    assert is_binary(child_turn) and byte_size(child_turn) > 0 and child_turn != root_turn
    assert_start_pair(profile, events, child_id, child_turn, lower, ready_upper)
    start_record = assert_invocation(profile, "SubagentStart", root, child_id, child_turn)
    assert invocation_paths(profile) === [invocation_path(profile, "SubagentStart")]
    refute terminal?(events, child_id, child_turn)
    refute terminal?(events, root, root_turn)

    # Only the local model response is released. Codex alone finishes its child,
    # runs the Stop command, sends the child result and completes the root.
    assert {:ok, _} = Stdio.send(ctx.provider.transport, "release")

    events =
      await_finished(
        profile,
        session.pid,
        events,
        [{child_id, child_turn}, {root, root_turn}],
        min(deadline, now() + 5_000)
      )

    upper = System.system_time(:millisecond)
    assert_lifecycle(profile, events, child_id, child_turn, lower, upper)

    assert assert_invocation(profile, "SubagentStart", root, child_id, child_turn) ===
             start_record

    stop_record = assert_invocation(profile, "SubagentStop", root, child_id, child_turn)
    assert start_record.record["pid"] != stop_record.record["pid"]

    assert invocation_paths(profile) ===
             Enum.sort(
               for name <- ~w(SubagentStart SubagentStop),
                   do: invocation_path(profile, name)
             )

    assert_child_history(profile, session.pid, child_id, child_turn)
    assert_root_activity(events, root, root_turn, child_id)
    assert_provider(profile, root, root_turn, child_id, child_turn, false)

    assert call(profile, session.pid, "thread/read", %{"threadId" => root})["thread"]["id"] ===
             root

    events = drain(profile, session.pid, events)
    assert_lifecycle(profile, events, child_id, child_turn, lower, upper)
    assert now() < deadline, "Owned subagent hook journey deadline"
    assert_ready(session.pid)
    assert_frozen(ctx, configured)
    assert_originals(profile, events)
    close_native(session.pid, session.connection, session.identity)
    close_provider(ctx.provider, profile)

    assert assert_invocation(profile, "SubagentStart", root, child_id, child_turn) ===
             start_record

    assert assert_invocation(profile, "SubagentStop", root, child_id, child_turn) === stop_record

    assert invocation_paths(profile) ===
             Enum.sort(
               for name <- ~w(SubagentStart SubagentStop),
                   do: invocation_path(profile, name)
             )

    assert_provider(profile, root, root_turn, child_id, child_turn, true)
    assert_frozen(ctx, configured)
    methods = for record <- capture(profile), record.direction == :out, do: record.wire["method"]

    assert methods ===
             ~w(initialize initialized server/diagnostics hooks/list config/batchWrite thread/start turn/start thread/list thread/read thread/read)
  end

  defp configure_owned_hooks(profile, pid) do
    [entry] = call(profile, pid, "hooks/list", %{"cwds" => [profile.workspace]})["data"]
    assert entry["cwd"] === profile.workspace
    assert entry["errors"] === [] and entry["warnings"] === []
    hooks = entry["hooks"]
    assert Enum.map(hooks, & &1["eventName"]) === ["subagentStart", "subagentStop"]
    commands = read_json(profile, "hook-definition.json")

    for {{name, command_name}, index} <-
          Enum.with_index([{"subagentStart", "SubagentStart"}, {"subagentStop", "SubagentStop"}]) do
      hook = Enum.at(hooks, index)

      expected = %{
        "eventName" => name,
        "handlerType" => "command",
        "command" => commands[command_name],
        "async" => false,
        "timeoutSec" => 1,
        "sourcePath" => Path.join(profile.root, "codex/config.toml"),
        "source" => "user",
        "displayOrder" => index,
        "statusMessage" => @status_message
      }

      assert Map.take(hook, Map.keys(expected)) === expected
    end

    # Positive owned fixture configuration, following the existing ordinary
    # Interrupt fixture. No alternate trust/policy or permission behavior.
    state =
      Map.new(hooks, fn hook ->
        {Map.fetch!(hook, "key"),
         %{"trusted_hash" => Map.fetch!(hook, "currentHash"), "enabled" => true}}
      end)

    call(profile, pid, "config/batchWrite", %{
      "edits" => [%{"keyPath" => "hooks.state", "value" => state, "mergeStrategy" => "upsert"}],
      "reloadUserConfig" => true
    })
  end

  defp assert_start_pair(profile, events, child, turn, lower, upper) do
    [started, completed] = hooks(events)

    assert started.wire["method"] === "hook/started" and
             completed.wire["method"] === "hook/completed"

    assert started.sequence < completed.sequence
    assert_hook(profile, started, child, turn, {"subagentStart", 0}, "running", lower, upper)
    assert_hook(profile, completed, child, turn, {"subagentStart", 0}, "completed", lower, upper)
    # Root tool notices may still arrive while its wait begins. Compare the
    # fully observed hook family here; both thread terminals later bound the
    # complete lifecycle ledger comparison.
    originals =
      for record <- capture(profile),
          record.direction === :in and record.wire["method"] in ~w(hook/started hook/completed),
          do: record

    assert Enum.map(originals, & &1.wire) === Enum.map(hooks(events), & &1.wire)

    for {original, event} <- Enum.zip(originals, hooks(events)),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp assert_lifecycle(profile, events, child, turn, lower, upper) do
    [start, started, stop, stopped] = hooks(events)

    assert Enum.map([start, started, stop, stopped], & &1.wire["method"]) ===
             ~w(hook/started hook/completed hook/started hook/completed)

    assert_hook(profile, start, child, turn, {"subagentStart", 0}, "running", lower, upper)
    assert_hook(profile, started, child, turn, {"subagentStart", 0}, "completed", lower, upper)
    assert_hook(profile, stop, child, turn, {"subagentStop", 1}, "running", lower, upper)
    assert_hook(profile, stopped, child, turn, {"subagentStop", 1}, "completed", lower, upper)

    [turn_started] =
      Enum.filter(
        events,
        &child_event?(&1, "turn/started", child, turn)
      )

    [turn_completed] =
      Enum.filter(
        events,
        &child_event?(&1, "turn/completed", child, turn)
      )

    [answer] =
      Enum.filter(
        events,
        &(child_event?(&1, "item/completed", child, turn) and
            get_in(&1.wire, ["params", "item", "type"]) === "agentMessage")
      )

    assert turn_started.wire["params"]["turn"]["status"] === "inProgress"
    assert turn_completed.wire["params"]["turn"]["status"] === "completed"
    assert answer.wire["params"]["item"]["text"] === @child_answer
    selected = [turn_started, start, started, answer, stop, stopped, turn_completed]
    sequences = Enum.map(selected, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))

    for event <- selected do
      emitted = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted) and lower <= emitted and emitted <= upper
      assert :ok = Schema.validate(schema(), event.wire, max_depth: 32)
    end

    assert_originals(profile, events)
  end

  defp child_event?(event, method, child, turn),
    do:
      event.wire["method"] === method and
        event.wire["params"]["threadId"] === child and event_turn(event) === turn

  defp hooks(events),
    do: Enum.filter(events, &(&1.wire["method"] in ~w(hook/started hook/completed)))

  defp event_turn(event),
    do: event.wire["params"]["turnId"] || get_in(event.wire, ["params", "turn", "id"])

  defp terminal?(events, thread, turn) do
    Enum.any?(
      events,
      &(&1.wire["method"] === "turn/completed" and
          &1.wire["params"]["threadId"] === thread and event_turn(&1) === turn)
    )
  end

  defp assert_child_history(profile, pid, child, turn) do
    thread =
      call(profile, pid, "thread/read", %{"threadId" => child, "includeTurns" => true})["thread"]

    assert thread["id"] === child
    assert [%{"id" => ^turn, "status" => "completed"} = actual] = thread["turns"]
    [answer] = Enum.filter(actual["items"], &(&1["type"] === "agentMessage"))
    assert answer["text"] === @child_answer
  end

  defp assert_root_activity(events, root, turn, child) do
    [activity] =
      Enum.filter(
        events,
        &(&1.wire["method"] === "item/completed" and
            &1.wire["params"]["threadId"] === root and event_turn(&1) === turn and
            get_in(&1.wire, ["params", "item", "type"]) === "subAgentActivity" and
            get_in(&1.wire, ["params", "item", "kind"]) === "started")
      )

    assert activity.wire["params"]["item"] === %{
             "type" => "subAgentActivity",
             "id" => @spawn,
             "kind" => "started",
             "agentThreadId" => child,
             "agentPath" => @child_path,
             "model" => "mock-model",
             "reasoningEffort" => "medium"
           }

    [answer] =
      Enum.filter(
        events,
        &(&1.wire["method"] === "item/completed" and
            &1.wire["params"]["threadId"] === root and event_turn(&1) === turn and
            get_in(&1.wire, ["params", "item", "type"]) === "agentMessage")
      )

    assert answer.wire["params"]["item"]["text"] === @root_answer
  end

  defp assert_hook(profile, event, thread, turn, {name, order}, status, lower, upper) do
    actual = event.wire["params"]["run"]
    started = Map.fetch!(actual, "startedAt")
    assert_seconds(started, lower, upper)

    {completed, duration} =
      if status == "running" do
        {nil, nil}
      else
        completed = Map.fetch!(actual, "completedAt")
        duration = Map.fetch!(actual, "durationMs")
        assert_seconds(completed, lower, upper)
        assert completed >= started
        assert is_integer(duration) and duration >= 0 and duration <= upper - lower
        {completed, duration}
      end

    source = Path.join(profile.root, "codex/config.toml")

    expected = %{
      "id" =>
        "#{if name == "subagentStart", do: "subagent-start", else: "subagent-stop"}:#{order}:#{source}",
      "eventName" => name,
      "handlerType" => "command",
      "executionMode" => "sync",
      "scope" => if(name == "subagentStart", do: "thread", else: "turn"),
      "sourcePath" => source,
      "source" => "user",
      "displayOrder" => order,
      "status" => status,
      "statusMessage" => @status_message,
      "startedAt" => started,
      "completedAt" => completed,
      "durationMs" => duration,
      "entries" => []
    }

    assert_notice(
      profile,
      event,
      %{"threadId" => thread, "turnId" => turn, "run" => expected},
      lower,
      upper
    )
  end

  defp assert_notice(profile, event, params, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === profile.generation

    assert event.wire === %{
             "method" => event.wire["method"],
             "params" => params,
             "emittedAtMs" => emitted
           }

    assert :ok = Schema.validate(schema(), event.wire, max_depth: 32)
  end

  defp assert_seconds(value, lower, upper),
    do: assert(is_integer(value) and div(lower, 1000) <= value and value <= div(upper, 1000))

  defp invocation_path(profile, event), do: Path.join(profile.root, "#{event}-invocation.json")

  defp invocation_paths(profile),
    do: Enum.sort(Path.wildcard(Path.join(profile.root, "*-invocation.json")))

  defp assert_invocation(profile, event, root, child, turn) do
    body = File.read!(invocation_path(profile, event))
    assert byte_size(body) <= 4096
    record = JSON.decode!(body)
    native = Map.fetch!(record, "pid")
    assert is_integer(native) and native > 0

    expected = %{
      "hook_event_name" => event,
      "session_id" => root,
      "turn_id" => turn,
      "cwd" => profile.workspace,
      "model" => "mock-model",
      "agent_id" => child,
      "agent_type" => "default",
      "pid" => native,
      "marker" => @status_message
    }

    expected =
      if event === "SubagentStop",
        do:
          Map.merge(expected, %{
            "stop_hook_active" => false,
            "last_assistant_message" => @child_answer
          }),
        else: expected

    assert record === expected
    refute File.exists?("/proc/#{native}")
    %{bytes: body, record: record}
  end

  defp assert_provider(profile, root, root_turn, child, child_turn, closed) do
    requests = read_json(profile, "requests.json")
    assert length(requests) === 4
    assert Enum.map(requests, & &1["index"]) === [1, 2, 3, 4]
    roots = Enum.filter(requests, &(&1["kind"] === "root"))
    children = Enum.filter(requests, &(&1["kind"] === "child"))
    assert Enum.map(roots, & &1["step"]) === [1, 2, 3]
    assert [child_request] = children

    for request <- requests do
      size = Map.fetch!(request, "bytes")
      assert is_integer(size) and size > 0 and size <= 1_048_576
      assert request["model"] === "mock-model" and request["effort"] === "medium"

      assert Enum.sort(Map.keys(request)) ===
               Enum.sort(
                 ~w(index kind step thread_id turn_id model effort bytes pre_present post_present tool_outputs message)
               )
    end

    assert_root_requests(roots, root, root_turn)
    assert_child_request(child_request, child, child_turn)
    assert_provider_state(profile, closed)
  end

  defp assert_root_requests(roots, root, root_turn) do
    for request <- roots do
      assert request["thread_id"] === root and request["turn_id"] === root_turn
    end

    [first, second, third] = roots

    assert first["tool_outputs"] === %{} and first["pre_present"] === false and
             first["post_present"] === false

    assert first["message"] === nil and second["message"] === nil
    assert second["tool_outputs"] === %{@spawn => %{"task_name" => @child_path}}
    assert second["pre_present"] in [false, true]
    assert second["post_present"] === false

    assert third["tool_outputs"] === %{
             @spawn => %{"task_name" => @child_path},
             @wait => %{"message" => "Wait completed.", "timed_out" => false}
           }

    assert third["pre_present"] === true and third["post_present"] === true

    assert third["message"] ===
             "Message Type: FINAL_ANSWER\nTask name: /root\nSender: /root/hook_child\nPayload:\n" <>
               @child_answer
  end

  defp assert_child_request(child_request, child, child_turn) do
    assert child_request["thread_id"] === child and child_request["turn_id"] === child_turn
    assert child_request["step"] === 1 and child_request["tool_outputs"] === %{}
    assert child_request["pre_present"] === true and child_request["post_present"] === false

    assert child_request["message"] ===
             "Message Type: NEW_TASK\nTask name: /root/hook_child\nSender: /root\nPayload:\n" <>
               @child_marker
  end

  defp assert_provider_state(profile, closed) do
    state = read_json(profile, "provider-state.json")
    assert state["root_requests"] === 3 and state["child_requests"] === 1
    assert state["errors"] === [] and state["child_held"] === true and state["released"] === true
    assert state["closed"] === closed

    if closed,
      do:
        assert(
          state === %{
            "root_requests" => 3,
            "child_requests" => 1,
            "finished_handlers" => 4,
            "child_held" => true,
            "released" => true,
            "errors" => [],
            "closed" => true
          }
        )
  end

  defp await_ready(profile, pid, events, deadline) do
    assert now() < deadline, "Owned subagent hook readiness deadline"
    events = drain(profile, pid, events)
    state = read_json(profile, "provider-state.json")
    assert state["errors"] === []
    assert state["released"] === false
    assert state["child_requests"] <= 1 and state["root_requests"] <= 2

    if state["child_held"] and state["root_requests"] === 2 and length(hooks(events)) === 2 do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected child startup gap")
      after
        min(max(deadline - now(), 0), 10) -> :ok
      end

      await_ready(profile, pid, events, deadline)
    end
  end

  defp await_finished(profile, pid, events, turns, deadline) do
    assert now() < deadline, "Owned subagent hook terminal deadline"
    events = drain(profile, pid, events)
    assert read_json(profile, "provider-state.json")["errors"] === []

    if Enum.all?(turns, fn {thread, turn} -> terminal?(events, thread, turn) end) do
      for {thread, turn} <- turns do
        [event] =
          Enum.filter(
            events,
            &(&1.wire["method"] === "turn/completed" and
                &1.wire["params"]["threadId"] === thread and event_turn(&1) === turn)
          )

        assert event.wire["params"]["turn"]["status"] === "completed"
      end

      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected child terminal gap")
      after
        min(max(deadline - now(), 0), 10) -> :ok
      end

      await_finished(profile, pid, events, turns, deadline)
    end
  end

  defp drain(profile, pid, events) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert Enum.all?(
             events,
             &(&1.kind === :notification and &1.generation === profile.generation)
           )

    refute Enum.any?(events, &(&1.wire["method"] == "error"))
    assert_ready(pid)
    events
  end

  defp assert_ready(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
  end

  defp assert_originals(profile, events) do
    originals =
      for record <- capture(profile),
          record.direction == :in and record.wire["method"] in @lifecycle,
          do: record

    selected = Enum.filter(events, &(&1.wire["method"] in @lifecycle))
    assert Enum.map(originals, & &1.wire) === Enum.map(selected, & &1.wire)

    for {original, event} <- Enum.zip(originals, selected),
        do: assert(JSON.decode!(original.encoded) === event.wire)
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
    provider = %{transport: transport, identity: identity}
    on_exit(fn -> close_provider(provider, profile) end)
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(profile.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    provider
  end

  defp provider_startup(port, buffer, deadline) do
    assert now() < deadline, "Owned subagent hook provider startup deadline"

    receive do
      {^port, {:data, bytes}} ->
        provider_line(port, buffer <> bytes, deadline)

      {^port, {:exit_status, status}} ->
        flunk("Owned subagent hook provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned subagent hook provider startup output")
      [_partial] -> provider_startup(port, buffer, deadline)
    end
  end

  defp start_native(profile) do
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
    info = %{"name" => "owned_subagent_hook", "version" => "0.1.0"}

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
    %{pid: pid, connection: connection, identity: identity}
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

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp read_json(profile, name) do
    body = File.read!(Path.join(profile.root, name))
    assert byte_size(body) <= 2_097_152
    JSON.decode!(body)
  end

  defp assert_frozen(ctx, configured) do
    assert File.ls!(ctx.profile.workspace) === []
    assert Enum.all?(ctx.originals, fn {path, bytes} -> File.read!(path) === bytes end)
    assert File.read!(Path.join(ctx.profile.root, "codex/config.toml")) === configured
    assert hash(File.read!(@script)) === @script_sha
  end

  defp close_native(pid, connection, identity) do
    assert :ok = StdioSessionFixture.close(pid, connection)
    close_transport(connection, identity)
  end

  defp close_provider(provider, profile) do
    if Port.info(provider.transport.port) != nil,
      do: Stdio.send(provider.transport, "stop")

    close_transport(provider.transport, provider.identity)

    for path <- invocation_paths(profile) do
      body = File.read!(path)
      assert byte_size(body) <= 4096
      native = JSON.decode!(body)["pid"]
      if is_integer(native), do: refute(File.exists?("/proc/#{native}"))
    end
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
    do: "owned-subagent-hook-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
