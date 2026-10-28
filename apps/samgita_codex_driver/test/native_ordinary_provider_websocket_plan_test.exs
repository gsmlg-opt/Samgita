defmodule SamgitaCodexDriver.NativeOrdinaryProviderWebsocketPlanTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand(
            "../../../scripts/codex/ordinary_provider_websocket_plan_fixture.py",
            __DIR__
          )
  @script_sha "84d02fc5d840fed0eebfb52bacf6429b3e09854450af9ea8769887ae02cb965e"
  @notification_sha "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1"
  @node_sha "565fa8b5abbd16a7d83b8368ad9a2b364902095465634efaa584b2eef01825a2"
  @node_bytes """
  {
    "$ref": "#/definitions/PlanType"
  }
  """
  @input "Owned ordinary provider WebSocket quota metadata λ🙂"
  @answer "Owned provider WebSocket quota response β🙂"
  @rate_method "account/rateLimits/updated"
  @rate_projection %{"limitId" => "owned_provider_plan", "planType" => "pro"}

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
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 128, else: 768
      message_limit = if direction == :out, do: 4096, else: 131_072
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 4_194_304 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
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
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(schema_path("ServerNotification.json"))) === @notification_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-provider-plan-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    resources = :atomics.new(3, [])

    on_exit(fn ->
      assert Enum.all?(1..3, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining provider fixture #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-provider-websocket-plan")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)

    on_exit(fn ->
      assert :ok = ModelFixture.close(fixture)
      assert :atomics.get(fixture.transport.owner.completion, 1) === 1
      assert Port.info(fixture.port) === nil
      :atomics.put(resources, 1, 2)
    end)

    paths = [
      @script,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "models.json"),
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex"),
      schema_path("ClientRequest.json"),
      schema_path("ServerNotification.json")
    ]

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: capture,
      resources: resources,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "native provider WebSocket quota metadata preserves nonnull planType through completion and cold history",
       ctx do
    warm = start(ctx, 2)
    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert peer(ctx)["requests"] === []

    thread_result =
      call(ctx, warm.pid, "thread/start", %{
        "cwd" => ctx.fixture.workspace,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "ephemeral" => false,
        "historyMode" => "paginated"
      })

    thread = thread_result["thread"]["id"]
    assert is_binary(thread) and byte_size(thread) > 0
    await_peer(ctx, "prewarm_served")
    assert [%{"kind" => "prewarm"}] = ModelFixture.requests(ctx.fixture)

    assert Enum.map(peer(ctx)["sent"], &JSON.decode!(&1["raw"])["type"]) ===
             ["response.created", "response.completed"]

    turn_result =
      call(ctx, warm.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })

    turn = turn_result["turn"]["id"]
    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(warm.pid, thread, turn, [], now() + 15_000)
    await_peer(ctx, "generation_served")
    assert_turn(events, thread, turn)
    assert_native_rates(ctx, events)
    assert_peer(ctx)
    history = call(ctx, warm.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert_history(history, thread, turn)
    assert_controls(ctx)
    assert_idle(warm.pid)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    await_peer(ctx, "provider_closed")
    assert peer(ctx)["activeConnections"] === 0
    assert peer(ctx)["connectionClosures"] === 1
    original_peer = peer(ctx)
    original_requests = ModelFixture.requests(ctx.fixture)

    cold = start(ctx, 3)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    cold_history =
      call(ctx, cold.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})

    assert_history(cold_history, thread, turn)
    assert cold_history["thread"]["turns"] === history["thread"]["turns"]
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert peer(ctx) === original_peer
    assert ModelFixture.requests(ctx.fixture) === original_requests
    assert_idle(cold.pid)
    close(cold)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    assert_controls(ctx)
    close_peer(ctx)
    assert_controls(ctx)
  end

  defp assert_turn(events, thread, turn) do
    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/completed",
               do: event.wire["params"]
             )

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/started",
               do: event.wire["params"]
             )

    assert [started] =
             for(
               event <- events,
               event.wire["method"] == "item/started",
               event.wire["params"]["item"]["type"] == "userMessage",
               do: event.wire["params"]
             )

    assert [completed] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "userMessage",
               do: event.wire["params"]
             )

    user = completed["item"]

    assert user === %{
             "type" => "userMessage",
             "id" => user["id"],
             "clientId" => nil,
             "content" => [%{"type" => "text", "text" => @input, "text_elements" => []}]
           }

    assert started["item"] === user

    for params <- [started, completed] do
      assert params["threadId"] === thread and params["turnId"] === turn
    end

    assert [agent] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]
             )

    assert agent["threadId"] === thread and agent["turnId"] === turn
    assert agent["item"] === expected_agent()
  end

  defp expected_agent,
    do: %{
      "type" => "agentMessage",
      "id" => "owned-provider-plan-message",
      "text" => @answer,
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

  defp assert_native_rates(ctx, events) do
    selected = Enum.filter(events, &(&1.wire["method"] === @rate_method))
    assert length(selected) in 1..8
    document = schema("ServerNotification.json")
    definitions = document["definitions"]

    node =
      get_in(definitions, ["RateLimitSnapshot", "properties", "planType", "anyOf"]) |> Enum.at(0)

    assert node === %{"$ref" => "#/definitions/PlanType"}
    assert JSON.decode!(@node_bytes) === node
    assert hash(@node_bytes) === @node_sha
    node_document = Map.put(node, "definitions", Map.take(definitions, ["PlanType"]))

    originals =
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.in, fn entry -> entry.wire["method"] === @rate_method end)
      )

    assert length(originals) === length(selected)

    for {event, original} <- Enum.zip(selected, originals) do
      assert event.kind === :notification
      rates = event.wire["params"]["rateLimits"]
      assert is_map(rates)
      assert Map.take(rates, ["limitId", "planType"]) === @rate_projection
      # Only this positive descriptive field is qualified. Entitlement,
      # credit, account and permission outputs remain opaque captured data.
      assert :ok = Schema.validate(node_document, rates["planType"])
      assert original.wire === event.wire
      assert JSON.decode!(original.encoded) === event.wire
      assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 64)
      assert decoded === event.wire
    end
  end

  defp assert_history(history, thread, turn) do
    assert history["thread"]["id"] === thread

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => items}] =
             history["thread"]["turns"]

    assert [user, agent] = items
    assert user["type"] === "userMessage"
    assert user["content"] === [%{"type" => "text", "text" => @input, "text_elements" => []}]
    assert agent === expected_agent()
  end

  defp assert_peer(ctx) do
    data = peer(ctx)
    assert data["errors"] === []
    assert data["http"] === [%{"method" => "GET", "path" => "/v1/responses"}]
    assert data["httpCount"] === 1 and data["connections"] === 1
    assert data["activeConnections"] === 1 and data["connectionClosures"] === 0
    assert data["receivedFrames"] in 2..6 and data["sentFrames"] in 6..10
    assert [prewarm, generation] = data["requests"]
    assert [prewarm, generation] === ModelFixture.requests(ctx.fixture)
    assert prewarm["kind"] === "prewarm" and generation["kind"] === "generation"

    for entry <- [prewarm, generation] do
      assert JSON.decode!(entry["raw"]) === entry["request"]
      assert entry["request"]["type"] === "response.create"
      assert entry["request"]["model"] === "mock-model"
      assert byte_size(entry["raw"]) <= 262_144
    end

    assert prewarm["request"]["generate"] === false
    refute Map.has_key?(generation["request"], "generate")
    assert provider_markers(prewarm["request"]) === []
    assert provider_markers(generation["request"]) === [@input]

    expected = [
      %{"type" => "response.created", "response" => %{"id" => "owned-provider-plan-prewarm"}},
      %{
        "type" => "response.completed",
        "response" => %{
          "id" => "owned-provider-plan-prewarm",
          "usage" => %{
            "input_tokens" => 0,
            "input_tokens_details" => nil,
            "output_tokens" => 0,
            "output_tokens_details" => nil,
            "total_tokens" => 0
          }
        }
      },
      %{"type" => "response.created", "response" => %{"id" => "owned-provider-plan-response"}},
      %{
        "type" => "codex.rate_limits",
        "plan_type" => "pro",
        "metered_limit_name" => "owned-provider-plan",
        "rate_limits" => %{
          "primary" => %{
            "used_percent" => 12.5,
            "window_minutes" => 60,
            "reset_at" => 1_704_069_000
          },
          "secondary" => %{
            "used_percent" => 73.4,
            "window_minutes" => 10_080,
            "reset_at" => 1_704_673_800
          }
        }
      },
      %{
        "type" => "response.output_item.done",
        "item" => %{
          "id" => "owned-provider-plan-message",
          "type" => "message",
          "role" => "assistant",
          "content" => [%{"type" => "output_text", "text" => @answer}]
        }
      },
      %{
        "type" => "response.completed",
        "response" => %{
          "id" => "owned-provider-plan-response",
          "usage" => %{
            "input_tokens" => 7,
            "input_tokens_details" => nil,
            "output_tokens" => 3,
            "output_tokens_details" => nil,
            "total_tokens" => 10
          }
        }
      }
    ]

    assert Enum.map(data["sent"], &JSON.decode!(&1["raw"])) === expected

    for entry <- data["sent"] do
      assert Base.decode64!(entry["frame"]) === server_frame(entry["raw"])
    end
  end

  defp server_frame(raw) when byte_size(raw) < 126, do: <<0x81, byte_size(raw)>> <> raw

  defp server_frame(raw) when byte_size(raw) <= 65_535,
    do: <<0x81, 126, byte_size(raw)::16>> <> raw

  defp server_frame(raw), do: <<0x81, 127, byte_size(raw)::64>> <> raw

  defp provider_markers(request),
    do:
      for(
        item <- request["input"],
        item["role"] == "user",
        part <- Map.get(item, "content", []),
        part["type"] == "input_text",
        part["text"] == @input,
        do: part["text"]
      )

  defp start(ctx, resource_slot) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    :atomics.put(ctx.resources, resource_slot, 1)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      :atomics.put(ctx.resources, resource_slot, 2)
    end)

    id = request_id()
    info = %{"name" => "owned_ordinary_provider_websocket_plan", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp await_peer(ctx, event), do: await_peer(ctx, event, <<>>, now() + 5_000)

  defp await_peer(ctx, event, buffer, deadline) do
    port = ctx.fixture.port
    remaining = max(deadline - now(), 0)

    receive do
      {^port, {:data, part}} ->
        buffer = buffer <> part
        assert byte_size(buffer) <= 4096

        case String.split(buffer, "\n", parts: 2) do
          [line, rest] ->
            assert rest === ""
            assert JSON.decode!(line) === %{"event" => event}

          [_partial] ->
            await_peer(ctx, event, buffer, deadline)
        end

      {^port, {:exit_status, status}} ->
        flunk("Owned provider dependency exited: #{status}")
    after
      remaining -> flunk("Owned provider dependency barrier not reached: #{event}")
    end
  end

  defp collect(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    complete =
      Enum.any?(
        events,
        &(&1.wire["method"] === "turn/completed" and
            &1.wire["params"]["threadId"] === thread and &1.wire["params"]["turn"]["id"] === turn)
      )

    rates = Enum.any?(events, &(&1.wire["method"] === @rate_method))

    if complete and rates do
      events
    else
      remaining = deadline - now()
      assert remaining > 0, "Owned ordinary provider turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary provider event gap")
      after
        remaining -> flunk("Owned ordinary provider turn event barrier was not reached")
      end

      collect(pid, thread, turn, events, deadline)
    end
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_controls(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert File.ls!(ctx.fixture.workspace) === []
    assert peer(ctx)["errors"] === []
  end

  defp peer(ctx),
    do: snapshot(Path.join(ctx.root, "provider-websocket-plan-peer.json")).bytes |> JSON.decode!()

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert {:ok, []} = Session.drain(pid, 256)
  end

  defp close(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_peer(ctx) do
    native = peer(ctx)["pid"]
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    refute File.exists?("/proc/#{native}")

    assert JSON.decode!(
             snapshot(Path.join(ctx.root, "provider-websocket-plan-closed.json")).bytes
           ) ===
             %{
               "activeSockets" => 0,
               "handlerThreads" => 0,
               "threadAlive" => false,
               "serverClosed" => true
             }
  end

  defp assert_inventory(ledger) do
    warm =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/start turn/start thread/read)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/read thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 11 and length(Enum.uniq(ids)) === 11
    assert length(replies) === 11
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 2_097_152
    bytes = File.read!(path)
    assert byte_size(bytes) <= 2_097_152
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-provider-plan-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
