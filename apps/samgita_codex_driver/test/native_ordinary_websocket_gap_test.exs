defmodule SamgitaCodexDriver.NativeOrdinaryWebsocketGapTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Wire

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/ordinary_websocket_gap_fixture.py", __DIR__)
  @script_sha "902b9c19a7fded7a11d4050de94b6fe7bb7855aba8218889be7aa7d84eaca233"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned ordinary WebSocket detached stream λ🙂"
  @first "Owned visible λ "
  @answer @first <> "detached completion β🙂"
  @scoped ~w(turn/started turn/completed item/started item/completed item/agentMessage/delta)

  defmodule CaptureWebSocket do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.WebSocket
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- WebSocket.open(Keyword.delete(opts, :capture)) do
        generation =
          Agent.get_and_update(
            capture,
            &{&1.generation + 1, %{&1 | generation: &1.generation + 1}}
          )

        {:ok, Map.merge(state, %{capture: capture, capture_generation: generation})}
      end
    end

    @impl true
    def send(state, encoded) do
      case WebSocket.send(state, encoded) do
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
      case WebSocket.handle_info(message, state) do
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
          frame = %{direction: direction, generation: state.capture_generation, encoded: encoded}

          {:ok,
           %{ledger | frames: ledger.frames ++ [frame], bytes: ledger.bytes + byte_size(encoded)}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: WebSocket.close(state)
    @impl true
    def metadata(state), do: WebSocket.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    root = Path.join(System.tmp_dir!(), "owned-websocket-gap-#{suffix}")
    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-websocket-gap")
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
    capture = start_supervised!({Agent, fn -> %{generation: 0, frames: [], bytes: 0} end})
    %{binary: binary, root: root, fixture: fixture, resources: resources, capture: capture}
  end

  test "native detached WebSocket stream completes once and explicit history recovery preserves its gap",
       ctx do
    port = free_port()

    {:ok, native_owner} =
      Stdio.open(
        executable: ctx.binary,
        args:
          NativeLaunchFixture.ordinary_args(["app-server", "--listen", "ws://127.0.0.1:#{port}"]),
        cwd: ctx.fixture.workspace,
        inherit_env: [],
        max_message_bytes: 131_072,
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
      )

    :atomics.put(ctx.resources, 2, 1)

    on_exit(fn ->
      assert :ok = Stdio.close(native_owner)
      assert :atomics.get(native_owner.owner.completion, 1) === 1
      assert Port.info(native_owner.port) === nil
      :atomics.put(ctx.resources, 2, 2)
    end)

    wait_listener(port, now() + 5_000)

    {:ok, pid} =
      Session.start_link(
        max_events: 256,
        max_event_bytes: 1_048_576,
        max_message_bytes: 131_072,
        transport:
          {CaptureWebSocket,
           [
             url: "ws://127.0.0.1:#{port}/app-server",
             capture: ctx.capture,
             max_message_bytes: 131_072,
             max_frame_bytes: 131_072,
             max_read_bytes: 262_144,
             connect_timeout_ms: 3_000,
             send_timeout_ms: 3_000
           ]}
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    initialize(ctx, pid)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] === []

    thread =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    visible_deadline = now() + 5_000

    visible =
      collect(
        pid,
        [],
        fn events ->
          Enum.any?(events, &(get_in(&1.wire, ["params", "delta"]) === @first))
        end,
        visible_deadline
      )

    [delta] = Enum.filter(visible, &(&1.wire["method"] === "item/agentMessage/delta"))
    assert delta.wire["params"]["threadId"] === thread
    assert delta.wire["params"]["turnId"] === turn
    refute Enum.any?(visible, &(&1.wire["method"] === "turn/completed"))

    await_provider_checkpoint(
      ctx.fixture,
      %{"event" => "first_flushed", "handlers" => 1, "requests" => 1},
      visible_deadline
    )

    assert read_state(ctx.root)["first_flushed"] === true
    assert read_state(ctx.root)["released"] === false

    # Explicit native acknowledgement is the subscription-detach barrier.
    assert call(ctx, pid, "thread/unsubscribe", %{"threadId" => thread}) === %{
             "status" => "unsubscribed"
           }

    assert :ok = Session.reconnect(pid)
    assert %{phase: :new, generation: 2, gap: gap} = Session.status(pid)
    assert gap.reason === :explicit_reconnect and gap.generation === 1
    initialize(ctx, pid)
    assert %{phase: :ready, generation: 2, gap: ^gap} = Session.status(pid)

    assert {:ok, detached} = Session.drain(pid)
    refute Enum.any?(detached, &(&1.generation === 2 and &1.wire["method"] in @scoped))
    assert length(ModelFixture.requests(ctx.fixture)) === 1
    detached_deadline = now() + 5_000
    assert Port.command(ctx.fixture.port, JSON.encode!(%{"release" => true}) <> "\n")

    await_provider_checkpoint(
      ctx.fixture,
      %{"event" => "stream_finished", "handlers" => 0, "requests" => 1},
      detached_deadline
    )

    # Status is a global native projection, distinct from thread-scoped notices.
    # It supplies the causal barrier without polling repeated history requests.
    detached_completion =
      collect(
        pid,
        [],
        fn events ->
          Enum.any?(events, fn event ->
            event.generation === 2 and event.wire["method"] === "thread/status/changed" and
              event.wire["params"] === %{"threadId" => thread, "status" => %{"type" => "idle"}}
          end)
        end,
        detached_deadline,
        gap
      )

    # Reading does not subscribe. A later resume command runs on this same
    # serial native listener after its completion handler has returned.
    terminal =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert_history(terminal, thread, turn)
    assert read_state(ctx.root)["finished"] === true
    assert read_state(ctx.root)["errors"] === []
    refute Enum.any?(detached_completion, &(&1.generation === 2 and &1.wire["method"] in @scoped))

    resumed = call(ctx, pid, "thread/resume", %{"threadId" => thread})["thread"]
    assert_history(resumed, thread, turn)

    recovered =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert_history(recovered, thread, turn)
    assert recovered["turns"] === terminal["turns"]
    assert resumed["turns"] === terminal["turns"]

    assert call(ctx, pid, "thread/unsubscribe", %{"threadId" => thread}) === %{
             "status" => "unsubscribed"
           }

    assert {:ok, after_resume} = Session.drain(pid)
    refute Enum.any?(after_resume, &(&1.generation === 2 and &1.wire["method"] in @scoped))

    assert %{phase: :ready, generation: 2, pending: 0, interactions: 0, uncertain: 0, gap: ^gap} =
             Session.status(pid)

    [provider] = ModelFixture.requests(ctx.fixture)
    assert provider["thread_id"] === thread and provider["turn_id"] === turn
    assert provider["marker"] === @input and provider["model"] === "mock-model"
    assert provider["bytes"] > 0 and provider["bytes"] <= 1_048_576
    assert read_state(ctx.root)["handlers"] === 0

    frames = Agent.get(ctx.capture, & &1.frames)

    wires =
      Enum.map(frames, fn frame ->
        assert {:ok, wire} = Wire.decode(frame.encoded, max_depth: 64, max_bytes: 131_072)
        {frame, wire}
      end)

    outgoing = for {%{direction: :out}, wire} <- wires, do: wire
    assert Enum.count(outgoing, &(&1["method"] === "initialize")) === 2
    assert Enum.count(outgoing, &(&1["method"] === "initialized")) === 2
    assert Enum.count(outgoing, &(&1["method"] === "thread/start")) === 1
    assert Enum.count(outgoing, &(&1["method"] === "turn/start")) === 1
    assert Enum.count(outgoing, &(&1["method"] === "thread/resume")) === 1

    assert Enum.map(outgoing, & &1["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/start turn/start thread/unsubscribe initialize initialized thread/read thread/resume thread/read thread/unsubscribe)

    requests =
      for {%{direction: :out, generation: generation}, wire} <- wires,
          Map.has_key?(wire, "id"),
          do: {generation, wire}

    responses =
      for {%{direction: :in, generation: generation}, wire} <- wires,
          Map.has_key?(wire, "id"),
          do: {generation, wire}

    assert length(requests) === 11 and length(responses) === 11

    for {generation, request} <- requests do
      [{^generation, response}] =
        Enum.filter(responses, fn {reply_generation, reply} ->
          reply_generation === generation and
            Map.fetch!(reply, "id") === Map.fetch!(request, "id")
        end)

      assert Map.has_key?(response, "result") and not Map.has_key?(response, "error")
    end

    refute Enum.any?(wires, fn {frame, wire} ->
             frame.direction === :in and frame.generation === 2 and wire["method"] in @scoped
           end)

    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}")
    assert :ok = Stdio.close(native_owner)
    assert :atomics.get(native_owner.owner.completion, 1) === 1
    refute File.exists?("/proc/#{native}")
    :atomics.put(ctx.resources, 2, 2)
    assert hash(File.read!(@script)) === @script_sha
    assert length(ModelFixture.requests(ctx.fixture)) === 1
  end

  defp assert_history(thread, id, turn) do
    assert thread["id"] === id
    assert thread["status"] === %{"type" => "idle"}

    assert [%{"id" => ^turn, "status" => "completed", "items" => [user, assistant]}] =
             thread["turns"]

    assert user["type"] === "userMessage"
    assert user["content"] === [%{"type" => "text", "text" => @input, "text_elements" => []}]

    assert assistant === %{
             "type" => "agentMessage",
             "id" => "owned-websocket-gap-message",
             "text" => @answer,
             "phase" => nil,
             "memoryCitation" => nil,
             "delivery" => nil,
             "questions" => nil
           }
  end

  defp initialize(ctx, pid) do
    id = request_id()
    info = %{"name" => "owned_ordinary_websocket_gap", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    request = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    before = length(Agent.get(ctx.capture, & &1.frames))
    generation = Session.status(pid).generation

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 3_000)

    assert_exchange(ctx, before, generation, request, response)
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    request = %{"id" => id, "method" => method, "params" => params}
    before = length(Agent.get(ctx.capture, & &1.frames))
    generation = Session.status(pid).generation

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request(pid, method, params, id: id, timeout_ms: 3_000)

    assert_exchange(ctx, before, generation, request, response)
    result
  end

  defp assert_exchange(ctx, before, generation, request, response) do
    frames = Agent.get(ctx.capture, &Enum.drop(&1.frames, before))
    id = Map.fetch!(request, "id")
    assert Map.fetch!(response, "id") === id

    paired =
      for frame <- frames,
          frame.generation === generation,
          decoded = JSON.decode!(frame.encoded),
          Map.get(decoded, "id") === id,
          do: {frame, decoded}

    [{sent, original_request}] =
      Enum.filter(paired, fn {frame, _} -> frame.direction === :out end)

    [{received, original_response}] =
      Enum.filter(paired, fn {frame, _} -> frame.direction === :in end)

    assert original_request === request
    assert original_response === response

    for {frame, expected} <- [{sent, request}, {received, response}] do
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64, max_bytes: 131_072)
      assert decoded === expected
      assert JSON.decode!(frame.encoded) === expected
      assert Map.fetch!(decoded, "id") === id
    end
  end

  defp request_id, do: "owned-websocket-gap-#{System.unique_integer([:positive, :monotonic])}"

  defp await_provider_checkpoint(fixture, expected, deadline) do
    await_provider_checkpoint(fixture.port, expected, <<>>, deadline)
  end

  defp await_provider_checkpoint(port, expected, buffer, deadline) do
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
            await_provider_checkpoint(port, expected, buffer, deadline)
        end

      {^port, {:exit_status, status}} ->
        flunk("Owned provider exited before checkpoint: #{status}")
    after
      remaining -> flunk("Owned provider checkpoint deadline")
    end
  end

  defp collect(pid, events, predicate, deadline, expected_gap \\ nil) do
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch
    assert length(events) <= 128
    assert %{phase: :ready, gap: ^expected_gap} = Session.status(pid)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "Owned native stream observation deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        10 -> :ok
      end

      collect(pid, events, predicate, deadline, expected_gap)
    end
  end

  defp wait_listener(port, deadline) do
    assert now() < deadline, "Owned native listener deadline"

    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 50) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      {:error, _} ->
        receive do
        after
          10 -> :ok
        end

        wait_listener(port, deadline)
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp read_state(root),
    do: root |> Path.join("websocket-gap-state.json") |> File.read!() |> JSON.decode!()

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
