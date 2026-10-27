defmodule SamgitaCodexDriver.NativeProjectNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @methods ~w(project/changed thread/project/updated)
  @name "Owned empty project member λ"

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

    # Observe original native bodies before Session decoding without replacing
    # any server message. The local ledger has independent finite byte bounds.
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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-project-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, child))
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

    sentinel = Path.join(root, "workspace/preserved.txt")
    File.write!(sentinel, "Owned project classification must preserve workspace bytes.\n")
    frozen = Map.new([config, sentinel], &{&1, File.read!(&1)})
    %{root: root, binary: Path.expand(binary), frozen: frozen}
  end

  test "native project envelopes follow committed membership changes and preserve an empty durable thread",
       ctx do
    warm = start_native(ctx)
    assert project_notices(warm.pid) === []
    workspace = Path.join(ctx.root, "workspace")

    {started, _response, _request} =
      call(warm, "thread/start", %{
        "cwd" => workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    thread_id = started["thread"]["id"]
    assert is_binary(thread_id) and byte_size(thread_id) > 0
    assert started["thread"]["turns"] === []

    assert {%{}, _response, _request} =
             call(warm, "thread/name/set", %{"threadId" => thread_id, "name" => @name})

    thread = read_thread(warm, thread_id)

    assert Map.take(thread, ~w(id cwd ephemeral projectId turns)) === %{
             "id" => thread_id,
             "cwd" => workspace,
             "ephemeral" => false,
             "projectId" => nil,
             "turns" => []
           }

    history = %{path: Map.fetch!(thread, "path"), bytes: nil}
    assert is_binary(history.path) and File.regular?(history.path)
    history = %{history | bytes: File.read!(history.path)}
    assert byte_size(history.bytes) > 0
    assert project_notices(warm.pid) === []
    assert_projects(warm, [])

    params = %{
      "name" => "Owned imported project λ",
      "roots" => [%{"path" => workspace}],
      "metadata" => %{"marker" => "initial"},
      "threads" => [thread_id],
      "idempotencyKey" => "owned-project-envelope-import"
    }

    lower = System.system_time(:millisecond)
    {result, response, request} = call(warm, "project/import", params)
    project = Map.fetch!(result, "project")
    project_id = Map.fetch!(project, "id")
    assert is_binary(project_id) and byte_size(project_id) > 0

    assert Map.take(project, ~w(name roots metadata)) ===
             Map.take(params, ~w(name roots metadata))

    upper = System.system_time(:millisecond)
    assert_project_times(project, lower, upper)
    imported = await_notices(warm.pid, 2, [], now() + 5_000)

    assert_notices(
      warm,
      imported,
      [changed(project_id, "created"), member(thread_id, project_id)],
      lower,
      upper
    )

    assert_causal_frames(warm, request, imported, response)
    assert_committed(ctx, warm, project, thread_id, history)

    # A replay uses the original durable key and has no new membership effect.
    {replayed, _response, _request} =
      call(
        warm,
        "project/import",
        Map.merge(params, %{"name" => "Ignored replay", "threads" => []})
      )

    assert replayed === %{"project" => project}
    assert_committed(ctx, warm, project, thread_id, history)
    assert project_notices(warm.pid) === []

    update = %{
      "projectId" => project_id,
      "name" => "Owned updated project 雪",
      "roots" => [],
      "metadata" => %{"marker" => "updated"}
    }

    lower = System.system_time(:millisecond)
    {result, response, request} = call(warm, "project/update", update)
    updated = Map.fetch!(result, "project")

    assert Map.take(updated, ~w(id createdAt position recencyAt)) ===
             Map.take(project, ~w(id createdAt position recencyAt))

    assert Map.take(updated, ~w(name roots metadata)) ===
             Map.take(update, ~w(name roots metadata))

    notices = await_notices(warm.pid, 1, [], now() + 5_000)

    assert_notices(
      warm,
      notices,
      [changed(project_id, "updated")],
      lower,
      System.system_time(:millisecond)
    )

    assert_causal_frames(warm, request, notices, response)
    assert_committed(ctx, warm, updated, thread_id, history)

    {unchanged, _response, _request} = call(warm, "project/update", update)
    assert unchanged === %{"project" => updated}
    assert_committed(ctx, warm, updated, thread_id, history)
    assert project_notices(warm.pid) === []

    lower = System.system_time(:millisecond)
    {deleted, response, request} = call(warm, "project/delete", %{"projectId" => project_id})
    assert deleted === %{}
    removed = await_notices(warm.pid, 2, [], now() + 5_000)

    assert_notices(
      warm,
      removed,
      [changed(project_id, "deleted"), member(thread_id, nil)],
      lower,
      System.system_time(:millisecond)
    )

    assert_causal_frames(warm, request, removed, response)
    assert_deleted(ctx, warm, thread_id, history)
    assert_idle(warm, [thread_id])

    events = imported ++ notices ++ removed
    sequences = Enum.map(events, & &1.sequence)
    assert length(events) === 5
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences === Enum.sort(Enum.uniq(sequences))
    close_native(warm)
    assert_originals(warm, events)
    assert_inventory(warm, true)

    cold = start_native(ctx)
    refute cold.native === warm.native
    assert_deleted(ctx, cold, thread_id, history)
    assert_idle(cold, [])
    close_native(cold)
    assert_originals(cold, [])
    assert_inventory(cold, false)
    assert_frozen(ctx, history)
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
    session = %{pid: pid, capture: capture, identity: identity, connection: connection}
    on_exit(fn -> close_native(session) end)
    id = request_id()
    info = %{"name" => "owned_project_notification_envelope", "version" => "0.1.0"}

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
    Map.merge(session, %{native: native, generation: Session.status(pid).generation})
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

  defp read_thread(session, id) do
    {result, _response, _request} =
      call(session, "thread/read", %{"threadId" => id, "includeTurns" => false})

    Map.fetch!(result, "thread")
  end

  defp assert_projects(session, projects) do
    {result, _response, _request} = call(session, "project/list", %{})
    assert result === %{"data" => projects, "nextCursor" => nil}
  end

  defp assert_committed(ctx, session, project, thread_id, history) do
    {result, _response, _request} = call(session, "project/read", %{"projectId" => project["id"]})
    assert result === %{"project" => project}
    assert_projects(session, [project])
    assert_thread(ctx, session, thread_id, project["id"], history)
  end

  defp assert_deleted(ctx, session, thread_id, history) do
    assert_projects(session, [])
    assert_thread(ctx, session, thread_id, nil, history)
    assert project_notices(session.pid) === []
  end

  defp assert_thread(ctx, session, id, project_id, history) do
    actual = read_thread(session, id)

    assert Map.take(actual, ~w(id cwd ephemeral projectId path turns)) === %{
             "id" => id,
             "cwd" => Path.join(ctx.root, "workspace"),
             "ephemeral" => false,
             "projectId" => project_id,
             "path" => history.path,
             "turns" => []
           }

    assert_frozen(ctx, history)
  end

  defp assert_project_times(project, lower, upper) do
    for field <- ~w(createdAt updatedAt),
        do:
          assert(
            is_integer(project[field]) and div(lower, 1000) <= project[field] and
              project[field] <= div(upper, 1000)
          )

    assert is_integer(project["position"])
  end

  defp changed(id, type), do: {"project/changed", %{"projectId" => id, "changeType" => type}}

  defp member(thread, project),
    do: {"thread/project/updated", %{"threadId" => thread, "projectId" => project}}

  defp project_notices(pid) do
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    Enum.filter(events, &(&1.wire["method"] in @methods))
  end

  defp await_notices(pid, count, events, deadline) do
    combined = events ++ project_notices(pid)
    assert length(combined) <= count

    if length(combined) === count do
      combined
    else
      assert now() < deadline, "Native project notification deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected project event gap")
      after
        10 -> :ok
      end

      await_notices(pid, count, combined, deadline)
    end
  end

  defp assert_notices(session, events, expected, lower, upper) do
    assert length(events) === length(expected)

    for {event, {method, params}} <- Enum.zip(events, expected) do
      emitted = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted) and lower <= emitted and emitted <= upper
      assert event.kind === :notification and event.generation === session.generation
      assert event.wire === %{"method" => method, "params" => params, "emittedAtMs" => emitted}
      assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
    end
  end

  defp assert_causal_frames(session, request, events, response) do
    records = capture(session)
    assert [sent] = positions(records, :out, request)
    assert [received] = positions(records, :in, response)

    originals =
      for {record, index} <- Enum.with_index(records),
          sent < index and index < received and record.direction === :in and
            record.wire["method"] in @methods,
          do: record

    assert Enum.map(originals, & &1.wire) === Enum.map(events, & &1.wire)

    for {original, event} <- Enum.zip(originals, events),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp positions(records, direction, wire),
    do:
      for(
        {record, index} <- Enum.with_index(records),
        record.direction === direction and record.wire === wire,
        do: index
      )

  defp assert_originals(session, events) do
    originals =
      Enum.filter(capture(session), &(&1.direction === :in and &1.wire["method"] in @methods))

    assert Enum.map(originals, & &1.wire) === Enum.map(events, & &1.wire)

    for {original, event} <- Enum.zip(originals, events),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp assert_inventory(session, warm?) do
    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    methods = Enum.map(outgoing, & &1.wire["method"])

    counts =
      if warm?,
        do: %{
          "thread/start" => 1,
          "thread/name/set" => 1,
          "project/import" => 2,
          "project/update" => 2,
          "project/delete" => 1
        },
        else: %{}

    for method <- ~w(thread/start thread/name/set project/import project/update project/delete),
        do: assert(Enum.count(methods, &(&1 === method)) === Map.get(counts, method, 0))

    assert Enum.all?(
             methods,
             &(&1 in ~w(initialize initialized server/diagnostics thread/start thread/name/set thread/read thread/loaded/list project/import project/update project/delete project/read project/list))
           )

    assert Enum.count(methods, &(&1 === "initialize")) === 1
    assert Enum.count(methods, &(&1 === "initialized")) === 1
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === length(requests)

    for request <- requests do
      assert [_sent, received] = Enum.filter(records, &(&1.wire["id"] === request.wire["id"]))
      assert_exchange(session, request.wire, received.wire)
    end
  end

  defp assert_idle(session, loaded) do
    {result, _response, _request} = call(session, "thread/loaded/list", %{})
    assert result === %{"data" => loaded, "nextCursor" => nil}

    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil,
             buffered_events: 0
           } = Session.status(session.pid)

    assert Session.uncertain_operations(session.pid) === []
    assert project_notices(session.pid) === []
  end

  defp assert_frozen(ctx, history) do
    for {path, bytes} <- ctx.frozen, do: assert(File.read!(path) === bytes)
    assert File.read!(history.path) === history.bytes
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

  defp request_id, do: "owned-project-envelope-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
