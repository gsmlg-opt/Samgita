defmodule SamgitaCodexDriver.NativeReviewDeliveryProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_review_delivery_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Review the owned synthetic change λ🙂"
  @raw_instructions " \n\tReview the owned synthetic change λ🙂\t\n "
  @parent_input "Owned review parent context λ"
  @parent_answer "Owned parent materialized"
  @answer "No findings. Owned review λ🙂"
  @deprecation %{
    "summary" =>
      "review/start with delivery \"detached\" is deprecated and will be removed in a future release.",
    "details" =>
      "Use thread/start followed by review/start with delivery \"inline\" for a separate review thread, or thread/fork followed by turn/start with your own review instructions."
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-review-delivery-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [
          @script,
          "--root",
          root,
          "--codex",
          Path.expand(binary),
          "--scenario",
          tags.scenario
        ],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{
      root: root,
      owner: owner,
      socket: Path.join(root, "native.sock"),
      scenario: tags.scenario
    }

    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert [ready] = events(ctx, "bem-journal.json", "review_provider_ready")
    assert ready["source_provider_requests"] == 0 and ready["request_auth"] == "none"

    assert ready["output"] == "fixed_assistant_messages_only" and
             ready["scenario"] == tags.scenario

    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "cli_auth_credentials_store = \"file\""
    assert config =~ "requires_openai_auth = false"
    assert config =~ "supports_websockets = false"
    assert config =~ "enable_request_compression = false"
    assert config =~ "[analytics]\nenabled = false"
    refute config =~ "experimental_bearer_token"
    refute config =~ "experimental_realtime"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    ctx
  end

  @tag scenario: "detached"
  test "legacy detached review introduces a distinct child before fixed completion and cold read",
       ctx do
    pid = connect(ctx)
    parent = thread(pid, ctx, "legacy")

    materialize =
      call(pid, "turn/start", %{
        "threadId" => parent,
        "input" => [%{"type" => "text", "text" => @parent_input}]
      })["turn"]["id"]

    materialized = collect(pid, &completed?(&1, parent, materialize))
    assert_completed(materialized, parent, materialize)
    parent_turns = turns(pid, parent)
    assert_final(parent_turns, materialize, @parent_answer)
    assert {:ok, _} = Session.drain(pid)

    review = call(pid, "review/start", review_params(parent, "detached"))
    child = review["reviewThreadId"]
    assert_uuid(child)
    refute child == parent

    prompt =
      "Use [$review-agent](#{ctx.root}/codex/skills/.system/review-agent/SKILL.md) for this review.\n\n#{@instructions}"

    turn = assert_immediate(review, child, prompt)

    introduced =
      collect(pid, fn rows ->
        notice(rows, "thread/started") && notice(rows, "deprecationNotice")
      end)

    assert notices(introduced, "deprecationNotice") == [@deprecation]
    assert [started] = notices(introduced, "thread/started")
    assert started["thread"]["id"] == child and started["thread"]["sessionId"] == child
    {before_intro, _} = Enum.split_while(introduced, &(&1.wire["method"] != "thread/started"))

    refute Enum.any?(
             before_intro,
             &(get_in(&1.wire, ["params", "threadId"]) == child and
                 &1.wire["method"] == "thread/status/changed")
           )

    await(fn -> length(events(ctx, "review-http.json", "review_pending")) == 1 end)
    refute completed?(introduced, child, turn)
    assert Enum.map(events(ctx, "review-http.json", "response_released"), & &1["index"]) == [1]
    control(ctx, "releaseReview")
    execution = collect(pid, &completed?(&1, child, turn), introduced)
    assert_completed(execution, child, turn)
    assert notices(execution, "deprecationNotice") == [@deprecation]
    answer = item(execution, "item/completed", "agentMessage")
    assert answer["threadId"] == child and answer["turnId"] == turn
    assert answer["item"]["text"] == @answer

    refute Enum.any?(
             execution,
             &(get_in(&1.wire, ["params", "item", "type"]) in [
                 "enteredReviewMode",
                 "exitedReviewMode"
               ])
           )

    assert_final(turns(pid, child), turn, @answer)
    assert turns(pid, parent) == parent_turns
    assert [first, second] = json(ctx, "requests.json")
    assert @parent_input in user_texts(first)
    assert @parent_input in user_texts(second) and prompt in user_texts(second)
    assert_safe(ctx, pid, materialized ++ execution, 2)

    cold = restart(ctx, pid)
    assert_final(turns(cold, child), turn, @answer)
    assert turns(cold, parent) == parent_turns
    assert call(cold, "thread/read", %{"threadId" => child})["thread"]["id"] == child
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_safe(ctx, cold, [], 2)
    finish(ctx, cold)
  end

  @tag scenario: "rejected"
  test "paginated detached review rejects after its exact notice without starting work", ctx do
    pid = connect(ctx)
    parent = thread(pid, ctx, "paginated")
    assert {:ok, %{"data" => [^parent]}} = loaded(pid)

    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, "review/start", review_params(parent, "detached"))

    assert error["code"] == -32_600
    assert error["message"] == "paginated threads do not support detached review"
    rejected = collect(pid, &notice(&1, "deprecationNotice"))
    assert notices(rejected, "deprecationNotice") == [@deprecation]

    refute Enum.any?(
             rejected,
             &(&1.wire["method"] in [
                 "thread/started",
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ])
           )

    assert call(pid, "thread/read", %{"threadId" => parent})["thread"]["id"] == parent
    assert {:ok, %{"data" => [^parent]}} = loaded(pid)
    assert json(ctx, "requests.json") == []
    assert events(ctx, "review-http.json", "review_pending") == []
    assert_safe(ctx, pid, rejected, 0)
    finish(ctx, pid)
  end

  for mode <- ~w(legacy paginated), delivery <- [:omitted, nil, "inline"] do
    @history_mode mode
    @delivery delivery
    @tag scenario: "inline"
    test "#{mode} review delivery #{inspect(delivery)} executes inline and persists its result",
         ctx do
      pid = connect(ctx)
      original = thread(pid, ctx, @history_mode)
      review = call(pid, "review/start", review_params(original, @delivery))
      turn = assert_immediate(review, original, @instructions)
      pending = collect(pid, &item(&1, "item/started", "enteredReviewMode"))
      entered = item(pending, "item/started", "enteredReviewMode")
      assert entered["threadId"] == original and entered["turnId"] == turn
      assert entered["item"]["review"] == @instructions
      await(fn -> length(events(ctx, "review-http.json", "review_pending")) == 1 end)
      refute completed?(pending, original, turn)
      assert events(ctx, "review-http.json", "response_released") == []
      control(ctx, "releaseReview")
      execution = collect(pid, &completed?(&1, original, turn), pending)
      assert_completed(execution, original, turn)
      exited = item(execution, "item/completed", "exitedReviewMode")
      assert exited["threadId"] == original and exited["turnId"] == turn
      assert exited["item"]["review"] == @answer
      assert notices(execution, "deprecationNotice") == []
      assert notices(execution, "thread/started") == []
      assert [request] = json(ctx, "requests.json")
      assert @instructions in user_texts(request)
      refute @raw_instructions in user_texts(request)
      marker_ids = {entered["item"]["id"], exited["item"]["id"]}
      persisted = assert_inline_final(turns(pid, original), turn, @history_mode, marker_ids)
      assert_safe(ctx, pid, execution, 1)
      cold = restart(ctx, pid)
      cold_persisted = assert_inline_final(turns(cold, original), turn, @history_mode, marker_ids)
      if @history_mode == "legacy", do: assert(cold_persisted == persisted)

      assert call(cold, "thread/read", %{"threadId" => original})["thread"]["historyMode"] ==
               @history_mode

      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_safe(ctx, cold, [], 1)
      finish(ctx, cold)
    end
  end

  @tag scenario: "inline"
  test "paginated review entry survives selective warm and unhydrated cold reads", ctx do
    pid = connect(ctx)
    original = thread(pid, ctx, "paginated")
    review = call(pid, "review/start", review_params(original, "inline"))
    turn = assert_immediate(review, original, @instructions)

    pending =
      collect(pid, fn rows ->
        item(rows, "item/started", "enteredReviewMode") &&
          item(rows, "item/completed", "enteredReviewMode")
      end)

    entered = item(pending, "item/started", "enteredReviewMode")
    completed = item(pending, "item/completed", "enteredReviewMode")
    entered_id = entered["item"]["id"]
    assert_uuid(entered_id)
    started = entered["startedAtMs"]
    finished = completed["completedAtMs"]
    assert is_integer(started) and started > 0
    assert is_integer(finished) and finished >= started

    # Only generated identity/times come from observations; fields are prescribed.
    expected_item = %{
      "type" => "enteredReviewMode",
      "id" => entered_id,
      "review" => @instructions
    }

    assert entered == %{
             "threadId" => original,
             "turnId" => turn,
             "item" => expected_item,
             "startedAtMs" => started
           }

    assert completed == %{
             "threadId" => original,
             "turnId" => turn,
             "item" => expected_item,
             "completedAtMs" => finished
           }

    await(fn -> length(events(ctx, "review-http.json", "review_pending")) == 1 end)
    refute completed?(pending, original, turn)
    assert events(ctx, "review-http.json", "response_released") == []
    control(ctx, "releaseReview")
    execution = collect(pid, &completed?(&1, original, turn), pending)
    assert_completed(execution, original, turn)

    for {method, expected} <- [{"item/started", entered}, {"item/completed", completed}] do
      assert Enum.filter(notices(execution, method), &(&1["item"]["type"] == "enteredReviewMode")) ==
               [expected]
    end

    assert notices(execution, "deprecationNotice") == []
    assert notices(execution, "thread/started") == []
    requests = json(ctx, "requests.json")
    assert [request] = requests
    assert @instructions in user_texts(request)
    refute @raw_instructions in user_texts(request)

    # Native producer/store readiness only; history never supplies expected fields.
    hydrated = call(pid, "thread/read", %{"threadId" => original, "includeTurns" => true})
    assert hydrated["thread"]["id"] == original
    assert hydrated["thread"]["historyMode"] == "paginated"

    query = %{"threadId" => original, "turnId" => turn, "itemIds" => [entered_id]}

    expected_entry = %{
      "turnId" => turn,
      "item" => expected_item,
      "startedAtMs" => started,
      "completedAtMs" => finished
    }

    assert_selected = fn client ->
      response = call(client, "thread/items/read", query)
      assert Map.keys(response) == ["data"]
      assert [entry] = response["data"]
      assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
      assert entry == expected_entry

      assert call(client, "thread/items/read", %{
               query
               | "itemIds" => ["owned-absent-review-item", entered_id, entered_id]
             }) == %{"data" => [expected_entry]}

      assert call(client, "thread/items/read", %{
               query
               | "itemIds" => ["owned-absent-review-item"]
             }) == %{"data" => []}

      assert call(client, "thread/items/read", %{
               query
               | "turnId" => "owned-absent-review-turn"
             }) == %{"data" => []}

      assert json(ctx, "requests.json") == requests
    end

    assert_selected.(pid)
    assert_safe(ctx, pid, execution, 1)
    cold = restart(ctx, pid)

    # First thread-content operation in the new process: no resume/read/turn.
    assert_selected.(cold)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_safe(ctx, cold, [], 1)
    finish(ctx, cold)
  end

  defp connect(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport: {UnixSocket, [socket_path: ctx.socket]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    # review/start is stable; choosing historyMode is experimental at the pin.
    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_review_delivery", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp thread(pid, ctx, mode) do
    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => mode,
        "ephemeral" => false
      })["thread"]["id"]

    assert_uuid(id)
    started = collect(pid, &notice(&1, "thread/started"))
    assert notice(started, "thread/started")["thread"]["id"] == id
    assert notices(started, "deprecationNotice") == []
    id
  end

  defp review_params(thread, delivery) do
    params = %{
      "threadId" => thread,
      "target" => %{"type" => "custom", "instructions" => @raw_instructions}
    }

    if delivery == :omitted, do: params, else: Map.put(params, "delivery", delivery)
  end

  defp assert_immediate(review, thread, text) do
    assert review["reviewThreadId"] == thread
    turn = review["turn"]
    assert_uuid(turn["id"])

    assert turn == %{
             "id" => turn["id"],
             "rootTurnId" => nil,
             "items" => [
               %{
                 "type" => "userMessage",
                 "id" => turn["id"],
                 "clientId" => nil,
                 "content" => [%{"type" => "text", "text" => text, "text_elements" => []}]
               }
             ],
             "itemsView" => "notLoaded",
             "error" => nil,
             "status" => "inProgress",
             "startedAt" => nil,
             "completedAt" => nil,
             "durationMs" => nil
           }

    turn["id"]
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

  defp assert_final(turns, id, answer) do
    assert turn = Enum.find(turns, &(&1["id"] == id))
    assert turn["status"] == "completed" and turn["error"] == nil
    assert Enum.any?(turn["items"], &(&1["type"] == "agentMessage" and &1["text"] == answer))
  end

  defp assert_inline_final(turns, id, "legacy", {entered_id, exited_id}) do
    assert_uuid(entered_id)
    assert_uuid(exited_id)
    refute entered_id == exited_id
    assert turn = Enum.find(turns, &(&1["id"] == id))
    assert turn["status"] == "completed" and turn["error"] == nil

    assert turn["items"] == [
             %{"type" => "enteredReviewMode", "id" => entered_id, "review" => @instructions},
             %{"type" => "exitedReviewMode", "id" => exited_id, "review" => @answer}
           ]

    turn
  end

  defp assert_inline_final(turns, id, "paginated", _marker_ids) do
    assert_final(turns, id, @answer)
    Enum.find(turns, &(&1["id"] == id))
  end

  defp assert_completed(events, thread, turn) do
    [completion] =
      Enum.filter(
        notices(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

    assert completion["turn"]["status"] == "completed" and completion["turn"]["error"] == nil
  end

  defp completed?(events, thread, turn),
    do:
      Enum.any?(
        notices(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp assert_safe(ctx, pid, execution, count) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)

    refute Enum.any?(
             execution ++ remaining,
             &(&1.kind == :server_request or &1.wire["method"] == "error")
           )

    assert json(ctx, "provider-errors.json") == []
    assert length(json(ctx, "requests.json")) == count
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert events(ctx, "realtime-journal.json", "handshake") == []
    assert events(ctx, "realtime-journal.json", "native_frame") == []
    assert Enum.all?(json(ctx, "requests.json"), &(&1["model"] == "mock-model"))
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp restart(ctx, pid) do
    instance = Session.status(pid).instance_id
    native = json(ctx, "state.json")["native_pid"]
    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}")
    control(ctx, "restart")
    refute File.exists?("/proc/#{native}")
    assert json(ctx, "state.json")["native_pid"] != native
    cold = connect(ctx)
    assert Session.status(cold).instance_id != instance
    assert call(cold, "thread/loaded/list", %{})["data"] == []
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

    IO.puts(:stderr, "Owned review delivery evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp loaded(pid) do
    case Session.request(pid, "thread/loaded/list", %{}) do
      {:ok, %{"result" => result}} -> {:ok, result}
      error -> error
    end
  end

  defp user_texts(request),
    do:
      for(
        message <- request["input"],
        message["role"] == "user",
        part <- message["content"],
        part["type"] == "input_text",
        do: part["text"]
      )

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-review-#{System.unique_integer([:positive])}"
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
      assert System.monotonic_time(:millisecond) < deadline, "Owned review native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected review event gap")
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
        assert System.monotonic_time(:millisecond) < deadline, "Owned review fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp item(events, method, type),
    do:
      Enum.find_value(
        events,
        &if(&1.wire["method"] == method and get_in(&1.wire, ["params", "item", "type"]) == type,
          do: &1.wire["params"]
        )
      )

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp notice(events, method), do: List.first(notices(events, method))
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp events(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
