defmodule SamgitaCodexDriver.NativeCollaborationLifecycleValuesTest do
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
  @script Path.expand("../../../scripts/codex/collaboration_lifecycle_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @first "OWNED_COLLAB_CHILD_FIRST"
  @followup "OWNED_COLLAB_CHILD_FOLLOWUP"
  @first_done "Owned collaboration child first done"
  @followup_done "Owned collaboration child followup done"
  @captured_methods ["thread/start", "turn/start", "thread/items/read", "thread/loaded/list"]

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
      wire = JSON.decode!(encoded)

      if wire["method"] in [
           "thread/start",
           "turn/start",
           "thread/items/read",
           "thread/loaded/list"
         ] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
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

  setup tags do
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

    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "multi_agent_version" => "v1",
      "default_reasoning_level" => "low",
      "supported_reasoning_levels" => [%{"effort" => "low", "description" => "Owned low effort"}]
    })

    inputs = [@script | Path.wildcard(Path.join(ctx.fixture.codex_home, "*.{toml,json}"))]
    originals = Map.new(inputs, &{&1, File.read!(&1)})
    Map.merge(ctx, %{capture: start_supervised!({Agent, fn -> [] end}), originals: originals})
  end

  test "one real child completes, closes, resumes and receives a distinct followup", ctx do
    pid = start(ctx)

    root =
      request(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(root)
    first = run_phase(ctx, pid, root, 1)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 6
    child = tool_result(requests, "owned-collab-spawn")["agent_id"]
    assert is_binary(child) and child != root
    assert loaded(ctx, pid) == [root]

    expected_first =
      items(root, child, [
        {"owned-collab-spawn", "spawnAgent", @first, "mock-model", "low", nil},
        {"owned-collab-wait-first", "wait", nil, nil, nil, @first_done},
        {"owned-collab-close-first", "closeAgent", nil, nil, nil, @first_done},
        {"owned-collab-wait-closed", "wait", nil, nil, nil, :not_found}
      ])

    assert_terminal_items(ctx, pid, root, first, expected_first)
    assert File.read!(ctx.fixture.requests) |> JSON.decode!() == requests

    resumed = run_phase(ctx, pid, root, 2)
    assert length(ModelFixture.requests(ctx.fixture)) == 8

    # A separate public query after the completed resume turn proves this
    # exact child was loaded before send_input could auto-load anything.
    assert loaded(ctx, pid) == Enum.sort([root, child])

    assert_terminal_items(
      ctx,
      pid,
      root,
      resumed,
      items(root, child, [{"owned-collab-resume", "resumeAgent", nil, nil, nil, nil}])
    )

    followup = run_phase(ctx, pid, root, 3)
    assert loaded(ctx, pid) == [root]

    assert_terminal_items(
      ctx,
      pid,
      root,
      followup,
      items(root, child, [
        {"owned-collab-send", "sendInput", @followup, nil, nil, nil},
        {"owned-collab-wait-followup", "wait", nil, nil, nil, @followup_done},
        {"owned-collab-close-followup", "closeAgent", nil, nil, nil, @followup_done}
      ])
    )

    journal = File.read!(ctx.fixture.requests)
    assert_provider_journal(JSON.decode!(journal), root, child, [first, resumed, followup])
    assert_terminal_items(ctx, pid, root, first, expected_first)
    assert loaded(ctx, pid) == [root]
    assert File.read!(ctx.fixture.requests) == journal
    assert Enum.all?(ctx.originals, fn {path, bytes} -> File.read!(path) == bytes end)
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    wires = Agent.get(ctx.capture, & &1)
    assert length(wires) == 12
    assert length(Enum.uniq_by(wires, & &1["id"])) == length(wires)
    native = native_id(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp run_phase(ctx, pid, root, phase) do
    before_turn = System.system_time(:millisecond)

    turn =
      request(ctx, pid, "turn/start", %{
        "threadId" => root,
        "input" => [%{"type" => "text", "text" => "OWNED_COLLAB_ROOT_#{phase}"}]
      })["turn"]["id"]

    assert is_binary(turn)
    events = complete(pid, root, turn, [], deadline(20_000))
    after_turn = System.system_time(:millisecond)

    assert %{"item" => %{"text" => text}} =
             TurnFixture.notification(events, "item/completed", fn params ->
               params["threadId"] == root and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)

    assert text == "Owned collaboration root #{phase} done"
    %{id: turn, events: events, before: before_turn, after: after_turn}
  end

  defp items(root, child, definitions) do
    for {id, tool, prompt, model, effort, message} <- definitions do
      base = %{
        "id" => id,
        "type" => "collabAgentToolCall",
        "tool" => tool,
        "status" => if(message == :not_found, do: "failed", else: "completed"),
        "senderThreadId" => root,
        "receiverThreadIds" => [child],
        "prompt" => prompt,
        "model" => model,
        "reasoningEffort" => effort
      }

      case message do
        nil ->
          base

        :not_found ->
          Map.put(base, "agentsStates", %{child => %{"status" => "notFound", "message" => nil}})

        text ->
          Map.put(base, "agentsStates", %{child => %{"status" => "completed", "message" => text}})
      end
    end
  end

  defp assert_terminal_items(ctx, pid, root, turn, expected) do
    entries = Enum.map(expected, &terminal_entry(turn, root, &1))

    data =
      request(ctx, pid, "thread/items/read", %{
        "threadId" => root,
        "turnId" => turn.id,
        "itemIds" => Enum.map(expected, & &1["id"])
      })["data"]

    assert length(data) == length(entries)

    for {saved, entry} <- Enum.zip(data, entries) do
      assert Map.drop(saved, ["item"]) === Map.drop(entry, ["item"])
      assert_item(Map.fetch!(saved, "item"), Map.fetch!(entry, "item"))
    end
  end

  defp terminal_entry(turn, root, expected) do
    matching = fn method ->
      Enum.filter(turn.events, fn event ->
        event.wire["method"] == method and event.wire["params"]["threadId"] == root and
          event.wire["params"]["turnId"] == turn.id and
          event.wire["params"]["item"]["id"] == expected["id"]
      end)
    end

    assert [started] = matching.("item/started")
    assert [completed] = matching.("item/completed")
    started_at = Map.fetch!(started.wire["params"], "startedAtMs")
    completed_at = Map.fetch!(completed.wire["params"], "completedAtMs")
    assert is_integer(started_at) and is_integer(completed_at)

    assert turn.before <= started_at and started_at <= completed_at and
             completed_at <= turn.after

    assert_item(Map.fetch!(completed.wire["params"], "item"), expected)

    %{
      "turnId" => turn.id,
      "item" => expected,
      "startedAtMs" => started_at,
      "completedAtMs" => completed_at
    }
  end

  defp assert_item(actual, expected) do
    if Map.has_key?(expected, "agentsStates") do
      assert actual === expected
    else
      # Spawn/send/resume status snapshots are timing-dependent. Qualify only
      # prescribed stable fields; PendingInit/Running remain unverified.
      assert Map.drop(actual, ["agentsStates"]) === expected
    end
  end

  defp assert_provider_journal(requests, root, child, turns) do
    assert length(requests) == 13
    by_thread = Enum.group_by(requests, &metadata(&1)["thread_id"])
    assert Enum.sort(Map.keys(by_thread)) == Enum.sort([root, child])
    root_requests = Map.fetch!(by_thread, root)
    assert length(root_requests) == 11

    assert Enum.map(root_requests, &metadata(&1)["turn_id"]) ==
             List.duplicate(Enum.at(turns, 0).id, 5) ++
               List.duplicate(Enum.at(turns, 1).id, 2) ++
               List.duplicate(Enum.at(turns, 2).id, 4)

    child_requests = Map.fetch!(by_thread, child)
    assert length(child_requests) == 2
    assert length(Enum.uniq_by(child_requests, &metadata(&1)["turn_id"])) == 2
    assert Enum.map(child_requests, &latest_user/1) == [@first, @followup]

    for request <- requests do
      assert Map.fetch!(request, "model") == "mock-model"
      assert Map.fetch!(request, "reasoning") |> Map.fetch!("effort") == "low"
    end

    for {id, expected} <- [
          {"owned-collab-wait-first",
           %{"status" => %{child => %{"completed" => @first_done}}, "timed_out" => false}},
          {"owned-collab-close-first", %{"previous_status" => %{"completed" => @first_done}}},
          {"owned-collab-wait-closed",
           %{"status" => %{child => "not_found"}, "timed_out" => false}},
          {"owned-collab-wait-followup",
           %{"status" => %{child => %{"completed" => @followup_done}}, "timed_out" => false}},
          {"owned-collab-close-followup",
           %{"previous_status" => %{"completed" => @followup_done}}}
        ] do
      assert tool_result(requests, id) === expected
    end

    assert %{"status" => _snapshot} = tool_result(requests, "owned-collab-resume")
    assert %{"submission_id" => submission} = tool_result(requests, "owned-collab-send")
    assert is_binary(submission) and submission != ""
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

  defp latest_user(request) do
    request["input"]
    |> Enum.filter(&(&1["role"] == "user"))
    |> Enum.flat_map(&Map.get(&1, "content", []))
    |> Enum.map(& &1["text"])
    |> Enum.filter(&(&1 in [@first, @followup]))
    |> List.last()
  end

  defp metadata(request),
    do: JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

  defp complete(pid, root, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    case TurnFixture.notification(events, "turn/completed", fn params ->
           params["threadId"] == root and params["turn"]["id"] == turn
         end) do
      nil ->
        assert Session.status(pid).phase == :ready
        assert System.monotonic_time(:millisecond) < until, "native collaboration turn deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected collaboration event gap")
        after
          10 -> :ok
        end

        complete(pid, root, turn, events, until)

      notice ->
        assert notice["turn"]["status"] == "completed"
        events
    end
  end

  defp request(ctx, pid, method, params) when method in @captured_methods do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-collab-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id, timeout_ms: 5_000)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp loaded(ctx, pid),
    do: request(ctx, pid, "thread/loaded/list", %{}) |> Map.fetch!("data") |> Enum.sort()

  defp native_id(pid) do
    id = "owned-collab-diagnostics-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "server/diagnostics", %{}, id: id, timeout_ms: 5_000)

    native = result["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_collaboration_lifecycle", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
