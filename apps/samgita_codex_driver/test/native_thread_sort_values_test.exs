defmodule SamgitaCodexDriver.NativeThreadSortValuesTest do
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
  @instructions "Owned ordinary thread-sort fixture instructions."
  @needle "Owned explicit timestamp sort λ🙂"
  @answer "Deterministic local fixture answer"
  @captured ~w(thread/start turn/start thread/list thread/search)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ~w(thread/start turn/start thread/list thread/search) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 64 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
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
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "explicit native search and list timestamp sorts retain independent orders and cold pages",
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
    second_text = "second " <> @needle
    second_turn = turn(ctx, warm, second, second_text, 2)
    before = timestamps(ctx)
    assert MapSet.new(Map.keys(before)) == MapSet.new([first, second])
    assert before[first]["created_at"] < before[second]["created_at"]
    await_clock(latest_timestamp(before), deadline(2_000))

    continuation = "Owned first-thread timestamp continuation"
    later_turn = turn(ctx, warm, first, continuation, 3)
    observed = timestamps(ctx)

    for id <- [first, second] do
      assert observed[id]["created_at"] == before[id]["created_at"]
    end

    for key <- ["updated_at", "recency_at"] do
      assert observed[first][key] > before[first][key]
      assert observed[first][key] > observed[second][key]
      assert order(observed, key, "desc") == [first, second]
      refute order(observed, key, "desc") == order(observed, "created_at", "desc")
    end

    # Both native clocks may move together. This fixture detects a key ignored
    # in favor of created_at, not an updated_at/recency_at swap in every case.
    expected = %{
      first => [{first_turn, first_text}, {later_turn, continuation}],
      second => [{second_turn, second_text}]
    }

    saved = Map.new(expected, fn {id, turns} -> {id, saved_history(ctx, warm, id, turns)} end)
    snippets = %{first => first_text, second => second_text}
    journal = snapshot(ctx.fixture.requests)
    retained = Map.put(ctx.inputs, ctx.fixture.requests, journal)
    warm_pages = matrix(ctx, warm, observed, snippets, saved)
    assert_retained(ctx, warm, observed, expected, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []

    # First content queries in the replacement process are sort/page reads,
    # before full-history hydration or resume. All threads remain unloaded.
    assert matrix(ctx, cold, observed, snippets, saved) === warm_pages
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, observed, expected, saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 45
    assert Enum.count(captures, &(&1["method"] == "thread/start")) == 2
    assert Enum.count(captures, &(&1["method"] == "turn/start")) == 3
    assert Enum.count(captures, &(&1["method"] == "thread/list")) == 24
    assert Enum.count(captures, &(&1["method"] == "thread/search")) == 16
  end

  defp matrix(ctx, pid, observed, snippets, saved) do
    for {method, keys} <- [
          {"thread/list", ["updated_at", "recency_at"]},
          {"thread/search", ["created_at", "updated_at"]}
        ],
        key <- keys,
        direction <- ["asc", "desc"] do
      expected = order(observed, key, direction)

      params =
        if method == "thread/list",
          do: %{"useStateDbOnly" => true},
          else: %{"searchTerm" => @needle}

      params =
        Map.merge(params, %{"sortKey" => key, "sortDirection" => direction, "limit" => 100})

      full = call(ctx, pid, method, params)
      assert_page(ctx, method, full, expected, observed, snippets, saved)
      assert Map.fetch!(full, "nextCursor") == nil
      first_params = Map.put(params, "limit", 1)
      first = call(ctx, pid, method, first_params)
      assert_page(ctx, method, first, Enum.take(expected, 1), observed, snippets, saved)
      cursor = Map.fetch!(first, "nextCursor")
      assert is_binary(cursor) and byte_size(cursor) > 0 and byte_size(cursor) <= 256

      if method == "thread/list" do
        second_params = Map.put(first_params, "cursor", cursor)
        second = call(ctx, pid, method, second_params)
        assert_page(ctx, method, second, Enum.drop(expected, 1), observed, snippets, saved)
        assert Map.fetch!(second, "nextCursor") == nil
        {method, key, direction, cursor, ids(method, second)}
      else
        # Created search pagination loses fractional precision in pinned
        # recorder.rs:2170. This unit qualifies only full/first search pages;
        # it makes no valid created continuation or reverse-page claim.
        {method, key, direction, cursor, ids(method, first)}
      end
    end
  end

  defp assert_page(ctx, method, page, expected, observed, snippets, saved) do
    assert ids(method, page) == expected

    for row <- Map.fetch!(page, "data") do
      thread = if method == "thread/search", do: Map.fetch!(row, "thread"), else: row
      id = Map.fetch!(thread, "id")
      assert Map.fetch!(thread, "historyMode") == "paginated"
      assert Map.fetch!(thread, "turns") == []
      assert Map.fetch!(thread, "cwd") == ctx.fixture.workspace
      assert Map.fetch!(thread, "modelProvider") == "fixture"
      assert Map.fetch!(thread, "path") == saved[id].path

      for {field, raw} <- [
            {"createdAt", "created_at"},
            {"updatedAt", "updated_at"},
            {"recencyAt", "recency_at"}
          ] do
        assert Map.fetch!(thread, field) == div(Map.fetch!(observed[id], raw), 1_000)
      end

      if method == "thread/search", do: assert(Map.fetch!(row, "snippet") == snippets[id])
    end
  end

  defp ids("thread/search", page), do: Enum.map(Map.fetch!(page, "data"), & &1["thread"]["id"])
  defp ids("thread/list", page), do: Enum.map(Map.fetch!(page, "data"), & &1["id"])

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
    id
  end

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
      assert System.monotonic_time(:millisecond) < until, "native ordinary sort turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected ordinary sort event gap")
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
    %{path: path, snapshot: snapshot(path), turns: saved["turns"]}
  end

  defp assert_history(saved, id, expected) do
    assert Map.fetch!(saved, "id") == id
    assert Map.fetch!(saved, "historyMode") == "paginated"
    assert Enum.map(saved["turns"], & &1["id"]) == Enum.map(expected, &elem(&1, 0))

    for {turn, {expected_id, text}} <- Enum.zip(saved["turns"], expected) do
      assert Map.fetch!(turn, "id") == expected_id
      assert Map.fetch!(turn, "status") == "completed"
      assert Map.fetch!(turn, "error") == nil
      users = Enum.filter(turn["items"], &(&1["type"] == "userMessage"))
      assert [user] = users

      assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) == [
               %{"type" => "text", "text" => text}
             ]

      assert [%{"text" => @answer}] = Enum.filter(turn["items"], &(&1["type"] == "agentMessage"))
    end
  end

  defp assert_retained(ctx, pid, observed, expected, saved, inputs) do
    assert_inputs(inputs)
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    for {id, source} <- saved do
      assert snapshot(source.path) === source.snapshot
      native = read(ctx, pid, id)
      assert_history(native, id, Map.fetch!(expected, id))
      assert Map.fetch!(native, "path") == source.path
      assert Map.fetch!(native, "turns") === source.turns
      assert snapshot(source.path) === source.snapshot
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
    assert status == 0, "owned read-only sort timestamp observation failed: #{output}"
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
        flunk("Owned ordinary sort fixture clock did not advance")

      true ->
        receive do
        after
          1 -> await_clock(timestamp, until)
        end
    end
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-thread-sort-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [actual] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

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
               %{"name" => "owned_thread_sort_values", "version" => "0.1.0"},
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
