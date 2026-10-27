defmodule SamgitaCodexDriver.NativeFuzzyNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 30_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @updated "fuzzyFileSearch/sessionUpdated"
  @completed "fuzzyFileSearch/sessionCompleted"
  @paths ~w(abc abcde abexy zzz.txt sub/abce)

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

    # Preserve original ingress bytes before Session decoding, not a JSON
    # reconstruction of the later driver event.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
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
        "samgita-fuzzy-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: Path.expand(binary), root: root}
  end

  test "whole native fuzzy notification envelopes preserve actual ranked roots and selected empty snapshots",
       ctx do
    for {id, omit} <- [
          {"owned-fuzzy-envelope-full λ", false},
          {"owned-fuzzy-envelope-subset 雪", true}
        ] do
      run_profile(ctx, id, omit)
    end
  end

  defp run_profile(ctx, id, omit) do
    profile = profile(ctx, id, omit)
    session = start(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    assert {:ok, []} = Session.drain(session.pid, 128)
    before_start = System.system_time(:millisecond)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => id,
             "roots" => [profile.tree]
           }) === %{}

    complete_params = %{"sessionId" => id}
    {idle, events} = await_notice(session.pid, @completed, complete_params, [], 0)

    assert_notice(
      profile,
      idle,
      @completed,
      complete_params,
      before_start,
      System.system_time(:millisecond)
    )

    # A completed notice means scanner idle. Actual query results, rather than
    # that notice or an RPC acknowledgement, prove the next operation's effect.
    before_query = System.system_time(:millisecond)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionUpdate", %{
             "sessionId" => id,
             "query" => "abe"
           }) === %{}

    ranked_params = %{"sessionId" => id, "query" => "abe", "files" => expected_files(profile)}
    {ranked, events} = await_notice(session.pid, @updated, ranked_params, events, idle.sequence)

    assert_notice(
      profile,
      ranked,
      @updated,
      ranked_params,
      before_query,
      System.system_time(:millisecond)
    )

    assert_inputs(profile)

    # Drain previously delivered snapshots before requesting clear. The later
    # empty snapshot has no query-generation token: a startup empty update
    # already spawned upstream could arrive late, even with a later timestamp.
    # This observes an exact empty wire value, not a causal clear/fence proof.
    events = drain(session.pid, events)
    prior_sequence = last_sequence(events)
    before_clear = System.system_time(:millisecond)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionUpdate", %{
             "sessionId" => id,
             "query" => ""
           }) === %{}

    clear_params = %{"sessionId" => id, "query" => "", "files" => []}
    {cleared, events} = await_notice(session.pid, @updated, clear_params, events, prior_sequence)

    assert_notice(
      profile,
      cleared,
      @updated,
      clear_params,
      before_clear,
      System.system_time(:millisecond)
    )

    assert cleared.sequence > ranked.sequence
    assert_original_order(profile, [idle, ranked, cleared])
    assert_inputs(profile)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => id}) === %{}
    assert diagnostics(profile, session.pid) === session.native
    events = drain(session.pid, events)
    assert_event_bounds(profile, events)
    assert_inventory(profile)
    assert Session.uncertain_operations(session.pid) === []
    assert Session.interaction_outcomes(session.pid) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    close_resources(session.pid, session.connection, session.native_identity)
    assert_inputs(profile)
  end

  defp profile(ctx, id, omit) do
    directory = if omit, do: "subset", else: "full"
    root = Path.join(ctx.root, directory)

    for child <- ~w(home codex workspace tmp search-root),
        do: File.mkdir_p!(Path.join(root, child))

    tree = Path.join(root, "search-root")
    paths = if omit, do: ~w(abc abcde zzz.txt sub/abce), else: @paths
    inputs = Map.new(paths, &{Path.join(tree, &1), "Owned fuzzy file #{&1}\n"})
    for {path, bytes} <- inputs, do: write_input(path, bytes)
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
    memories = false
    shell_snapshot = false
    """)

    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: {Agent, id})

    %{
      binary: ctx.binary,
      root: root,
      id: id,
      omit: omit,
      tree: tree,
      paths: paths,
      inputs: inputs,
      workspace: Path.join(root, "workspace"),
      config: config,
      original_config: File.read!(config),
      capture: capture
    }
  end

  defp write_input(path, bytes) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes, [:exclusive])
  end

  defp start(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
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
    on_exit(fn -> close_resources(pid, connection, identity) end)
    id = request_id()
    info = %{"name" => "owned_fuzzy_notification_envelope", "version" => "0.1.0"}

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
    %{pid: pid, connection: connection, native: native, native_identity: identity}
  end

  # Exact independent goldens from the pinned official five-file fixture. The
  # one-shot source itself uses create_session and the same matcher/options.
  defp expected_files(%{omit: false, tree: root}) do
    [
      %{
        "root" => root,
        "path" => "abexy",
        "match_type" => "file",
        "file_name" => "abexy",
        "score" => 84,
        "indices" => [0, 1, 2]
      },
      %{
        "root" => root,
        "path" => "sub/abce",
        "match_type" => "file",
        "file_name" => "abce",
        "score" => 72,
        "indices" => [4, 5, 7]
      },
      %{
        "root" => root,
        "path" => "abcde",
        "match_type" => "file",
        "file_name" => "abcde",
        "score" => 71,
        "indices" => [0, 1, 4]
      }
    ]
  end

  defp expected_files(%{omit: true, tree: root}) do
    [
      %{
        "root" => root,
        "path" => "sub/abce",
        "match_type" => "file",
        "file_name" => "abce",
        "score" => 72,
        "indices" => [4, 5, 7]
      },
      %{
        "root" => root,
        "path" => "abcde",
        "match_type" => "file",
        "file_name" => "abcde",
        "score" => 71,
        "indices" => [0, 1, 4]
      }
    ]
  end

  defp diagnostics(profile, pid) do
    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    native
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
    assert Map.keys(response) |> Enum.sort() === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp await_notice(pid, method, params, events, prior_sequence),
    do: await_notice(pid, method, params, events, prior_sequence, now() + 5_000)

  defp await_notice(pid, method, params, events, prior_sequence, deadline) do
    events = drain(pid, events)
    expected = %{method: method, params: params, prior_sequence: prior_sequence}
    event = Enum.find(events, &selected?(&1, expected))
    await_or_return(pid, expected, events, event, deadline)
  end

  defp selected?(event, expected) do
    event.sequence > expected.prior_sequence and event.wire["method"] == expected.method and
      event.wire["params"] === expected.params
  end

  defp await_or_return(pid, expected, events, nil, deadline) do
    assert now() < deadline, "Native selected fuzzy notification deadline"
    Process.sleep(10)
    await_notice(pid, expected.method, expected.params, events, expected.prior_sequence, deadline)
  end

  defp await_or_return(_pid, _expected, events, event, _deadline), do: {event, events}

  defp drain(pid, events) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 128
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= 1_048_576
    combined
  end

  defp last_sequence(events), do: events |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)

  defp assert_notice(profile, event, method, params, lower, upper) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire === %{"emittedAtMs" => emitted_at, "method" => method, "params" => params}
  end

  defp assert_original_order(profile, selected) do
    originals = Enum.filter(capture(profile), &(&1.direction == :in))
    Enum.reduce(selected, originals, &consume_original/2)
  end

  defp consume_original(event, originals) do
    assert [original | remaining] = Enum.drop_while(originals, &(&1.wire !== event.wire))
    assert JSON.decode!(original.encoded) === event.wire
    remaining
  end

  defp assert_event_bounds(profile, events) do
    assert Enum.map(events, & &1.sequence) === Enum.sort(Enum.map(events, & &1.sequence))
    assert length(Enum.uniq_by(events, & &1.sequence)) === length(events)
    for event <- events, do: assert_fuzzy_event(profile, event)
  end

  defp assert_fuzzy_event(profile, event) do
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire["method"] in [@updated, @completed]
    assert event.wire["params"]["sessionId"] === profile.id
    # Partial snapshots and duplicate idle notices are allowed, finite ingress.
    # Only selected full snapshots above establish the complete golden oracle.
    assert Enum.sort(Map.keys(event.wire)) === ["emittedAtMs", "method", "params"]
    assert is_integer(event.wire["emittedAtMs"])
  end

  defp assert_inventory(profile) do
    records = capture(profile)
    outgoing = Enum.filter(records, &(&1.direction == :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics fuzzyFileSearch/sessionStart fuzzyFileSearch/sessionUpdate fuzzyFileSearch/sessionUpdate fuzzyFileSearch/sessionStop server/diagnostics)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 7
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === 7
    for record <- records, do: assert_incoming_kind(record)
    assert length(records) <= 128
  end

  defp assert_incoming_kind(%{direction: :in, wire: %{"id" => _} = wire}),
    do: refute(Map.has_key?(wire, "method"))

  defp assert_incoming_kind(_record), do: :ok

  defp assert_inputs(profile) do
    for {path, bytes} <- profile.inputs, do: assert_input(path, bytes)

    entries =
      if profile.omit, do: ~w(abc abcde sub zzz.txt), else: ~w(abc abcde abexy sub zzz.txt)

    assert Enum.sort(File.ls!(profile.tree)) === entries
    assert File.ls!(Path.join(profile.tree, "sub")) === ["abce"]
    assert File.stat!(profile.config).size <= 4096
    assert File.read!(profile.config) === profile.original_config
    assert File.ls!(profile.workspace) === []
  end

  defp assert_input(path, bytes) do
    assert File.stat!(path).size <= 256
    assert File.read!(path) === bytes
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

  defp request_id, do: "owned-fuzzy-envelope-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
