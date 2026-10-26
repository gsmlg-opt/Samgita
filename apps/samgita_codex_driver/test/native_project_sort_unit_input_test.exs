defmodule SamgitaCodexDriver.NativeProjectSortUnitInputTest do
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
  @instructions "Owned ordinary project-sort unit fixture instructions."
  @answer "Deterministic local fixture answer"
  @captured ~w(thread/start turn/start project/create project/move project/list)

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

      if wire["method"] in ~w(thread/start turn/start project/create project/move project/list) do
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
    Map.merge(ctx, %{capture: capture, inputs: inputs, capture_limit: 48})
  end

  test "project key unit objects select independent position recency and default order across cold reads",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    projects = create_projects(ctx, warm)
    [empty_first, older, empty_second, newer] = projects

    assert call(ctx, warm, "project/move", %{
             "projectId" => newer["id"],
             "beforeProjectId" => empty_first["id"]
           }) == %{}

    position_asc = Enum.map([newer, empty_first, older, empty_second], & &1["id"])
    assert ModelFixture.requests(ctx.fixture) == []

    first_thread = thread(ctx, warm, older["id"])
    first_turn = turn(ctx, warm, first_thread, "Owned project-key older λ🙂", 1)
    first_stored = stored_projects(ctx)
    first_recency = Map.fetch!(first_stored["recencies"], older["id"])
    assert is_integer(first_recency)
    assert Map.fetch!(first_stored["recencies"], newer["id"]) == nil
    await_clock(first_recency, deadline(2_000))

    second_thread = thread(ctx, warm, newer["id"])
    refute second_thread == first_thread
    second_turn = turn(ctx, warm, second_thread, "Owned project-key newer λ🙂", 2)
    refute second_turn.id == first_turn.id
    entries = first_turn.entries ++ second_turn.entries
    assert length(entries) == 4
    assert length(Enum.uniq(Enum.map(entries, & &1["item"]["id"]))) == 4

    stored = stored_projects(ctx)
    recencies = Map.fetch!(stored, "recencies")
    assert Map.fetch!(recencies, older["id"]) == first_recency
    assert Map.fetch!(recencies, newer["id"]) > first_recency

    for project <- [empty_first, empty_second],
        do: assert(Map.fetch!(recencies, project["id"]) == nil)

    recency_asc = recency_order(recencies, :asc)
    recency_desc = recency_order(recencies, :desc)
    assert Enum.take(recency_asc, 2) == [older["id"], newer["id"]]
    assert Enum.take(recency_desc, 2) == [newer["id"], older["id"]]
    assert Enum.drop(recency_asc, 2) == Enum.sort([empty_first["id"], empty_second["id"]])
    assert Enum.drop(recency_desc, 2) == Enum.sort([empty_first["id"], empty_second["id"]], :desc)
    refute recency_asc == position_asc
    refute recency_desc == Enum.reverse(position_asc)

    orders = %{
      {"position", "asc"} => position_asc,
      {"position", "desc"} => Enum.reverse(position_asc),
      {"recencyAt", "asc"} => recency_asc,
      {"recencyAt", "desc"} => recency_desc
    }

    ledger = read_projects(ctx, warm, position_asc)

    assert_project_storage(stored, projects, position_asc, ledger, %{
      first_thread => older["id"],
      second_thread => newer["id"]
    })

    expected = %{first_thread => [first_turn], second_thread => [second_turn]}
    saved = Map.new(expected, fn {id, turns} -> {id, saved_history(ctx, warm, id, turns)} end)
    assert read(ctx, warm, first_thread)["projectId"] == older["id"]
    assert read(ctx, warm, second_thread)["projectId"] == newer["id"]
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))
    warm_pages = matrix(ctx, warm, orders, ledger)
    assert_retained(ctx, warm, stored, ledger, expected, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    # All sixteen selected cold queries precede history hydration. No resume is
    # issued; project facts do not require loading either execution runtime.
    assert matrix(ctx, cold, orders, ledger) === warm_pages
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_inputs(retained)
    for {_id, source} <- saved, do: assert(snapshot(source.path) === source.snapshot)
    assert stored_projects(ctx) === stored
    assert_functional_state(ctx, cold)
    assert_retained(ctx, cold, stored, ledger, expected, saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 41
    assert capture_count(captures, "project/create") == 4
    assert capture_count(captures, "project/move") == 1
    assert capture_count(captures, "thread/start") == 2
    assert capture_count(captures, "turn/start") == 2
    assert capture_count(captures, "project/list") == 32
    assert length(ModelFixture.requests(ctx.fixture)) == 2
  end

  defp create_projects(ctx, pid) do
    names = [
      "Owned project-key P empty",
      "Owned project-key Q older",
      "Owned project-key R empty",
      "Owned project-key S newer"
    ]

    projects =
      for {name, position} <- Enum.with_index(names) do
        project =
          call(ctx, pid, "project/create", %{
            "name" => name,
            "roots" => [],
            "metadata" => %{"label" => name},
            "idempotencyKey" => name
          })["project"]

        assert is_binary(project["id"]) and byte_size(project["id"]) > 0
        assert project["name"] == name
        assert project["metadata"] === %{"label" => name}
        assert project["roots"] == []
        assert project["position"] == position
        assert Map.fetch!(project, "recencyAt") == nil
        project
      end

    assert length(Enum.uniq(Enum.map(projects, & &1["id"]))) == 4
    projects
  end

  defp matrix(ctx, pid, orders, ledger) do
    for {key, object} <- key_forms(),
        direction_fields <- [
          %{},
          %{"sortDirection" => nil},
          %{"sortDirection" => "asc"},
          %{"sortDirection" => "desc"}
        ] do
      direction =
        direction_fields["sortDirection"] || if(key == "position", do: "asc", else: "desc")

      params = Map.merge(%{"sortKey" => object, "limit" => 100}, direction_fields)
      page = call(ctx, pid, "project/list", params)
      expected = Enum.map(Map.fetch!(orders, {key, direction}), &Map.fetch!(ledger, &1))
      assert page === %{"data" => expected, "nextCursor" => nil}
      assert_functional_state(ctx, pid)
      {object, direction_fields, page}
    end
  end

  defp key_forms do
    for key <- ["position", "recencyAt"], payload <- [nil, %{}], do: {key, %{key => payload}}
  end

  defp recency_order(times, direction) do
    {empty, active} = Enum.split_with(times, fn {_id, value} -> is_nil(value) end)
    active = Enum.sort_by(active, fn {id, value} -> {value, id} end, direction)
    empty = Enum.sort_by(empty, &elem(&1, 0), direction)
    Enum.map(active ++ empty, &elem(&1, 0))
  end

  defp read_projects(ctx, pid, ids),
    do: Map.new(ids, &{&1, call(ctx, pid, "project/read", %{"projectId" => &1})["project"]})

  defp assert_project_storage(stored, created, position_asc, ledger, thread_projects) do
    assert map_size(Map.fetch!(stored, "projects")) == 4
    assert Map.fetch!(stored, "roots") == []
    assert Map.fetch!(stored, "keys") === Map.new(created, &{&1["name"], &1["id"]})
    assert map_size(Map.fetch!(stored, "threads")) == 2

    assert Map.new(stored["threads"], fn {id, row} -> {id, row["project_id"]} end) ===
             thread_projects

    for {id, position} <- Enum.with_index(position_asc) do
      row = Map.fetch!(stored["projects"], id)
      recency = Map.fetch!(stored["recencies"], id)
      assert row["id"] == id
      assert row["position"] == position
      assert is_integer(row["created_at_ms"]) and is_integer(row["updated_at_ms"])

      assert Map.fetch!(ledger, id) === %{
               "id" => id,
               "name" => row["name"],
               "metadata" => JSON.decode!(row["metadata"]),
               "position" => position,
               "roots" => [],
               "createdAt" => div(row["created_at_ms"], 1_000),
               "updatedAt" => div(row["updated_at_ms"], 1_000),
               "recencyAt" => if(is_nil(recency), do: nil, else: div(recency, 1_000))
             }

      assert ledger[id]["metadata"] === %{"label" => ledger[id]["name"]}
    end

    for {_id, row} <- stored["threads"] do
      assert row["archived"] == 0
      assert is_integer(row["created_at_ms"])
      assert is_integer(row["updated_at_ms"])
      assert is_integer(row["recency_at_ms"])
    end
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
            'SELECT * FROM projects ORDER BY id LIMIT 5')}
        keys = dict(connection.execute(
            'SELECT key, project_id FROM project_idempotency_keys ORDER BY key LIMIT 5'))
        roots = [list(row) for row in connection.execute(
            'SELECT project_id, position, path FROM project_roots ORDER BY project_id, position LIMIT 5')]
        threads = {row['id']: dict(row) for row in connection.execute('''
            SELECT id, project_id, created_at_ms, updated_at_ms, recency_at_ms, archived
            FROM threads ORDER BY id LIMIT 3''')}
        recencies = dict(connection.execute('''
            SELECT p.id, MAX(t.recency_at_ms) FROM projects p
            LEFT JOIN threads t ON t.project_id = p.id AND t.archived = 0
            GROUP BY p.id ORDER BY p.id LIMIT 5'''))
    print(json.dumps({'projects': projects, 'keys': keys, 'roots': roots,
                     'threads': threads, 'recencies': recencies}))
    """

    {output, status} = System.cmd("python3", ["-B", "-c", script, path], stderr_to_stdout: true)
    assert status == 0, "owned read-only project-key observation failed: #{output}"
    assert byte_size(output) <= 16_384
    JSON.decode!(String.trim(output))
  end

  defp assert_functional_state(ctx, pid) do
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp capture_count(captures, method),
    do: Enum.count(captures, fn {_bytes, wire} -> wire["method"] == method end)

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

  defp thread(ctx, pid, project) do
    result =
      call(ctx, pid, "thread/start", %{
        "projectId" => project,
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
             "native project-sort unit turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected project-sort unit event gap")
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

  defp assert_retained(ctx, pid, stored, ledger, expected, saved, inputs) do
    assert_inputs(inputs)
    assert stored_projects(ctx) === stored
    assert read_projects(ctx, pid, Map.keys(ledger)) === ledger

    for {id, source} <- saved do
      assert snapshot(source.path) === source.snapshot
      native = read(ctx, pid, id)
      assert_history(native, id, Map.fetch!(expected, id))
      assert native["path"] == source.path
      assert native["turns"] === source.turns
      assert native["preview"] == source.preview
      assert native["projectId"] == stored["threads"][id]["project_id"]
      assert snapshot(source.path) === source.snapshot
    end

    assert stored_projects(ctx) === stored
    assert File.ls!(ctx.fixture.workspace) == []
    assert_functional_state(ctx, pid)
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(inputs)
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp await_clock(timestamp, until) do
    cond do
      System.system_time(:millisecond) > timestamp ->
        :ok

      System.monotonic_time(:millisecond) >= until ->
        flunk("Owned project-sort unit fixture clock did not advance")

      true ->
        receive do
        after
          1 -> await_clock(timestamp, until)
        end
    end
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-project-sort-unit-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
      assert_key_object(bytes, method, params)
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

  defp assert_key_object(bytes, "project/list", params) do
    object = Map.fetch!(params, "sortKey")
    assert is_map(object) and map_size(object) == 1
    assert :binary.match(bytes, JSON.encode!(object)) != :nomatch
  end

  defp assert_key_object(_bytes, _method, _params), do: :ok

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
               %{"name" => "owned_project_sort_unit_input", "version" => "0.1.0"},
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
