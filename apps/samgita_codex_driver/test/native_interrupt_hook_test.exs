defmodule SamgitaCodexDriver.NativeInterruptHookTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/interrupt_hook_fixture.py", __DIR__)
  @script_sha "f44e7ccfd880b076090ece70735582fa7512fc71541c5ec66f2721590c2cc2d4"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @marker "OWNED_V428_INTERRUPT_ROOT"
  @status_message "Owned ordinary Interrupt λ🙂"
  @lifecycle ~w(turn/started hook/started hook/completed turn/completed)

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
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-interrupt-hook-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
      Map.new([@script, Path.join(root, "codex/models.json")], &{&1, File.read!(&1)})

    %{profile: profile, provider: provider, originals: originals}
  end

  test "native root interruption emits the exact ordinary command hook pair", ctx do
    assert Enum.at(schema()["definitions"]["HookEventName"]["enum"], 11) === "interrupt"
    session = start_native(ctx.profile)
    profile = Map.put(ctx.profile, :generation, Session.status(session.pid).generation)
    configure_owned_hook(profile, session.pid)
    configured = File.read!(Path.join(profile.root, "codex/config.toml"))
    assert read_json(profile, "requests.json") === []
    refute File.exists?(Path.join(profile.root, "hook-invocation.json"))

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
    lower = System.system_time(:millisecond)
    deadline = now() + 20_000

    turn =
      call(profile, session.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0

    events =
      await_ready(profile, session.pid, thread, turn, [], min(deadline, now() + 5_000))

    interrupt_lower = System.system_time(:millisecond)

    assert call(profile, session.pid, "turn/interrupt", %{
             "threadId" => thread,
             "turnId" => turn
           }) === %{}

    events = await_terminal(profile, session.pid, events, min(deadline, now() + 5_000))
    upper = System.system_time(:millisecond)
    assert now() < deadline, "Owned Interrupt journey deadline"
    assert_provider(profile, thread, turn, false)
    assert_lifecycle(profile, events, thread, turn, lower, interrupt_lower, upper)
    assert_hook_record(profile, thread, turn)

    # A native store/query barrier and driver drain bound the observation. No
    # elapsed sleep is evidence of absence and no reconnect replays execution.
    read = call(profile, session.pid, "thread/read", %{"threadId" => thread})
    assert read["thread"]["id"] === thread
    events = drain(profile, session.pid, events)
    assert_lifecycle(profile, events, thread, turn, lower, interrupt_lower, upper)
    assert_hook_record(profile, thread, turn)
    assert_provider(profile, thread, turn, false)
    assert_ready(session.pid)
    assert_frozen(ctx, configured)
    close_native(session.pid, session.connection, session.identity)
    assert_originals(profile, events)
    close_provider(ctx.provider, profile)
    assert_provider(profile, thread, turn, true)
    assert_frozen(ctx, configured)

    methods = for record <- capture(profile), record.direction == :out, do: record.wire["method"]

    assert methods ===
             ~w(initialize initialized server/diagnostics hooks/list config/batchWrite thread/start turn/start turn/interrupt thread/read)
  end

  defp configure_owned_hook(profile, pid) do
    [entry] = call(profile, pid, "hooks/list", %{"cwds" => [profile.workspace]})["data"]
    assert entry["cwd"] === profile.workspace
    assert entry["errors"] === [] and entry["warnings"] === []
    [hook] = entry["hooks"]

    expected = %{
      "eventName" => "interrupt",
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
    # Positive fixture configuration only. No trust-status/policy assertion,
    # alternate state, changed hash, bypass or permission behavior is exercised.
    key = Map.fetch!(hook, "key")
    current_hash = Map.fetch!(hook, "currentHash")

    call(profile, pid, "config/batchWrite", %{
      "edits" => [
        %{
          "keyPath" => "hooks.state",
          "value" => %{key => %{"trusted_hash" => current_hash, "enabled" => true}},
          "mergeStrategy" => "upsert"
        }
      ],
      "reloadUserConfig" => true
    })
  end

  defp assert_lifecycle(profile, events, thread, turn, lower, interrupt_lower, upper) do
    selected = Enum.filter(events, &(&1.wire["method"] in @lifecycle))
    assert Enum.map(selected, & &1.wire["method"]) === @lifecycle
    [started, hook_started, hook_completed, finished] = selected

    assert_turn(profile, started, thread, turn, "inProgress", lower, upper)
    assert_turn(profile, finished, thread, turn, "interrupted", lower, upper)
    assert_hook(profile, hook_started, thread, turn, "running", interrupt_lower, upper)
    assert_hook(profile, hook_completed, thread, turn, "completed", interrupt_lower, upper)

    sequences = Enum.map(selected, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
    assert_originals(profile, events)
  end

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

    expected = %{
      "id" => turn,
      "rootTurnId" => turn,
      "items" => [],
      "itemsView" => "notLoaded",
      "status" => status,
      "error" => nil,
      "startedAt" => started,
      "completedAt" => completed,
      "durationMs" => duration
    }

    assert_notice(profile, event, %{"threadId" => thread, "turn" => expected}, lower, upper)
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
      "id" => "interrupt:0:#{source}",
      "eventName" => "interrupt",
      "handlerType" => "command",
      "executionMode" => "sync",
      "scope" => "turn",
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

  defp assert_hook_record(profile, thread, turn) do
    path = Path.join(profile.root, "hook-invocation.json")
    assert byte_size(File.read!(path)) <= 4096
    record = read_json(profile, "hook-invocation.json")
    native = Map.fetch!(record, "pid")
    assert is_integer(native) and native > 0

    assert record === %{
             "hook_event_name" => "Interrupt",
             "session_id" => thread,
             "turn_id" => turn,
             "cwd" => profile.workspace,
             "pid" => native,
             "marker" => @status_message
           }

    refute File.exists?("/proc/#{native}")
  end

  defp assert_provider(profile, thread, turn, released) do
    [request] = read_json(profile, "requests.json")
    size = Map.fetch!(request, "bytes")
    assert is_integer(size) and size > 0 and size <= 1_048_576

    assert request === %{
             "marker" => @marker,
             "model" => "mock-model",
             "bytes" => size,
             "thread_id" => thread,
             "turn_id" => turn
           }

    assert read_json(profile, "provider-state.json") === %{
             "requests" => 1,
             "thread_id" => thread,
             "turn_id" => turn,
             "held" => true,
             "released" => released,
             "finished_handlers" => if(released, do: 1, else: 0),
             "response_events" => [],
             "errors" => []
           }
  end

  defp await_ready(profile, pid, thread, turn, events, deadline) do
    assert now() < deadline, "Owned Interrupt native/provider readiness deadline"
    events = drain(profile, pid, events)
    state = read_json(profile, "provider-state.json")
    assert state["errors"] === []
    starts = Enum.filter(events, &(&1.wire["method"] == "turn/started"))

    if state["held"] and starts != [] do
      [started] = starts
      assert started.wire["params"]["threadId"] === thread
      assert started.wire["params"]["turn"]["id"] === turn
      assert started.wire["params"]["turn"]["status"] === "inProgress"
      assert Enum.filter(events, &(&1.wire["method"] in tl(@lifecycle))) === []
      assert_provider(profile, thread, turn, false)
      events
    else
      Process.sleep(10)
      await_ready(profile, pid, thread, turn, events, deadline)
    end
  end

  defp await_terminal(profile, pid, events, deadline) do
    assert now() < deadline, "Owned Interrupt terminal deadline"
    events = drain(profile, pid, events)

    if Enum.any?(events, &(&1.wire["method"] == "turn/completed")) do
      events
    else
      Process.sleep(10)
      await_terminal(profile, pid, events, deadline)
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
    assert now() < deadline, "Owned Interrupt provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned Interrupt provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned Interrupt provider startup output")
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
    info = %{"name" => "owned_interrupt_hook", "version" => "0.1.0"}

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
    if Port.info(provider.transport.port) != nil do
      # Signal the held handler before close can join the provider's threads.
      # The Python finally block repeats this release on every failure path.
      _result = Stdio.send(provider.transport, "release")
    end

    close_transport(provider.transport, provider.identity)
    record = Path.join(profile.root, "hook-invocation.json")

    if File.exists?(record) do
      native = read_json(profile, "hook-invocation.json")["pid"]
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
    do: "owned-interrupt-hook-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
