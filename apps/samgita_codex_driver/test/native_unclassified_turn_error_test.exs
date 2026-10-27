defmodule SamgitaCodexDriver.NativeUnclassifiedTurnErrorTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/reasoning_checklist_envelope_fixture.py", __DIR__)
  @script_sha "d42e156eb535595d63140870db8414f9cde90298c349d378a1d413dd2c2ba5ff"
  @provider_base Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_base_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @marker "owned-unclassified-shell-marker.txt"
  @methods ~w(turn/started error turn/completed)

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
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Preserve original native JSONL before Session decoding or projection.
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
        "samgita-unclassified-error-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
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
    frozen = frozen_files(profile)
    session = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    %{profile: profile, provider: provider, session: session, frozen: frozen}
  end

  test "native standalone shell emits a nonnull unclassified TurnError with no selected environment",
       ctx do
    profile = ctx.profile
    pid = ctx.session.pid

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "ephemeral" => false,
        "historyMode" => "paginated",
        "environments" => []
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    lower = System.system_time(:millisecond)
    active_deadline = now() + 20_000

    assert call(profile, pid, "thread/shellCommand", %{
             "threadId" => thread,
             "command" => "printf '%s\\n' 'owned-unclassified-shell-effect' > #{@marker}",
             "timeoutMs" => 5_000
           }) === %{}

    events = collect(pid, thread, [], active_deadline)
    upper = System.system_time(:millisecond)
    [started] = notices(events, "turn/started")
    [failure] = notices(events, "error")
    [finished] = notices(events, "turn/completed")
    turn = Map.fetch!(started.wire["params"]["turn"], "id")
    assert is_binary(turn) and byte_size(turn) > 0

    expected_error = %{
      "message" => "shell is unavailable in this session",
      "codexErrorInfo" => nil,
      "additionalDetails" => nil,
      "misalignment" => nil
    }

    error_params = %{
      "threadId" => thread,
      "turnId" => turn,
      "error" => expected_error,
      "willRetry" => false
    }

    assert_notice(profile, failure, "error", error_params, lower, upper)
    assert Map.has_key?(failure.wire["params"]["error"], "codexErrorInfo")
    assert Map.fetch!(failure.wire["params"]["error"], "codexErrorInfo") === nil
    assert_lifecycle(profile, started, finished, thread, turn, expected_error, lower, upper)
    assert started.sequence < failure.sequence and failure.sequence < finished.sequence
    assert Enum.map(events, & &1.sequence) === Enum.sort(Enum.map(events, & &1.sequence))
    assert length(Enum.uniq_by(events, & &1.sequence)) === length(events)
    assert_originals(profile, [started, failure, finished])

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === profile.generation
    assert Session.uncertain_operations(pid) === []
    assert_frozen(ctx)
    close_native(pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.provider.transport, ctx.provider.identity)
    assert_frozen(ctx)
    assert_originals(profile, [started, failure, finished])

    outgoing = for record <- capture(profile), record.direction == :out, do: record.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/shellCommand)
  end

  defp assert_lifecycle(profile, started, finished, thread, turn, error, lower, upper) do
    started_at = Map.fetch!(started.wire["params"]["turn"], "startedAt")
    completed_at = Map.fetch!(finished.wire["params"]["turn"], "completedAt")
    duration_ms = Map.fetch!(finished.wire["params"]["turn"], "durationMs")

    assert is_integer(started_at) and div(lower, 1000) <= started_at and
             started_at <= div(upper, 1000)

    assert is_integer(completed_at) and started_at <= completed_at and
             completed_at <= div(upper, 1000)

    assert is_integer(duration_ms) and duration_ms >= 0 and duration_ms <= upper - lower

    started_turn = %{
      "id" => turn,
      "rootTurnId" => turn,
      "items" => [],
      "itemsView" => "notLoaded",
      "status" => "inProgress",
      "error" => nil,
      "startedAt" => started_at,
      "completedAt" => nil,
      "durationMs" => nil
    }

    completed_turn = %{
      "id" => turn,
      "rootTurnId" => turn,
      "items" => [],
      "itemsView" => "notLoaded",
      "status" => "failed",
      "error" => error,
      "startedAt" => started_at,
      "completedAt" => completed_at,
      "durationMs" => duration_ms
    }

    assert_notice(
      profile,
      started,
      "turn/started",
      %{"threadId" => thread, "turn" => started_turn},
      lower,
      upper
    )

    assert_notice(
      profile,
      finished,
      "turn/completed",
      %{"threadId" => thread, "turn" => completed_turn},
      lower,
      upper
    )
  end

  defp assert_notice(profile, event, method, params, lower, upper) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire === %{"method" => method, "params" => params, "emittedAtMs" => emitted_at}
    assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
  end

  defp collect(pid, thread, events, deadline) do
    assert now() < deadline, "Owned unclassified shell turn deadline"
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    if Enum.any?(notices(events, "turn/completed"), &(&1.wire["params"]["threadId"] == thread)) do
      events
    else
      assert Session.status(pid).phase === :ready
      Process.sleep(10)
      collect(pid, thread, events, deadline)
    end
  end

  defp start_provider(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [
                 @script,
                 "--root",
                 profile.root,
                 "--scenario",
                 "reasoning",
                 "--answer-phase",
                 "final_answer"
               ],
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
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    assert hash(File.read!(profile.python)) === hash(File.read!("/proc/#{native}/exe"))
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
    info = %{"name" => "owned_unclassified_turn_error", "version" => "0.1.0"}

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

  defp frozen_files(profile) do
    for name <- [
          "codex/config.toml",
          "codex/models.json",
          "requests.json",
          "provider-events.json"
        ],
        into: %{},
        do: {name, File.read!(Path.join(profile.root, name))}
  end

  defp assert_frozen(ctx) do
    assert frozen_files(ctx.profile) === ctx.frozen
    assert ctx.frozen["requests.json"] === "[]"
    assert ctx.frozen["provider-events.json"] === "[]"
    refute File.exists?(Path.join(ctx.profile.root, "provider-error.json"))
    refute File.exists?(Path.join(ctx.profile.workspace, @marker))
    assert File.ls!(ctx.profile.workspace) === []
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@provider_base)) === @provider_base_sha
  end

  defp assert_originals(profile, events) do
    originals =
      for record <- capture(profile),
          record.direction == :in,
          record.wire["method"] in @methods,
          do: record

    assert Enum.map(originals, & &1.wire) === Enum.map(events, & &1.wire)

    for {original, event} <- Enum.zip(originals, events),
        do: assert(JSON.decode!(original.encoded) === event.wire)
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
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] == method))

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
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
    do: "owned-unclassified-error-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
