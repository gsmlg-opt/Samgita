defmodule SamgitaCodexDriver.NativeCollaborationFailureRunningTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [configure_model: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/collaboration_failure_running_fixture.py", __DIR__)
  @script_sha "7ebf31807ea44629ecae248870e0211d0a8057d65e5242f8772c5e51b76461f6"
  @base_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @base_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @root "OWNED_V359_ROOT"
  @child_a "OWNED_V359_CHILD_FAILURE"
  @child_b "OWNED_V359_CHILD_HELD"
  @failure "Owned V359 child failure."
  @answer "Owned V359 root continued after failure and shutdown."
  @calls ~w(owned-v359-spawn-a owned-v359-wait-a owned-v359-close-a owned-v359-spawn-b owned-v359-close-b)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      frames = Agent.get(state.capture, & &1)

      if length(frames) < 32 and byte_size(encoded) <= 4096 and
           Enum.reduce(frames, byte_size(encoded), &(byte_size(&1.encoded) + &2)) <= 131_072 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: JSON.decode!(encoded)}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@script)) == @script_sha
    assert hash(File.read!(@base_script)) == @base_sha

    root =
      Path.join(System.tmp_dir!(), "owned-v359-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, root: root, fixture: fixture}

    configure_model(ctx, %{
      "multi_agent_version" => "v1",
      "default_reasoning_level" => "low",
      "supported_reasoning_levels" => [%{"effort" => "low", "description" => "Owned low effort"}]
    })

    originals =
      Map.new(
        [@script, @base_script | Path.wildcard(Path.join(fixture.codex_home, "*.{toml,json}"))],
        &{&1, File.read!(&1)}
      )

    Map.merge(ctx, %{originals: originals, capture: start_supervised!({Agent, fn -> [] end})})
  end

  test "failed child propagates to parent and held running child closes with retained historical snapshot",
       ctx do
    {pid, connection} = start_native(ctx)
    native = native_id(ctx, pid)
    instance = Session.status(pid).instance_id

    root =
      request(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(root) and byte_size(root) > 0
    assert ModelFixture.requests(ctx.fixture) == []
    before_turn = System.system_time(:millisecond)

    turn =
      request(ctx, pid, "turn/start", %{
        "threadId" => root,
        "input" => [%{"type" => "text", "text" => @root}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = complete(pid, root, turn, [], System.monotonic_time(:millisecond) + 20_000)
    after_turn = System.system_time(:millisecond)
    requests = ModelFixture.requests(ctx.fixture)
    {a, b} = assert_provider(ctx, requests, root, turn)

    assert [final] =
             Enum.filter(
               events,
               &(&1.wire["method"] == "item/completed" and &1.wire["params"]["threadId"] == root and
                   get_in(&1.wire, ["params", "item", "type"]) == "agentMessage")
             )

    assert final.wire["params"]["turnId"] == turn
    assert final.wire["params"]["item"]["text"] === @answer
    assert request(ctx, pid, "thread/loaded/list", %{})["data"] == [root]

    definitions = [
      {"owned-v359-wait-a", "wait", a, "failed", "errored", @failure},
      {"owned-v359-close-a", "closeAgent", a, "failed", "errored", @failure},
      {"owned-v359-close-b", "closeAgent", b, "completed", "running", nil}
    ]

    expected =
      for definition <- definitions do
        terminal_entry(events, root, turn, definition, before_turn, after_turn)
      end

    # Spawn snapshots are deliberately not an oracle: native scheduling can
    # advance them. Wait and both closes have independently prescribed states.
    query = %{
      "threadId" => root,
      "turnId" => turn,
      "itemIds" => ["owned-v359-close-b", "owned-v359-wait-a", "owned-v359-close-a"]
    }

    assert_selection(ctx, pid, query, expected)
    journal = File.read!(ctx.fixture.requests)
    observed = File.read!(Path.join(ctx.root, "failure-running-observed.json"))
    assert_ready(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    refute File.exists?("/proc/#{native}")

    {cold, cold_connection} = start_native(ctx)
    replacement = native_id(ctx, cold)
    assert replacement != native
    refute Session.status(cold).instance_id == instance
    assert request(ctx, cold, "thread/loaded/list", %{})["data"] == []
    # First content operation in the distinct process is selective persistence.
    assert_selection(ctx, cold, query, expected)
    assert request(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert {:ok, remaining} = Session.drain(cold, 256)

    refute Enum.any?(
             remaining,
             &(&1.kind == :server_request or
                 &1.wire["method"] in [
                   "turn/started",
                   "turn/completed",
                   "item/started",
                   "item/completed"
                 ])
           )

    assert File.read!(ctx.fixture.requests) === journal
    assert File.read!(Path.join(ctx.root, "failure-running-observed.json")) === observed
    assert assert_provider(ctx, ModelFixture.requests(ctx.fixture), root, turn) == {a, b}
    assert Enum.all?(ctx.originals, fn {path, bytes} -> File.read!(path) === bytes end)
    assert File.ls!(ctx.fixture.workspace) == []
    assert_ready(cold)
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    refute File.exists?("/proc/#{replacement}")
    assert File.read!(ctx.fixture.requests) === journal
  end

  defp terminal_entry(
         events,
         root,
         turn,
         {id, tool, child, status, child_status, message},
         before_time,
         after_time
       ) do
    expected = %{
      "id" => id,
      "type" => "collabAgentToolCall",
      "tool" => tool,
      "status" => status,
      "senderThreadId" => root,
      "receiverThreadIds" => [child],
      "prompt" => nil,
      "model" => nil,
      "reasoningEffort" => nil,
      "agentsStates" => %{child => %{"status" => child_status, "message" => message}}
    }

    matching = fn method ->
      Enum.filter(
        events,
        &(&1.wire["method"] == method and &1.wire["params"]["threadId"] == root and
            &1.wire["params"]["turnId"] == turn and
            get_in(&1.wire, ["params", "item", "id"]) == id)
      )
    end

    assert [started] = matching.("item/started")
    assert [completed] = matching.("item/completed")
    start_time = Map.fetch!(started.wire["params"], "startedAtMs")
    end_time = Map.fetch!(completed.wire["params"], "completedAtMs")
    assert is_integer(start_time) and is_integer(end_time)
    assert before_time <= start_time and start_time <= end_time and end_time <= after_time
    assert started.sequence < completed.sequence

    assert started.wire["params"] === %{
             "threadId" => root,
             "turnId" => turn,
             "startedAtMs" => start_time,
             "item" => %{expected | "status" => "inProgress", "agentsStates" => %{}}
           }

    assert completed.wire["params"] === %{
             "threadId" => root,
             "turnId" => turn,
             "completedAtMs" => end_time,
             "item" => expected
           }

    schema = schema("ServerNotification.json")

    for event <- [started, completed] do
      assert :ok = Schema.validate(schema, event.wire, max_depth: 32)
      assert_codec(event.wire)
    end

    %{
      "turnId" => turn,
      "item" => expected,
      "startedAtMs" => start_time,
      "completedAtMs" => end_time
    }
  end

  defp assert_selection(ctx, pid, query, expected) do
    actual = request(ctx, pid, "thread/items/read", query)
    assert actual === %{"data" => expected}
    assert :ok = Schema.validate(schema("v2/ThreadItemsReadResponse.json"), actual, max_depth: 32)
    assert_ready(pid)
  end

  defp assert_provider(ctx, requests, root, turn) do
    assert length(requests) == 8
    a = tool_result(requests, "owned-v359-spawn-a")["agent_id"]
    b = tool_result(requests, "owned-v359-spawn-b")["agent_id"]
    assert is_binary(a) and a != root
    assert is_binary(b) and b not in [root, a]
    grouped = Enum.group_by(requests, &metadata(&1)["thread_id"])
    assert Enum.sort(Map.keys(grouped)) == Enum.sort([root, a, b])
    root_requests = Map.fetch!(grouped, root)
    assert length(root_requests) == 6
    assert Enum.map(root_requests, &metadata(&1)["turn_id"]) == List.duplicate(turn, 6)

    for {request, index} <- Enum.with_index(root_requests) do
      results = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))
      assert Enum.map(results, & &1["call_id"]) === Enum.take(@calls, index)
      assert Enum.count(user_texts(request), &(&1 == @root)) == 1
    end

    for {child, marker} <- [{a, @child_a}, {b, @child_b}] do
      assert [request] = Map.fetch!(grouped, child)
      assert is_binary(metadata(request)["turn_id"]) and metadata(request)["turn_id"] != turn
      assert Enum.count(user_texts(request), &(&1 == marker)) == 1
      refute @root in user_texts(request)
      assert Enum.filter(request["input"], &(&1["type"] == "function_call_output")) == []
    end

    for request <- requests do
      assert request["model"] == "mock-model"
      assert request["reasoning"]["effort"] == "low"
    end

    assert tool_result(requests, "owned-v359-wait-a") === %{
             "status" => %{a => %{"errored" => @failure}},
             "timed_out" => false
           }

    assert tool_result(requests, "owned-v359-close-a") === %{
             "previous_status" => %{"errored" => @failure}
           }

    assert tool_result(requests, "owned-v359-close-b") === %{"previous_status" => "running"}

    observed =
      ctx.root |> Path.join("failure-running-observed.json") |> File.read!() |> JSON.decode!()

    assert observed === %{
             "root_requests" => 6,
             "child_a_requests" => 1,
             "child_b_requests" => 1,
             "root_responses" => @calls ++ ["root_final"],
             "failure_sent" => true,
             "b_held" => true,
             "close_b_after_request" => true,
             "errors" => []
           }

    {a, b}
  end

  defp tool_result(requests, id) do
    values =
      for request <- requests,
          item <- request["input"],
          item["type"] == "function_call_output" and item["call_id"] == id,
          do: JSON.decode!(item["output"])

    assert [value] = Enum.uniq(values)
    value
  end

  defp user_texts(request),
    do:
      for(
        item <- request["input"],
        item["role"] == "user",
        content <- item["content"],
        content["type"] == "input_text",
        do: content["text"]
      )

  defp metadata(request), do: JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

  defp complete(pid, root, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert length(Enum.uniq_by(events, & &1.wire["method"])) <= 32
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert Enum.all?(events, &(&1.kind == :notification and &1.generation == generation))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.sort(Enum.uniq(sequences))

    refute Enum.any?(
             events,
             &(&1.wire["method"] == "error" and &1.wire["params"]["threadId"] == root)
           )

    terminal =
      Enum.filter(
        events,
        &(&1.wire["method"] == "turn/completed" and &1.wire["params"]["threadId"] == root and
            get_in(&1.wire, ["params", "turn", "id"]) == turn)
      )

    case terminal do
      [event] ->
        assert event.wire["params"]["turn"]["status"] == "completed"
        events

      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Native v359 root completion deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected collaboration event gap")
        after
          remaining -> flunk("Native v359 root completion deadline")
        end

        complete(pid, root, turn, events, deadline)

      _ ->
        flunk("Duplicate native root terminal event")
    end
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-v359-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request(pid, method, params, id: id, timeout_ms: 5_000)

    assert [frame] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert frame.wire === %{"id" => id, "method" => method, "params" => params}
    assert JSON.decode!(frame.encoded) === frame.wire
    assert_codec(response)
    result
  end

  defp assert_codec(wire) do
    assert {:ok, bytes} = Wire.encode(wire, max_depth: 32)
    assert {:ok, preserved} = Wire.decode(bytes, max_depth: 32)
    assert preserved === wire
  end

  defp schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp assert_ready(pid),
    do:
      assert(
        %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
          Session.status(pid)
      )

  defp native_id(ctx, pid) do
    id = request(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(id) and id > 0
    assert hash(File.read!("/proc/#{id}/exe")) == @binary_sha
    id
  end

  defp start_native(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             executable: ctx.binary,
             capture: ctx.capture,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    connection = :sys.get_state(pid).connection

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(connection.owner.completion, 1) == 1
      assert Port.info(connection.port) == nil
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_collaboration_failure_running", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "optOutNotificationMethods" => ["remoteControl/status/changed"]
               }
             )

    {pid, connection}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
