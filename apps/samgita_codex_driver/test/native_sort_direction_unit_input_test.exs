defmodule SamgitaCodexDriver.NativeSortDirectionUnitInputTest do
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
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @instructions "Owned ordinary sort-direction unit fixture instructions."
  @needle "Owned unit-object direction λ🙂"
  @answer "Deterministic local fixture answer"
  @captured ~w(thread/start turn/start thread/list thread/search thread/turns/list thread/items/list thread/resume project/create project/move project/list)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @max_frame_bytes 4096

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      limit = Keyword.fetch!(opts, :capture_limit)
      transport_opts = Keyword.drop(opts, [:capture, :capture_limit])

      with {:ok, state} <- Stdio.open(transport_opts),
           do: {:ok, Map.merge(state, %{capture: capture, capture_limit: limit})}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ~w(thread/start turn/start thread/list thread/search thread/turns/list thread/items/list thread/resume project/create project/move project/list) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < state.capture_limit and
           byte_size(encoded) <= @max_frame_bytes do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [{encoded, wire}]))
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
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

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
      "model_messages" => %{"instructions_template" => @instructions}
    })

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> [] end})

    Map.merge(ctx, %{
      capture: capture,
      inputs: inputs,
      capture_limit: if(tags[:projects], do: 16, else: 48)
    })
  end

  test "direction unit objects select native list search turn item and resume order across restart",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    first = thread(ctx, warm)
    first_text = "first " <> @needle
    first_turn = turn(ctx, warm, first, first_text, 1)
    first_times = timestamps(ctx)
    assert Map.keys(first_times) == [first]
    await_clock(latest_timestamp(first_times), deadline(2_000))

    second = thread(ctx, warm)
    refute second == first
    second_text = "second " <> @needle
    second_turn = turn(ctx, warm, second, second_text, 2)
    before = timestamps(ctx)
    assert MapSet.new(Map.keys(before)) == MapSet.new([first, second])
    assert before[first]["created_at"] < before[second]["created_at"]
    await_clock(latest_timestamp(before), deadline(2_000))
    later_turn = turn(ctx, warm, first, "Owned direction continuation", 3)
    observed = timestamps(ctx)
    for id <- [first, second], do: assert(observed[id]["created_at"] == before[id]["created_at"])

    expected = %{first => [first_turn, later_turn], second => [second_turn]}
    assert length(Enum.uniq(Enum.map([first_turn, second_turn, later_turn], & &1.id))) == 3
    all_entries = first_turn.entries ++ second_turn.entries ++ later_turn.entries
    assert length(all_entries) == 6
    assert length(Enum.uniq(Enum.map(all_entries, & &1["item"]["id"]))) == 6
    assert length(first_turn.entries ++ later_turn.entries) == 4

    assert length(
             Enum.uniq(Enum.map(first_turn.entries ++ later_turn.entries, & &1["item"]["id"]))
           ) == 4

    saved = Map.new(expected, fn {id, turns} -> {id, saved_history(ctx, warm, id, turns)} end)
    snippets = %{first => first_text, second => second_text}
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))

    warm_reads = read_matrix(ctx, warm, first, observed, snippets, expected, saved, :warm)
    warm_resume = resume_matrix(ctx, warm, first, expected[first], saved[first])
    assert_retained(ctx, warm, observed, expected, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    # All sixteen cold content reads precede explicit resume and hydration.
    assert read_matrix(ctx, cold, first, observed, snippets, expected, saved, :cold) ===
             warm_reads

    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_inputs(retained)
    for {_id, source} <- saved, do: assert(snapshot(source.path) === source.snapshot)
    assert timestamps(ctx) === observed
    assert_functional_state(ctx, cold, 3)

    # Only the first explicit resume is a cold-load branch. The remaining three
    # exercise the same request path with an already loaded native runtime.
    {cold_resume, resumed_saved, resumed_times} =
      cold_resume_matrix(ctx, cold, first, expected[first], saved, observed)

    assert cold_resume === warm_resume

    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == [first]
    assert_retained(ctx, cold, resumed_times, expected, resumed_saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == [first]
    close(cold, cold_native)
    assert_inputs(retained)

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 45
    assert capture_count(captures, "thread/start") == 2
    assert capture_count(captures, "turn/start") == 3

    for method <- ~w(thread/list thread/search thread/turns/list thread/items/list thread/resume),
        do: assert(capture_count(captures, method) == 8)
  end

  @tag projects: true
  test "direction unit objects retain publicly prescribed project position order across restart",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    names = ["Owned direction project P", "Owned direction project Q"]

    projects =
      for {name, position} <- Enum.with_index(names) do
        project =
          call(ctx, warm, "project/create", %{
            "name" => name,
            "roots" => [],
            "metadata" => %{"label" => name},
            "idempotencyKey" => name
          })["project"]

        assert project["name"] == name
        assert project["metadata"] === %{"label" => name}
        assert project["roots"] == []
        assert project["position"] == position
        assert Map.fetch!(project, "recencyAt") == nil
        project
      end

    [first, second] = projects
    refute first["id"] == second["id"]

    assert call(ctx, warm, "project/move", %{
             "projectId" => second["id"],
             "beforeProjectId" => first["id"]
           }) == %{}

    expected_ids = [second["id"], first["id"]]
    ledger = read_projects(ctx, warm, expected_ids)
    stored = stored_projects(ctx)
    assert_project_storage(stored, names, expected_ids, ledger)
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))
    warm_pages = project_matrix(ctx, warm, expected_ids, ledger)
    assert_project_retained(ctx, warm, stored, ledger, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert project_matrix(ctx, cold, expected_ids, ledger) === warm_pages
    assert_project_retained(ctx, cold, stored, ledger, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 11
    assert capture_count(captures, "project/create") == 2
    assert capture_count(captures, "project/move") == 1
    assert capture_count(captures, "project/list") == 8
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp read_matrix(ctx, pid, first, observed, snippets, expected, saved, mode) do
    for {direction, object} <- direction_forms(),
        method <- ~w(thread/list thread/search thread/turns/list thread/items/list) do
      params = read_params(method, first, object)
      page = call(ctx, pid, method, params)
      assert Map.fetch!(page, "nextCursor") == nil

      case method do
        "thread/list" ->
          assert_thread_page(
            ctx,
            page,
            order(observed, "created_at", direction),
            observed,
            saved,
            nil,
            mode
          )

        "thread/search" ->
          assert_thread_page(
            ctx,
            page,
            order(observed, "created_at", direction),
            observed,
            saved,
            snippets,
            mode
          )

        "thread/turns/list" ->
          assert_turn_rows(page["data"], ordered(expected[first], direction))

        "thread/items/list" ->
          assert page["data"] === ordered(Enum.flat_map(expected[first], & &1.entries), direction)
      end

      if method in ["thread/turns/list", "thread/items/list"],
        do: assert(is_binary(Map.fetch!(page, "backwardsCursor")))

      assert_functional_state(ctx, pid, 3)
      {method, object, durable_page(page, method)}
    end
  end

  defp read_params(method, first, object) do
    case method do
      "thread/list" ->
        %{
          "sortKey" => "created_at",
          "useStateDbOnly" => true,
          "limit" => 100,
          "sortDirection" => object
        }

      "thread/search" ->
        %{
          "searchTerm" => @needle,
          "sortKey" => "created_at",
          "limit" => 100,
          "sortDirection" => object
        }

      "thread/turns/list" ->
        %{
          "threadId" => first,
          "itemsView" => "full",
          "limit" => 100,
          "sortDirection" => object
        }

      "thread/items/list" ->
        %{"threadId" => first, "limit" => 100, "sortDirection" => object}
    end
  end

  defp resume_matrix(ctx, pid, thread, expected, saved) do
    for form <- direction_forms(), do: resume_page(ctx, pid, thread, expected, saved, form)
  end

  defp cold_resume_matrix(ctx, pid, thread, expected, saved, observed) do
    [first | remaining] = direction_forms()
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] == []
    await_clock(latest_timestamp(observed), deadline(2_000))
    before_resume = System.system_time(:millisecond)
    assert before_resume > latest_timestamp(observed)
    first_page = resume_page(ctx, pid, thread, expected, saved[thread], first)
    after_resume = System.system_time(:millisecond)

    source = saved[thread]
    checkpoint = snapshot(source.path)
    stamped = assert_resume_checkpoint(ctx, thread, source.snapshot.bytes, checkpoint.bytes)
    assert stamped >= before_resume and stamped <= after_resume
    resumed_times = timestamps(ctx)
    updated = Map.fetch!(resumed_times[thread], "updated_at")
    assert updated > Map.fetch!(observed[thread], "updated_at")
    assert updated >= before_resume and updated >= stamped and updated <= after_resume
    restored_creation = original_creation_ms(source.snapshot.bytes, thread)

    expected_times =
      observed
      |> put_in([thread, "created_at"], restored_creation)
      |> put_in([thread, "updated_at"], updated)

    assert resumed_times === expected_times
    resumed_saved = put_in(saved, [thread, :snapshot], checkpoint)

    rest =
      for form <- remaining do
        page = resume_page(ctx, pid, thread, expected, source, form)
        assert call(ctx, pid, "thread/loaded/list", %{})["data"] == [thread]

        for {_id, retained} <- resumed_saved,
            do: assert(snapshot(retained.path) === retained.snapshot)

        assert timestamps(ctx) === resumed_times
        page
      end

    {[first_page | rest], resumed_saved, resumed_times}
  end

  defp resume_page(ctx, pid, thread, expected, saved, {direction, object}) do
    params = %{
      "threadId" => thread,
      "excludeTurns" => true,
      "initialTurnsPage" => %{"limit" => 100, "itemsView" => "full", "sortDirection" => object}
    }

    result = call(ctx, pid, "thread/resume", params)
    assert result["thread"]["id"] == thread
    assert result["thread"]["historyMode"] == "paginated"
    assert result["thread"]["path"] == saved.path
    assert result["thread"]["turns"] == []
    page = Map.fetch!(result, "initialTurnsPage")
    assert Map.fetch!(page, "nextCursor") == nil
    assert is_binary(Map.fetch!(page, "backwardsCursor"))
    assert_turn_rows(Map.fetch!(page, "data"), ordered(expected, direction))
    assert_functional_state(ctx, pid, 3)
    {object, page}
  end

  defp assert_thread_page(ctx, page, expected, observed, saved, snippets, mode) do
    threads = if snippets, do: Enum.map(page["data"], & &1["thread"]), else: page["data"]
    assert Enum.map(threads, & &1["id"]) == expected

    for thread <- threads do
      id = Map.fetch!(thread, "id")
      assert_runtime_projection(ctx, thread, mode)
      assert Map.fetch!(thread, "historyMode") == "paginated"
      assert Map.fetch!(thread, "turns") == []
      assert Map.fetch!(thread, "cwd") == ctx.fixture.workspace
      assert Map.fetch!(thread, "modelProvider") == "fixture"
      assert Map.fetch!(thread, "path") == saved[id].path
      assert Map.fetch!(thread, "preview") == saved[id].preview

      for {field, raw} <- [
            {"createdAt", "created_at"},
            {"updatedAt", "updated_at"},
            {"recencyAt", "recency_at"}
          ],
          do: assert(Map.fetch!(thread, field) == div(Map.fetch!(observed[id], raw), 1_000))
    end

    if snippets do
      for row <- page["data"],
          do: assert(Map.fetch!(row, "snippet") == snippets[row["thread"]["id"]])
    end
  end

  defp assert_runtime_projection(ctx, thread, :warm) do
    assert Map.fetch!(thread, "status") === %{"type" => "idle"}

    assert Map.fetch!(thread, "environments") === [
             %{
               "environmentId" => "local",
               "cwd" => ctx.fixture.workspace,
               "runtimeWorkspaceRoots" => [ctx.fixture.workspace]
             }
           ]
  end

  defp assert_runtime_projection(_ctx, thread, :cold) do
    assert Map.fetch!(thread, "status") === %{"type" => "notLoaded"}
    assert Map.fetch!(thread, "environments") === nil
  end

  # Runtime projections above are checked independently for both process states.
  # Every other page field must survive the owned process replacement exactly.
  defp durable_page(page, "thread/list"),
    do:
      Map.update!(
        page,
        "data",
        &Enum.map(&1, fn row -> Map.drop(row, ["status", "environments"]) end)
      )

  defp durable_page(page, "thread/search"),
    do:
      Map.update!(
        page,
        "data",
        &Enum.map(&1, fn row ->
          Map.update!(row, "thread", fn thread -> Map.drop(thread, ["status", "environments"]) end)
        end)
      )

  defp durable_page(page, _method), do: page

  defp assert_turn_rows(actual, expected) do
    assert Enum.map(actual, & &1["id"]) == Enum.map(expected, & &1.id)

    for {turn, wanted} <- Enum.zip(actual, expected) do
      assert Map.fetch!(turn, "id") == wanted.id
      assert Map.fetch!(turn, "status") == "completed"
      assert Map.fetch!(turn, "error") == nil
      assert Map.fetch!(turn, "itemsView") == "full"
      assert Map.fetch!(turn, "items") === Enum.map(wanted.entries, & &1["item"])
      assert Enum.map(turn["items"], & &1["type"]) == ["userMessage", "agentMessage"]
      [user, agent] = turn["items"]

      assert user["content"] == [
               %{"type" => "text", "text" => wanted.text, "text_elements" => []}
             ]

      assert agent["text"] == @answer
    end
  end

  defp direction_forms do
    for direction <- ["asc", "desc"],
        payload <- [nil, %{}],
        do: {direction, %{direction => payload}}
  end

  defp ordered(rows, "asc"), do: rows
  defp ordered(rows, "desc"), do: Enum.reverse(rows)

  defp capture_count(captures, method),
    do: Enum.count(captures, fn {_bytes, wire} -> wire["method"] == method end)

  defp project_matrix(ctx, pid, ascending, ledger) do
    for {direction, object} <- direction_forms() do
      params = %{"sortKey" => "position", "sortDirection" => object, "limit" => 100}
      page = call(ctx, pid, "project/list", params)

      assert page === %{
               "data" => Enum.map(ordered(ascending, direction), &Map.fetch!(ledger, &1)),
               "nextCursor" => nil
             }

      assert_functional_state(ctx, pid, 0)
      {object, page}
    end
  end

  defp read_projects(ctx, pid, ids),
    do: Map.new(ids, &{&1, call(ctx, pid, "project/read", %{"projectId" => &1})["project"]})

  defp assert_project_storage(stored, names, ordered_ids, ledger) do
    assert Map.fetch!(stored, "thread_count") == 0
    assert Map.fetch!(stored, "roots") == []
    assert map_size(stored["projects"]) == 2
    assert stored["keys"] === Map.new(Enum.zip(names, Enum.reverse(ordered_ids)))

    for {id, index} <- Enum.with_index(ordered_ids) do
      row = Map.fetch!(stored["projects"], id)
      project = Map.fetch!(ledger, id)
      assert row["id"] == id
      assert row["position"] == index
      assert project["position"] == index
      assert project["id"] == id
      assert project["name"] == row["name"]
      assert project["metadata"] === %{"label" => project["name"]}
      assert JSON.decode!(row["metadata"]) === project["metadata"]
      assert project["roots"] == []
      assert Map.fetch!(project, "recencyAt") == nil
      assert project["createdAt"] == div(row["created_at_ms"], 1000)
      assert project["updatedAt"] == div(row["updated_at_ms"], 1000)
    end
  end

  defp assert_project_retained(ctx, pid, stored, ledger, inputs) do
    assert_inputs(inputs)
    assert stored_projects(ctx) === stored
    assert read_projects(ctx, pid, Map.keys(ledger)) === ledger
    assert File.ls!(ctx.fixture.workspace) == []
    assert_functional_state(ctx, pid, 0)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(inputs)
  end

  defp stored_projects(ctx) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
    assert File.lstat!(path).type == :regular

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        connection.row_factory = sqlite3.Row
        projects = {row['id']: dict(row) for row in connection.execute(
            'SELECT * FROM projects ORDER BY id LIMIT 3')}
        keys = dict(connection.execute(
            'SELECT key, project_id FROM project_idempotency_keys ORDER BY key LIMIT 3'))
        roots = [list(row) for row in connection.execute(
            'SELECT project_id, position, path FROM project_roots ORDER BY project_id, position LIMIT 3')]
        thread_count = connection.execute('SELECT COUNT(*) FROM threads').fetchone()[0]
    print(json.dumps({'projects': projects, 'keys': keys, 'roots': roots, 'thread_count': thread_count}))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned read-only direction project observation failed: #{output}"
    assert byte_size(output) <= 16_384
    JSON.decode!(String.trim(output))
  end

  defp assert_functional_state(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp thread(ctx, pid) do
    result =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    id = result["thread"]["id"]
    assert is_binary(id) and byte_size(id) > 0
    id
  end

  defp turn(ctx, pid, thread, text, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count - 1

    id =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

    assert is_binary(id) and byte_size(id) > 0
    events = complete_turn(pid, thread, id, [], deadline(20_000))

    assert Enum.any?(events, fn event ->
             event.wire["method"] == "item/completed" and
               event.wire["params"]["threadId"] == thread and
               event.wire["params"]["turnId"] == id and
               event.wire["params"]["item"]["type"] == "agentMessage" and
               event.wire["params"]["item"]["text"] == @answer
           end)

    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    request = List.last(requests)
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^id} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    texts =
      for item <- request["input"],
          item["role"] == "user",
          part <- item["content"],
          part["type"] == "input_text",
          do: part["text"]

    assert Enum.count(texts, &(&1 == text)) == 1

    # Completion delivery is not a disk barrier; synchronously read native
    # full history before observing the persisted SQLite timestamp oracle.
    saved = read(ctx, pid, thread)
    assert Enum.any?(saved["turns"], &(&1["id"] == id and &1["status"] == "completed"))
    entries = completed_entries(events, thread, id)

    %{id: id, text: text, entries: entries}
  end

  defp completed_entries(events, thread, id) do
    completed = item_events(events, "item/completed")
    assert Enum.map(completed, & &1["item"]["type"]) == ["userMessage", "agentMessage"]

    entries =
      for event <- completed do
        item = Map.fetch!(event, "item")
        assert is_binary(item["id"]) and byte_size(item["id"]) > 0
        assert event["threadId"] == thread
        assert event["turnId"] == id

        assert [began] =
                 Enum.filter(
                   item_events(events, "item/started"),
                   &(&1["item"]["id"] == item["id"])
                 )

        assert began["threadId"] == thread
        assert began["turnId"] == id
        started = Map.fetch!(began, "startedAtMs")
        ended = Map.fetch!(event, "completedAtMs")
        assert is_integer(started) and started > 0
        assert is_integer(ended) and ended >= started
        %{"turnId" => id, "item" => item, "startedAtMs" => started, "completedAtMs" => ended}
      end

    entries
  end

  defp item_events(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    completed =
      Enum.find(events, fn event ->
        event.wire["method"] == "turn/completed" and
          event.wire["params"]["threadId"] == thread and
          event.wire["params"]["turn"]["id"] == turn
      end)

    if completed do
      assert completed.wire["params"]["turn"]["status"] == "completed"
      events
    else
      assert System.monotonic_time(:millisecond) < until,
             "native sort-direction unit turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected sort-direction unit event gap")
      after
        10 -> :ok
      end

      complete_turn(pid, thread, turn, events, until)
    end
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp saved_history(ctx, pid, id, expected) do
    saved = read(ctx, pid, id)
    assert_history(saved, id, expected)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    %{
      path: path,
      snapshot: snapshot(path),
      turns: saved["turns"],
      preview: Map.fetch!(saved, "preview")
    }
  end

  defp assert_history(saved, id, expected) do
    assert Map.fetch!(saved, "id") == id
    assert Map.fetch!(saved, "historyMode") == "paginated"
    assert_turn_rows(Map.fetch!(saved, "turns"), expected)
  end

  defp assert_retained(ctx, pid, observed, expected, saved, inputs) do
    assert_inputs(inputs)
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    for {id, source} <- saved do
      retained = snapshot(source.path)

      assert retained === source.snapshot

      native = read(ctx, pid, id)
      assert_history(native, id, Map.fetch!(expected, id))
      assert Map.fetch!(native, "path") == source.path
      assert Map.fetch!(native, "turns") === source.turns
      assert Map.fetch!(native, "preview") == source.preview
      assert snapshot(source.path) === retained
    end

    assert timestamps(ctx) === observed
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(inputs)
  end

  # Cold resume restores creation time from the original session metadata,
  # independently sampled after the first SQLite creation timestamp.
  defp original_creation_ms(original, thread) do
    records = original |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert [metadata] = Enum.filter(records, &(Map.fetch!(&1, "type") == "session_meta"))
    assert hd(records) === metadata
    payload = Map.fetch!(metadata, "payload")
    assert Map.fetch!(payload, "id") == thread
    assert {:ok, created, 0} = DateTime.from_iso8601(Map.fetch!(payload, "timestamp"))
    DateTime.to_unix(created, :millisecond)
  end

  # Successful cold resume persists this checkpoint before returning.
  defp assert_resume_checkpoint(ctx, thread, original, actual) do
    assert String.starts_with?(actual, original)
    suffix = binary_part(actual, byte_size(original), byte_size(actual) - byte_size(original))
    assert byte_size(suffix) <= 4096
    assert [line, ""] = String.split(suffix, "\n")
    entry = JSON.decode!(line)
    previous = original |> String.split("\n", trim: true) |> List.last() |> JSON.decode!()
    assert Map.fetch!(entry, "ordinal") == Map.fetch!(previous, "ordinal") + 1
    assert Map.fetch!(entry, "type") == "event_msg"
    payload = Map.fetch!(entry, "payload")
    assert Map.fetch!(payload, "type") == "thread_settings_applied"
    assert Map.fetch!(payload, "thread_id") == thread
    settings = Map.fetch!(payload, "thread_settings")

    assert Map.take(settings, ~w(model model_provider_id cwd runtime_workspace_roots)) === %{
             "model" => "mock-model",
             "model_provider_id" => "fixture",
             "cwd" => ctx.fixture.workspace,
             "runtime_workspace_roots" => [ctx.fixture.workspace]
           }

    assert {:ok, stamped, 0} = DateTime.from_iso8601(Map.fetch!(entry, "timestamp"))
    assert {:ok, earlier, 0} = DateTime.from_iso8601(Map.fetch!(previous, "timestamp"))
    assert DateTime.compare(stamped, earlier) in [:eq, :gt]
    DateTime.to_unix(stamped, :millisecond)
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp timestamps(ctx) do
    path = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.root) <> "/")
    assert File.lstat!(path).type == :regular

    script = """
    import json, pathlib, sqlite3, sys
    database = pathlib.Path(sys.argv[1]).resolve().as_uri() + '?mode=ro'
    with sqlite3.connect(database, uri=True, timeout=1) as connection:
        connection.execute('PRAGMA query_only = ON')
        rows = connection.execute(
            'SELECT id, created_at_ms, updated_at_ms, recency_at_ms FROM threads'
        ).fetchall()
        print(json.dumps({
            row[0]: dict(zip(('created_at', 'updated_at', 'recency_at'), row[1:]))
            for row in rows
        }))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned read-only sort-direction timestamp observation failed: #{output}"
    assert byte_size(output) <= 4096
    result = JSON.decode!(String.trim(output))
    assert map_size(result) in 1..2

    assert Enum.all?(result, fn {id, row} ->
             is_binary(id) and
               Enum.sort(Map.keys(row)) == ["created_at", "recency_at", "updated_at"] and
               Enum.all?(Map.values(row), &is_integer/1)
           end)

    result
  end

  defp order(timestamps, key, direction) do
    ordered =
      timestamps
      |> Enum.sort_by(fn {id, row} -> {Map.fetch!(row, key), id} end)
      |> Enum.map(&elem(&1, 0))

    if direction == "asc", do: ordered, else: Enum.reverse(ordered)
  end

  defp latest_timestamp(timestamps),
    do: timestamps |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.max()

  defp await_clock(timestamp, until) do
    cond do
      System.system_time(:millisecond) > timestamp ->
        :ok

      System.monotonic_time(:millisecond) >= until ->
        flunk("Owned sort-direction unit fixture clock did not advance")

      true ->
        receive do
        after
          1 -> await_clock(timestamp, until)
        end
    end
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-sort-direction-unit-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
      assert_direction_object(bytes, method, params)
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

  defp assert_direction_object(bytes, method, params)
       when method in [
              "thread/list",
              "thread/search",
              "thread/turns/list",
              "thread/items/list",
              "thread/resume",
              "project/list"
            ] do
    object =
      if method == "thread/resume",
        do: get_in(params, ["initialTurnsPage", "sortDirection"]),
        else: Map.fetch!(params, "sortDirection")

    assert is_map(object) and map_size(object) == 1
    assert :binary.match(bytes, JSON.encode!(object)) != :nomatch
  end

  defp assert_direction_object(_bytes, _method, _params), do: :ok

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             capture_limit: ctx.capture_limit,
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
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_sort_direction_unit_input", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
