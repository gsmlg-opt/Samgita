defmodule SamgitaCodexDriver.NativeMemoryCitationProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  # Qualifies native synthetic Responses citation parsing and persisted reads.
  # No memory retrieval, host-memory access, account or other profile is qualified.
  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_memory_citation_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @scenario "fixed-memory-citation"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-memory-citation-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp bin),
        do: File.mkdir_p!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      socket: Path.join(root, "native.sock"),
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary), "--scenario", @scenario],
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

    on_exit(fn -> close_fixture(ctx, owner) end)
    await(fn -> ready?(ctx) end, "private memory-citation namespace/native UDS startup")
    proof = read_json(ctx, "state.json")
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert File.ls!(ctx.workspace) == []
    Map.put(ctx, :owner, owner)
  end

  test "native citation markup becomes exact live and first cold selective memoryCitation", ctx do
    warm = client(ctx)

    thread =
      call(warm, "thread/start", %{
        "cwd" => ctx.workspace,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert read_json(ctx, "requests.json") == []
    config = File.read!(Path.join(ctx.root, "codex/config.toml"))
    before_ms = System.system_time(:millisecond)

    turn =
      call(warm, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:memory-citation:" <> @scenario}]
      })["turn"]["id"]

    events = collect(warm, thread, turn, [])
    after_ms = System.system_time(:millisecond)
    expected = assert_live_items(events, thread, turn, {before_ms, after_ms})
    assert [request] = read_json(ctx, "requests.json")
    assert_inert(ctx, warm)

    # Producer/store barrier only; never obtain expected citation values here.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(warm, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
               "thread"
             ]["turns"]

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => Enum.map(items(), & &1["id"])}
    assert_selection(warm, query, expected)
    assert read_json(ctx, "requests.json") === [request]
    assert_inert(ctx, warm)
    warm_instance = Session.status(warm).instance_id
    assert :ok = Session.close(warm)
    restart(ctx)
    cold = client(ctx)
    refute Session.status(cold).instance_id == warm_instance
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # First content read after PID replacement: no resume or history hydration.
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected)
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # Independently prescribed content must also survive the public history API.
    assert [%{"id" => ^turn, "items" => history}] =
             call(cold, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
               "thread"
             ]["turns"]

    assert Enum.filter(history, &(&1["type"] == "agentMessage")) === items()
    assert read_json(ctx, "requests.json") === [request]
    assert File.read!(Path.join(ctx.root, "codex/config.toml")) === config
    assert_inert(ctx, cold)
    assert :ok = Session.close(cold)
  end

  defp items do
    [
      agent_item("modern", "Owned modern visible λ. Tail.", "commentary", %{
        "entries" => [
          %{
            "path" => "synthetic/owned-memory.md",
            "lineStart" => 7,
            "lineEnd" => 11,
            "note" => "owned summary λ"
          },
          %{
            "path" => "synthetic/owned-detail.md",
            "lineStart" => 20,
            "lineEnd" => 23,
            "note" => "owned detail"
          }
        ],
        # Output preserves parser strings, deduplicated in first-seen order;
        # UUID filtering belongs only to local usage accounting, not this wire.
        "threadIds" => ["owned-rollout-alpha", "owned-rollout-beta"]
      }),
      agent_item("legacy", "Owned legacy visible. Done.", "final_answer", %{
        "entries" => [
          %{
            "path" => "synthetic/owned-legacy.md",
            "lineStart" => 2,
            "lineEnd" => 4,
            "note" => "owned legacy note"
          }
        ],
        "threadIds" => ["owned-thread-first", "owned-thread-second"]
      })
    ]
  end

  defp agent_item(name, text, phase, citation),
    do: %{
      "type" => "agentMessage",
      "id" => "owned-memory-" <> name,
      "text" => text,
      "phase" => phase,
      "memoryCitation" => citation,
      "delivery" => nil,
      "questions" => nil
    }

  defp assert_live_items(events, thread, turn, {before_ms, after_ms}) do
    started = agent_notifications(events, "item/started")
    completed = agent_notifications(events, "item/completed")
    ids = Enum.map(items(), & &1["id"])
    assert Enum.map(started, & &1["item"]["id"]) == ids
    assert Enum.map(completed, & &1["item"]["id"]) == ids

    entries =
      for {item, start, finish} <- Enum.zip([items(), started, completed]) do
        started_at = Map.fetch!(start, "startedAtMs")
        completed_at = Map.fetch!(finish, "completedAtMs")
        assert is_integer(started_at) and is_integer(completed_at)
        assert before_ms <= started_at and started_at <= completed_at and completed_at <= after_ms

        assert start === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => item,
                 "startedAtMs" => started_at
               }

        assert finish === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => item,
                 "completedAtMs" => completed_at
               }

        refute item["text"] =~ "citation"
        refute item["text"] =~ "synthetic/"

        %{
          "turnId" => turn,
          "item" => item,
          "startedAtMs" => started_at,
          "completedAtMs" => completed_at
        }
      end

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             notifications(events, "turn/completed")

    assert Enum.all?(notifications(events, "item/completed"), fn params ->
             params["item"]["type"] in ~w(userMessage agentMessage)
           end)

    %{"data" => entries}
  end

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === expected

    for entry <- expected["data"] do
      assert call(pid, "thread/items/read", %{query | "itemIds" => [entry["item"]["id"]]}) ===
               %{"data" => [entry]}
    end

    ids = ["owned-absent-memory-item" | Enum.reverse(query["itemIds"]) ++ query["itemIds"]]
    assert call(pid, "thread/items/read", %{query | "itemIds" => ids}) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-memory-item"]}) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-memory-turn"}) ===
             %{"data" => []}
  end

  defp restart(ctx) do
    previous = read_json(ctx, "state.json")
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"restart" => true}))

    await(
      fn ->
        ready?(ctx) and read_json(ctx, "state.json")["generation"] == previous["generation"] + 1
      end,
      "explicit owned memory-citation native restart"
    )

    for pid <- previous["native_pids"], do: refute(File.exists?("/proc/#{pid}"))
    current = read_json(ctx, "state.json")
    assert length(current["native_pids"]) == length(previous["native_pids"]) + 1
    refute List.last(current["native_pids"]) in previous["native_pids"]
  end

  defp assert_inert(ctx, pid) do
    refute Enum.any?(
             drain(pid),
             &String.starts_with?(&1.wire["method"] || "", ["turn/", "item/"])
           )

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "home/.codex"))
    assert File.ls!(ctx.workspace) == []
    assert length(read_json(ctx, "requests.json")) == 1
  end

  defp client(ctx) do
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
               %{"name" => "owned_memory_citation", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp collect(pid, thread, turn, events, deadline \\ nil) do
    deadline = deadline || now() + 5_000
    events = events ++ drain(pid)

    if Enum.any?(
         notifications(events, "turn/completed"),
         &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
       ) do
      events
    else
      assert now() < deadline, "native memory-citation turn completion barrier"

      receive do
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, deadline)
    end
  end

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

  defp notifications(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp agent_notifications(events, method),
    do: Enum.filter(notifications(events, method), &(&1["item"]["type"] == "agentMessage"))

  defp close_fixture(ctx, owner) do
    assert :ok = Stdio.close(owner)
    assert length(read_json(ctx, "requests.json")) == 1
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = read_json(ctx, "state.json")

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: await_gone(pid)
    end
  end

  defp await_gone(pid),
    do: await(fn -> not File.exists?("/proc/#{pid}") end, "owned memory-citation process reaping")

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
