defmodule SamgitaCodexDriver.NativeAttachmentEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @updated "thread/attachment/updated"
  @attachment_type "owned-v442-document λ"
  @key "owned-v442-key"
  @input "Owned attachment membership materialization"
  @payload %{"version" => 1, "values" => [nil, true, 9, "λ🙂"]}
  @duplicate_payload %{"version" => 2}
  @replacement_payload ["replacement", nil]
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  @membership_methods ["thread/attachment/list", "thread/attachmentOwner/list"]
  @startup_methods ["initialize", "initialized", "server/diagnostics"]

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

    # Preserve every original framed body before Session decoding. Overflow fails.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded, index: ledger.count + 1}

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

  setup tags do
    assert hash(File.read!(@script)) === @script_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) === @binary_sha
    File.mkdir!(Path.join(ctx.root, "tmp"))
    TurnFixture.configure_model(ctx, %{})

    inputs =
      Map.new(~w(config.toml turn-models.json), fn name ->
        path = Path.join(ctx.fixture.codex_home, name)
        {path, File.read!(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "whole native attachment changes preserve committed replay and cold membership", ctx do
    warm = start_native(ctx, new_capture(:warm_attachment_capture))
    thread = materialize(ctx, warm)
    assert attachment_originals(warm) === []
    assert [provider_request] = ModelFixture.requests(ctx.fixture)

    {original, created, events} = create(warm, thread, @payload, [])
    events = membership(warm, thread, [original], events)
    assert_exact_notices(warm, events, [created])

    duplicate = exchange(warm, "thread/attachment/add", add_params(thread, @duplicate_payload))
    assert duplicate.result === %{"outcome" => "existing", "attachment" => original}
    validate_result(duplicate, "v2/ThreadAttachmentAddResponse.json")
    events = membership(warm, thread, [original], events)
    assert_exact_notices(warm, events, [created])

    lower = System.system_time(:millisecond)
    removed = exchange(warm, "thread/attachment/remove", identity_params(thread))
    assert removed.result === %{}
    validate_result(removed, "v2/ThreadAttachmentRemoveResponse.json")

    {deleted, events} =
      await_change(warm, thread, original["id"], "deleted", removed, lower, events)

    events = membership(warm, thread, [], events)
    assert_exact_notices(warm, events, [created, deleted])

    duplicate_remove = exchange(warm, "thread/attachment/remove", identity_params(thread))
    assert duplicate_remove.result === %{}
    validate_result(duplicate_remove, "v2/ThreadAttachmentRemoveResponse.json")
    events = membership(warm, thread, [], events)
    assert_exact_notices(warm, events, [created, deleted])

    {replacement, recreated, events} = create(warm, thread, @replacement_payload, events)
    refute replacement["id"] === original["id"]
    events = membership(warm, thread, [replacement], events)
    originals = [created, deleted, recreated]
    assert_exact_notices(warm, events, originals)
    assert_ready(warm)
    assert ModelFixture.requests(ctx.fixture) === [provider_request]
    assert_inputs(ctx)
    assert_inventory(warm, warm_methods())
    warm_prefix = capture(warm)

    close_native(warm)
    assert capture(warm) === warm_prefix
    assert attachment_originals(warm) === originals

    cold = start_native(ctx, new_capture(:cold_attachment_capture))
    refute cold.pid === warm.pid
    refute cold.capture === warm.capture
    refute cold.native === warm.native
    refute cold.instance_id === warm.instance_id
    assert cold.generation === 1 and warm.generation === 1
    assert_unloaded(cold)
    cold_events = membership(cold, thread, [replacement], [])
    assert_unloaded(cold)
    cold_events = drain(cold, cold_events)
    assert_exact_notices(cold, cold_events, [])
    assert_ready(cold)
    assert ModelFixture.requests(ctx.fixture) === [provider_request]
    assert_inputs(ctx)

    assert_inventory(
      cold,
      @startup_methods ++
        ["thread/loaded/list"] ++
        @membership_methods ++ @membership_methods ++ ["thread/loaded/list"]
    )

    cold_prefix = capture(cold)
    close_native(cold)
    close_provider(ctx.fixture)
    assert capture(cold) === cold_prefix
    assert attachment_originals(cold) === []
    assert capture(warm) === warm_prefix
    assert ModelFixture.requests(ctx.fixture) === [provider_request]
    assert_inputs(ctx)
  end

  defp new_capture(id),
    do: start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: id)

  defp start_native(ctx, capture) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: Path.expand(ctx.binary),
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: environment(ctx),
                    max_message_bytes: 65_536
                  ]}
             )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    session = %{pid: pid, capture: capture, connection: connection, identity: identity}
    on_exit(fn -> close_native(session) end)
    info = %{"name" => "owned_attachment_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

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

    native = exchange(session, "server/diagnostics", %{}).result["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    status = Session.status(pid)

    Map.merge(session, %{
      native: native,
      generation: status.generation,
      instance_id: status.instance_id
    })
  end

  defp environment(ctx) do
    %{
      "HOME" => ctx.fixture.home,
      "CODEX_HOME" => ctx.fixture.codex_home,
      "TMPDIR" => Path.join(ctx.root, "tmp"),
      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
      "SHELL" => Path.join(ctx.fixture.bin, "sh"),
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }
  end

  defp materialize(ctx, session) do
    started =
      exchange(session, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "ephemeral" => false,
        "historyMode" => "paginated"
      })

    thread = Map.fetch!(started.result["thread"], "id")
    assert_uuid(thread)

    turn =
      exchange(session, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      }).result["turn"]["id"]

    events = TurnFixture.finish_turn(session.pid, thread, turn)
    assert Enum.filter(events, &(&1.wire["method"] == @updated)) === []
    assert_ready(session)
    thread
  end

  defp create(session, thread, payload, events) do
    lower = System.system_time(:millisecond)
    added = exchange(session, "thread/attachment/add", add_params(thread, payload))
    upper = System.system_time(:millisecond)
    attachment = Map.fetch!(added.result, "attachment")
    id = Map.fetch!(attachment, "id")
    created = Map.fetch!(attachment, "createdAt")
    assert_uuid(id)
    assert is_integer(created) and div(lower, 1000) <= created and created <= div(upper, 1000)

    expected = %{
      "id" => id,
      "attachmentType" => @attachment_type,
      "identityKey" => @key,
      "payload" => payload,
      "createdAt" => created
    }

    assert added.result === %{"outcome" => "created", "attachment" => expected}
    validate_result(added, "v2/ThreadAttachmentAddResponse.json")
    {original, events} = await_change(session, thread, id, "created", added, lower, events)
    {expected, original, events}
  end

  defp await_change(session, thread, attachment, operation, exchange, lower, events) do
    params =
      Map.merge(identity_params(thread), %{"attachmentId" => attachment, "operation" => operation})

    events = collect_change(session, params, events, now() + 5_000)
    upper = System.system_time(:millisecond)

    [event] =
      Enum.filter(events, &(&1.wire["method"] == @updated and &1.wire["params"] == params))

    [original] = Enum.filter(attachment_originals(session), &(&1.wire["params"] == params))
    emitted = Map.fetch!(original.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    expected = %{"method" => @updated, "params" => params, "emittedAtMs" => emitted}
    assert event.kind === :notification and event.generation === session.generation
    assert event.wire === expected
    assert original.index > exchange.received_index
    assert_original(original, expected)
    assert :ok = Schema.validate(schema("ServerNotification.json"), expected, max_depth: 32)
    {original, events}
  end

  defp collect_change(session, params, events, deadline) do
    events = drain(session, events)

    cond do
      Enum.any?(events, &(&1.wire["method"] == @updated and &1.wire["params"] == params)) ->
        events

      now() >= deadline ->
        flunk("Native attachment notice deadline: #{inspect(Session.status(session.pid))}")

      true ->
        pid = session.pid

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Unexpected native gap: #{inspect(gap)}")
        after
          min(20, max(0, deadline - now())) -> :ok
        end

        collect_change(session, params, events, deadline)
    end
  end

  defp membership(session, thread, attachments, events) do
    owners = if attachments === [], do: [], else: [%{"threadId" => thread, "archived" => false}]

    Enum.reduce(1..2, events, fn _, acc ->
      listed =
        exchange(session, "thread/attachment/list", %{
          "threadId" => thread,
          "cursor" => nil,
          "limit" => 10
        })

      assert listed.result === %{"data" => attachments, "nextCursor" => nil}
      validate_result(listed, "v2/ThreadAttachmentListResponse.json")

      owner_list =
        exchange(session, "thread/attachmentOwner/list", %{
          "attachmentType" => @attachment_type,
          "identityKey" => @key,
          "archived" => false,
          "cursor" => nil,
          "limit" => 10
        })

      assert owner_list.result === %{"data" => owners, "nextCursor" => nil}
      validate_result(owner_list, "v2/ThreadAttachmentOwnerListResponse.json")
      assert_ready(session)
      drain(session, acc)
    end)
  end

  defp assert_unloaded(session) do
    loaded = exchange(session, "thread/loaded/list", %{})
    assert loaded.result === %{"data" => [], "nextCursor" => nil}
    validate_result(loaded, "v2/ThreadLoadedListResponse.json")
  end

  defp identity_params(thread),
    do: %{"threadId" => thread, "attachmentType" => @attachment_type, "identityKey" => @key}

  defp add_params(thread, payload), do: Map.put(identity_params(thread), "payload", payload)

  defp exchange(session, method, params) do
    id = request_id()
    request = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), request, max_depth: 32)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(session.pid, request, timeout_ms: 5_000)

    received_index = assert_exchange(session, request, response)
    %{result: result, received_index: received_index}
  end

  defp assert_exchange(session, request, response) do
    assert [sent, received] = Enum.filter(capture(session), &(&1.wire["id"] == request["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.index < received.index
    assert sent.encoded === JSON.encode!(request)
    assert_original(sent, request)
    assert response === %{"id" => request["id"], "result" => Map.fetch!(response, "result")}
    assert_original(received, response)
    received.index
  end

  defp assert_original(original, expected) do
    assert original.wire === expected
    assert JSON.decode!(original.encoded) === expected
    assert {:ok, preserved} = Wire.decode(original.encoded, max_depth: 32)
    assert preserved === expected
  end

  defp validate_result(exchange, relative),
    do: assert(:ok = Schema.validate(schema(relative), exchange.result, max_depth: 32))

  defp drain(session, events) do
    assert {:ok, batch} = Session.drain(session.pid, 128)
    events = events ++ batch
    assert length(events) <= 128

    assert Enum.all?(
             events,
             &(&1.kind === :notification and &1.generation === session.generation)
           )

    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
    events
  end

  defp assert_exact_notices(session, events, originals) do
    assert attachment_originals(session) === originals
    selected = Enum.filter(events, &(&1.wire["method"] == @updated))
    assert Enum.map(selected, & &1.wire) === Enum.map(originals, & &1.wire)
  end

  defp capture(session),
    do:
      Agent.get(session.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp attachment_originals(session),
    do: Enum.filter(capture(session), &(&1.direction === :in and &1.wire["method"] == @updated))

  defp assert_inventory(session, methods) do
    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    assert Enum.map(outgoing, & &1.wire["method"]) === methods
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === length(Enum.uniq(ids))
    replies = Enum.filter(records, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === length(requests)

    for request <- requests do
      assert [reply] = Enum.filter(replies, &(&1.wire["id"] == request.wire["id"]))
      assert request.index < reply.index

      assert_original(reply, %{
        "id" => request.wire["id"],
        "result" => Map.fetch!(reply.wire, "result")
      })
    end

    assert [initialized] = Enum.filter(outgoing, &(&1.wire["method"] == "initialized"))
    assert_original(initialized, %{"method" => "initialized"})
  end

  defp warm_methods do
    mutations = [
      "thread/attachment/add",
      "thread/attachment/add",
      "thread/attachment/remove",
      "thread/attachment/remove",
      "thread/attachment/add"
    ]

    @startup_methods ++
      ["thread/start", "turn/start"] ++
      Enum.flat_map(mutations, &([&1] ++ @membership_methods ++ @membership_methods))
  end

  defp assert_ready(session) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             status = Session.status(session.pid)

    assert status.generation === session.generation
    assert status.instance_id === session.instance_id
    assert Session.uncertain_operations(session.pid) === []
  end

  defp assert_inputs(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
    assert hash(File.read!(@script)) === @script_sha
  end

  defp close_native(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp schema(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)
      |> File.read!()
      |> JSON.decode!()

  defp assert_uuid(id), do: assert(is_binary(id) and Regex.match?(@uuid, id))
  defp request_id, do: "owned-attachment-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
