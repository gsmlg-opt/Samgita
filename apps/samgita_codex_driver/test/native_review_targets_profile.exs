defmodule SamgitaCodexDriver.NativeReviewTargetsProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_review_targets_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @title "Owned commit λ🙂"
  @answer "No findings. Owned review λ🙂"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip git), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-review-targets-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
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
    repository = json(ctx, "git-fixture.json")

    assert length(
             Enum.uniq([repository["rootSHA"], repository["baseSHA"], repository["headSHA"]])
           ) == 3

    assert repository["initial"]["head"] == repository["headSHA"]
    assert repository["initial"]["remotes"] == ""
    assert repository["initial"]["status"] =~ "M  staged.txt"
    assert repository["initial"]["status"] =~ " M tracked.txt"
    assert repository["initial"]["status"] =~ "?? untracked.txt"
    ctx
  end

  # The fixed model proves native routing/lifecycle, never diff review or quality.
  for scenario <- ~w(uncommitted base commit-title commit-omitted commit-null commit-blank) do
    @scenario scenario
    @tag scenario: scenario
    test "native #{@scenario} target normalizes prompt and persists exact review markers", ctx do
      pid = connect(ctx)
      original = thread(pid, ctx, "legacy")
      {target, hint, prompt} = target(ctx, @scenario)
      review = call(pid, "review/start", %{"threadId" => original, "target" => target})
      turn = assert_immediate(review, original, hint)
      pending = collect(pid, &item(&1, "item/started", "enteredReviewMode"))
      entered = item(pending, "item/started", "enteredReviewMode")
      assert entered["threadId"] == original and entered["turnId"] == turn
      assert entered["item"]["review"] == hint
      await(fn -> length(events(ctx, "review-http.json", "review_pending")) == 1 end)
      refute completed?(pending, original, turn)
      assert events(ctx, "review-http.json", "response_released") == []
      assert [request] = json(ctx, "requests.json")
      assert prompt in user_texts(request)
      refute hint == prompt
      assert_request_target(target, @scenario, ctx)
      control(ctx, "releaseReview")
      execution = collect(pid, &completed?(&1, original, turn), pending)
      assert_completed(execution, original, turn)
      exited = item(execution, "item/completed", "exitedReviewMode")
      assert exited["threadId"] == original and exited["turnId"] == turn
      assert exited["item"]["review"] == @answer
      assert notices(execution, "deprecationNotice") == []
      assert notices(execution, "thread/started") == []
      marker_ids = {entered["item"]["id"], exited["item"]["id"]}

      persisted =
        assert_inline_final(turns(pid, original), turn, marker_ids, hint, prompt, "inProgress")

      assert_safe(ctx, pid, execution, 1)
      cold = restart(ctx, pid)

      cold_history =
        assert_inline_final(turns(cold, original), turn, marker_ids, hint, prompt, "interrupted")

      assert cold_history ==
               List.update_at(persisted, 1, &Map.put(&1, "status", "interrupted"))

      assert call(cold, "thread/read", %{"threadId" => original})["thread"]["historyMode"] ==
               "legacy"

      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_safe(ctx, cold, [], 1)
      finish(ctx, cold)
    end
  end

  for {scenario, target, message} <- [
        {"blank-branch", %{"type" => "baseBranch", "branch" => " \n\t "},
         "branch must not be empty"},
        {"blank-sha", %{"type" => "commit", "sha" => " \n\t ", "title" => nil},
         "sha must not be empty"}
      ] do
    @scenario scenario
    @target target
    @message message
    @tag scenario: scenario
    test "native #{@scenario} rejects before review or model work", ctx do
      pid = connect(ctx)
      original = thread(pid, ctx, "legacy")
      assert_unmaterialized(pid, original)

      assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
               Session.request(pid, "review/start", %{"threadId" => original, "target" => @target})

      assert error["code"] == -32_600 and error["message"] == @message
      assert json(ctx, "requests.json") == []
      assert events(ctx, "review-http.json", "review_pending") == []
      assert_unmaterialized(pid, original)
      assert {:ok, %{"data" => [^original]}} = loaded(pid)
      assert {:ok, rejected} = Session.drain(pid)

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

      assert_safe(ctx, pid, rejected, 0)
      finish(ctx, pid)
    end
  end

  defp target(_ctx, "uncommitted") do
    {%{"type" => "uncommittedChanges"}, "current changes",
     "Review the current code changes (staged, unstaged, and untracked files) and provide prioritized findings."}
  end

  defp target(ctx, "base") do
    root = json(ctx, "git-fixture.json")["rootSHA"]

    {%{"type" => "baseBranch", "branch" => " \n main\t "}, "changes against 'main'",
     "Review the code changes against the base branch 'main'. The merge base commit for this comparison is #{root}. Run `git diff #{root}` to inspect the changes relative to main. Provide prioritized, actionable findings."}
  end

  defp target(ctx, scenario) do
    sha = json(ctx, "git-fixture.json")["baseSHA"]
    base = %{"type" => "commit", "sha" => " \n#{sha}\t "}

    {target, suffix, title} =
      case scenario do
        "commit-title" ->
          {Map.put(base, "title", " \n#{@title}\t "), ": #{@title}", " (\"#{@title}\")"}

        "commit-omitted" ->
          {base, "", ""}

        "commit-null" ->
          {Map.put(base, "title", nil), "", ""}

        "commit-blank" ->
          {Map.put(base, "title", " \n\t "), "", ""}
      end

    {target, "commit #{String.slice(sha, 0, 7)}#{suffix}",
     "Review the code changes introduced by commit #{sha}#{title}. Provide prioritized, actionable findings."}
  end

  defp assert_request_target(target, "uncommitted", _ctx),
    do: assert(target == %{"type" => "uncommittedChanges"})

  defp assert_request_target(target, "base", ctx) do
    assert target == %{"type" => "baseBranch", "branch" => " \n main\t "}
    repository = json(ctx, "git-fixture.json")
    assert repository["rootSHA"] != repository["baseSHA"]
    assert repository["rootSHA"] != repository["headSHA"]
  end

  defp assert_request_target(target, scenario, ctx) do
    sha = json(ctx, "git-fixture.json")["baseSHA"]
    assert target["type"] == "commit" and target["sha"] == " \n#{sha}\t "
    assert sha != json(ctx, "git-fixture.json")["headSHA"]

    case scenario do
      "commit-title" -> assert target["title"] == " \n#{@title}\t "
      "commit-omitted" -> refute Map.has_key?(target, "title")
      "commit-null" -> assert Map.fetch!(target, "title") == nil
      "commit-blank" -> assert target["title"] == " \n\t "
    end
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
               %{"name" => "samgita_review_targets", "version" => "0.1.0"},
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

  defp assert_unmaterialized(pid, id) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, "thread/turns/list", %{
               "threadId" => id,
               "limit" => 100,
               "sortDirection" => "asc",
               "itemsView" => "full"
             })

    assert error["code"] == -32_600

    assert error["message"] ==
             "thread #{id} is not materialized yet; thread/turns/list is unavailable before first user message"
  end

  defp assert_inline_final(turns, id, {entered_id, exited_id}, hint, prompt, delegate_status) do
    assert_uuid(entered_id)
    assert_uuid(exited_id)
    refute entered_id == exited_id
    assert [%{"id" => ^id} = turn, %{"rootTurnId" => ^id} = delegate] = turns
    assert turn["status"] == "completed" and turn["error"] == nil

    assert turn["items"] == [
             %{"type" => "enteredReviewMode", "id" => entered_id, "review" => hint},
             %{"type" => "exitedReviewMode", "id" => exited_id, "review" => @answer}
           ]

    # Legacy review forwards delegate start/items while consuming its completion.
    # Preserve that exact native projection; do not hide the second stored turn.
    assert_uuid(delegate["id"])
    refute delegate["id"] == id
    assert delegate["status"] == delegate_status and delegate["error"] == nil
    assert delegate["completedAt"] == nil and delegate["durationMs"] == nil
    assert delegate["itemsView"] == "full" and is_integer(delegate["startedAt"])

    assert delegate["items"] ==
             for(
               index <- [1, 2],
               do: %{
                 "type" => "userMessage",
                 "id" => "item-#{index}",
                 "clientId" => nil,
                 "content" => [%{"type" => "text", "text" => prompt, "text_elements" => []}]
               }
             ) ++
               [
                 %{
                   "type" => "agentMessage",
                   "id" => "item-3",
                   "text" => @answer,
                   "delivery" => nil,
                   "memoryCitation" => nil,
                   "phase" => nil,
                   "questions" => nil
                 }
               ]

    turns
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
    control(ctx, "verifyRepository")
    assert Enum.all?(json(ctx, "git-verifications.json"), &(&1["unchanged"] == true))

    assert Enum.sort(Map.keys(json(ctx, "git-fixture.json")["initial"]["files"])) ==
             ~w(feature.txt staged.txt tracked.txt untracked.txt)

    assert Enum.sort(File.ls!(Path.join(ctx.root, "workspace"))) ==
             ~w(.git feature.txt staged.txt tracked.txt untracked.txt)

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

    IO.puts(:stderr, "Owned review target evidence retained: #{ctx.root}")
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
