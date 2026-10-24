defmodule SamgitaCodexDriver.NativeQueueLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/queued_model_fixture.py", __DIR__)
  @missing "00000000-0000-4000-8000-000000000000"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-queue-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, Map.get(tags, :scenario, "auto"))
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  test "capacity rejection preserves all 100 ordered submissions through native restart", ctx do
    {pid, id} = unloaded(ctx)

    expected =
      for index <- 1..100 do
        client = "capacity-client-#{index}"
        text = "capacity message #{index}"
        item = add(pid, id, client, text)
        assert is_binary(item["id"]) and byte_size(item["id"]) > 0

        assert item == %{
                 "id" => item["id"],
                 "clientUserMessageId" => client,
                 "input" => normalized(text)
               }

        item
      end

    assert expected |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == 100

    assert call(pid, "thread/queue/list", %{"threadId" => id, "limit" => 100}) == %{
             "data" => expected,
             "nextCursor" => nil
           }

    assert_unloaded(ctx, pid, id, 1)

    assert upstream_error(pid, "thread/queue/add", %{
             "threadId" => id,
             "clientUserMessageId" => "capacity-overflow",
             "input" => input("capacity item 101 must not persist")
           }) == %{
             "code" => -32_600,
             "message" => "queue cannot contain more than 100 submissions"
           }

    assert call(pid, "thread/queue/list", %{"threadId" => id, "limit" => 100}) == %{
             "data" => expected,
             "nextCursor" => nil
           }

    assert_unloaded(ctx, pid, id, 1)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert File.read_link!("/proc/#{native}/exe") == Path.expand(ctx.binary)
    instance = Session.status(pid).instance_id
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    refute File.exists?("/proc/#{native}")

    cold = start(ctx)
    cold_native = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(cold_native) and cold_native > 0
    refute cold_native == native
    assert File.read_link!("/proc/#{cold_native}/exe") == Path.expand(ctx.binary)
    refute Session.status(cold).instance_id == instance

    assert call(cold, "thread/queue/list", %{"threadId" => id, "limit" => 100}) == %{
             "data" => expected,
             "nextCursor" => nil
           }

    assert_unloaded(ctx, cold, id, 1)
  end

  test "unloaded queue CRUD order and client identities survive a second native restart", ctx do
    {pid, id} = unloaded(ctx)
    first = add(pid, id, "same-client", "first")
    second = add(pid, id, "same-client", "second")
    third = add(pid, id, "third-client", "third")
    refute first["id"] == second["id"]
    assert Enum.sort(Map.keys(first)) == ["clientUserMessageId", "id", "input"]
    assert first["clientUserMessageId"] == second["clientUserMessageId"]
    page = call(pid, "thread/queue/list", %{"threadId" => id, "limit" => 0})
    assert page["data"] == [first]
    assert page["nextCursor"] == "1"

    assert call(pid, "thread/queue/list", %{
             "threadId" => id,
             "cursor" => page["nextCursor"],
             "limit" => 1
           }) == %{"data" => [second], "nextCursor" => "2"}

    assert call(pid, "thread/queue/list", %{"threadId" => id, "cursor" => "2", "limit" => 1}) ==
             %{"data" => [third], "nextCursor" => nil}

    edited = update(pid, id, first["id"], "first edited λ")
    assert edited == %{first | "input" => normalized("first edited λ")}

    assert call(pid, "thread/queue/reorder", %{
             "threadId" => id,
             "queuedSubmissionIds" => [third["id"], second["id"], first["id"]]
           }) == %{}

    assert delete(pid, id, second["id"]) == %{"deleted" => true}
    expected = [third, edited]
    assert queue(pid, id) == expected
    assert_unloaded(ctx, pid, id, 1)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert queue(cold, id) == expected
    assert_unloaded(ctx, cold, id, 1)

    assert upstream_error(cold, "thread/queue/start", %{"threadId" => id}) == %{
             "code" => -32_600,
             "message" => "resume the thread before starting a queued message"
           }

    assert queue(cold, id) == expected
    assert_unloaded(ctx, cold, id, 1)
  end

  test "invalid reorders missing identities empty input and bad cursors preserve durable state",
       ctx do
    {pid, id} = unloaded(ctx)
    first = add(pid, id, "first", "first")
    second = add(pid, id, "second", "second")
    expected = [first, second]

    for ids <- [[first["id"]], [first["id"], first["id"]], [first["id"], "foreign"]] do
      assert upstream_error(pid, "thread/queue/reorder", %{
               "threadId" => id,
               "queuedSubmissionIds" => ids
             }) == %{
               "code" => -32_600,
               "message" => "queue reorder must include every queued submission exactly once"
             }

      assert queue(pid, id) == expected
    end

    assert upstream_error(pid, "thread/queue/update", %{
             "threadId" => id,
             "queuedSubmissionId" => "missing",
             "input" => input("new")
           }) == %{"code" => -32_600, "message" => "queued submission not found: missing"}

    assert delete(pid, id, "missing") == %{"deleted" => false}

    for {method, params} <- [
          {"thread/queue/add",
           %{"threadId" => id, "clientUserMessageId" => "invalid", "input" => []}},
          {"thread/queue/update",
           %{"threadId" => id, "queuedSubmissionId" => first["id"], "input" => []}}
        ] do
      assert upstream_error(pid, method, params)["message"] ==
               "only user input can be added to the user-message queue"
    end

    error =
      upstream_error(pid, "thread/queue/list", %{"threadId" => id, "cursor" => "not-a-cursor"})

    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "invalid queue pagination cursor: ")

    assert call(pid, "thread/queue/list", %{"threadId" => id, "cursor" => "999"}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert queue(pid, id) == expected
    assert_unloaded(ctx, pid, id, 1)
  end

  test "adding to an idle loaded thread auto-dispatches native queue identity and trigger metadata",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    queued = add(pid, id, "idle-client-λ", "idle durable message λ")
    events = finish_queue(pid, id, [queued])
    assert_queue_notifications(events, id)
    assert queue(pid, id) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_dispatch(ctx, events, id, [queued], 1)
    assert_ready(pid)
  end

  @tag scenario: "hold_first"
  test "active provider hold permits edits and reorder before release auto-drains the retained FIFO",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    active = start_turn(pid, id, "held active queue barrier")
    assert_held(ctx, 1, id, active)
    first = add(pid, id, "first-client", "first")
    changed(pid, id)
    second = add(pid, id, "second-client", "second")
    changed(pid, id)
    discarded = add(pid, id, "discard-client", "discarded")
    changed(pid, id)
    edited = update(pid, id, first["id"], "first edited during active turn")
    changed(pid, id)

    assert call(pid, "thread/queue/reorder", %{
             "threadId" => id,
             "queuedSubmissionIds" => [second["id"], first["id"], discarded["id"]]
           }) == %{}

    changed(pid, id)
    assert delete(pid, id, discarded["id"]) == %{"deleted" => true}
    changed(pid, id)

    assert upstream_error(pid, "thread/queue/start", %{
             "threadId" => id,
             "queuedSubmissionId" => first["id"]
           }) == %{"code" => -32_600, "message" => "thread already has an active or pending turn"}

    assert queue(pid, id) == [second, edited]
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    refute observation(ctx, 1)["released"]
    release(ctx, 1)
    events = finish_queue(pid, id, [second, edited], &completed?(&1, id, active, "completed"))
    assert_queue_notifications(events, id)
    assert queue(pid, id) == []
    assert_dispatch(ctx, events, id, [second, edited], 2)
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_ready(pid)
  end

  @tag scenario: "hold_first"
  test "interruption and cold resume preserve pause until explicit non-head start then FIFO",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    active = start_turn(pid, id, "held interrupted queue barrier")
    assert_held(ctx, 1, id, active)
    first = add(pid, id, "first-paused", "first paused")
    second = add(pid, id, "second-paused", "second paused")
    interrupt(pid, id, active)
    release(ctx, 1)
    assert queue(pid, id) == [first, second]
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert queue(cold, id) == [first, second]
    assert_unloaded(ctx, cold, id, 1)
    assert call(cold, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    third = add(cold, id, "third-paused", "third added after cold resume")
    assert queue(cold, id) == [first, second, third]
    assert length(ModelFixture.requests(ctx.fixture)) == 1

    started =
      call(cold, "thread/queue/start", %{"threadId" => id, "queuedSubmissionId" => second["id"]})
      |> assert_start_snapshot()

    assert started["status"] == "inProgress"
    assert started["rootTurnId"] == started["id"]
    events = finish_queue(cold, id, [second, first, third])
    assert user_item(events, second["clientUserMessageId"])["turnId"] == started["id"]
    assert queue(cold, id) == []
    assert_dispatch(ctx, events, id, [second, first, third], 2)
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert_ready(cold)
  end

  @tag scenario: "hold_first"
  test "queue start without a selected ID restarts the preserved head after interruption", ctx do
    pid = start(ctx)
    id = thread(ctx, pid)
    active = start_turn(pid, id, "held head selection barrier")
    assert_held(ctx, 1, id, active)
    first = add(pid, id, "head-client", "head message")
    second = add(pid, id, "tail-client", "tail message")
    interrupt(pid, id, active)
    release(ctx, 1)
    assert queue(pid, id) == [first, second]

    assert upstream_error(pid, "thread/queue/start", %{
             "threadId" => id,
             "queuedSubmissionId" => "missing"
           }) == %{"code" => -32_600, "message" => "queued submission not found: missing"}

    assert queue(pid, id) == [first, second]
    started = call(pid, "thread/queue/start", %{"threadId" => id}) |> assert_start_snapshot()
    events = finish_queue(pid, id, [first, second])
    assert user_item(events, first["clientUserMessageId"])["turnId"] == started["id"]
    assert started["rootTurnId"] == started["id"]
    assert queue(pid, id) == []
    assert_dispatch(ctx, events, id, [first, second], 2)

    assert upstream_error(pid, "thread/queue/start", %{"threadId" => id}) == %{
             "code" => -32_600,
             "message" => "queue is empty"
           }

    assert_ready(pid)
  end

  test "resuming a cold noninterrupted thread dispatches its persisted unloaded queue", ctx do
    {pid, id} = unloaded(ctx)
    queued = add(pid, id, "cold-resume-client", "cold-resumed queued content")
    assert queue(pid, id) == [queued]
    assert_unloaded(ctx, pid, id, 1)
    assert call(pid, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    events = finish_queue(pid, id, [queued])
    assert queue(pid, id) == []
    assert_dispatch(ctx, events, id, [queued], 2)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_ready(pid)
  end

  test "all queue methods enforce experimental and native thread and malformed-input boundaries",
       ctx do
    for negotiation <- [:absent, false] do
      pid = start(ctx, negotiation)

      for {method, params} <- methods(@missing) do
        assert {:error, %Error{code: :experimental_api_required}} =
                 Session.request(pid, method, params)

        assert upstream_error(pid, method, params, validation: :wire) == %{
                 "code" => -32_600,
                 "message" => "#{method} requires experimentalApi capability"
               }
      end

      assert :ok = Session.close(pid)
    end

    pid = start(ctx)
    ephemeral = thread(ctx, pid, %{"ephemeral" => true})

    for {method, params} <- methods(ephemeral) do
      assert upstream_error(pid, method, params) == %{
               "code" => -32_600,
               "message" => "ephemeral thread does not support queued submissions: #{ephemeral}"
             }
    end

    assert upstream_error(pid, "thread/queue/list", %{"threadId" => @missing}) == %{
             "code" => -32_603,
             "message" =>
               "failed to read thread: invalid thread-store request: no rollout found for thread id #{@missing}"
           }

    invalid = upstream_error(pid, "thread/queue/list", %{"threadId" => "invalid"})

    assert invalid["code"] == -32_600 and
             String.starts_with?(invalid["message"], "invalid thread id: ")

    for {method, params} <- [
          {"thread/queue/add",
           %{"threadId" => @missing, "input" => [], "clientUserMessageId" => 42}},
          {"thread/queue/list", %{"threadId" => @missing, "limit" => -1}},
          {"thread/queue/reorder", %{"threadId" => @missing, "queuedSubmissionIds" => "invalid"}},
          {"thread/queue/update",
           %{"threadId" => @missing, "queuedSubmissionId" => "x", "input" => nil}},
          {"thread/queue/delete", %{"threadId" => @missing}},
          {"thread/queue/start", %{"threadId" => 42}}
        ] do
      assert {:error, %Error{}} = Session.request(pid, method, params)
      error = upstream_error(pid, method, params, validation: :wire)

      assert error["code"] == -32_600 and
               String.starts_with?(error["message"], "Invalid request: ")
    end

    id = thread(ctx, pid)
    turn = start_turn(pid, id, "materialize archived queue boundary")
    await(pid, &completed?(&1, id, turn, "completed"))
    assert call(pid, "thread/archive", %{"threadId" => id}) == %{}

    assert upstream_error(pid, "thread/queue/list", %{"threadId" => id}) == %{
             "code" => -32_600,
             "message" =>
               "session #{id} is archived. Run `codex unarchive #{id}` to unarchive it first."
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_ready(pid)
  end

  defp start(ctx, negotiation \\ true) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_queue_fixture", "version" => "0.1.0"},
               capabilities
             )

    pid
  end

  defp thread(ctx, pid, extra \\ %{}), do: TurnFixture.thread(ctx, pid, extra)
  defp call(pid, method, params), do: TurnFixture.call(pid, method, params)

  defp upstream_error(pid, method, params, opts \\ []),
    do: TurnFixture.upstream_error(pid, method, params, opts)

  defp input(text), do: [%{"type" => "text", "text" => text}]
  defp normalized(text), do: [%{"type" => "text", "text" => text, "text_elements" => []}]

  defp assert_start_snapshot(response) do
    assert Map.keys(response) == ["turn"]
    turn = response["turn"]
    turn_id = turn["id"]
    assert is_binary(turn_id) and byte_size(turn_id) > 0

    assert turn == %{
             "id" => turn_id,
             "rootTurnId" => turn_id,
             "items" => [],
             "itemsView" => "notLoaded",
             "status" => "inProgress",
             "error" => nil,
             "startedAt" => nil,
             "completedAt" => nil,
             "durationMs" => nil
           }

    turn
  end

  defp start_turn(pid, id, text),
    do: call(pid, "turn/start", %{"threadId" => id, "input" => input(text)})["turn"]["id"]

  defp add(pid, id, client, text),
    do:
      call(pid, "thread/queue/add", %{
        "threadId" => id,
        "clientUserMessageId" => client,
        "input" => input(text)
      })["queuedSubmission"]

  defp update(pid, id, queued_id, text),
    do:
      call(pid, "thread/queue/update", %{
        "threadId" => id,
        "queuedSubmissionId" => queued_id,
        "input" => input(text)
      })["queuedSubmission"]

  defp delete(pid, id, queued_id),
    do: call(pid, "thread/queue/delete", %{"threadId" => id, "queuedSubmissionId" => queued_id})

  defp queue(pid, id), do: call(pid, "thread/queue/list", %{"threadId" => id})["data"]

  defp unloaded(ctx) do
    pid = start(ctx)
    id = thread(ctx, pid)
    turn = start_turn(pid, id, "materialize persisted queue thread")
    await(pid, &completed?(&1, id, turn, "completed"))
    assert :ok = Session.close(pid)
    cold = start(ctx)
    assert_unloaded(ctx, cold, id, 1)
    {cold, id}
  end

  defp assert_unloaded(ctx, pid, id, requests) do
    assert call(pid, "thread/loaded/list", %{})["data"] == []

    assert call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"][
             "status"
           ] == %{"type" => "notLoaded"}

    assert length(ModelFixture.requests(ctx.fixture)) == requests
    assert_ready(pid)
  end

  defp methods(id) do
    [
      {"thread/queue/add",
       %{"threadId" => id, "input" => input("gated"), "clientUserMessageId" => "gated-client"}},
      {"thread/queue/list", %{"threadId" => id}},
      {"thread/queue/update",
       %{"threadId" => id, "queuedSubmissionId" => "gated-item", "input" => input("gated")}},
      {"thread/queue/delete", %{"threadId" => id, "queuedSubmissionId" => "gated-item"}},
      {"thread/queue/reorder", %{"threadId" => id, "queuedSubmissionIds" => []}},
      {"thread/queue/start", %{"threadId" => id}}
    ]
  end

  defp interrupt(pid, id, turn) do
    assert call(pid, "turn/interrupt", %{"threadId" => id, "turnId" => turn}) == %{}
    await(pid, &completed?(&1, id, turn, "interrupted"))
  end

  defp changed(pid, id) do
    events =
      await(pid, &notification(&1, "thread/queue/changed", fn p -> p["threadId"] == id end))

    assert_queue_notifications(events, id)
  end

  defp assert_queue_notifications(events, id) do
    changes = Enum.filter(events, &(&1.wire["method"] == "thread/queue/changed"))
    assert changes != []
    assert Enum.all?(changes, &(&1.wire["params"] == %{"threadId" => id}))
  end

  defp finish_queue(pid, id, queued, extra \\ fn _ -> true end) do
    await(pid, fn events ->
      extra.(events) and
        Enum.all?(queued, &submission_completed?(events, id, &1))
    end)
  end

  defp submission_completed?(events, id, item) do
    case user_item(events, item["clientUserMessageId"]) do
      nil -> false
      event -> completed?(events, id, event["turnId"], "completed")
    end
  end

  defp user_item(events, client) do
    notification(
      events,
      "item/started",
      &(&1["item"]["type"] == "userMessage" and &1["item"]["clientId"] == client)
    )
  end

  defp completed?(events, id, turn, status),
    do:
      notification(
        events,
        "turn/completed",
        &(&1["threadId"] == id and &1["turn"]["id"] == turn and &1["turn"]["status"] == status)
      ) != nil

  defp assert_dispatch(ctx, events, id, queued, first_index) do
    selected_clients = Enum.map(queued, & &1["clientUserMessageId"])

    starts =
      Enum.flat_map(events, fn event ->
        params = event.wire["params"]

        if event.wire["method"] == "item/started" and params["item"]["type"] == "userMessage" and
             params["item"]["clientId"] in selected_clients,
           do: [params],
           else: []
      end)

    assert Enum.map(starts, & &1["item"]["clientId"]) == selected_clients

    for {queued, index} <- Enum.with_index(queued, first_index) do
      item = user_item(events, queued["clientUserMessageId"])
      assert item["threadId"] == id
      assert item["item"]["content"] == queued["input"]

      assert notification(
               events,
               "turn/started",
               &(&1["threadId"] == id and &1["turn"]["id"] == item["turnId"])
             )

      record = wait_observation(ctx, index)
      assert record["metadata"]["thread_id"] == id
      assert record["metadata"]["turn_id"] == item["turnId"]
      assert record["metadata"]["turn_trigger"] == "queue"
      refute record["timedOut"]
      request = Enum.at(ModelFixture.requests(ctx.fixture), index - 1)

      texts =
        request["input"]
        |> Enum.flat_map(&Map.get(&1, "content", []))
        |> Enum.filter(&(&1["type"] == "input_text"))
        |> Enum.map(& &1["text"])

      assert hd(queued["input"])["text"] in texts
    end
  end

  defp observation(ctx, index),
    do:
      ctx.root
      |> Path.join("queue-observations.json")
      |> File.read!()
      |> JSON.decode!()
      |> Map.get(to_string(index))

  defp wait_observation(ctx, index) do
    wait_value(fn -> observation(ctx, index) end, "provider request #{index}")
  end

  defp assert_held(ctx, index, id, turn) do
    record = wait_observation(ctx, index)

    assert record["held"] and not record["released"] and not record["answered"] and
             not record["timedOut"]

    assert record["metadata"]["thread_id"] == id
    assert record["metadata"]["turn_id"] == turn
  end

  defp release(ctx, index),
    do: assert({:ok, _} = Stdio.send(ctx.fixture.transport, JSON.encode!(%{"release" => index})))

  defp wait_value(get, label),
    do: wait_value(get, label, System.monotonic_time(:millisecond) + 10_000)

  defp wait_value(get, label, deadline) do
    case get.() do
      nil ->
        assert System.monotonic_time(:millisecond) < deadline, "Native queue #{label} deadline"

        receive do
        after
          10 -> :ok
        end

        wait_value(get, label, deadline)

      value ->
        value
    end
  end

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp await(pid, predicate),
    do: await(pid, predicate, [], System.monotonic_time(:millisecond) + 20_000)

  defp await(pid, predicate, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    cond do
      predicate.(acc) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native queue event deadline: #{inspect(acc)}")

      true ->
        assert_ready(pid)

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Native queue gap: #{inspect(gap)}")
        after
          10 -> :ok
        end

        await(pid, predicate, acc, deadline)
    end
  end

  defp assert_ready(pid),
    do: assert(%{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid))
end
