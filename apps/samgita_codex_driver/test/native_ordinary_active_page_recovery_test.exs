defmodule SamgitaCodexDriver.NativeOrdinaryActivePageRecoveryTest do
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
  alias SamgitaProtocolCodex.Wire

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/ordinary_active_page_fixture.py", __DIR__)
  @script_sha "d0db342363b622096bb5f7b8bfe798339ffd7cfc98fd4659828ce11f7e922b22"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @prefix "Owned active-page completed prefix λ"
  @active "Owned active-page interrupted turn 🙂"
  @answers ["Owned persisted prefix answer β", "Owned interrupted assistant answer γ🙂"]
  @item_ids ["owned-active-page-prefix-message", "owned-active-page-active-message"]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      label = Keyword.fetch!(opts, :label)

      with {:ok, state} <- Stdio.open(Keyword.drop(opts, [:capture, :label])) do
        {:ok, Map.merge(state, %{capture: capture, capture_label: label})}
      end
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
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
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        if length(ledger.frames) < 256 and byte_size(encoded) <= 131_072 and
             ledger.bytes + byte_size(encoded) <= 1_048_576 do
          frame = %{direction: direction, label: state.capture_label, encoded: encoded}

          {:ok,
           %{ledger | frames: ledger.frames ++ [frame], bytes: ledger.bytes + byte_size(encoded)}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
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
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    root = Path.join(System.tmp_dir!(), "owned-active-page-#{suffix}")
    File.mkdir!(root)
    resources = :atomics.new(3, [])

    on_exit(fn ->
      assert Enum.all?(1..3, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-active-page")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)
    provider_pid = read_state(root)["pid"]

    on_exit(fn ->
      assert :ok = ModelFixture.close(fixture)
      assert :atomics.get(fixture.transport.owner.completion, 1) === 1
      assert Port.info(fixture.port) === nil
      refute File.exists?("/proc/#{provider_pid}")
      :atomics.put(resources, 1, 2)
    end)

    TurnFixture.configure_model(%{fixture: fixture}, %{})
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    %{binary: binary, root: root, fixture: fixture, resources: resources, capture: capture}
  end

  test "small active bootstrap page survives explicit interrupt and first cold content read",
       ctx do
    {warm, warm_connection} = start(ctx, :warm, 2)
    warm_process = call(ctx, warm, "server/diagnostics", %{})["process"]["id"]

    thread =
      call(ctx, warm, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    prefix = start_turn(ctx, warm, thread, @prefix)

    prefix_events =
      collect(
        warm,
        [],
        fn events -> terminal?(events, thread, prefix, "completed") end,
        now() + 20_000
      )

    assert terminal?(prefix_events, thread, prefix, "completed")

    # Paginated includeTurns explicitly persists before history projection.
    before =
      call(ctx, warm, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert before["id"] === thread and before["status"] === %{"type" => "idle"}
    [prefix_snapshot] = before["turns"]
    assert_turn(prefix_snapshot, prefix, "completed", @prefix, 0)

    active = start_turn(ctx, warm, thread, @active)
    refute active === prefix
    checkpoint(ctx.fixture, %{"event" => "active_item_flushed", "requests" => 2}, now() + 3_000)

    active_events =
      collect(
        warm,
        [],
        fn events ->
          item_done?(events, thread, active) and trailing_started?(events, thread, active)
        end,
        now() + 3_000
      )

    assert item_done?(active_events, thread, active)
    assert trailing_started?(active_events, thread, active)

    refute Enum.any?(
             active_events,
             &(&1.wire["method"] === "turn/completed" and
                 &1.wire["params"]["turn"]["id"] === active)
           )

    assert read_state(ctx.root)["active_completed_sent"] === false

    params = %{"limit" => 2, "sortDirection" => "desc", "itemsView" => "full"}

    bootstrap =
      call(ctx, warm, "thread/resume", %{
        "threadId" => thread,
        "excludeTurns" => true,
        "initialTurnsPage" => params
      })

    assert bootstrap["thread"]["id"] === thread
    assert bootstrap["thread"]["turns"] === []
    assert %{"type" => "active"} = bootstrap["thread"]["status"]
    page = Map.fetch!(bootstrap, "initialTurnsPage")
    assert Enum.map(page["data"], & &1["id"]) === [active, prefix]
    [active_snapshot, prefix_page] = page["data"]
    assert prefix_page === prefix_snapshot
    # The pinned live reducer has legacy item-1/item-2 identities. Its
    # canonical paginated projection preserves provider/core identities instead.
    # The subsequent native item/started proves the prior legacy assistant event
    # has been reduced, without polling history or inventing native state.
    assert_turn(active_snapshot, active, "inProgress", @active, 1, "item-2")
    assert hd(active_snapshot["items"])["id"] === "item-1"
    assert Map.fetch!(page, "nextCursor") === nil
    assert is_binary(Map.fetch!(page, "backwardsCursor"))

    # A normal interrupt ACK waits for this original native TurnAborted.
    assert call(ctx, warm, "turn/interrupt", %{"threadId" => thread, "turnId" => active}) === %{}

    interrupted =
      collect(
        warm,
        active_events,
        fn events -> terminal?(events, thread, active, "interrupted") end,
        now() + 3_000
      )

    assert terminal?(interrupted, thread, active, "interrupted")
    assert Port.command(ctx.fixture.port, JSON.encode!(%{"close_active" => true}) <> "\n")
    checkpoint(ctx.fixture, %{"event" => "active_handler_closed", "requests" => 2}, now() + 3_000)

    settled =
      call(ctx, warm, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert settled["id"] === thread and settled["status"] === %{"type" => "idle"}
    assert Enum.map(settled["turns"], & &1["id"]) === [prefix, active]
    [persisted_prefix, persisted_active] = settled["turns"]
    assert persisted_prefix === prefix_snapshot
    assert_turn(persisted_active, active, "interrupted", @active, 1)

    assert Enum.map(persisted_active["items"], &Map.drop(&1, ["id"])) ===
             Enum.map(active_snapshot["items"], &Map.drop(&1, ["id"]))

    assert_provider_inventory(ctx, thread, prefix, active)
    close(ctx, warm, warm_connection, warm_process, 2)

    {cold, cold_connection} = start(ctx, :cold, 3)
    cold_process = call(ctx, cold, "server/diagnostics", %{})["process"]["id"]
    refute cold_process === warm_process
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] === []

    # FIRST content operation in the distinct process: no earlier read, list,
    # resume or implicit hydration can populate/correct this cold page.
    cold_page = call(ctx, cold, "thread/turns/list", Map.put(params, "threadId", thread))
    assert Enum.map(cold_page["data"], & &1["id"]) === [active, prefix]
    assert cold_page["data"] === [persisted_active, prefix_snapshot]
    assert Map.fetch!(cold_page, "nextCursor") === nil
    assert is_binary(Map.fetch!(cold_page, "backwardsCursor"))
    assert_turn(hd(cold_page["data"]), active, "interrupted", @active, 1)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] === []
    assert_provider_inventory(ctx, thread, prefix, active)
    assert Session.uncertain_operations(cold) === []
    close(ctx, cold, cold_connection, cold_process, 3)
    assert_wire_inventory(ctx, thread, prefix, active)
    assert hash(File.read!(@script)) === @script_sha
  end

  defp start(ctx, label, resource) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             max_message_bytes: 131_072,
             capture: ctx.capture,
             label: label,
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
               "SHELL" => "/bin/sh",
               "NO_PROXY" => "*",
               "no_proxy" => "*",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    :atomics.put(ctx.resources, resource, 1)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      :atomics.put(ctx.resources, resource, 2)
    end)

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_active_page_recovery", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               id: id,
               timeout_ms: 3_000
             )

    {pid, connection}
  end

  defp close(ctx, pid, connection, native_process, resource) do
    monitor = Process.monitor(pid)
    assert :ok = Session.close(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 3_000
    assert :ok = Stdio.close(connection)
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    refute File.exists?("/proc/#{native_process}")
    :atomics.put(ctx.resources, resource, 2)
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    %{connection: %{capture_label: label}} = :sys.get_state(pid)
    request = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request(pid, method, params, id: id, timeout_ms: 3_000)

    frames = Agent.get(ctx.capture, & &1.frames)

    for {direction, expected} <- [{:out, request}, {:in, response}] do
      [frame] =
        Enum.filter(
          frames,
          &(&1.label === label and &1.direction === direction and
              JSON.decode!(&1.encoded)["id"] === id)
        )

      assert JSON.decode!(frame.encoded) === expected
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64, max_bytes: 131_072)
      assert decoded === expected
    end

    result
  end

  defp start_turn(ctx, pid, thread, text),
    do:
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

  defp assert_turn(turn, id, status, text, index, assistant_id \\ nil) do
    assert turn["id"] === id and turn["status"] === status
    assert turn["itemsView"] === "full"
    [user, assistant] = turn["items"]
    assert user["type"] === "userMessage" and is_binary(user["id"])
    assert user["content"] === [%{"type" => "text", "text" => text, "text_elements" => []}]
    expected = expected_assistant(index)

    assert assistant ===
             if(assistant_id, do: Map.put(expected, "id", assistant_id), else: expected)

    assert length(Enum.uniq_by(turn["items"], & &1["id"])) === 2
  end

  defp expected_assistant(index),
    do: %{
      "type" => "agentMessage",
      "id" => Enum.at(@item_ids, index),
      "text" => Enum.at(@answers, index),
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

  defp terminal?(events, thread, turn, status),
    do:
      Enum.any?(events, fn event ->
        event.wire["method"] === "turn/completed" and event.wire["params"]["threadId"] === thread and
          event.wire["params"]["turn"]["id"] === turn and
          event.wire["params"]["turn"]["status"] === status
      end)

  defp item_done?(events, thread, turn),
    do:
      Enum.any?(events, fn event ->
        event.wire["method"] === "item/completed" and event.wire["params"]["threadId"] === thread and
          event.wire["params"]["turnId"] === turn and
          event.wire["params"]["item"] === expected_assistant(1)
      end)

  defp trailing_started?(events, thread, turn),
    do:
      Enum.any?(events, fn event ->
        expected =
          expected_assistant(1)
          |> Map.put("id", "owned-active-page-trailing-message")
          |> Map.put("text", "")

        event.wire["method"] === "item/started" and event.wire["params"]["threadId"] === thread and
          event.wire["params"]["turnId"] === turn and event.wire["params"]["item"] === expected
      end)

  defp collect(pid, events, predicate, deadline) do
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch
    assert length(events) <= 128
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "Owned active-page native checkpoint deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        10 -> :ok
      end

      collect(pid, events, predicate, deadline)
    end
  end

  defp checkpoint(fixture, expected, deadline),
    do: checkpoint(fixture.port, expected, <<>>, deadline)

  defp checkpoint(port, expected, buffer, deadline) do
    remaining = max(deadline - now(), 0)

    receive do
      {^port, {:data, bytes}} ->
        buffer = buffer <> bytes
        assert byte_size(buffer) <= 4096

        case String.split(buffer, "\n", parts: 2) do
          [line, rest] ->
            assert rest === ""
            assert JSON.decode!(line) === expected

          [_partial] ->
            checkpoint(port, expected, buffer, deadline)
        end

      {^port, {:exit_status, status}} ->
        flunk("Owned active-page provider exited: #{status}")
    after
      remaining -> flunk("Owned active-page provider checkpoint deadline")
    end
  end

  defp assert_provider_inventory(ctx, thread, prefix, active) do
    [first, second] = ModelFixture.requests(ctx.fixture)
    assert first["index"] === 0 and first["thread_id"] === thread and first["turn_id"] === prefix
    assert first["markers"] === [@prefix]

    assert second["index"] === 1 and second["thread_id"] === thread and
             second["turn_id"] === active

    assert second["markers"] === [@prefix, @active]
    assert Enum.all?([first, second], &(&1["bytes"] > 0 and &1["bytes"] <= 1_048_576))
    state = read_state(ctx.root)
    assert state["prefix_completed_sent"] === true and state["active_item_flushed"] === true
    assert state["active_completed_sent"] === false and state["active_closed"] === true
    assert state["handlers"] === 0 and state["errors"] === []
  end

  defp assert_wire_inventory(ctx, thread, prefix, active) do
    wires =
      Enum.map(Agent.get(ctx.capture, & &1.frames), fn frame ->
        assert {:ok, wire} = Wire.decode(frame.encoded, max_depth: 64, max_bytes: 131_072)
        assert wire === JSON.decode!(frame.encoded)
        {frame, wire}
      end)

    outgoing = for {%{direction: :out}, wire} <- wires, do: wire

    assert Enum.map(outgoing, & &1["method"]) ===
             ~w(initialize initialized server/diagnostics thread/start turn/start thread/read turn/start thread/resume turn/interrupt thread/read initialize initialized server/diagnostics thread/loaded/list thread/turns/list thread/loaded/list)

    requests =
      for {%{direction: :out, label: label}, wire} <- wires,
          Map.has_key?(wire, "id"),
          do: {label, wire}

    responses =
      for {%{direction: :in, label: label}, wire} <- wires,
          Map.has_key?(wire, "id"),
          do: {label, wire}

    assert length(requests) === 14 and length(responses) === 14
    assert length(Enum.uniq_by(requests, fn {_label, wire} -> wire["id"] end)) === 14

    for {label, request} <- requests do
      [{^label, response}] =
        Enum.filter(responses, fn {reply_label, reply} ->
          reply_label === label and reply["id"] === request["id"]
        end)

      assert Map.has_key?(response, "result") and not Map.has_key?(response, "error")
    end

    assert_turn_event_inventory(wires, thread, prefix, active)
  end

  defp assert_turn_event_inventory(wires, thread, prefix, active) do
    started =
      for {%{direction: :in, label: :warm}, %{"method" => "turn/started", "params" => params}} <-
            wires,
          params["threadId"] === thread,
          do: params["turn"]["id"]

    assert started === [prefix, active]

    completed =
      for {%{direction: :in, label: :warm}, %{"method" => "turn/completed", "params" => params}} <-
            wires,
          params["threadId"] === thread,
          do: {params["turn"]["id"], params["turn"]["status"]}

    assert completed === [{prefix, "completed"}, {active, "interrupted"}]

    cold_turn_events =
      for {%{direction: :in, label: :cold}, %{"method" => method}} <- wires,
          method in ~w(turn/started turn/completed item/started item/completed item/agentMessage/delta),
          do: method

    assert cold_turn_events === []
  end

  defp request_id, do: "owned-active-page-#{System.unique_integer([:positive, :monotonic])}"

  defp read_state(root),
    do: root |> Path.join("active-page-state.json") |> File.read!() |> JSON.decode!()

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
