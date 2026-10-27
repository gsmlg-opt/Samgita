defmodule SamgitaCodexDriver.NativeMcpHookTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_hook_fixture.py", __DIR__)
  @script_sha "f91c1c2cf1af02d9aca0013f083de5b11f9440b9f6550e1cdd44303fb3c59c83"
  @response_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @seed "OWNED_V501_TOOL_TURN"
  @followup "OWNED_V501_TOOL_FOLLOWUP"
  @call_id "owned-v501-exec-call"
  @effect "Owned finite printf λ🙂\n"
  @status_message "Owned ordinary tool hook λ🙂"
  @lifecycle ~w(mcpServer/startupStatus/updated turn/started hook/started hook/completed item/started item/completed turn/completed)

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
        "samgita-mcp-hook-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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

  test "native root command invokes one synchronous MCP post observer with original hook envelopes",
       ctx do
    assert Enum.at(schema()["definitions"]["HookHandlerType"]["enum"], 1) === "mcpTool"
    session = start_native(ctx.profile)
    profile = Map.put(ctx.profile, :generation, Session.status(session.pid).generation)
    configure_owned_hooks(profile, session.pid)
    configured = File.read!(Path.join(profile.root, "codex/config.toml"))
    assert read_json(profile, "requests.json") === []
    assert mcp_journal(profile) === []

    for event <- ~w(PreToolUse PostToolUse),
        do: refute(File.exists?(Path.join(profile.root, "#{event}-invocation.json")))

    refute File.exists?(Path.join(profile.root, "command-process.json"))
    refute File.exists?(Path.join(profile.root, "printf-effect.txt"))
    deadline = now() + 20_000
    startup_lower = System.system_time(:millisecond)

    thread =
      call(profile, session.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "historyMode" => "paginated",
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    events = await_mcp_ready(profile, session.pid, thread, [], min(deadline, now() + 5_000))
    startup_upper = System.system_time(:millisecond)
    assert_mcp_startup(profile, events, thread, startup_lower, startup_upper)
    await_mcp_reply(profile, "tools/list", min(deadline, now() + 5_000))
    assert_mcp_discovery(profile)
    assert read_json(profile, "requests.json") === []
    lower = System.system_time(:millisecond)
    turn = start_turn(profile, session.pid, thread, @seed)

    events =
      await_finished(profile, session.pid, events, turn, min(deadline, now() + 5_000), true)

    upper = System.system_time(:millisecond)
    assert_lifecycle(profile, events, thread, turn, lower, upper)
    assert_hook_records(profile, thread, turn)
    await_mcp_reply(profile, "tools/call", min(deadline, now() + 5_000))
    assert_mcp_records(profile, thread, turn, false)
    followup = start_turn(profile, session.pid, thread, @followup)

    events =
      await_finished(profile, session.pid, events, followup, min(deadline, now() + 5_000), false)

    assert now() < deadline, "Owned MCP hook journey deadline"
    assert_provider(profile, thread, turn, followup, false)

    assert call(profile, session.pid, "thread/read", %{"threadId" => thread})["thread"]["id"] ===
             thread

    events = drain(profile, session.pid, events)
    assert_lifecycle(profile, events, thread, turn, lower, upper)
    assert_mcp_startup(profile, events, thread, startup_lower, startup_upper)

    assert length(Enum.filter(events, &(&1.wire["method"] in ~w(hook/started hook/completed)))) ===
             4

    assert_hook_records(profile, thread, turn)
    assert_mcp_records(profile, thread, turn, false)
    assert_ready(session.pid)
    assert_frozen(ctx, configured)
    close_native(session.pid, session.connection, session.identity)
    await_mcp_gone(profile, now() + 5_000)
    assert_originals(profile, events)
    close_provider(ctx.provider, profile)
    assert_mcp_records(profile, thread, turn, true)
    assert_provider(profile, thread, turn, followup, true)
    assert_frozen(ctx, configured)
    methods = for record <- capture(profile), record.direction == :out, do: record.wire["method"]

    assert methods ===
             ~w(initialize initialized server/diagnostics hooks/list config/batchWrite thread/start turn/start turn/start thread/read)
  end

  defp await_mcp_ready(profile, pid, thread, events, deadline) do
    assert now() < deadline, "Owned MCP hook ready deadline"
    events = drain(profile, pid, events)
    notices = Enum.filter(events, &(&1.wire["method"] === "mcpServer/startupStatus/updated"))
    assert Enum.all?(notices, &(get_in(&1.wire, ["params", "threadId"]) === thread))
    assert Enum.all?(notices, &(get_in(&1.wire, ["params", "name"]) === "owned_hook"))
    refute Enum.any?(notices, &(get_in(&1.wire, ["params", "status"]) in ["failed", "cancelled"]))

    if Enum.any?(notices, &(get_in(&1.wire, ["params", "status"]) === "ready")) do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected owned MCP startup gap")
      after
        min(max(deadline - now(), 0), 10) -> :ok
      end

      await_mcp_ready(profile, pid, thread, events, deadline)
    end
  end

  defp assert_mcp_startup(profile, events, thread, lower, upper) do
    notices = Enum.filter(events, &(&1.wire["method"] === "mcpServer/startupStatus/updated"))
    assert Enum.map(notices, & &1.wire["params"]["status"]) === ["starting", "ready"]

    for {notice, status} <- Enum.zip(notices, ["starting", "ready"]) do
      assert_notice(
        profile,
        notice,
        %{
          "threadId" => thread,
          "name" => "owned_hook",
          "status" => status,
          "error" => nil,
          "failureReason" => nil
        },
        lower,
        upper
      )
    end
  end

  defp start_turn(profile, pid, thread, marker) do
    turn =
      call(profile, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    turn
  end

  defp configure_owned_hooks(profile, pid) do
    [entry] = call(profile, pid, "hooks/list", %{"cwds" => [profile.workspace]})["data"]
    assert entry["cwd"] === profile.workspace
    assert entry["errors"] === [] and entry["warnings"] === []
    hooks = entry["hooks"]
    assert Enum.map(hooks, & &1["eventName"]) === ["preToolUse", "postToolUse"]
    commands = read_json(profile, "hook-definition.json")

    for {{name, command_name}, index} <-
          Enum.with_index([{"preToolUse", "PreToolUse"}, {"postToolUse", "PostToolUse"}]) do
      hook = Enum.at(hooks, index)

      common = %{
        "eventName" => name,
        "timeoutSec" => 1,
        "sourcePath" => Path.join(profile.root, "codex/config.toml"),
        "source" => "user",
        "displayOrder" => index,
        "statusMessage" => @status_message
      }

      handler =
        if name == "preToolUse" do
          %{"handlerType" => "command", "command" => commands[command_name], "async" => false}
        else
          %{"handlerType" => "mcpTool", "server" => "owned_hook", "tool" => "observe_post"}
        end

      expected = Map.merge(common, handler)
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

  defp assert_lifecycle(profile, events, thread, turn, lower, upper) do
    selected =
      Enum.filter(events, &(event_turn(&1) === turn and lifecycle_event?(&1)))

    assert Enum.frequencies_by(selected, & &1.wire["method"]) === %{
             "turn/started" => 1,
             "turn/completed" => 1,
             "hook/started" => 2,
             "hook/completed" => 2,
             "item/started" => 1,
             "item/completed" => 1
           }

    [started] = Enum.filter(selected, &(&1.wire["method"] === "turn/started"))
    [finished] = Enum.filter(selected, &(&1.wire["method"] === "turn/completed"))
    [item_started] = Enum.filter(selected, &(&1.wire["method"] === "item/started"))
    [item_completed] = Enum.filter(selected, &(&1.wire["method"] === "item/completed"))

    [pre_started, pre_completed, post_started, post_completed] =
      Enum.filter(selected, &(&1.wire["method"] in ~w(hook/started hook/completed)))

    assert_turn(profile, started, thread, turn, "inProgress", lower, upper)
    assert_turn(profile, finished, thread, turn, "completed", lower, upper)
    assert_hook(profile, pre_started, thread, turn, {"preToolUse", 0}, "running", lower, upper)

    assert_hook(
      profile,
      pre_completed,
      thread,
      turn,
      {"preToolUse", 0},
      "completed",
      lower,
      upper
    )

    assert_hook(profile, post_started, thread, turn, {"postToolUse", 1}, "running", lower, upper)

    assert_hook(
      profile,
      post_completed,
      thread,
      turn,
      {"postToolUse", 1},
      "completed",
      lower,
      upper
    )

    assert_command_pair(profile, item_started, item_completed, thread, turn, lower, upper)

    # Stored finite commands finish their public item in a separate watcher.
    # Require each native causal chain, with no invented watcher/post order.
    assert_order([started, pre_started, pre_completed, item_started])
    assert_order([item_started, post_started, post_completed, finished])
    assert_order([item_started, item_completed])
    assert_originals(profile, events)
  end

  defp lifecycle_event?(event),
    do:
      event.wire["method"] in ~w(turn/started turn/completed hook/started hook/completed) or
        (event.wire["method"] in ~w(item/started item/completed) and
           get_in(event.wire, ["params", "item", "type"]) === "commandExecution")

  defp assert_command_pair(profile, item_started, item_completed, thread, turn, lower, upper) do
    initial = item_started.wire["params"]["item"]
    final = item_completed.wire["params"]["item"]
    process = Map.fetch!(initial, "processId")
    assert is_binary(process) and byte_size(process) > 0
    assert is_binary(initial["command"]) and byte_size(initial["command"]) > 0
    assert is_list(initial["commandActions"]) and initial["commandActions"] != []
    # Presentation is schema checked; the provider, native hook stdin and real
    # command effect independently bind the exact executed command and call ID.
    common = %{
      "type" => "commandExecution",
      "id" => @call_id,
      "pluginId" => nil,
      "scriptPath" => nil,
      "command" => initial["command"],
      "cwd" => profile.workspace,
      "processId" => process,
      "source" => "unifiedExecStartup",
      "commandActions" => initial["commandActions"]
    }

    assert initial ===
             Map.merge(common, %{
               "status" => "inProgress",
               "aggregatedOutput" => nil,
               "exitCode" => nil,
               "durationMs" => nil
             })

    duration = Map.fetch!(final, "durationMs")
    assert is_integer(duration) and duration >= 0 and duration <= upper - lower

    assert final ===
             Map.merge(common, %{
               "status" => "completed",
               "aggregatedOutput" => @effect,
               "exitCode" => 0,
               "durationMs" => duration
             })

    assert_item_notices(profile, item_started, item_completed, thread, turn, lower, upper)
  end

  defp assert_item_notices(profile, item_started, item_completed, thread, turn, lower, upper) do
    initial = item_started.wire["params"]["item"]
    final = item_completed.wire["params"]["item"]
    first_at = Map.fetch!(item_started.wire["params"], "startedAtMs")
    last_at = Map.fetch!(item_completed.wire["params"], "completedAtMs")
    assert is_integer(first_at) and lower <= first_at and first_at <= upper
    assert is_integer(last_at) and first_at <= last_at and last_at <= upper

    assert_notice(
      profile,
      item_started,
      %{"threadId" => thread, "turnId" => turn, "item" => initial, "startedAtMs" => first_at},
      lower,
      upper
    )

    assert_notice(
      profile,
      item_completed,
      %{"threadId" => thread, "turnId" => turn, "item" => final, "completedAtMs" => last_at},
      lower,
      upper
    )
  end

  defp assert_order(events) do
    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
  end

  defp event_turn(event),
    do: event.wire["params"]["turnId"] || get_in(event.wire, ["params", "turn", "id"])

  defp assert_turn(profile, event, thread, turn, status, lower, upper) do
    actual = event.wire["params"]["turn"]
    started = Map.fetch!(actual, "startedAt")
    assert_seconds(started, lower, upper)

    {completed, duration} =
      if status == "inProgress" do
        {nil, nil}
      else
        completed = Map.fetch!(actual, "completedAt")
        duration = Map.fetch!(actual, "durationMs")
        assert_seconds(completed, lower, upper)
        assert completed >= started
        assert is_integer(duration) and duration >= 0 and duration <= upper - lower
        {completed, duration}
      end

    {items, view} = turn_items(status)

    expected = %{
      "id" => turn,
      "rootTurnId" => turn,
      "items" => items,
      "itemsView" => view,
      "status" => status,
      "error" => nil,
      "startedAt" => started,
      "completedAt" => completed,
      "durationMs" => duration
    }

    assert_notice(profile, event, %{"threadId" => thread, "turn" => expected}, lower, upper)
  end

  defp turn_items("inProgress"), do: {[], "notLoaded"}

  defp turn_items("completed") do
    {[
       %{
         "type" => "agentMessage",
         "id" => "fixture-message-2",
         "text" => "Owned MCP hook answer 2",
         "delivery" => nil,
         "memoryCitation" => nil,
         "phase" => nil,
         "questions" => nil
       }
     ], "summary"}
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
        "#{if name == "preToolUse", do: "pre-tool-use", else: "post-tool-use"}:#{order}:#{source}:#{@call_id}",
      "eventName" => name,
      "handlerType" => if(name == "preToolUse", do: "command", else: "mcpTool"),
      "executionMode" => "sync",
      "scope" => "turn",
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

  defp assert_hook_records(profile, thread, turn) do
    command = read_json(profile, "command-definition.json")["command"]

    records =
      for event <- ~w(PreToolUse PostToolUse) do
        path = Path.join(profile.root, "#{event}-invocation.json")
        assert byte_size(File.read!(path)) <= 4096
        record = read_json(profile, "#{event}-invocation.json")
        native = Map.fetch!(record, "pid")
        assert is_integer(native) and native > 0

        expected = %{
          "hook_event_name" => event,
          "session_id" => thread,
          "turn_id" => turn,
          "cwd" => profile.workspace,
          "model" => "mock-model",
          "tool_name" => "Bash",
          "tool_use_id" => @call_id,
          "tool_input" => %{"command" => command},
          "pid" => native,
          "marker" => @status_message
        }

        expected =
          if event == "PostToolUse",
            do: Map.put(expected, "tool_response", @effect),
            else: expected

        assert record === expected
        if event == "PreToolUse", do: refute(File.exists?("/proc/#{native}"))
        native
      end

    assert length(Enum.uniq(records)) === 2

    assert Enum.sort(Path.wildcard(Path.join(profile.root, "*-invocation.json"))) ===
             Enum.sort(
               for event <- ~w(PreToolUse PostToolUse),
                   do: Path.join(profile.root, "#{event}-invocation.json")
             )

    assert byte_size(File.read!(Path.join(profile.root, "command-process.json"))) <= 4096
    process = read_json(profile, "command-process.json")
    native = Map.fetch!(process, "pid")
    assert is_integer(native) and native > 0 and native not in records

    assert process === %{
             "pid" => native,
             "cwd" => profile.workspace,
             "tool_use_id" => @call_id,
             "pre_pid" => hd(records),
             "marker" => @effect
           }

    refute File.exists?("/proc/#{native}")
    assert File.read!(Path.join(profile.root, "printf-effect.txt")) === @effect
  end

  defp mcp_journal(profile) do
    raw = File.read!(Path.join(profile.root, "mcp-journal.jsonl"))
    assert byte_size(raw) <= 131_072
    lines = String.split(raw, "\n", trim: true)
    assert length(lines) <= 64
    assert Enum.all?(lines, &(byte_size(&1) <= 16_384))
    rows = Enum.map(lines, &JSON.decode!/1)
    refute Enum.any?(rows, &(&1["event"] === "fatal"))
    rows
  end

  defp assert_mcp_discovery(profile) do
    rows = mcp_journal(profile)
    [started] = Enum.filter(rows, &(&1["event"] === "started"))
    assert hash(File.read!("/proc/#{started["pid"]}/exe")) === hash(File.read!(profile.python))
    [reply] = Enum.filter(rows, &(&1["event"] === "reply" and &1["method"] === "tools/list"))
    assert JSON.decode!(reply["encoded"]) === reply["reply"]
    assert Enum.map(reply["reply"]["result"]["tools"], & &1["name"]) === ["observe_post"]

    refute Enum.any?(
             rows,
             &(&1["event"] === "observed" or &1["request"]["method"] === "tools/call")
           )
  end

  defp await_mcp_reply(profile, method, deadline) do
    replies =
      Enum.filter(mcp_journal(profile), &(&1["event"] === "reply" and &1["method"] === method))

    cond do
      replies != [] ->
        :ok

      now() >= deadline ->
        flunk("Owned MCP hook reply journal deadline")

      true ->
        receive do
        after
          10 -> await_mcp_reply(profile, method, deadline)
        end
    end
  end

  defp assert_mcp_records(profile, thread, turn, closed) do
    rows = mcp_journal(profile)
    [started] = Enum.filter(rows, &(&1["event"] === "started"))
    peer = started["pid"]
    assert is_integer(peer) and peer > 0

    if closed do
      refute File.exists?("/proc/#{peer}")
    else
      assert hash(File.read!("/proc/#{peer}/exe")) === hash(File.read!(profile.python))
    end

    assert Enum.all?(rows, &(&1["pid"] === peer))
    assert read_json(profile, "PostToolUse-invocation.json")["pid"] === peer
    requests = Enum.filter(rows, &(&1["event"] === "request"))
    replies = Enum.filter(rows, &(&1["event"] === "reply"))
    assert Enum.count(requests, &(&1["request"]["method"] === "initialize")) === 1
    assert Enum.count(requests, &(&1["request"]["method"] === "notifications/initialized")) === 1
    assert Enum.count(requests, &(&1["request"]["method"] === "tools/list")) === 1

    assert Enum.all?(
             requests,
             &(&1["request"]["method"] in ~w(initialize notifications/initialized tools/list resources/list resources/templates/list tools/call))
           )

    for request <- requests do
      assert JSON.decode!(request["encoded"]) === request["request"]
      assert byte_size(request["encoded"]) <= 65_536

      if Map.has_key?(request["request"], "id") do
        [reply] = Enum.filter(replies, &(&1["reply"]["id"] === request["request"]["id"]))
        assert reply["method"] === request["request"]["method"]
        assert JSON.decode!(reply["encoded"]) === reply["reply"]
        assert Enum.sort(Map.keys(reply["reply"])) === ["id", "jsonrpc", "result"]
      end
    end

    command = read_json(profile, "command-definition.json")["command"]

    expected = %{
      "hook_event_name" => "PostToolUse",
      "session_id" => thread,
      "turn_id" => turn,
      "cwd" => profile.workspace,
      "model" => "mock-model",
      "tool_name" => "Bash",
      "tool_use_id" => @call_id,
      "tool_input" => %{"command" => command},
      "tool_response" => @effect
    }

    [call] = Enum.filter(requests, &(&1["request"]["method"] === "tools/call"))
    assert call["request"]["params"]["name"] === "observe_post"
    assert call["request"]["params"]["arguments"] === expected
    assert call["request"]["params"]["_meta"]["threadId"] === thread
    [observed] = Enum.filter(rows, &(&1["event"] === "observed"))

    assert observed === %{
             "event" => "observed",
             "pid" => peer,
             "arguments" => expected,
             "effect" => @effect
           }

    [reply] = Enum.filter(replies, &(&1["method"] === "tools/call"))

    assert reply["reply"] === %{
             "jsonrpc" => "2.0",
             "id" => call["request"]["id"],
             "result" => %{"content" => [%{"type" => "text", "text" => "{}"}], "isError" => false}
           }

    # These are local peer journal append positions, not cross-transport ordering.
    indices =
      Enum.map([call, observed, reply], fn target -> Enum.find_index(rows, &(&1 === target)) end)

    assert indices === Enum.sort(Enum.uniq(indices))
  end

  defp await_mcp_gone(profile, deadline) do
    pids = for row <- mcp_journal(profile), row["event"] === "started", do: row["pid"]

    cond do
      Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) ->
        :ok

      now() >= deadline ->
        flunk("Owned MCP hook observer reaping deadline")

      true ->
        receive do
        after
          10 -> await_mcp_gone(profile, deadline)
        end
    end
  end

  defp assert_provider(profile, thread, turn, followup, closed) do
    requests = read_json(profile, "requests.json")
    assert length(requests) === 3

    expected = [
      {"tool", turn, [@seed], [], false, false},
      {"answer", turn, [@seed], [@call_id], true, true},
      {"followup", followup, [@seed, @followup], [@call_id], true, true}
    ]

    for {{request, {kind, expected_turn, markers, output_ids, pre, post}}, index} <-
          Enum.with_index(Enum.zip(requests, expected), 1) do
      size = Map.fetch!(request, "bytes")
      assert is_integer(size) and size > 0 and size <= 1_048_576

      assert request === %{
               "index" => index,
               "kind" => kind,
               "model" => "mock-model",
               "bytes" => size,
               "thread_id" => thread,
               "turn_id" => expected_turn,
               "markers" => markers,
               "output_call_ids" => output_ids,
               "pre_present" => pre,
               "post_present" => post
             }
    end

    state = read_json(profile, "provider-state.json")
    assert state["requests"] === 3 and state["errors"] === [] and state["closed"] === closed

    if closed,
      do:
        assert(
          state === %{
            "requests" => 3,
            "finished_handlers" => 3,
            "errors" => [],
            "closed" => true
          }
        )
  end

  defp await_finished(profile, pid, events, turn, deadline, settle_tool) do
    assert now() < deadline, "Owned MCP hook terminal deadline"
    assert read_json(profile, "provider-state.json")["errors"] === []
    events = drain(profile, pid, events)
    target = turn

    terminals =
      Enum.filter(events, fn event ->
        target != nil and event.wire["method"] === "turn/completed" and
          event_turn(event) === target
      end)

    if terminals != [] and (not settle_tool or tool_settled?(events, turn)) do
      [completed] = terminals
      assert completed.wire["params"]["turn"]["status"] === "completed"
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected owned MCP hook gap")
      after
        min(max(deadline - now(), 0), 10) -> :ok
      end

      await_finished(profile, pid, events, turn, deadline, settle_tool)
    end
  end

  defp tool_settled?(events, turn) do
    notices = Enum.filter(events, &(event_turn(&1) === turn))
    hook_count = Enum.count(notices, &(&1.wire["method"] in ~w(hook/started hook/completed)))

    completed =
      Enum.any?(
        notices,
        &(&1.wire["method"] === "item/completed" and
            get_in(&1.wire, ["params", "item", "type"]) === "commandExecution" and
            get_in(&1.wire, ["params", "item", "id"]) === @call_id)
      )

    # A turn terminal alone does not join the stored-command watcher. Await its
    # actual item terminal too; exact maps/counts are required after this gate.
    hook_count >= 4 and completed
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
    assert now() < deadline, "Owned MCP hook provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned MCP hook provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned MCP hook provider startup output")
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
    info = %{"name" => "owned_mcp_hook", "version" => "0.1.0"}

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

    if File.exists?(Path.join(profile.root, "command-process.json")) do
      native = read_json(profile, "command-process.json")["pid"]
      if is_integer(native), do: refute(File.exists?("/proc/#{native}"))
    end

    assert_hook_pid_gone(profile, "PreToolUse")
    await_mcp_gone(profile, now() + 5_000)
  end

  defp assert_hook_pid_gone(profile, event) do
    if File.exists?(Path.join(profile.root, "#{event}-invocation.json")) do
      native = read_json(profile, "#{event}-invocation.json")["pid"]
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
    do: "owned-mcp-hook-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
