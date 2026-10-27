defmodule SamgitaCodexDriver.NativeReadStateNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @changed "thread/readState/changed"
  @input "Owned read-state input remains inert.\n"

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

    # Native JSONL bodies are preserved before Session decoding, unchanged.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction === :out, do: 8192, else: 65_536

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

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-read-state-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, child))
    catalog = Path.join(root, "codex/models.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "owned-read-state-model",
            "display_name" => "Owned unused read-state model",
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{"instructions_template" => "Owned inert read-state fixture."},
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
    model = "owned-read-state-model"
    model_catalog_json = #{JSON.encode!(catalog)}
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
    [skills.bundled]
    enabled = false
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

    input = Path.join(root, "workspace/INPUT.md")
    File.write!(input, @input)
    frozen = Map.new([config, catalog, input], &{&1, File.read!(&1)})
    %{binary: Path.expand(binary), root: root, frozen: frozen}
  end

  test "native read-state envelopes match committed unread/read snapshots and cold persistence",
       ctx do
    warm = start_native(ctx)
    assert {:ok, []} = Session.drain(warm.pid, 128)

    {created, _response, _request} =
      call(warm, "thread/start", %{
        "cwd" => Path.join(ctx.root, "workspace"),
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    thread_id = Map.fetch!(Map.fetch!(created, "thread"), "id")
    assert is_binary(thread_id) and byte_size(thread_id) > 0

    assert {%{}, _response, _request} =
             call(warm, "thread/name/set", %{
               "threadId" => thread_id,
               "name" => "Owned empty read-state envelope λ"
             })

    baseline = read(warm, thread_id)
    initial = state(baseline, nil)
    thread = Map.fetch!(baseline, "thread")
    assert Map.fetch!(thread, "turns") === []
    assert Map.fetch!(thread, "ephemeral") === false
    history_path = Map.fetch!(thread, "path")
    assert is_binary(history_path) and String.starts_with?(history_path, ctx.root <> "/")
    history = snapshot(history_path)
    initial_events = drain_metadata(warm.pid)
    assert Enum.filter(initial_events, &(&1.wire["method"] === @changed)) === []

    {states, events, _latest} =
      Enum.reduce(
        [{"unread", %{"type" => "threadStart"}}, {"read", nil}],
        {[], [], initial},
        fn {operation, position}, {states, events, previous} ->
          lower = System.system_time(:millisecond)

          {updated, response, request} =
            call(warm, "thread/readState/update", %{
              "threadId" => thread_id,
              "expectedRevision" => Map.fetch!(previous, "revision"),
              "operation" => %{"type" => operation}
            })

          assert Map.keys(updated) === ["readState"]
          committed = state(updated, position)
          refute committed["revision"] in Enum.map([initial | states], & &1["revision"])
          fresh = await_notice(warm.pid, [], now() + 5_000)
          [event] = Enum.filter(fresh, &(&1.wire["method"] === @changed))
          upper = System.system_time(:millisecond)
          assert_notice(warm, event, thread_id, committed, lower, upper)
          assert_causal_frame(warm, request, event, response)
          queried = read(warm, thread_id)
          assert state(queried, position) === committed
          assert Map.fetch!(queried, "thread") === thread
          assert snapshot(history_path) === history
          assert_frozen(ctx)
          {states ++ [committed], events ++ fresh, committed}
        end
      )

    [unread, marked_read] = states
    assert unread["firstUnread"] === %{"type" => "threadStart"}
    assert marked_read["firstUnread"] === nil
    assert_idle(warm, [thread_id])
    events = initial_events ++ events ++ drain_metadata(warm.pid)
    close_native(warm)
    assert_originals(warm, events, [unread, marked_read])
    assert_inventory(warm, :warm)
    assert snapshot(history_path) === history
    assert_frozen(ctx)

    cold = start_native(ctx)
    refute cold.native === warm.native
    refute cold.connection.port === warm.connection.port
    refute Session.status(cold.pid).instance_id === warm.instance
    assert {:ok, []} = Session.drain(cold.pid, 128)

    cold_thread =
      Map.merge(thread, %{
        "status" => %{"type" => "notLoaded"},
        "environments" => nil,
        "canAcceptDirectInput" => nil,
        "model" => nil
      })

    for _ <- 1..2 do
      queried = read(cold, thread_id)
      assert state(queried, nil) === marked_read
      assert Map.fetch!(queried, "thread") === cold_thread
      assert snapshot(history_path) === history
      assert_frozen(ctx)
    end

    assert_idle(cold, [])
    cold_events = drain_metadata(cold.pid)
    close_native(cold)
    assert_originals(cold, cold_events, [])
    assert_inventory(cold, :cold)
    assert snapshot(history_path) === history
    assert_frozen(ctx)
  end

  defp start_native(ctx) do
    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: make_ref())

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: Path.join(ctx.root, "workspace"),
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => Path.join(ctx.root, "home"),
                      "CODEX_HOME" => Path.join(ctx.root, "codex"),
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    session = %{pid: pid, connection: connection, identity: identity, capture: capture}
    on_exit(fn -> close_native(session) end)
    id = request_id()
    info = %{"name" => "owned_read_state_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    {diagnostics, _response, _request} = call(session, "server/diagnostics", %{})
    native = diagnostics["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    status = Session.status(pid)

    Map.merge(session, %{
      native: native,
      generation: status.generation,
      instance: status.instance_id
    })
  end

  defp call(session, method, params) do
    wire = %{"id" => request_id(), "method" => method, "params" => params}

    assert {:ok, %{"result" => result} = response} =
             Session.request_native(session.pid, wire, timeout_ms: 5_000)

    assert_exchange(session, wire, response)
    {result, response, wire}
  end

  defp assert_exchange(session, wire, response) do
    assert response["id"] === wire["id"]
    assert [sent, received] = Enum.filter(capture(session), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp read(session, thread_id) do
    {result, _response, _request} =
      call(session, "thread/read", %{"threadId" => thread_id, "includeTurns" => false})

    assert Enum.sort(Map.keys(result)) === ~w(readState thread)
    result
  end

  defp state(result, first_unread) do
    assert %{"firstUnread" => ^first_unread, "revision" => revision} =
             state = Map.fetch!(result, "readState")

    assert Enum.sort(Map.keys(state)) === ~w(firstUnread revision)
    assert is_binary(revision) and byte_size(revision) > 0
    state
  end

  defp await_notice(pid, events, deadline) do
    combined = events ++ drain_metadata(pid)
    assert length(combined) <= 16

    if Enum.any?(combined, &(&1.wire["method"] === @changed)) do
      combined
    else
      assert now() < deadline, "Native committed read-state notice deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native read-state event gap")
      after
        10 -> :ok
      end

      await_notice(pid, combined, deadline)
    end
  end

  defp assert_notice(session, event, thread_id, state, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === session.generation

    assert event.wire === %{
             "method" => @changed,
             "params" => %{"threadId" => thread_id, "readState" => state},
             "emittedAtMs" => emitted
           }

    assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
  end

  defp assert_causal_frame(session, request, event, response) do
    records = capture(session)
    assert [sent] = positions(records, :out, request)
    assert [received] = positions(records, :in, response)
    assert [notice] = positions(records, :in, event.wire)
    assert sent < notice and notice < received
  end

  defp positions(records, direction, wire),
    do:
      for(
        {record, index} <- Enum.with_index(records),
        record.direction === direction and record.wire === wire,
        do: index
      )

  defp assert_originals(session, events, states) do
    selected = Enum.filter(events, &(&1.wire["method"] === @changed))

    originals =
      Enum.filter(capture(session), &(&1.direction === :in and &1.wire["method"] === @changed))

    assert Enum.map(selected, &get_in(&1.wire, ["params", "readState"])) === states
    assert Enum.map(originals, & &1.wire) === Enum.map(selected, & &1.wire)
    sequences = Enum.map(selected, & &1.sequence)
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences === Enum.sort(Enum.uniq(sequences))

    for {original, event} <- Enum.zip(originals, selected),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp assert_inventory(session, profile) do
    expected =
      case profile do
        :warm ->
          ~w(initialize initialized server/diagnostics thread/start thread/name/set thread/read thread/readState/update thread/read thread/readState/update thread/read thread/loaded/list)

        :cold ->
          ~w(initialize initialized server/diagnostics thread/read thread/read thread/loaded/list)
      end

    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === length(requests)
    replies = Enum.filter(records, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === length(requests)

    for request <- requests do
      assert [_sent, received] = Enum.filter(records, &(&1.wire["id"] === request.wire["id"]))
      assert_exchange(session, request.wire, received.wire)
    end
  end

  defp drain_metadata(pid) do
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert Enum.all?(events, fn event ->
             event.kind === :notification and
               event.wire["method"] in [
                 "thread/started",
                 "thread/status/changed",
                 "thread/name/updated",
                 @changed
               ]
           end)

    events
  end

  defp assert_idle(session, loaded) do
    assert {%{"data" => ^loaded, "nextCursor" => nil}, _response, _request} =
             call(session, "thread/loaded/list", %{})

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    assert Session.uncertain_operations(session.pid) === []
  end

  defp assert_frozen(ctx) do
    for {path, bytes} <- ctx.frozen, do: assert(snapshot(path) === bytes)
    assert File.ls!(Path.join(ctx.root, "workspace")) === ["INPUT.md"]
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    File.read!(path)
  end

  defp capture(session),
    do:
      Agent.get(session.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_native(session) do
    connection = session.connection
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id,
    do: "owned-read-state-envelope-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
