defmodule SamgitaCodexDriver.NativeFsNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @changed "fs/changed"
  @first_id "owned-watch-first λ"
  @control_id "owned-watch-control 雪"

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

    # Capture native ingress bytes before Session decoding or projection.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)

      if ledger.count < 128 and size <= 65_536 and ledger.bytes + size <= 2_097_152 do
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
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-fs-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for child <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, child))
    workspace = Path.join(root, "workspace")
    first = Path.join(workspace, "first é🙂.txt")
    control = Path.join(workspace, "control 雪.txt")
    File.write!(first, "Owned first initial\n", [:exclusive])
    File.write!(control, "Owned control initial\n", [:exclusive])
    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
    check_for_update_on_startup = false
    allow_login_shell = false
    [analytics]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [memories]
    generate_memories = false
    use_memories = false
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    remote_models = false
    memories = false
    shell_snapshot = false
    hooks = false
    """)

    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      binary: Path.expand(binary),
      root: root,
      workspace: workspace,
      first: first,
      control: control,
      config: config,
      original_config: File.read!(config),
      capture: capture
    }

    session = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    %{profile: profile, session: session}
  end

  test "whole native fs envelopes follow actual file mutations and explicit unwatch fences",
       ctx do
    profile = ctx.profile
    session = ctx.session
    pid = session.pid
    assert {:ok, []} = Session.drain(pid, 128)
    assert_inputs(profile, "Owned first initial\n", "Owned control initial\n")

    assert {first_response, _} =
             call(profile, pid, "fs/watch", %{"watchId" => @first_id, "path" => profile.first})

    assert first_response === %{"path" => profile.first}

    assert {control_response, _} =
             call(profile, pid, "fs/watch", %{"watchId" => @control_id, "path" => profile.control})

    assert control_response === %{"path" => profile.control}
    events = drain(pid, [])
    assert events === []

    first_lower = System.system_time(:millisecond)
    File.write!(profile.first, "Owned first changed λ🙂\n")
    assert_inputs(profile, "Owned first changed λ🙂\n", "Owned control initial\n")
    first_params = %{"watchId" => @first_id, "changedPaths" => [profile.first]}
    {first, events} = await_change(pid, first_params, events, 0, now() + 5_000)
    assert_notice(profile, first, first_params, first_lower, System.system_time(:millisecond))

    {first_unwatch, first_fence} = call(profile, pid, "fs/unwatch", %{"watchId" => @first_id})
    assert first_unwatch === %{}
    first_upper = System.system_time(:millisecond)
    events = drain(pid, events)
    prior_sequence = last_sequence(events)

    # B proves the native watcher remains live after A's completed unwatch.
    control_lower = System.system_time(:millisecond)
    File.write!(profile.first, "Owned retired first changed\n")
    File.write!(profile.control, "Owned live control changed 雪\n")
    assert_inputs(profile, "Owned retired first changed\n", "Owned live control changed 雪\n")
    control_params = %{"watchId" => @control_id, "changedPaths" => [profile.control]}

    {control, events} =
      await_change(pid, control_params, events, prior_sequence, now() + 5_000)

    assert_notice(
      profile,
      control,
      control_params,
      control_lower,
      System.system_time(:millisecond)
    )

    assert first.sequence < control.sequence

    {control_unwatch, control_fence} =
      call(profile, pid, "fs/unwatch", %{"watchId" => @control_id})

    assert control_unwatch === %{}
    control_upper = System.system_time(:millisecond)
    events = drain(pid, events)
    File.write!(profile.first, "Owned first final\n")
    File.write!(profile.control, "Owned control final\n")
    assert_inputs(profile, "Owned first final\n", "Owned control final\n")
    events = quiet(pid, events, now() + 500)
    assert diagnostics(profile, pid) === session.native
    events = drain(pid, events)

    cohorts = %{
      @first_id => {first_params, first_lower, first_upper},
      @control_id => {control_params, control_lower, control_upper}
    }

    assert_events(profile, events, cohorts)
    assert_inventory(profile)
    assert Session.uncertain_operations(pid) === []
    assert Session.interaction_outcomes(pid) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    close_resources(pid, session.connection, session.identity)
    assert_originals(profile, events, %{@first_id => first_fence, @control_id => control_fence})
    assert_inventory(profile)
    assert_inputs(profile, "Owned first final\n", "Owned control final\n")
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
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => Path.join(profile.root, "home"),
                      "CODEX_HOME" => Path.join(profile.root, "codex"),
                      "TMPDIR" => Path.join(profile.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])

    on_exit(fn ->
      # Never remove the owned files/root before checked native shutdown.
      close_resources(pid, connection, identity)
      File.rm_rf!(profile.root)
    end)

    id = request_id()
    info = %{"name" => "owned_fs_notification_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

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

    native = diagnostics(profile, pid)
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, identity: identity}
  end

  defp diagnostics(profile, pid) do
    {result, _response} = call(profile, pid, "server/diagnostics", %{})
    native = result["process"]["id"]
    assert is_integer(native) and native > 0
    native
  end

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    {result, response}
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp await_change(pid, params, events, prior_sequence, deadline) do
    events = drain(pid, events)

    selected =
      Enum.find(events, fn event ->
        event.sequence > prior_sequence and event.wire["method"] == @changed and
          event.wire["params"] === params
      end)

    await_or_return(pid, params, events, prior_sequence, selected, deadline)
  end

  defp await_or_return(pid, params, events, prior_sequence, nil, deadline) do
    assert now() < deadline,
           "BLOCKED_ENV: required actual native fs/changed absent for #{inspect(params)}; " <>
             "the OS watcher must emit, registration success or a noop backend cannot pass"

    Process.sleep(10)
    await_change(pid, params, events, prior_sequence, deadline)
  end

  defp await_or_return(_pid, _params, events, _prior_sequence, selected, _deadline),
    do: {selected, events}

  defp quiet(pid, events, deadline) do
    events = drain(pid, events)

    if now() < deadline do
      Process.sleep(10)
      quiet(pid, events, deadline)
    else
      events
    end
  end

  defp drain(pid, events) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 128
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= 2_097_152
    combined
  end

  defp last_sequence(events), do: events |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)

  defp assert_notice(profile, event, params, lower, upper) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire === %{"method" => @changed, "params" => params, "emittedAtMs" => emitted_at}
    assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
  end

  defp assert_events(profile, events, cohorts) do
    assert Enum.map(events, & &1.sequence) === Enum.sort(Enum.map(events, & &1.sequence))
    assert length(Enum.uniq_by(events, & &1.sequence)) === length(events)

    for watch_id <- [@first_id, @control_id] do
      selected = Enum.filter(events, &(&1.wire["params"]["watchId"] == watch_id))
      assert selected !== []
    end

    # OS writes may produce duplicate batches; every actual batch must keep the
    # same independently prescribed complete map, within the fixed finite cap.
    for event <- events do
      assert event.wire["method"] === @changed
      {params, lower, upper} = Map.fetch!(cohorts, event.wire["params"]["watchId"])
      assert_notice(profile, event, params, lower, upper)
    end
  end

  defp assert_originals(profile, events, fences) do
    originals = capture(profile)

    notifications =
      Enum.filter(originals, &(&1.direction == :in and &1.wire["method"] == @changed))

    # Inspect after checked shutdown so late or duplicate ingress is not hidden
    # by stopping collection as soon as the selected notice was received.
    assert Enum.map(notifications, & &1.wire) === Enum.map(events, & &1.wire)

    for {watch_id, response} <- fences do
      assert [position] =
               for(
                 {record, position} <- Enum.with_index(originals),
                 record.direction == :in and record.wire === response,
                 do: position
               )

      for {record, index} <- Enum.with_index(originals),
          record.direction == :in and record.wire["method"] == @changed and
            record.wire["params"]["watchId"] == watch_id do
        assert index < position
        assert JSON.decode!(record.encoded) === record.wire
      end
    end
  end

  defp assert_inventory(profile) do
    records = capture(profile)
    outgoing = Enum.filter(records, &(&1.direction == :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics fs/watch fs/watch fs/unwatch fs/unwatch server/diagnostics)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 7
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === 7

    # Repeat pair uniqueness against final capture, including any ingress
    # arriving after the individual request initially returned.
    for request <- requests do
      assert [sent, received] = Enum.filter(records, &(&1.wire["id"] == request.wire["id"]))
      assert sent === request and received.direction === :in
      assert_exchange(profile, request.wire, received.wire)
    end

    for record <- records, record.direction == :in, Map.has_key?(record.wire, "id") do
      refute Map.has_key?(record.wire, "method")
    end

    assert length(records) <= 128
  end

  defp assert_inputs(profile, first, control) do
    for {path, contents} <- [{profile.first, first}, {profile.control, control}] do
      assert File.stat!(path).size <= 256
      assert File.read!(path) === contents
    end

    assert Enum.sort(File.ls!(profile.workspace)) ===
             Enum.sort([Path.basename(profile.first), Path.basename(profile.control)])

    assert File.stat!(profile.config).size <= 4096
    assert File.read!(profile.config) === profile.original_config
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_resources(pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id, do: "owned-fs-envelope-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
