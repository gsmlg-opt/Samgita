defmodule SamgitaCodexDriver.NativeQueueImageSnapshotProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ImageFixture, Session}
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_queue_image_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @materialize "Owned queue image materialization"
  @enqueue "Owned immutable queue image"
  @replacement "Owned replacement queue image"
  @answer "Owned queued image snapshot acknowledged"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-qi-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
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
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
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
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]
    assert [ready] = events(ctx, "bem-journal.json", "queue_provider_ready")
    assert ready["scenario"] == tags.scenario
    assert ready["source_provider_requests"] == 0 and ready["request_auth"] == "none"
    assert ready["output"] == "fixed_assistant_messages_only"

    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "cli_auth_credentials_store = \"file\""
    assert config =~ "requires_openai_auth = false"
    assert config =~ "supports_websockets = false"
    assert config =~ "enable_request_compression = false"
    assert config =~ "shell_snapshot = false"
    assert config =~ "shell_tool = false"
    assert config =~ "unified_exec = false"
    assert config =~ "[analytics]\nenabled = false"
    refute config =~ "experimental_bearer_token"
    refute config =~ "experimental_realtime"
    refute File.exists?(Path.join(root, "codex/auth.json"))

    assert [%{"supports_image_detail_original" => true}] =
             json(ctx, "codex/models.json")["models"]

    ctx
  end

  @tag scenario: "enqueue"
  test "legacy queue freezes an accepted PNG before overwrite deletion and cold dispatch", ctx do
    {pid, id, baseline} = unloaded(ctx, "legacy")
    source = Path.join(ctx.root, "workspace/owned enqueue.png")
    original = ImageFixture.png(2, 3)
    replacement = ImageFixture.png(4, 5)
    refute hash(original) == hash(replacement)
    File.write!(source, original)
    saved = add(pid, id, "owned-queue-image-enqueue", @enqueue, source)
    assert_saved(saved, "owned-queue-image-enqueue", @enqueue, original, {2, 3})
    assert_queue(pid, id, saved)
    assert_safe(ctx, pid, [], 1, true)

    File.write!(source, replacement)
    assert File.read!(source) == replacement
    assert hash(File.read!(source)) == hash(replacement)
    refute hash(File.read!(source)) == hash(original)
    assert_queue(pid, id, saved)
    assert_safe(ctx, pid, [], 1, true)
    File.rm!(source)
    assert File.ls!(Path.join(ctx.root, "workspace")) == []

    cold = restart(ctx, pid)
    assert_unloaded(ctx, cold, id, saved, "legacy")
    assert_dispatched_snapshot(ctx, cold, id, saved, original, {2, 3}, baseline)
  end

  @tag scenario: "update"
  test "paginated queue atomically replaces a PNG and retains the accepted snapshot after rejection",
       ctx do
    {pid, id, baseline} = unloaded(ctx, "paginated")
    source = Path.join(ctx.root, "workspace/owned original.png")
    edited = Path.join(ctx.root, "workspace/owned replacement.png")
    missing = Path.join(ctx.root, "workspace/owned absent.png")
    original = ImageFixture.png(2, 3)
    replacement = ImageFixture.png(4, 5)
    refute hash(original) == hash(replacement)
    File.write!(source, original)
    saved = add(pid, id, "owned-queue-image-update", "Owned superseded queue image", source)

    assert_saved(
      saved,
      "owned-queue-image-update",
      "Owned superseded queue image",
      original,
      {2, 3}
    )

    File.rm!(source)
    File.write!(edited, replacement)

    updated =
      call(pid, "thread/queue/update", %{
        "threadId" => id,
        "queuedSubmissionId" => saved["id"],
        "input" => local_input(@replacement, edited)
      })["queuedSubmission"]

    assert updated == %{saved | "input" => normalized(@replacement, replacement)}
    assert_saved(updated, "owned-queue-image-update", @replacement, replacement, {4, 5})
    File.rm!(edited)
    refute File.exists?(missing)

    assert {:error, %Error{code: :upstream_error, wire: %{"error" => rejected}}} =
             Session.request(pid, "thread/queue/update", %{
               "threadId" => id,
               "queuedSubmissionId" => saved["id"],
               "input" => local_input("Owned rejected queue replacement", missing)
             })

    assert rejected == %{
             "code" => -32_600,
             "message" =>
               "local queued attachment is invalid: No such file or directory (os error 2)"
           }

    assert_queue(pid, id, updated)
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    assert_safe(ctx, pid, [], 1, true)
    cold = restart(ctx, pid)
    assert_unloaded(ctx, cold, id, updated, "paginated")
    assert_dispatched_snapshot(ctx, cold, id, updated, replacement, {4, 5}, baseline)
  end

  defp unloaded(ctx, mode) do
    pid = connect(ctx)

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

    turn =
      call(pid, "turn/start", %{"threadId" => id, "input" => text_input(@materialize)})["turn"][
        "id"
      ]

    execution = collect(pid, &completed?(&1, id, turn))
    baseline = turns(pid, id)
    assert [%{"id" => ^turn, "status" => "completed", "error" => nil}] = baseline
    assert_safe(ctx, pid, execution, 1)
    cold = restart(ctx, pid)

    assert call(cold, "thread/queue/list", %{"threadId" => id}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert turns(cold, id) == baseline
    assert_safe(ctx, cold, [], 1, true)
    {cold, id, baseline}
  end

  defp assert_saved(saved, client, text, bytes, dimensions) do
    assert_uuid(saved["id"])

    assert saved == %{
             "id" => saved["id"],
             "clientUserMessageId" => client,
             "input" => normalized(text, bytes)
           }

    [_, image] = saved["input"]
    assert_image(image["url"], bytes, dimensions)
  end

  defp assert_unloaded(ctx, pid, id, saved, mode) do
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    facts = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]
    assert facts["id"] == id and facts["historyMode"] == mode
    assert facts["status"] == %{"type" => "notLoaded"}
    assert_queue(pid, id, saved)
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_safe(ctx, pid, [], 1, true)
  end

  defp assert_dispatched_snapshot(ctx, pid, id, saved, bytes, dimensions, baseline) do
    # A noninterrupted resumed thread automatically wakes its stored queue.
    # Resume is the only dispatch trigger here; queue/start is deliberately absent.
    assert call(pid, "thread/resume", %{"threadId" => id})["thread"]["id"] == id
    client = saved["clientUserMessageId"]

    execution =
      collect(pid, fn batch ->
        case user_item(batch, "item/started", client) do
          nil -> false
          item -> completed?(batch, id, item["turnId"])
        end
      end)

    {turn, expected_item, started, finished} = assert_user_item(execution, id, saved)

    {expected_assistant, assistant_started, assistant_finished} =
      assert_assistant_item(execution, id, turn)

    assert assistant_started >= finished
    {stored_item, stored_assistant} = stored_items(ctx, expected_item, expected_assistant)
    [original] = baseline
    assert [^original, persisted] = turns(pid, id)
    assert persisted["id"] == turn and persisted["status"] == "completed"
    assert persisted["error"] == nil and persisted["itemsView"] == "full"
    assert persisted["items"] == [stored_item, stored_assistant]

    entry = %{
      "turnId" => turn,
      "item" => stored_item,
      "startedAtMs" => started,
      "completedAtMs" => finished
    }

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [stored_item["id"]]}
    assert_selected_history(ctx, pid, query, entry)

    assistant_selection =
      if ctx.scenario == "update" do
        assistant_query = %{
          "threadId" => id,
          "turnId" => turn,
          "itemIds" => [expected_assistant["id"]]
        }

        assistant_entry = %{
          "turnId" => turn,
          "item" => expected_assistant,
          "startedAtMs" => assistant_started,
          "completedAtMs" => assistant_finished
        }

        assert_selected_history(ctx, pid, assistant_query, assistant_entry)
        {assistant_query, assistant_entry}
      end

    assert call(pid, "thread/queue/list", %{"threadId" => id}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert_provider_snapshot(ctx, id, turn, saved, bytes, dimensions)
    assert_safe(ctx, pid, execution, 2)
    history = turns(pid, id)
    cold = restart(ctx, pid)
    assert turns(cold, id) == history
    assert_selected_history(ctx, cold, query, entry)

    if assistant_selection do
      {assistant_query, assistant_entry} = assistant_selection
      assert_selected_history(ctx, cold, assistant_query, assistant_entry)
    end

    assert call(cold, "thread/queue/list", %{"threadId" => id}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_safe(ctx, cold, [], 2, true)
    finish(ctx, cold)
  end

  defp stored_items(%{scenario: "enqueue"}, user, assistant) do
    # Legacy history assigns sequential IDs across the two materialized turns.
    {%{user | "id" => "item-3"}, %{assistant | "id" => "item-4"}}
  end

  defp stored_items(%{scenario: "update"}, user, assistant), do: {user, assistant}

  defp assert_selected_history(%{scenario: "enqueue"}, pid, query, _entry) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, "thread/items/read", query)

    assert error == %{
             "code" => -32_601,
             "message" => "thread/items/read is not supported yet"
           }
  end

  defp assert_selected_history(%{scenario: "update"}, pid, query, entry),
    do: assert(call(pid, "thread/items/read", query) == %{"data" => [entry]})

  defp assert_user_item(execution, id, saved) do
    client = saved["clientUserMessageId"]
    began = user_item(execution, "item/started", client)
    ended = user_item(execution, "item/completed", client)
    turn = began["turnId"]
    assert_uuid(turn)
    assert is_binary(began["item"]["id"]) and byte_size(began["item"]["id"]) > 0

    expected_item = %{
      "type" => "userMessage",
      "id" => began["item"]["id"],
      "clientId" => client,
      "content" => saved["input"]
    }

    for item <- [began, ended] do
      assert item["threadId"] == id and item["turnId"] == turn
      assert item["item"] == expected_item
    end

    for method <- ["item/started", "item/completed"] do
      assert length(Enum.filter(notices(execution, method), &(&1["item"]["clientId"] == client))) ==
               1
    end

    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn}}] = notices(execution, "turn/started")
    assert [completion] = notices(execution, "turn/completed")
    assert completion["threadId"] == id
    assert completion["turn"]["id"] == turn
    assert completion["turn"]["status"] == "completed" and completion["turn"]["error"] == nil
    started = Map.fetch!(began, "startedAtMs")
    finished = Map.fetch!(ended, "completedAtMs")
    assert is_integer(started) and started > 0
    assert is_integer(finished) and finished >= started

    {turn, expected_item, started, finished}
  end

  defp assert_assistant_item(execution, id, turn) do
    assert [began] =
             Enum.filter(
               notices(execution, "item/started"),
               &(&1["item"]["type"] == "agentMessage")
             )

    assert [ended] =
             Enum.filter(
               notices(execution, "item/completed"),
               &(&1["item"]["type"] == "agentMessage")
             )

    expected_assistant = %{
      "type" => "agentMessage",
      "id" => "owned-queue-image-2",
      "text" => @answer,
      "delivery" => nil,
      "memoryCitation" => nil,
      "phase" => nil,
      "questions" => nil
    }

    for item <- [began, ended] do
      assert item["threadId"] == id and item["turnId"] == turn
      assert item["item"] == expected_assistant
    end

    started = Map.fetch!(began, "startedAtMs")
    finished = Map.fetch!(ended, "completedAtMs")
    assert is_integer(started) and started > 0
    assert is_integer(finished) and finished >= started
    {expected_assistant, started, finished}
  end

  defp assert_provider_snapshot(ctx, id, turn, saved, bytes, dimensions) do
    await(fn ->
      length(json(ctx, "queue-http.json")) == 2 and
        Enum.all?(json(ctx, "queue-http.json"), & &1["responded"])
    end)

    assert [first_request, queued_request] = json(ctx, "requests.json")
    assert @materialize in user_texts(first_request)
    [text, _] = saved["input"]
    assert text["text"] in user_texts(queued_request)

    assert [%{"type" => "input_image", "image_url" => image, "detail" => "original"}] =
             for(
               message <- queued_request["input"],
               message["role"] == "user",
               part <- Map.get(message, "content", []),
               part["type"] == "input_image",
               do: part
             )

    assert image == ImageFixture.data_url(bytes)
    assert_image(image, bytes, dimensions)

    assert [_, record] = json(ctx, "queue-http.json")
    assert record["metadata"]["thread_id"] == id
    assert record["metadata"]["turn_id"] == turn
    assert record["metadata"]["turn_trigger"] == "queue"
  end

  defp assert_image(url, bytes, dimensions) do
    assert url == ImageFixture.data_url(bytes)
    assert {decoded, ^dimensions} = ImageFixture.decode_png!(url)
    assert decoded == bytes and hash(decoded) == hash(bytes)
  end

  defp assert_safe(ctx, pid, execution, count, inert \\ false) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    observed = execution ++ remaining
    refute Enum.any?(observed, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    if inert, do: assert(notices(observed, "turn/started") == [])
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert events(ctx, "realtime-journal.json", "handshake") == []
    assert events(ctx, "realtime-journal.json", "native_frame") == []

    await(fn ->
      length(json(ctx, "queue-http.json")) == count and
        Enum.all?(json(ctx, "queue-http.json"), & &1["responded"])
    end)

    requests = json(ctx, "requests.json")
    records = json(ctx, "queue-http.json")
    assert length(requests) == count and length(records) == count

    for {record, index} <- Enum.with_index(records, 1) do
      raw = Base.decode64!(record["rawBodyBase64"])
      assert byte_size(raw) > 0 and byte_size(raw) <= 4_194_304
      assert hash(raw) == record["rawBodySHA256"]
      assert JSON.decode!(raw) == Enum.at(requests, index - 1)
      assert record["index"] == index and record["path"] == "/v1/responses"
      assert record["requestAuth"] == "none" and record["responded"]
    end

    assert File.ls!(Path.join(ctx.root, "workspace")) in [[], ["owned enqueue.png"]]
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp add(pid, id, client, text, path),
    do:
      call(pid, "thread/queue/add", %{
        "threadId" => id,
        "clientUserMessageId" => client,
        "input" => local_input(text, path)
      })["queuedSubmission"]

  defp text_input(text), do: [%{"type" => "text", "text" => text}]

  defp local_input(text, path),
    do: text_input(text) ++ [%{"type" => "localImage", "path" => path, "detail" => "original"}]

  defp normalized(text, bytes),
    do: [
      %{"type" => "text", "text" => text, "text_elements" => []},
      %{"type" => "image", "url" => ImageFixture.data_url(bytes), "detail" => "original"}
    ]

  defp assert_queue(pid, id, saved),
    do:
      assert(
        call(pid, "thread/queue/list", %{"threadId" => id}) == %{
          "data" => [saved],
          "nextCursor" => nil
        }
      )

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
               %{"name" => "samgita_queue_image_snapshot", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
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

    IO.puts(:stderr, "Owned queued image evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-queue-#{System.unique_integer([:positive])}"
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
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned queue image native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected queue image event gap")
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
               "Owned queue image fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp user_item(execution, method, client),
    do:
      Enum.find(
        notices(execution, method),
        &(&1["item"]["type"] == "userMessage" and &1["item"]["clientId"] == client)
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
