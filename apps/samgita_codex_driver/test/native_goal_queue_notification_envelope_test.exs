defmodule SamgitaCodexDriver.NativeGoalQueueNotificationEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/queued_model_fixture.py", __DIR__)
  @provider_sha "989d614f92d08cd2fe43798e144cf2a533a5a1082be118e902da63fd0087df16"
  @base_provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @base_provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @updated "thread/goal/updated"
  @cleared "thread/goal/cleared"
  @queue_changed "thread/queue/changed"
  @max_events 256
  @max_frame_bytes 262_144
  @max_bytes 4_194_304

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

    # Retain original framed bodies before Session receives/decodes them.
    # Capture overflow is a failure, not truncation or a successful observation.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)

      if ledger.count < 256 and size <= 262_144 and ledger.bytes + size <= 4_194_304 do
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
    assert hash(File.read!(@provider)) === @provider_sha
    assert hash(File.read!(@base_provider)) === @base_provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-goal-queue-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "auto")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> close_provider(fixture) end)
    File.write!(fixture.requests, "[]")
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: Path.expand(binary), root: root, fixture: fixture, capture: capture}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")
    original = File.read!(config)
    assert String.ends_with?(original, "\n[features]\nshell_snapshot = false\n")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        original <>
        "goals = true\napps = false\nplugins = false\nremote_plugin = false\n" <>
        "recommended_plugins = false\nmemories = false\n" <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        "\n[otel]\nexporter = \"none\"\ntrace_exporter = \"none\"\nmetrics_exporter = \"none\"\n"
    )

    inputs = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      @base_provider
    ]

    Map.put(ctx, :inputs, Map.new(inputs, &{&1, File.read!(&1)}))
  end

  test "whole paused native goal update and clear envelopes retain independent persisted state",
       ctx do
    session = start(ctx)
    ctx = Map.put(ctx, :generation, Session.status(session.pid).generation)
    thread = start_thread(ctx, session.pid)
    assert call(ctx, session.pid, "thread/goal/get", %{"threadId" => thread}) === %{"goal" => nil}
    events = drain(session.pid, [])
    prior = last_sequence(events)
    lower = System.system_time(:millisecond)

    {first_request, %{"goal" => first}} =
      request(ctx, session.pid, "thread/goal/set", %{
        "threadId" => thread,
        "objective" => "  Owned paused goal λ  ",
        "status" => "paused",
        "tokenBudget" => 100
      })

    expected_first =
      expected_goal(
        first,
        thread,
        "Owned paused goal λ",
        100,
        lower,
        System.system_time(:millisecond)
      )

    first_params = %{"threadId" => thread, "turnId" => nil, "goal" => expected_first}
    {first_event, events} = await_notice(session.pid, @updated, first_params, events, prior)

    assert_notice(
      ctx,
      first_event,
      @updated,
      first_params,
      lower,
      System.system_time(:millisecond)
    )

    assert_after_receipt(ctx, first_request, first_event)

    assert call(ctx, session.pid, "thread/goal/get", %{"threadId" => thread}) ===
             %{"goal" => expected_first}

    lower_update = System.system_time(:millisecond)

    {update_request, %{"goal" => updated}} =
      request(ctx, session.pid, "thread/goal/set", %{
        "threadId" => thread,
        "objective" => "Owned paused goal revised 雪",
        "status" => "paused",
        "tokenBudget" => nil
      })

    expected_updated =
      expected_goal(
        updated,
        thread,
        "Owned paused goal revised 雪",
        nil,
        lower_update,
        System.system_time(:millisecond),
        expected_first["createdAt"]
      )

    assert expected_updated["updatedAt"] >= expected_first["updatedAt"]
    updated_params = %{"threadId" => thread, "turnId" => nil, "goal" => expected_updated}

    {updated_event, events} =
      await_notice(session.pid, @updated, updated_params, events, first_event.sequence)

    assert_notice(
      ctx,
      updated_event,
      @updated,
      updated_params,
      lower_update,
      System.system_time(:millisecond)
    )

    assert_after_receipt(ctx, update_request, updated_event)

    assert call(ctx, session.pid, "thread/goal/get", %{"threadId" => thread}) ===
             %{"goal" => expected_updated}

    lower_clear = System.system_time(:millisecond)

    {clear_request, %{"cleared" => true}} =
      request(ctx, session.pid, "thread/goal/clear", %{"threadId" => thread})

    clear_params = %{"threadId" => thread}

    {clear_event, events} =
      await_notice(session.pid, @cleared, clear_params, events, updated_event.sequence)

    assert_notice(
      ctx,
      clear_event,
      @cleared,
      clear_params,
      lower_clear,
      System.system_time(:millisecond)
    )

    assert_after_receipt(ctx, clear_request, clear_event)
    assert_original_order(ctx, [first_event, updated_event, clear_event], first_request)
    assert call(ctx, session.pid, "thread/goal/get", %{"threadId" => thread}) === %{"goal" => nil}
    assert provider_requests(ctx) === []

    assert_inventory(
      ctx,
      ~w(initialize initialized server/diagnostics thread/start thread/goal/get thread/goal/set thread/goal/get thread/goal/set thread/goal/get thread/goal/clear thread/goal/get)
    )

    finish(ctx, session, events)
    assert provider_requests(ctx) === []
  end

  test "whole native queue changes retain real idle dispatch identity and completed effects",
       ctx do
    session = start(ctx)
    ctx = Map.put(ctx, :generation, Session.status(session.pid).generation)
    thread = start_thread(ctx, session.pid)
    events = drain(session.pid, [])
    prior = last_sequence(events)
    lower = System.system_time(:millisecond)
    client = "owned-queue-envelope-client-λ"
    text = "Owned queued envelope message 雪"

    {request_id, %{"queuedSubmission" => queued}} =
      request(ctx, session.pid, "thread/queue/add", %{
        "threadId" => thread,
        "clientUserMessageId" => client,
        "input" => [%{"type" => "text", "text" => text}]
      })

    assert is_binary(queued["id"]) and byte_size(queued["id"]) > 0

    assert queued === %{
             "id" => queued["id"],
             "clientUserMessageId" => client,
             "input" => [%{"type" => "text", "text" => text, "text_elements" => []}]
           }

    events = await_queue(session.pid, thread, client, prior, events, now() + 20_000)
    item = user_item(events, thread, client)
    turn = item["turnId"]
    assert is_binary(turn) and byte_size(turn) > 0
    assert item["item"]["content"] === queued["input"]

    assert notification(events, "turn/started", fn params ->
             params["threadId"] == thread and params["turn"]["id"] == turn
           end)

    assert call(ctx, session.pid, "thread/queue/list", %{"threadId" => thread}) ===
             %{"data" => [], "nextCursor" => nil}

    assert_provider_effect(ctx, thread, turn, text)
    # Cohort cutoff: events drained through the first actual completed queued
    # turn plus one public empty-queue readback. This is not a total-lifetime
    # notice count or a queue acknowledgement ordering guarantee.
    events = drain(session.pid, events)
    upper = System.system_time(:millisecond)
    changes = queue_changes(events, thread, prior)
    assert changes != []

    for event <- changes,
        do: assert_notice(ctx, event, @queue_changed, %{"threadId" => thread}, lower, upper)

    assert_original_order(ctx, changes, request_id)

    assert_inventory(
      ctx,
      ~w(initialize initialized server/diagnostics thread/start thread/queue/add thread/queue/list)
    )

    finish(ctx, session, events)
    assert_provider_effect(ctx, thread, turn, text)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: @max_events,
               max_event_bytes: @max_bytes,
               max_message_bytes: @max_frame_bytes,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: @max_frame_bytes,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_session(pid, connection, identity) end)
    id = request_id()
    info = %{"name" => "owned_goal_queue_notification_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, identity: identity}
  end

  # Inherit the fixed ordinary launch configuration. Do not invoke the older
  # TurnFixture.thread/3, which supplies different per-thread settings.
  defp start_thread(ctx, pid) do
    thread =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    thread
  end

  defp expected_goal(observed, thread, objective, budget, lower, upper, created \\ nil) do
    created_at = Map.fetch!(observed, "createdAt")
    updated_at = Map.fetch!(observed, "updatedAt")
    assert is_integer(created_at) and is_integer(updated_at)

    if created,
      do: assert(created_at === created),
      else: assert(div(lower, 1000) <= created_at and created_at <= div(upper, 1000))

    assert div(lower, 1000) <= updated_at and updated_at <= div(upper, 1000)
    assert updated_at >= created_at

    expected = %{
      "threadId" => thread,
      "objective" => objective,
      "status" => "paused",
      "tokenBudget" => budget,
      "tokensUsed" => 0,
      "timeUsedSeconds" => 0,
      "createdAt" => created_at,
      "updatedAt" => updated_at
    }

    assert observed === expected
    expected
  end

  defp await_notice(pid, method, params, events, prior),
    do: await_notice(pid, method, params, events, prior, now() + 5_000)

  defp await_notice(pid, method, params, events, prior, deadline) do
    events = drain(pid, events)

    selected =
      Enum.find(events, fn event ->
        event.sequence > prior and event.wire["method"] == method and
          event.wire["params"] === params
      end)

    if selected do
      {selected, events}
    else
      wait_available(pid, deadline)
      await_notice(pid, method, params, events, prior, deadline)
    end
  end

  defp await_queue(pid, thread, client, prior, events, deadline) do
    events = drain(pid, events)
    item = user_item(events, thread, client)

    if item && completed?(events, thread, item["turnId"]) &&
         queue_changes(events, thread, prior) != [] do
      events
    else
      wait_available(pid, deadline)
      await_queue(pid, thread, client, prior, events, deadline)
    end
  end

  defp wait_available(pid, deadline) do
    remaining = max(deadline - now(), 0)
    assert remaining > 0, "Native goal/queue notification deadline"
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, gap}} -> flunk("Native goal/queue event gap: #{inspect(gap)}")
    after
      remaining -> flunk("Native goal/queue notification deadline")
    end
  end

  defp drain(pid, events) do
    assert {:ok, fresh} = Session.drain(pid, @max_events)
    combined = events ++ fresh
    assert length(combined) <= @max_events
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= @max_bytes
    sequences = Enum.map(combined, & &1.sequence)
    assert Enum.sort(sequences) === sequences
    assert Enum.uniq(sequences) === sequences
    combined
  end

  defp queue_changes(events, thread, prior) do
    Enum.filter(events, fn event ->
      event.sequence > prior and event.wire["method"] == @queue_changed and
        event.wire["params"]["threadId"] == thread
    end)
  end

  defp user_item(events, thread, client) do
    notification(events, "item/started", fn params ->
      params["threadId"] == thread and params["item"]["type"] == "userMessage" and
        params["item"]["clientId"] == client
    end)
  end

  defp completed?(events, thread, turn) do
    notification(events, "turn/completed", fn params ->
      params["threadId"] == thread and params["turn"]["id"] == turn and
        params["turn"]["status"] == "completed"
    end) != nil
  end

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp assert_notice(ctx, event, method, params, lower, upper) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    assert event.kind === :notification and event.generation === ctx.generation
    assert event.wire === %{"emittedAtMs" => emitted_at, "method" => method, "params" => params}
  end

  defp assert_provider_effect(ctx, thread, turn, text) do
    assert [request] = provider_requests(ctx)

    texts =
      request["input"]
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.filter(&(&1["type"] == "input_text"))
      |> Enum.map(& &1["text"])

    assert text in texts
    path = Path.join(ctx.root, "queue-observations.json")
    assert File.stat!(path).size <= 65_536
    assert %{"1" => record} = path |> File.read!() |> JSON.decode!()
    assert record["metadata"]["thread_id"] === thread
    assert record["metadata"]["turn_id"] === turn
    assert record["metadata"]["turn_trigger"] === "queue"
    assert record["held"] === false
    assert record["timedOut"] === false
  end

  defp provider_requests(ctx) do
    assert File.stat!(ctx.fixture.requests).size <= @max_bytes
    ModelFixture.requests(ctx.fixture)
  end

  defp call(ctx, pid, method, params), do: elem(request(ctx, pid, method, params), 1)

  defp request(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    {id, result}
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent, received] = Enum.filter(capture(ctx), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(ctx) do
    Agent.get(ctx.capture, &Enum.reverse(&1.records))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp assert_after_receipt(ctx, id, event) do
    records = Enum.with_index(capture(ctx))

    assert {_response, receipt_index} =
             Enum.find(records, fn {record, _} ->
               record.direction == :in and record.wire["id"] == id
             end)

    assert {_original, notice_index} =
             Enum.find(records, fn {record, _} ->
               record.direction == :in and record.wire === event.wire
             end)

    assert receipt_index < notice_index
  end

  defp assert_original_order(ctx, selected, id) do
    records = capture(ctx)

    assert request_index =
             Enum.find_index(records, &(&1.direction == :out and &1.wire["id"] == id))

    originals = records |> Enum.drop(request_index + 1) |> Enum.filter(&(&1.direction == :in))
    Enum.reduce(selected, originals, &consume_original/2)
  end

  defp consume_original(event, originals) do
    assert [original | remaining] = Enum.drop_while(originals, &(&1.wire !== event.wire))
    assert JSON.decode!(original.encoded) === event.wire
    remaining
  end

  defp finish(ctx, session, events) do
    events = drain(session.pid, events)
    assert length(events) <= @max_events

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(session.pid)

    assert_inputs(ctx)
    close_session(session.pid, session.connection, session.identity)
    close_provider(ctx.fixture)
    assert_inputs(ctx)
  end

  defp assert_inventory(ctx, expected_methods) do
    records = capture(ctx)
    outgoing = Enum.filter(records, &(&1.direction == :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === expected_methods
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === length(ids)
    replies = Enum.filter(records, &(&1.direction == :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === length(requests)
  end

  defp assert_inputs(ctx) do
    for {path, bytes} <- ctx.inputs do
      assert File.stat!(path).size <= @max_frame_bytes
      assert File.read!(path) === bytes
    end

    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp close_session(pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp last_sequence(events), do: events |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)

  defp request_id,
    do: "owned-goal-queue-envelope-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
