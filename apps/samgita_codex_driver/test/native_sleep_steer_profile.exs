defmodule SamgitaCodexDriver.NativeSleepSteerProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_sleep_steer_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @initial "Owned native sleep initial input"
  @steer "Owned new input wakes this native sleep"
  @answer "Owned native sleep continued after accepted input"
  @call "owned-sleep-steer-1"
  @arguments ~s({"duration_ms":60000})
  @initial_client "owned-sleep-initial-client"
  @steer_client "owned-sleep-steer-client"
  @sleep %{"type" => "sleep", "id" => @call, "durationMs" => 60_000}

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ss-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{root: root, owner: owner, socket: Path.join(root, "native.sock")}
    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]
    assert [ready] = events(ctx, "bem-journal.json", "sleep_provider_ready")
    assert ready["source_provider_requests"] == 0 and ready["request_auth"] == "none"
    assert ready["output"] == "fixed_stock_sleep_call_then_fixed_assistant"
    assert ready["duration_ms"] == 60_000
    assert ready["clock_source"] == "system" and ready["sleep_tool_mode"] == "always_on"
    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "requires_openai_auth = false"
    assert config =~ "supports_websockets = false"
    assert config =~ "enable_request_compression = false"
    assert config =~ "shell_snapshot = false"
    assert config =~ "shell_tool = false"
    assert config =~ "unified_exec = false"
    assert config =~ "[features.sleep_tool]\nenabled = true\nmode = \"always_on\""

    assert config =~
             "[features.current_time_reminder]\nenabled = false\nclock_source = \"system\""

    assert config =~ "[analytics]\nenabled = false"
    refute config =~ "experimental_bearer_token"
    refute config =~ "experimental_realtime"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    assert File.ls!(Path.join(root, "workspace")) == []
    ctx
  end

  test "accepted steer wakes the stock sixty-second sleep in the same turn and preserves its exact durable item",
       ctx do
    pid = connect(ctx)
    assert_safe(ctx, pid, [], 0)

    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert_uuid(id)

    turn =
      call(pid, "turn/start", %{
        "threadId" => id,
        "clientUserMessageId" => @initial_client,
        "input" => input(@initial)
      })["turn"]["id"]

    assert_uuid(turn)
    pending = collect(pid, &(sleep_notice(&1, "item/started") != nil))
    began = sleep_notice(pending, "item/started")
    assert began["threadId"] == id and began["turnId"] == turn
    assert began["item"] == @sleep
    started = Map.fetch!(began, "startedAtMs")
    assert is_integer(started) and started > 0
    assert sleep_notice(pending, "item/completed") == nil
    assert notices(pending, "turn/completed") == []
    assert_safe(ctx, pid, pending, 1)
    assert [first] = json(ctx, "requests.json")
    assert_stock_sleep(first)
    assert Enum.count(user_texts(first), &(&1 == @initial)) == 1
    refute @steer in user_texts(first)

    assert Enum.filter(first["input"], &(&1["type"] in ["function_call", "function_call_output"])) ==
             []

    # The real stock tool is already waiting for 60 seconds. Only accepted
    # turn/steer wakes it; no turn/interrupt, restart, synthetic native item or
    # client tool response is used to manufacture completion.
    deadline = System.monotonic_time(:millisecond) + 10_000

    assert call(pid, "turn/steer", %{
             "threadId" => id,
             "expectedTurnId" => turn,
             "clientUserMessageId" => @steer_client,
             "input" => input(@steer)
           }) == %{"turnId" => turn}

    execution = collect(pid, &completed?(&1, id, turn), pending, deadline)
    assert System.monotonic_time(:millisecond) < deadline
    ended = sleep_notice(execution, "item/completed")
    assert ended["threadId"] == id and ended["turnId"] == turn
    assert ended["item"] == @sleep
    finished = Map.fetch!(ended, "completedAtMs")

    assert ended == %{
             "threadId" => id,
             "turnId" => turn,
             "item" => @sleep,
             "completedAtMs" => finished
           }

    assert is_integer(finished) and finished >= started and finished - started < 10_000
    assert ended["item"]["durationMs"] == 60_000
    refute ended["item"]["durationMs"] == finished - started

    for method <- ["item/started", "item/completed"] do
      assert Enum.filter(notices(execution, method), &(&1["item"]["type"] == "sleep")) ==
               [sleep_notice(execution, method)]
    end

    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn}}] = notices(execution, "turn/started")
    assert [completed] = notices(execution, "turn/completed")
    assert completed["threadId"] == id
    assert completed["turn"]["id"] == turn and completed["turn"]["status"] == "completed"
    assert completed["turn"]["error"] == nil
    initial = assert_user(execution, id, turn, @initial_client, @initial)
    steered = assert_user(execution, id, turn, @steer_client, @steer)

    assert [assistant] =
             Enum.filter(
               notices(execution, "item/completed"),
               &(&1["item"]["type"] == "agentMessage")
             )

    assert assistant["threadId"] == id and assistant["turnId"] == turn

    expected_assistant = %{
      "type" => "agentMessage",
      "id" => assistant["item"]["id"],
      "text" => @answer,
      "delivery" => nil,
      "memoryCitation" => nil,
      "phase" => nil,
      "questions" => nil
    }

    assert assistant["item"] == expected_assistant
    assert length(Enum.uniq([initial["id"], @call, steered["id"], expected_assistant["id"]])) == 4
    assert_model_continuation(ctx, id, turn)

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [@call]}

    entry = %{
      "turnId" => turn,
      "item" => @sleep,
      "startedAtMs" => started,
      "completedAtMs" => finished
    }

    assert call(pid, "thread/items/read", query) == %{"data" => [entry]}

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent", @call, @call]}) ==
             %{"data" => [entry]}

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent"]}) == %{
             "data" => []
           }

    history = turns(pid, id)

    assert [
             %{"id" => ^turn, "status" => "completed", "error" => nil, "itemsView" => "full"} =
               persisted
           ] = history

    assert persisted["items"] == [initial, @sleep, steered, expected_assistant]
    assert_safe(ctx, pid, execution, 2)
    requests = json(ctx, "requests.json")
    transcript = json(ctx, "sleep-http.json")
    cold = restart(ctx, pid)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert turns(cold, id) == history
    assert call(cold, "thread/items/read", query) == %{"data" => [entry]}
    facts = call(cold, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]
    assert facts["id"] == id and facts["historyMode"] == "paginated"
    assert facts["status"] == %{"type" => "notLoaded"}
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_safe(ctx, cold, [], 2, true)
    assert json(ctx, "requests.json") == requests
    assert json(ctx, "sleep-http.json") == transcript
    finish(ctx, cold)
  end

  defp assert_user(execution, thread, turn, client, text) do
    selected = fn method ->
      Enum.filter(
        notices(execution, method),
        &(&1["item"]["type"] == "userMessage" and &1["item"]["clientId"] == client)
      )
    end

    assert [began] = selected.("item/started")
    assert [ended] = selected.("item/completed")

    item = %{
      "type" => "userMessage",
      "id" => began["item"]["id"],
      "clientId" => client,
      "content" => [%{"type" => "text", "text" => text, "text_elements" => []}]
    }

    assert is_binary(item["id"]) and byte_size(item["id"]) > 0

    for event <- [began, ended] do
      assert event["threadId"] == thread and event["turnId"] == turn
      assert event["item"] == item
    end

    item
  end

  defp assert_model_continuation(ctx, thread, turn) do
    await(fn ->
      length(json(ctx, "sleep-http.json")) == 2 and
        Enum.all?(json(ctx, "sleep-http.json"), & &1["responded"])
    end)

    assert [first, continued] = json(ctx, "requests.json")
    for request <- [first, continued], do: assert_stock_sleep(request)
    assert Enum.count(user_texts(continued), &(&1 == @initial)) == 1
    assert Enum.count(user_texts(continued), &(&1 == @steer)) == 1
    assert [native_call] = Enum.filter(continued["input"], &(&1["type"] == "function_call"))
    assert native_call["namespace"] == "clock" and native_call["name"] == "sleep"
    assert native_call["call_id"] == @call and native_call["arguments"] == @arguments

    assert [%{"type" => "function_call_output", "call_id" => @call, "output" => output}] =
             Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

    assert [_, value] =
             Regex.run(
               ~r/\AWall time: ([0-9]+\.[0-9]{4}) seconds\nSleep interrupted by new input\.\z/,
               output
             )

    {elapsed, ""} = Float.parse(value)
    assert elapsed >= 0.0 and elapsed < 10.0
    assert output == "Wall time: #{value} seconds\nSleep interrupted by new input."
    assert [sent, received] = json(ctx, "sleep-http.json")

    for record <- [sent, received] do
      assert record["metadata"]["thread_id"] == thread
      assert record["metadata"]["turn_id"] == turn
    end

    assert received["nativeToolOutput"] == output
    assert received["elapsedSeconds"] == elapsed
    first_events = response_events(sent)

    assert Enum.map(first_events, & &1["type"]) == [
             "response.created",
             "response.output_item.done",
             "response.completed"
           ]

    assert Enum.at(first_events, 1)["item"] == %{
             "type" => "function_call",
             "namespace" => "clock",
             "name" => "sleep",
             "call_id" => @call,
             "arguments" => @arguments
           }

    last_events = response_events(received)

    assert Enum.map(last_events, & &1["type"]) == [
             "response.created",
             "response.output_item.done",
             "response.completed"
           ]

    assert Enum.at(last_events, 1)["item"] == %{
             "type" => "message",
             "role" => "assistant",
             "id" => "owned-sleep-answer",
             "content" => [%{"type" => "output_text", "text" => @answer}]
           }
  end

  defp assert_stock_sleep(request) do
    assert [clock] =
             Enum.filter(request["tools"], &(&1["type"] == "namespace" and &1["name"] == "clock"))

    assert [tool] = Enum.filter(clock["tools"], &(&1["name"] == "sleep"))
    assert tool["type"] == "function" and tool["strict"] == false
    assert is_binary(tool["description"]) and byte_size(tool["description"]) > 0
    params = tool["parameters"]
    assert params["type"] == "object"
    assert Map.keys(params["properties"]) == ["duration_ms"]
    assert params["properties"]["duration_ms"]["type"] == "number"
    assert params["required"] == ["duration_ms"] and params["additionalProperties"] == false
  end

  defp response_events(record) do
    record["rawResponseBase64"]
    |> Base.decode64!()
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn block ->
      assert ["event: " <> type, "data: " <> data] = String.split(block, "\n", parts: 2)
      decoded = JSON.decode!(data)
      assert decoded["type"] == type
      decoded
    end)
  end

  defp assert_safe(ctx, pid, execution, count, inert \\ false) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    observed = execution ++ remaining
    refute Enum.any?(observed, &(&1.kind == :server_request or &1.wire["method"] == "error"))

    if inert do
      for method <- ~w(turn/started turn/completed item/started item/completed),
          do: assert(notices(observed, method) == [])
    end

    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert events(ctx, "realtime-journal.json", "handshake") == []
    assert events(ctx, "realtime-journal.json", "native_frame") == []
    assert_transcript(ctx, count)
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp assert_transcript(ctx, count) do
    await(fn ->
      length(json(ctx, "sleep-http.json")) == count and
        Enum.all?(json(ctx, "sleep-http.json"), & &1["responded"])
    end)

    requests = json(ctx, "requests.json")
    records = json(ctx, "sleep-http.json")
    assert length(requests) == count and length(records) == count

    for {record, index} <- Enum.with_index(records, 1) do
      raw = Base.decode64!(record["rawBodyBase64"])
      response = Base.decode64!(record["rawResponseBase64"])
      assert byte_size(raw) > 0 and byte_size(raw) <= 4_194_304
      assert byte_size(response) > 0 and byte_size(response) < 4096
      assert hash(raw) == record["rawBodySHA256"]
      assert hash(response) == record["rawResponseSHA256"]
      assert JSON.decode!(raw) == Enum.at(requests, index - 1)
      assert record["index"] == index and record["path"] == "/v1/responses"
      assert record["requestAuth"] == "none" and record["responded"]
    end
  end

  defp connect(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport: {UnixSocket, [socket_path: ctx.socket]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(pid, %{"name" => "samgita_sleep_steer", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    pid
  end

  defp turns(pid, id) do
    page =
      call(pid, "thread/turns/list", %{
        "threadId" => id,
        "limit" => 100,
        "sortDirection" => "asc",
        "itemsView" => "full"
      })

    assert page["nextCursor"] == nil
    page["data"]
  end

  defp restart(ctx, pid) do
    instance = Session.status(pid).instance_id
    native = json(ctx, "state.json")["native_pid"]
    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}")
    control(ctx, "restart")
    refute File.exists?("/proc/#{native}")
    refute json(ctx, "state.json")["native_pid"] == native
    cold = connect(ctx)
    refute Session.status(cold).instance_id == instance
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    cold
  end

  defp finish(ctx, pid) do
    assert :ok = Session.close(pid)
    control(ctx, "close")
    assert length(events(ctx, "bem-journal.json", "fixture_closed")) == 1

    for native <- json(ctx, "state.json")["native_pids"],
        do: refute(File.exists?("/proc/#{native}"))
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: assert_process_reaped(pid)

      assert events(ctx, "bem-journal.json", "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned native sleep evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-sleep-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.find(events(ctx, "bem-journal.json", "control_done"), &(&1["id"] == id)) end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline, "Owned native sleep event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native sleep event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned native sleep fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp input(text), do: [%{"type" => "text", "text" => text}]

  defp sleep_notice(execution, method),
    do:
      Enum.find(
        notices(execution, method),
        &(&1["item"]["type"] == "sleep" and &1["item"]["id"] == @call)
      )

  defp completed?(execution, thread, turn),
    do:
      Enum.any?(
        notices(execution, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn and
            &1["turn"]["status"] == "completed")
      )

  defp notices(execution, method),
    do: for(event <- execution, event.wire["method"] == method, do: event.wire["params"])

  defp user_texts(request),
    do:
      for(
        message <- request["input"],
        message["role"] == "user",
        part <- Map.get(message, "content", []),
        part["type"] == "input_text",
        do: part["text"]
      )

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp events(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
