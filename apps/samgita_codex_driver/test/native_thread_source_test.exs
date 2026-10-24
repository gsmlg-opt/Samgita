defmodule SamgitaCodexDriver.NativeThreadSourceTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @custom "owned-feature λ🙂 / source"
  @search_text "Owned source search conversation marker"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  for mode <- ["legacy", "paginated"] do
    @history_mode mode
    test "#{mode} start preserves source strings and exact null defaults through cold resume",
         ctx do
      pid = start(ctx)

      rows =
        for {label, params, expected} <- source_cases() do
          thread = new_thread(ctx, pid, Map.put(params, "historyMode", @history_mode))
          assert_source(thread, expected)
          assert_started(pid, thread["id"], expected)
          assert thread["turns"] == []
          saved = save(pid, thread["id"], "Owned source #{label}")
          assert_source(saved, expected)
          assert saved["turns"] == []
          assert_meta_source(latest_meta(saved), expected)
          {thread["id"], expected}
        end

      assert_metadata_only_listing(pid, rows)
      assert_no_execution(ctx, pid, 0)
      process = process_id(pid)
      assert :ok = Session.close(pid)
      cold = start(ctx)
      refute process_id(cold) == process
      assert loaded(cold) == []
      assert_metadata_only_listing(cold, rows)

      for {id, expected} <- rows do
        saved = read(cold, id)
        assert_source(saved, expected)
        assert saved["turns"] == []
      end

      # Cold reads and listings do not load threads. Explicit resume restores
      # the persisted source rather than choosing a new analytics label.
      assert loaded(cold) == []

      for {id, expected} <- rows do
        resumed = call(cold, "thread/resume", %{"threadId" => id})["thread"]
        assert resumed["id"] == id
        assert_source(resumed, expected)
        assert resumed["turns"] == []
      end

      assert MapSet.new(loaded(cold)) == MapSet.new(Enum.map(rows, &elem(&1, 0)))
      assert_no_execution(ctx, cold, 0)
    end

    test "#{mode} fork resets omitted or null source and persists explicit child attribution",
         ctx do
      pid = start(ctx)

      parent =
        new_thread(ctx, pid, %{"historyMode" => @history_mode, "threadSource" => @custom})

      assert_started(pid, parent["id"], @custom)
      parent = save(pid, parent["id"], "Owned source parent")
      parent_meta = latest_meta(parent)
      assert_source(parent, @custom)
      assert parent["turns"] == []

      children =
        for {_label, params, expected} <- source_cases() do
          child = call(pid, "thread/fork", Map.put(params, "threadId", parent["id"]))["thread"]
          refute child["id"] == parent["id"]
          assert child["forkedFromId"] == parent["id"]
          assert child["turns"] == []
          assert_source(child, expected)
          assert_started(pid, child["id"], expected)
          assert_meta_source(latest_meta(child), expected)
          assert_source(read(pid, parent["id"]), @custom)
          assert latest_meta(parent) == parent_meta
          {child["id"], expected}
        end

      rows = [{parent["id"], @custom} | children]
      assert_metadata_only_listing(pid, rows)
      assert_no_execution(ctx, pid, 0)
      process = process_id(pid)
      assert :ok = Session.close(pid)
      cold = start(ctx)
      refute process_id(cold) == process
      assert loaded(cold) == []
      assert_metadata_only_listing(cold, rows)
      assert latest_meta(parent) == parent_meta

      for {id, expected} <- rows do
        assert_source(read(cold, id), expected)
      end

      assert loaded(cold) == []

      for {id, expected} <- rows do
        resumed = call(cold, "thread/resume", %{"threadId" => id})["thread"]
        assert_source(resumed, expected)
        assert resumed["turns"] == []

        if id != parent["id"], do: assert(resumed["forkedFromId"] == parent["id"])
      end

      assert_source(read(cold, parent["id"]), @custom)
      assert_meta_source(latest_meta(parent), @custom)
      assert_no_execution(ctx, cold, 0)
    end
  end

  test "native search and loaded read project null while cold read and resume retain attribution",
       ctx do
    pid = start(ctx)

    rows =
      for expected <- ["user", @custom, nil] do
        thread =
          new_thread(ctx, pid, %{"historyMode" => "legacy", "threadSource" => expected})

        assert_started(pid, thread["id"], expected)

        turn =
          TurnFixture.start_turn(pid, thread["id"], [
            %{"type" => "text", "text" => @search_text}
          ])

        TurnFixture.finish_turn(pid, thread["id"], turn)
        saved = read(pid, thread["id"])
        assert [%{"id" => ^turn, "status" => "completed"}] = saved["turns"]
        # Loaded reads reuse persisted metadata-only summaries. Once a legacy
        # rollout has a preview, that native projection omits the analytics
        # label. The canonical session metadata still retains the original.
        assert_source(saved, nil)
        assert_meta_source(latest_meta(saved), expected)
        {thread["id"], expected}
      end

    assert_search_sources(pid, rows)
    assert_no_execution(ctx, pid, 3)
    process = process_id(pid)
    assert :ok = Session.close(pid)
    cold = start(ctx)
    refute process_id(cold) == process
    assert loaded(cold) == []
    assert_search_sources(cold, rows)
    assert loaded(cold) == []

    for {id, expected} <- rows do
      assert_source(read(cold, id), expected)
    end

    assert loaded(cold) == []

    for {id, expected} <- rows do
      resumed = call(cold, "thread/resume", %{"threadId" => id})["thread"]
      assert_source(resumed, expected)
      assert [%{"status" => "completed"}] = resumed["turns"]
    end

    assert_search_sources(cold, rows)
    assert_no_execution(ctx, cold, 3)
  end

  test "stable source attribution needs no experimental gate and malformed values preserve threads",
       ctx do
    pid = start(ctx, experimental: false)
    parent = new_thread(ctx, pid, %{"threadSource" => @custom})
    assert_started(pid, parent["id"], @custom)
    parent = save(pid, parent["id"], "Owned stable source")
    assert_source(parent, @custom)

    child =
      call(pid, "thread/fork", %{"threadId" => parent["id"], "threadSource" => "user"})[
        "thread"
      ]

    assert_source(child, "user")
    assert_started(pid, child["id"], "user")
    baseline = [{parent["id"], @custom}, {child["id"], "user"}]
    loaded_before = MapSet.new(loaded(pid))
    parent_meta = latest_meta(parent)
    child_meta = latest_meta(child)

    for invalid <- [17, false, [], %{}] do
      for {method, params} <- [
            {"thread/start", Map.put(thread_params(ctx), "threadSource", invalid)},
            {"thread/fork", %{"threadId" => parent["id"], "threadSource" => invalid}}
          ] do
        error = upstream_error(pid, method, params, validation: :wire)
        assert error["code"] == -32_600
        assert String.starts_with?(error["message"], "Invalid request:")
        assert MapSet.new(loaded(pid)) == loaded_before
        assert_metadata_only_listing(pid, baseline)
        assert latest_meta(parent) == parent_meta
        assert latest_meta(child) == child_meta
        assert_no_execution(ctx, pid, 0)
      end
    end

    assert read(pid, parent["id"])["turns"] == []
    assert read(pid, child["id"])["turns"] == []
    assert_no_execution(ctx, pid, 0)
  end

  defp source_cases do
    [
      {"omitted", %{}, nil},
      {"null", %{"threadSource" => nil}, nil},
      {"user", %{"threadSource" => "user"}, "user"},
      {"custom", %{"threadSource" => @custom}, @custom},
      {"empty", %{"threadSource" => ""}, ""}
    ]
  end

  defp thread_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false
    }
  end

  defp new_thread(ctx, pid, extra),
    do: call(pid, "thread/start", Map.merge(thread_params(ctx), extra))["thread"]

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp save(pid, id, name) do
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    thread = read(pid, id)
    assert thread["name"] == name
    assert File.regular?(thread["path"])
    thread
  end

  defp list(pid), do: call(pid, "thread/list", %{"limit" => 100})["data"]
  defp loaded(pid), do: call(pid, "thread/loaded/list", %{})["data"]
  defp process_id(pid), do: call(pid, "server/diagnostics", %{})["process"]["id"]

  defp assert_source(thread, expected) do
    assert Map.fetch!(thread, "threadSource") == expected
    assert thread["source"] == "vscode"
  end

  defp assert_metadata_only_listing(pid, rows) do
    # Ordinary native discovery excludes active threads without previews, even
    # after name/set materializes their metadata. Explicit source/provider
    # filters demonstrate that this is not a source-kind or provider mismatch.
    assert list(pid) == []

    assert call(pid, "thread/list", %{
             "limit" => 100,
             "sourceKinds" => ["vscode"],
             "modelProviders" => []
           })["data"] == []

    for {id, expected} <- rows do
      saved = read(pid, id)
      assert_source(saved, expected)
      assert saved["turns"] == []
      assert_meta_source(latest_meta(saved), expected)
    end
  end

  defp assert_projected_sources(threads, rows) do
    assert length(threads) == length(rows)

    assert MapSet.new(Enum.map(threads, & &1["id"])) ==
             MapSet.new(Enum.map(rows, &elem(&1, 0)))

    # The pinned local store builds ordinary list/search summaries
    # with thread_source: None. Preserve that native response; verify the saved
    # label separately through metadata, thread/read and explicit resume.
    Enum.each(threads, &assert_source(&1, nil))
  end

  defp assert_search_sources(pid, rows) do
    response = call(pid, "thread/search", %{"searchTerm" => @search_text, "limit" => 100})
    assert Map.fetch!(response, "nextCursor") == nil
    assert_projected_sources(Enum.map(response["data"], & &1["thread"]), rows)
    assert Enum.all?(response["data"], &(&1["snippet"] == @search_text))
  end

  defp assert_meta_source(meta, nil), do: refute(Map.has_key?(meta, "thread_source"))

  defp assert_meta_source(meta, expected),
    do: assert(Map.fetch!(meta, "thread_source") === expected)

  defp latest_meta(thread) do
    metadata =
      thread["path"]
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)
      |> Enum.filter(&(&1["type"] == "session_meta" and &1["payload"]["id"] == thread["id"]))

    assert metadata != []
    List.last(metadata)["payload"]
  end

  defp assert_started(pid, id, expected),
    do: await_started(pid, id, expected, System.monotonic_time(:millisecond) + 5_000)

  defp await_started(pid, id, expected, deadline) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    case TurnFixture.notification(events, "thread/started", &(&1["thread"]["id"] == id)) do
      %{"thread" => thread} ->
        assert_source(thread, expected)
        assert thread["turns"] == []

      nil ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Missing native thread/started for #{id}"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected thread source event gap")
        after
          min(remaining, 20) -> :ok
        end

        await_started(pid, id, expected, deadline)
    end
  end

  defp assert_no_execution(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp start(ctx, opts \\ []) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: ["app-server", "--listen", "stdio://"],
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_native_thread_source", "version" => "0.1.0"},
               %{"experimentalApi" => Keyword.get(opts, :experimental, true)}
             )

    pid
  end
end
