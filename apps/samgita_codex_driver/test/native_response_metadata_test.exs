defmodule SamgitaCodexDriver.NativeResponseMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/response_metadata_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @canary "OWNED_RESPONSE_METADATA_PRIVATE_CANARY"
  @metadata_methods [
    "model/rerouted",
    "model/verification",
    "turn/moderationMetadata",
    "model/safetyBuffering/updated"
  ]
  @usage %{
    "input_tokens" => 12,
    "input_tokens_details" => %{"cached_tokens" => 3, "cache_write_tokens" => 2},
    "output_tokens" => 7,
    "output_tokens_details" => %{"reasoning_tokens" => 4},
    "total_tokens" => 19
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ["python3", "unshare", "ip"],
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-response-metadata-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ["home", "codex", "workspace", "tmp", "bin"],
        do: File.mkdir_p!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      scenario: tags.scenario,
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

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
          ctx.scenario
        ],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)
      assert length(read_json(ctx, "requests.json")) == 1
      refute File.exists?(Path.join(root, "unexpected-inference.json"))

      if File.exists?(Path.join(root, "state.json")) do
        proof = read_json(ctx, "state.json")

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do:
              await(
                fn -> not File.exists?("/proc/#{os_pid}") end,
                "owned metadata process reaping"
              )
      end
    end)

    await(fn -> ready?(ctx) end, "private metadata namespace/native UDS startup")
    proof = read_json(ctx, "state.json")
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert File.read!(Path.join(root, "codex/config.toml")) =~ @canary
    Map.put(ctx, :owner, owner)
  end

  @tag scenario: "rich"
  test "native metadata yields correlated raw usage, reroute, verification, moderation and buffering",
       ctx do
    {events, thread, turn} = run(ctx, true)
    assert_rich(events, thread, turn, ctx.scenario)

    assert notification(events, "turn/moderationMetadata") == %{
             "threadId" => thread,
             "turnId" => turn,
             "metadata" => %{"presentation" => "inline", "owned" => [1, nil]}
           }

    assert length(notifications(events, "turn/moderationMetadata")) == 1
  end

  @tag scenario: "null"
  test "null usage remains explicit and malformed or misplaced metadata creates no notices",
       ctx do
    {events, thread, turn} = run(ctx, true)

    assert notification(events, "rawResponse/completed") == %{
             "threadId" => thread,
             "turnId" => turn,
             "responseId" => "owned-response-null",
             "usage" => nil,
             "usageMetadata" => nil
           }

    for method <- @metadata_methods, do: assert(notifications(events, method) == [])
    item = output_item(events)
    refute Map.has_key?(item, "status")
    refute Map.has_key?(item, "phase")
  end

  @tag scenario: "nullable-metadata"
  test "metadata object and arbitrary moderation JSON retain explicit null values", ctx do
    {events, thread, turn} = run(ctx, true)

    assert notification(events, "rawResponse/completed") == %{
             "threadId" => thread,
             "turnId" => turn,
             "responseId" => "owned-response-nullable-metadata",
             "usage" => nil,
             "usageMetadata" => %{"amount" => nil, "metadata" => nil}
           }

    assert notification(events, "turn/moderationMetadata") == %{
             "threadId" => thread,
             "turnId" => turn,
             "metadata" => nil
           }

    for method <- @metadata_methods -- ["turn/moderationMetadata"],
        do: assert(notifications(events, method) == [])
  end

  @tag scenario: "stable"
  test "native connection filters experimental moderation while preserving stable metadata",
       ctx do
    {events, thread, turn} = run(ctx, false)
    assert_rich(events, thread, turn, ctx.scenario)
    assert notifications(events, "turn/moderationMetadata") == []
    assert notifications(events, "rawResponse/completed") == []
    assert notifications(events, "rawResponseItem/completed") == []
  end

  @tag scenario: "rich"
  test "final answer phase survives selective paginated history and owned cold restart", ctx do
    assert_persisted_phase(ctx, "final_answer")
  end

  @tag scenario: "phase-commentary"
  test "commentary phase survives selective paginated history and owned cold restart", ctx do
    assert_persisted_phase(ctx, "commentary")
  end

  @tag scenario: "phase-partial-answer"
  test "partial answer phase survives selective paginated history and owned cold restart", ctx do
    assert_persisted_phase(ctx, "partial_answer")
  end

  defp assert_persisted_phase(ctx, expected_phase) do
    {events, thread, turn, warm} =
      run_with_session(ctx, true, %{"historyMode" => "paginated"})

    # All public item values are prescribed by the provider fixture, independently
    # of the history response. Raw Responses items are a separate wire contract.
    expected_item = %{
      "type" => "agentMessage",
      "id" => "owned-metadata-item",
      "text" => "Owned metadata response.",
      "phase" => expected_phase,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

    assert [completed] =
             for(
               params <- notifications(events, "item/completed"),
               params["item"]["type"] == "agentMessage",
               do: params
             )

    completed_at = Map.fetch!(completed, "completedAtMs")
    assert is_integer(completed_at) and completed_at > 0

    assert completed == %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => expected_item,
             "completedAtMs" => completed_at
           }

    assert [request] = read_json(ctx, "requests.json")

    # At this pin, a loaded paginated full read calls persist_thread(Standard).
    # Its response is only the producer/store barrier, never the item oracle.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(warm, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
               "thread"
             ]["turns"]

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => ["owned-metadata-item"]}
    warm_response = call(warm, "thread/items/read", query)
    assert %{"data" => [entry]} = warm_response
    assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
    started_at = Map.fetch!(entry, "startedAtMs")
    assert is_nil(started_at) or (is_integer(started_at) and started_at <= completed_at)

    expected = %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => expected_item,
          "startedAtMs" => started_at,
          "completedAtMs" => completed_at
        }
      ]
    }

    assert warm_response === expected
    assert_selection(warm, query, expected)
    assert read_json(ctx, "requests.json") === [request]
    assert_no_history_execution(ctx, warm)
    warm_instance = Session.status(warm).instance_id
    assert :ok = Session.close(warm)

    before_restart = read_json(ctx, "state.json")
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"restart" => true}))

    await(
      fn ->
        state = read_json(ctx, "state.json")
        ready?(ctx) and state["generation"] == before_restart["generation"] + 1
      end,
      "explicit owned metadata native restart"
    )

    for os_pid <- before_restart["native_pids"],
        do: refute(File.exists?("/proc/#{os_pid}"))

    after_restart = read_json(ctx, "state.json")
    assert length(after_restart["native_pids"]) == length(before_restart["native_pids"]) + 1
    refute List.last(after_restart["native_pids"]) in before_restart["native_pids"]
    assert read_json(ctx, "requests.json") === [request]

    cold = client(ctx, true)
    refute Session.status(cold).instance_id == warm_instance
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # First content read in the replacement process: no resume, full-read
    # hydration, additional turn, or additional provider sample.
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert read_json(ctx, "requests.json") === [request]
    assert_no_history_execution(ctx, cold)
    assert :ok = Session.close(cold)
    assert read_json(ctx, "requests.json") === [request]
  end

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => ["owned-absent-item", "owned-metadata-item", "owned-metadata-item"]
           }) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-item"]}) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-turn"}) ===
             %{"data" => []}
  end

  defp assert_no_history_execution(ctx, pid) do
    methods = ~w(turn/started turn/completed item/started item/completed item/agentMessage/delta
                 rawResponse/completed rawResponseItem/completed)

    refute Enum.any?(drain(pid), &(&1.wire["method"] in methods))
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))
  end

  defp assert_rich(events, thread, turn, scenario) do
    if scenario != "stable" do
      assert notification(events, "rawResponse/completed") == %{
               "threadId" => thread,
               "turnId" => turn,
               "responseId" => "owned-response-" <> scenario,
               "usage" => %{
                 "inputTokens" => 12,
                 "cachedInputTokens" => 3,
                 "cacheWriteInputTokens" => 2,
                 "outputTokens" => 7,
                 "reasoningOutputTokens" => 4,
                 "totalTokens" => 19
               },
               "usageMetadata" => %{"amount" => "0.125", "metadata" => @usage}
             }

      item = output_item(events)
      assert Map.fetch!(item, "status") == "completed"
      assert Map.fetch!(item, "phase") == "final_answer"
    end

    assert notification(events, "model/rerouted") == %{
             "threadId" => thread,
             "turnId" => turn,
             "fromModel" => "mock-model",
             "toModel" => "owned-rerouted-model",
             "reason" => "highRiskCyberActivity"
           }

    assert length(notifications(events, "model/rerouted")) == 1

    assert notifications(events, "model/verification") == [
             %{
               "threadId" => thread,
               "turnId" => turn,
               "verifications" => ["trustedAccessForCyber"]
             }
           ]

    assert notifications(events, "model/safetyBuffering/updated") == [
             %{
               "threadId" => thread,
               "turnId" => turn,
               "model" => "mock-model",
               "useCases" => ["owned-case"],
               "reasons" => ["explicit"],
               "showBufferingUi" => true,
               "fasterModel" => "owned-wire-fast"
             },
             %{
               "threadId" => thread,
               "turnId" => turn,
               "model" => "mock-model",
               "useCases" => ["owned-case"],
               "reasons" => ["fallback"],
               "showBufferingUi" => true,
               "fasterModel" => "owned-header-fast"
             },
             %{
               "threadId" => thread,
               "turnId" => turn,
               "model" => "mock-model",
               "useCases" => [],
               "reasons" => ["explicit-null"],
               "showBufferingUi" => true,
               "fasterModel" => nil
             }
           ]
  end

  defp run(ctx, experimental) do
    {events, thread, turn, _pid} = run_with_session(ctx, experimental)
    {events, thread, turn}
  end

  defp client(ctx, experimental) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_response_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => experimental}
             )

    pid
  end

  defp run_with_session(ctx, experimental, thread_overrides \\ %{}) do
    pid = client(ctx, experimental)

    thread_params = %{
      "cwd" => ctx.workspace,
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request"
    }

    thread_params =
      if experimental,
        do: Map.put(thread_params, "experimentalRawEvents", true),
        else: thread_params

    thread_params = Map.merge(thread_params, thread_overrides)
    thread = call(pid, "thread/start", thread_params)["thread"]["id"]

    startup = drain(pid)
    assert read_json(ctx, "requests.json") == []

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:response-metadata:" <> ctx.scenario}]
      })["turn"]["id"]

    events = collect(pid, {thread, turn, experimental}, startup)
    assert notification(events, "turn/completed")["turn"]["status"] == "completed"
    assert length(read_json(ctx, "requests.json")) == 1
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))

    for event <- Enum.filter(events, &(&1.wire["method"] in ["item/started", "item/completed"])) do
      assert event.wire["params"]["item"]["type"] in ["userMessage", "agentMessage"]
    end

    assert Enum.any?(notifications(events, "item/completed"), fn params ->
             params["item"]["type"] == "agentMessage" and
               params["item"]["text"] == "Owned metadata response."
           end)

    encoded = JSON.encode!(Enum.map(events, & &1.wire))
    refute encoded =~ @canary
    refute JSON.encode!(read_json(ctx, "requests.json")) =~ @canary

    if experimental do
      item = output_item(events)

      assert Map.take(item, ["type", "id", "role", "content"]) == %{
               "type" => "message",
               "id" => "owned-metadata-item",
               "role" => "assistant",
               "content" => [%{"type" => "output_text", "text" => "Owned metadata response."}]
             }

      raw = notifications(events, "rawResponseItem/completed")

      assert Enum.any?(
               raw,
               &(&1["threadId"] == thread and &1["turnId"] == turn and &1["item"] == item)
             )
    end

    {events, thread, turn, pid}
  end

  defp output_item(events) do
    Enum.find_value(notifications(events, "rawResponseItem/completed"), fn params ->
      if params["item"]["id"] == "owned-metadata-item", do: params["item"]
    end)
  end

  defp notification(events, method), do: events |> notifications(method) |> List.first()

  defp notifications(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, failure} -> flunk("owned native #{method} failed: #{inspect(failure.wire)}")
    end
  end

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request)), "unapproved native server request"
    events
  end

  defp collect(pid, {thread, turn, raw?} = context, events, deadline \\ nil) do
    deadline = deadline || now() + 5_000
    events = events ++ drain(pid)

    completed =
      Enum.any?(
        notifications(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

    if completed &&
         (not raw? || (notification(events, "rawResponse/completed") && output_item(events))) do
      events
    else
      assert now() < deadline, "native response metadata barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      collect(pid, context, events, deadline)
    end
  end

  defp ready?(ctx) do
    if File.exists?(Path.join(ctx.root, "state.json")),
      do: read_json(ctx, "state.json")["ready"] and File.exists?(ctx.socket),
      else: false
  end

  defp read_json(ctx, path), do: ctx.root |> Path.join(path) |> File.read!() |> JSON.decode!()

  defp await(predicate, label, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(predicate, label, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
