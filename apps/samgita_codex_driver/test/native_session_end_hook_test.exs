defmodule SamgitaCodexDriver.NativeSessionEndHookTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/session_end_hook_fixture.py", __DIR__)
  @script_sha "e5476fa1c3f5d07228ad6c384a9d27cf40e98ff92e3a1acc41f30672b2cea00f"
  @response_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @first "OWNED_V494_RETAINED_FIRST"
  @second "OWNED_V494_REVERTED_SECOND"
  @followup "OWNED_V494_AFTER_REVERT"
  @status_message "Owned ordinary SessionEnd λ🙂"
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
        "samgita-session-end-hook-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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

  test "native root runtime replacement emits the exact successful SessionEnd pair", ctx do
    assert Enum.at(schema()["definitions"]["HookEventName"]["enum"], 6) === "sessionEnd"
    session = start_native(ctx.profile)
    profile = Map.put(ctx.profile, :generation, Session.status(session.pid).generation)
    configure_owned_hook(profile, session.pid)
    configured = File.read!(Path.join(profile.root, "codex/config.toml"))
    assert read_json(profile, "requests.json") === []
    assert invocation_paths(profile) === []

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
    deadline = now() + 20_000
    first = start_turn(profile, session.pid, thread, @first)
    events = await_finished(profile, session.pid, [], first, min(deadline, now() + 5_000))
    second = start_turn(profile, session.pid, thread, @second)
    events = await_finished(profile, session.pid, events, second, min(deadline, now() + 5_000))
    first_row = row(events, thread, first, @first, 1)
    second_row = row(events, thread, second, @second, 2)
    assert_history(profile, session.pid, thread, [first_row, second_row])
    assert invocation_paths(profile) === []
    assert hooks(events) === []

    lower = System.system_time(:millisecond)
    # The RPC acknowledgement alone is not the lifecycle proof. Original native
    # hook events and an independently written process record are checked below.
    reverted =
      call(profile, session.pid, "thread/revert", %{
        "threadId" => thread,
        "beforeTurnId" => second
      })

    upper = System.system_time(:millisecond)
    assert reverted["thread"]["id"] === thread and reverted["thread"]["turns"] === []
    assert is_binary(Map.fetch!(reverted, "turnsBackwardsCursor"))
    assert is_binary(Map.fetch!(reverted, "itemsBackwardsCursor"))
    events = drain(profile, session.pid, events)
    assert_pair(profile, events, thread, [first, second], lower, upper)
    first_record = assert_invocation(profile, 0, thread)
    assert invocation_paths(profile) === [invocation_path(profile, 0)]
    assert_history(profile, session.pid, thread, [first_row])
    assert length(read_json(profile, "requests.json")) === 2

    followup = start_turn(profile, session.pid, thread, @followup)
    events = await_finished(profile, session.pid, events, followup, min(deadline, now() + 5_000))
    followup_row = row(events, thread, followup, @followup, 3)
    assert_history(profile, session.pid, thread, [first_row, followup_row])
    events = drain(profile, session.pid, events)
    assert_pair(profile, events, thread, [first, second, followup], lower, upper)
    assert assert_invocation(profile, 0, thread) === first_record
    assert invocation_paths(profile) === [invocation_path(profile, 0)]
    assert_provider(profile, thread, first, second, followup, false)
    assert now() < deadline, "Owned SessionEnd replacement journey deadline"
    assert_ready(session.pid)
    assert_frozen(ctx, configured)
    assert_originals(profile, events)

    # Closing the replacement may cause a second genuine SessionEnd. Account for
    # that separately; closing stdio cannot qualify another delivered wire pair.
    close_native(session.pid, session.connection, session.identity)
    assert_cleanup_invocations(profile, thread, first_record)
    close_provider(ctx.provider, profile)
    assert_provider(profile, thread, first, second, followup, true)
    assert_frozen(ctx, configured)

    methods = for record <- capture(profile), record.direction == :out, do: record.wire["method"]

    assert methods ===
             ~w(initialize initialized server/diagnostics hooks/list config/batchWrite thread/start turn/start turn/start thread/read thread/revert thread/read turn/start thread/read)
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

  defp configure_owned_hook(profile, pid) do
    [entry] = call(profile, pid, "hooks/list", %{"cwds" => [profile.workspace]})["data"]
    assert entry["cwd"] === profile.workspace
    assert entry["errors"] === [] and entry["warnings"] === []
    [hook] = entry["hooks"]

    expected = %{
      "eventName" => "sessionEnd",
      "handlerType" => "command",
      "command" => read_json(profile, "hook-definition.json")["command"],
      "async" => false,
      "timeoutSec" => 1,
      "sourcePath" => Path.join(profile.root, "codex/config.toml"),
      "source" => "user",
      "displayOrder" => 0,
      "statusMessage" => @status_message
    }

    assert Map.take(hook, Map.keys(expected)) === expected
    # Existing positive owned fixture activation only; no alternate policy,
    # trust-state, permission, approval or authentication behavior is exercised.
    state = %{
      Map.fetch!(hook, "key") => %{
        "trusted_hash" => Map.fetch!(hook, "currentHash"),
        "enabled" => true
      }
    }

    call(profile, pid, "config/batchWrite", %{
      "edits" => [%{"keyPath" => "hooks.state", "value" => state, "mergeStrategy" => "upsert"}],
      "reloadUserConfig" => true
    })
  end

  defp assert_pair(profile, events, thread, user_turns, lower, upper) do
    [started, completed] = hooks(events)
    assert started.wire["method"] === "hook/started"
    assert completed.wire["method"] === "hook/completed"
    turn = Map.fetch!(started.wire["params"], "turnId")
    assert is_binary(turn) and Regex.match?(~r/\Aauto-compact-[0-9]+\z/, turn)
    refute turn in user_turns
    assert completed.wire["params"]["turnId"] === turn
    assert started.sequence < completed.sequence
    assert_hook(profile, started, thread, turn, "running", lower, upper)
    assert_hook(profile, completed, thread, turn, "completed", lower, upper)
    assert_originals(profile, events)

    records = capture(profile)

    [request] =
      Enum.filter(records, &(&1.direction == :out and &1.wire["method"] == "thread/revert"))

    [response] =
      Enum.filter(records, &(&1.direction == :in and &1.wire["id"] == request.wire["id"]))

    position = fn record -> Enum.find_index(records, &(&1 === record)) end

    [native_started, native_completed] =
      Enum.filter(records, fn record ->
        record.direction === :in and record.wire["method"] in ~w(hook/started hook/completed)
      end)

    assert position.(request) < position.(native_started)
    assert position.(native_started) < position.(native_completed)
    assert position.(native_completed) < position.(response)
  end

  defp hooks(events),
    do: Enum.filter(events, &(&1.wire["method"] in ~w(hook/started hook/completed)))

  defp event_turn(event),
    do: event.wire["params"]["turnId"] || get_in(event.wire, ["params", "turn", "id"])

  defp row(events, thread, turn, text, index) do
    selected =
      for event <- events,
          event.wire["method"] === "item/completed" and
            event.wire["params"]["threadId"] === thread and
            event.wire["params"]["turnId"] === turn,
          do: event.wire["params"]["item"]

    assert Enum.map(selected, & &1["type"]) === ["userMessage", "agentMessage"]
    [user, assistant] = selected

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => text}
           ]

    assert assistant["text"] === "Owned SessionEnd answer #{index}"
    assert is_binary(user["id"]) and byte_size(user["id"]) > 0
    assert is_binary(assistant["id"]) and byte_size(assistant["id"]) > 0

    %{
      id: turn,
      user: user["id"],
      assistant: assistant["id"],
      text: text,
      answer: assistant["text"]
    }
  end

  defp assert_history(profile, pid, thread, expected) do
    native =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert native["id"] === thread
    assert Enum.map(native["turns"], & &1["id"]) === Enum.map(expected, & &1.id)

    for {turn, row} <- Enum.zip(native["turns"], expected) do
      assert turn["status"] === "completed"
      assert Enum.map(turn["items"], & &1["type"]) === ["userMessage", "agentMessage"]
      [user, assistant] = turn["items"]
      assert user["id"] === row.user and assistant["id"] === row.assistant

      assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) ===
               [%{"type" => "text", "text" => row.text}]

      assert assistant["text"] === row.answer
    end
  end

  defp assert_hook(profile, event, thread, turn, status, lower, upper) do
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
      "id" => "session-end:0:#{source}",
      "eventName" => "sessionEnd",
      "handlerType" => "command",
      "executionMode" => "sync",
      "scope" => "thread",
      "sourcePath" => source,
      "source" => "user",
      "displayOrder" => 0,
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

  defp invocation_path(profile, ordinal),
    do: Path.join(profile.root, "SessionEnd-invocation-#{ordinal}.json")

  defp invocation_paths(profile),
    do: Enum.sort(Path.wildcard(Path.join(profile.root, "SessionEnd-invocation-*.json")))

  defp assert_invocation(profile, ordinal, thread) do
    path = invocation_path(profile, ordinal)
    body = File.read!(path)
    assert byte_size(body) <= 4096
    record = JSON.decode!(body)
    native = Map.fetch!(record, "pid")
    assert is_integer(native) and native > 0

    assert record === %{
             "hook_event_name" => "SessionEnd",
             "session_id" => thread,
             "cwd" => profile.workspace,
             "reason" => "other",
             "pid" => native,
             "marker" => @status_message,
             "ordinal" => ordinal
           }

    refute File.exists?("/proc/#{native}")
    %{bytes: body, record: record}
  end

  defp assert_cleanup_invocations(profile, thread, first) do
    assert assert_invocation(profile, 0, thread) === first
    paths = invocation_paths(profile)
    assert length(paths) in [1, 2]
    expected_paths = for ordinal <- 0..(length(paths) - 1), do: invocation_path(profile, ordinal)
    assert paths === expected_paths

    records =
      for ordinal <- 0..(length(paths) - 1), do: assert_invocation(profile, ordinal, thread)

    assert length(Enum.uniq(Enum.map(records, & &1.record["pid"]))) === length(records)
    # A possible second record belongs to the final replacement shutdown. Only
    # the first, fully observed revert pair establishes native wire coverage.
  end

  defp assert_provider(profile, thread, first, second, followup, closed) do
    requests = read_json(profile, "requests.json")
    assert length(requests) === 3

    expected = [
      {first, [@first], 0},
      {second, [@first, @second], 0},
      {followup, [@first, @followup], 1}
    ]

    for {{request, {turn, markers, count}}, index} <-
          Enum.with_index(Enum.zip(requests, expected), 1) do
      size = Map.fetch!(request, "bytes")
      assert is_integer(size) and size > 0 and size <= 1_048_576

      assert request === %{
               "index" => index,
               "model" => "mock-model",
               "bytes" => size,
               "thread_id" => thread,
               "turn_id" => turn,
               "markers" => markers,
               "hook_invocations" => count
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

  defp await_finished(profile, pid, events, turn, deadline) do
    assert now() < deadline, "Owned SessionEnd terminal deadline"
    events = drain(profile, pid, events)
    target = turn

    terminals =
      Enum.filter(events, fn event ->
        target != nil and event.wire["method"] === "turn/completed" and
          event_turn(event) === target
      end)

    if terminals != [] do
      [completed] = terminals
      assert completed.wire["params"]["turn"]["status"] === "completed"
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected owned SessionEnd gap")
      after
        min(max(deadline - now(), 0), 10) -> :ok
      end

      await_finished(profile, pid, events, turn, deadline)
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
    assert now() < deadline, "Owned SessionEnd provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned SessionEnd provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned SessionEnd provider startup output")
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
    info = %{"name" => "owned_session_end_hook", "version" => "0.1.0"}

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
    do: "owned-session-end-hook-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
