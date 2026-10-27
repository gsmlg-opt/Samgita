defmodule SamgitaCodexDriver.NativeFuzzyNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Error, Schema, Wire}

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

  for {label, warm_ids, cold_ids} <- [
        {"negative integer", {-5_061_134, -5_061_154}, {-5_062_134, -5_062_154}},
        {"positive integer", {5_061_134, 5_061_154}, {5_062_134, 5_062_154}},
        {"Unicode string", {"owned-search-λ🙂-warm", "owned-stop-雪🙂-warm"},
         {"owned-search-λ🙂-cold", "owned-stop-雪🙂-cold"}}
      ] do
    @tag warm_ids: warm_ids, cold_ids: cold_ids
    test "native fuzzy #{label} IDs retain real ranking populated stop and cold recovery", ctx do
      profile = profile(ctx, "owned-typed-fuzzy-session-λ🙂", false)
      frozen_code = frozen_code_inputs()
      warm = run_typed_native(profile, ctx.warm_ids, :warm)
      prefix = capture(profile)
      assert capture(profile) === prefix
      assert_code_inputs(frozen_code)

      cold = run_typed_native(profile, ctx.cold_ids, :cold)
      refute warm.native === cold.native
      refute warm.pid === cold.pid
      assert Enum.take(capture(profile), length(prefix)) === prefix
      assert_code_inputs(frozen_code)
      assert_inputs(profile)
    end
  end

  defp run_typed_native(profile, {query_id, stop_id}, mode) do
    before = length(capture(profile))
    session = start(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    assert {:ok, []} = Session.drain(session.pid, 128)

    if mode === :cold do
      assert_missing_session(profile, session.pid, "owned-cold-absence-probe")
    end

    expected = %{"files" => expected_files(profile)}
    params = %{"query" => "abe", "roots" => [profile.tree]}
    assert call(profile, session.pid, "fuzzyFileSearch", params, query_id) === expected
    assert {:ok, []} = Session.drain(session.pid, 128)

    # Neither cold initialization nor a one-shot search re-creates the old
    # registered session or replays public session notifications.
    assert capture(profile)
           |> Enum.drop(before)
           |> Enum.filter(&(&1.direction === :in and Map.has_key?(&1.wire, "method"))) === []

    before_start = System.system_time(:millisecond)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => profile.id,
             "roots" => [profile.tree]
           }) === %{}

    complete_params = %{"sessionId" => profile.id}
    {idle, events} = await_notice(session.pid, @completed, complete_params, [], 0)

    assert_notice(
      profile,
      idle,
      @completed,
      complete_params,
      before_start,
      System.system_time(:millisecond)
    )

    before_query = System.system_time(:millisecond)

    assert call(profile, session.pid, "fuzzyFileSearch/sessionUpdate", %{
             "sessionId" => profile.id,
             "query" => "abe"
           }) === %{}

    ranked_params = %{
      "sessionId" => profile.id,
      "query" => "abe",
      "files" => expected_files(profile)
    }

    {ranked, events} = await_notice(session.pid, @updated, ranked_params, events, idle.sequence)

    assert_notice(
      profile,
      ranked,
      @updated,
      ranked_params,
      before_query,
      System.system_time(:millisecond)
    )

    assert_original_order(profile, [idle, ranked])
    assert_inputs(profile)

    # The exact populated snapshot proves a real registered usable session.
    # Stop removes that entry; already spawned native notices may arrive late.
    stop = %{
      "id" => stop_id,
      "method" => "fuzzyFileSearch/sessionStop",
      "params" => %{"sessionId" => profile.id}
    }

    assert call(profile, session.pid, stop["method"], stop["params"], stop_id) === %{}
    assert_typed_stop_after_snapshot(profile, before, ranked.wire, stop)
    assert_missing_session(profile, session.pid, "owned-after-stop-probe")
    assert call(profile, session.pid, "fuzzyFileSearch", params) === expected

    assert call(profile, session.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert diagnostics(profile, session.pid) === session.native
    events = drain(session.pid, events)
    assert_event_bounds(profile, events)
    assert Session.uncertain_operations(session.pid) === []
    assert Session.interaction_outcomes(session.pid) === []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    close_resources(session.pid, session.connection, session.native_identity)
    # Validate bounded late original notices too, without a stop/worker fence.
    assert_typed_inventory(profile, before, mode, query_id, stop_id, before_start)
    assert_inputs(profile)
    %{pid: session.pid, native: session.native}
  end

  defp assert_missing_session(profile, pid, query) do
    wire = %{
      "id" => request_id(),
      "method" => "fuzzyFileSearch/sessionUpdate",
      "params" => %{"sessionId" => profile.id, "query" => query}
    }

    expected = %{
      "id" => wire["id"],
      "error" => %{
        "code" => -32_600,
        "message" => "fuzzy file search session not found: #{profile.id}"
      }
    }

    assert {:error, %Error{code: :upstream_error, wire: ^expected}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_original_pair(profile, wire, expected)
  end

  defp assert_typed_stop_after_snapshot(profile, before, ranked, stop) do
    records = capture(profile) |> Enum.drop(before) |> Enum.with_index()

    assert [{_, stop_index}] =
             Enum.filter(records, fn {record, _} ->
               record.direction === :out and record.wire === stop
             end)

    assert Enum.any?(records, fn {record, index} ->
             record.direction === :in and record.wire === ranked and index < stop_index
           end)
  end

  defp assert_typed_inventory(profile, before, mode, query_id, stop_id, lower) do
    records = Enum.drop(capture(profile), before)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === typed_methods(mode)
    assert length(outgoing) === if(mode === :cold, do: 12, else: 11)
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === length(requests)
    responses = Enum.filter(records, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(responses) === length(requests)

    for request <- requests do
      assert [response] = Enum.filter(responses, &(&1.wire["id"] === request.wire["id"]))
      assert_original_pair(profile, request.wire, response.wire)
    end

    assert [query, control] = Enum.filter(outgoing, &(&1.wire["method"] === "fuzzyFileSearch"))
    params = %{"query" => "abe", "roots" => [profile.tree]}
    assert query.wire === %{"id" => query_id, "method" => "fuzzyFileSearch", "params" => params}
    assert control.wire["params"] === params and is_binary(control.wire["id"])
    assert [stop] = Enum.filter(outgoing, &(&1.wire["method"] === "fuzzyFileSearch/sessionStop"))

    assert stop.wire === %{
             "id" => stop_id,
             "method" => "fuzzyFileSearch/sessionStop",
             "params" => %{"sessionId" => profile.id}
           }

    upper = System.system_time(:millisecond)

    for record <- records, record.direction === :in and Map.has_key?(record.wire, "method") do
      assert record.wire["method"] in [@updated, @completed]
      assert record.wire["params"]["sessionId"] === profile.id
      assert Enum.sort(Map.keys(record.wire)) === ["emittedAtMs", "method", "params"]
      emitted = record.wire["emittedAtMs"]
      assert is_integer(emitted) and lower <= emitted and emitted <= upper
      assert JSON.decode!(record.encoded) === record.wire
      assert {:ok, decoded} = Wire.decode(record.encoded, max_depth: 32)
      assert decoded === record.wire

      assert :ok =
               Schema.validate(protocol_schema("ServerNotification.json"), record.wire,
                 max_depth: 32
               )
    end
  end

  defp typed_methods(mode) do
    startup = ~w(initialize initialized server/diagnostics)

    startup =
      if mode === :cold, do: startup ++ ["fuzzyFileSearch/sessionUpdate"], else: startup

    startup ++
      ~w(fuzzyFileSearch fuzzyFileSearch/sessionStart fuzzyFileSearch/sessionUpdate fuzzyFileSearch/sessionStop fuzzyFileSearch/sessionUpdate fuzzyFileSearch thread/loaded/list server/diagnostics)
  end

  defp assert_original_pair(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) in [["id", "result"], ["error", "id"]]
    assert :ok = Schema.validate(protocol_schema("ClientRequest.json"), wire, max_depth: 32)
  end

  defp protocol_schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp frozen_code_inputs do
    Map.new(
      [
        __ENV__.file,
        Path.join(__DIR__, "support/native_launch_fixture.ex"),
        Path.join(__DIR__, "support/stdio_session_fixture.ex")
      ],
      fn path ->
        assert File.stat!(path).size <= 1_048_576
        {path, File.read!(path)}
      end
    )
  end

  defp assert_code_inputs(frozen) do
    for {path, bytes} <- frozen do
      assert File.stat!(path).size <= 1_048_576
      assert File.read!(path) === bytes
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

  defp call(profile, pid, method, params, id \\ nil) do
    id = id || request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)

    if method in ~w(fuzzyFileSearch fuzzyFileSearch/sessionStop),
      do: assert_original_pair(profile, wire, response)

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
