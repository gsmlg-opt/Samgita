defmodule SamgitaCodexDriver.NativeSessionBudgetTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, TurnFixture}
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_session_budget_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned synthetic session-budget input; no tools or external work."
  @answer "Owned synthetic session-budget response."
  @reminder "<rollout_budget>\nYou have 30 weighted tokens left in the shared session token budget.\n</rollout_budget>"
  @error %{
    "message" => "shared rollout token budget exhausted",
    "codexErrorInfo" => "sessionBudgetExceeded",
    "additionalDetails" => nil,
    "misalignment" => nil
  }
  @usage %{
    "input_tokens" => 7,
    "input_tokens_details" => %{"cached_tokens" => 3, "cache_write_tokens" => 0},
    "output_tokens" => 26,
    "output_tokens_details" => %{"reasoning_tokens" => 0},
    "total_tokens" => 33
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-sb-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
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

    assert [ready] = journal(ctx, "session_budget_provider_ready")
    assert ready["source_provider_requests"] == 0 and ready["request_budget"] == 1
    assert ready["request_auth"] == "none"
    assert ready["output"] == "fixed_session_budget_completion"

    config = File.read!(Path.join(root, "codex/config.toml"))

    for setting <- [
          "goals = false",
          "multi_agent = false",
          "multi_agent_v2 = false",
          "[features.rollout_budget]\nenabled = true",
          "limit_tokens = 30",
          "reminder_at_remaining_tokens = [20, 10]",
          "sampling_token_weight = 1.0",
          "prefill_token_weight = 1.0",
          "requires_openai_auth = false",
          "supports_websockets = false",
          "request_max_retries = 0",
          "stream_max_retries = 0",
          "enable_request_compression = false",
          "shell_tool = false",
          "unified_exec = false",
          "shell_snapshot = false",
          "plugins = false",
          "apps = false",
          "hooks = false",
          "[analytics]\nenabled = false"
        ] do
      assert config =~ setting
    end

    refute config =~ "experimental_bearer_token"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    ctx
  end

  test "native shared rollout usage fails one owned turn without retry or external effects",
       ctx do
    pid = connect(ctx)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert native == json(ctx, "state.json")["native_pid"]
    assert hash(File.read!("/proc/#{native}/exe")) == @sha
    assert json(ctx, "requests.json") == []
    assert json(ctx, "goal-attempts.json") == 0

    thread =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    # The only execution trigger. No goal mutation, subagent, retry or restart.
    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "turnTrigger" => "user",
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    events = collect(pid, thread, turn)

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn}}] =
             notices(events, "turn/started")

    assert notices(events, "error") == [
             %{"threadId" => thread, "turnId" => turn, "error" => @error, "willRetry" => false}
           ]

    assert [ended] = notices(events, "turn/completed")
    assert ended["threadId"] == thread and ended["turn"]["id"] == turn
    assert ended["turn"]["status"] == "failed"
    assert ended["turn"]["error"] == @error
    assert_provider(ctx, thread, turn)

    expected_usage = %{
      "inputTokens" => 7,
      "cachedInputTokens" => 3,
      "cacheWriteInputTokens" => 0,
      "outputTokens" => 26,
      "reasoningOutputTokens" => 0,
      "totalTokens" => 33
    }

    assert Enum.any?(notices(events, "thread/tokenUsage/updated"), fn params ->
             params["threadId"] == thread and params["turnId"] == turn and
               params["tokenUsage"]["last"] == expected_usage and
               params["tokenUsage"]["total"] == expected_usage
           end)

    # Native usage is33 total, but weighted noncached usage reaches the configured30.
    assert @usage["output_tokens"] +
             (@usage["input_tokens"] - @usage["input_tokens_details"]["cached_tokens"]) == 30

    result =
      call(pid, "thread/turns/list", %{
        "threadId" => thread,
        "limit" => 100,
        "sortDirection" => "asc",
        "itemsView" => "full"
      })

    assert result["nextCursor"] == nil
    assert [stored] = result["data"]
    assert stored["id"] == turn and stored["status"] == "failed" and stored["error"] == @error

    assert Enum.any?(stored["items"], fn item ->
             item["type"] == "userMessage" and
               Enum.any?(item["content"], &(&1["type"] == "text" and &1["text"] == @input))
           end)

    assert Enum.any?(stored["items"], &(&1["type"] == "agentMessage" and &1["text"] == @answer))
    assert call(pid, "server/diagnostics", %{})["process"]["id"] == native
    assert_quiet(ctx, pid, now() + 1_000)
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
    control(ctx, "close")
    assert length(journal(ctx, "fixture_closed")) == 1
    assert :ok = Stdio.close(ctx.owner)
    assert_owned_gone(ctx)
  end

  defp assert_provider(ctx, thread, turn) do
    await(fn ->
      case json(ctx, "goal-http.json") do
        [record] -> record["responded"]
        _ -> false
      end
    end)

    assert json(ctx, "goal-attempts.json") == 1
    assert [request] = json(ctx, "requests.json")
    assert [record] = json(ctx, "goal-http.json")
    assert record["index"] == 1 and record["status"] == 200
    assert record["path"] == "/v1/responses" and record["requestAuth"] == "none"
    assert record["metadata"]["thread_id"] == thread and record["metadata"]["turn_id"] == turn
    assert record["metadata"]["turn_trigger"] == "user"
    raw = Base.decode64!(record["rawBodyBase64"])
    assert hash(raw) == record["rawBodySHA256"] and JSON.decode!(raw) == request

    developer =
      for item <- request["input"],
          item["role"] == "developer",
          part <- Map.get(item, "content", []),
          is_binary(part["text"]),
          do: part["text"]

    assert Enum.count(developer, &(&1 == @reminder)) == 1
    response = Base.decode64!(record["rawResponseBase64"])
    assert hash(response) == record["rawResponseSHA256"]

    data =
      for line <- String.split(response, "\n"),
          String.starts_with?(line, "data: "),
          do: line |> String.replace_prefix("data: ", "") |> JSON.decode!()

    assert Enum.map(data, & &1["type"]) == [
             "response.created",
             "response.output_item.done",
             "response.completed"
           ]

    assert List.last(data)["response"]["usage"] == @usage
    refute Map.has_key?(List.last(data)["response"]["usage"], "codex_rollout_budget_units")
    assert Enum.at(data, 1)["item"]["content"] == [%{"type" => "output_text", "text" => @answer}]
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert json(ctx, "goal-attempts.json") == 1
    assert length(json(ctx, "requests.json")) == 1
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "codex/rules/default.rules"))
    assert length(journal(ctx, "native_started")) == 1
    assert journal(ctx, "control_done") == []
  end

  defp collect(pid, thread, turn, events \\ [], deadline \\ nil) do
    deadline = deadline || now() + 10_000
    assert {:ok, batch} = Session.drain(pid)
    refute Enum.any?(batch, &(&1.kind == :server_request)), "Unexpected native tool/approval"
    events = events ++ batch

    if Enum.any?(
         notices(events, "turn/completed"),
         &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
       ) do
      events
    else
      assert now() < deadline, "Owned native session-budget event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native session-budget gap")
      after
        20 -> :ok
      end

      collect(pid, thread, turn, events, deadline)
    end
  end

  defp assert_quiet(ctx, pid, deadline) do
    assert {:ok, batch} = Session.drain(pid)
    refute Enum.any?(batch, &(&1.kind == :server_request))

    refute Enum.any?(batch, fn event ->
             event.wire["method"] in ["error", "turn/started", "turn/completed"] or
               String.starts_with?(event.wire["method"] || "", "thread/goal/")
           end)

    assert json(ctx, "goal-attempts.json") == 1

    if now() < deadline do
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native session-budget gap")
      after
        20 -> :ok
      end

      assert_quiet(ctx, pid, deadline)
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
             Session.initialize(
               pid,
               %{"name" => "samgita_session_budget", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true
               }
             )

    pid
  end

  defp control(ctx, op) do
    id = "owned-session-budget-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.any?(journal(ctx, "control_done"), &(&1["id"] == id)) end)
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)
    if File.exists?(Path.join(ctx.root, "state.json")), do: assert_owned_gone(ctx)
    IO.puts(:stderr, "Owned session-budget evidence retained: #{ctx.root}")
  end

  defp assert_owned_gone(ctx) do
    proof = json(ctx, "state.json")

    for process <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]] do
      await(fn -> not File.exists?("/proc/#{process}") end)
    end

    assert length(journal(ctx, "fixture_closed")) == 1
    assert :atomics.get(ctx.owner.owner.completion, 1) == 1
    assert Port.info(ctx.owner.port) == nil
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || now() + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert now() < deadline, "Owned session-budget fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp journal(ctx, event),
    do: Enum.filter(json(ctx, "bem-journal.json"), &(&1["event"] == event))

  defp json(ctx, file), do: ctx.root |> Path.join(file) |> File.read!() |> JSON.decode!()
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
