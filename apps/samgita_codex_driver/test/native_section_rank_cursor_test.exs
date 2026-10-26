defmodule SamgitaCodexDriver.NativeSectionRankCursorTest do
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
  @instructions "Owned ordinary section-rank cursor fixture instructions."
  @answer "Deterministic local fixture answer"
  @captured ~w(thread/start turn/start threadSection/create thread/section/move thread/list)

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

      if wire["method"] in ~w(thread/start turn/start threadSection/create thread/section/move thread/list) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 40 and byte_size(encoded) <= 4096 do
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

    Map.merge(ctx, %{capture: start_supervised!({Agent, fn -> [] end}), inputs: inputs})
  end

  test "native integer-rank backwards cursor includes its anchor across warm and cold pages",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)

    histories =
      for label <- ["first", "second", "third"] do
        thread = thread(ctx, warm)
        text = "Owned section-rank #{label} history λ🙂"
        turn = turn(ctx, warm, thread, text)
        {thread, turn, text}
      end

    [{first, _, _}, {second, _, _}, {third, _, _}] = histories
    assert length(Enum.uniq([first, second, third])) == 3
    section = section(ctx, warm)
    for id <- [first, second, third], do: move(ctx, warm, id, section)
    move(ctx, warm, third, section, first)
    move(ctx, warm, first, section)

    # Independent public move semantics establish rank order. No cursor parsing,
    # storage edits, timestamp timing or equality-only ordering oracle is used.
    ordered = [third, second, first]
    saved = Map.new(histories, &save(ctx, warm, &1, section))
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))
    warm_pages = matrix(ctx, warm, ordered, section, saved)
    assert_retained(ctx, warm, histories, section, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []

    # First cold content queries are page reads, before read/resume hydration.
    assert matrix(ctx, cold, ordered, section, saved) === warm_pages
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, histories, section, saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)

    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 32

    for {method, count} <- [
          {"thread/start", 3},
          {"turn/start", 3},
          {"threadSection/create", 1},
          {"thread/section/move", 5},
          {"thread/list", 20}
        ] do
      assert Enum.count(frames, fn {_bytes, wire} -> wire["method"] == method end) == count
    end
  end

  defp matrix(ctx, pid, ordered, section, saved) do
    for direction <- ["asc", "desc"] do
      expected = if direction == "asc", do: ordered, else: Enum.reverse(ordered)
      opposite = if direction == "asc", do: "desc", else: "asc"
      first = page(ctx, pid, direction, section, nil, Enum.at(expected, 0), saved)

      second =
        page(
          ctx,
          pid,
          direction,
          section,
          cursor(first, "nextCursor"),
          Enum.at(expected, 1),
          saved
        )

      third =
        page(
          ctx,
          pid,
          direction,
          section,
          cursor(second, "nextCursor"),
          Enum.at(expected, 2),
          saved
        )

      assert Map.fetch!(third, "nextCursor") == nil

      # The original middle-page backwardsCursor goes unchanged to the native
      # opposite-direction consumer. Its first row must INCLUDE that anchor.
      reverse =
        page(
          ctx,
          pid,
          opposite,
          section,
          cursor(second, "backwardsCursor"),
          Enum.at(expected, 1),
          saved
        )

      previous =
        page(
          ctx,
          pid,
          opposite,
          section,
          cursor(reverse, "nextCursor"),
          Enum.at(expected, 0),
          saved
        )

      assert Map.fetch!(previous, "nextCursor") == nil
      assert length(ModelFixture.requests(ctx.fixture)) == 3
      {direction, Enum.map([first, second, third, reverse, previous], &stable_page/1)}
    end
  end

  defp page(ctx, pid, direction, section, cursor, expected, saved) do
    params = %{
      "sectionId" => section["id"],
      "sortKey" => "section_position",
      "sortDirection" => direction,
      "limit" => 1
    }

    params = if cursor == nil, do: params, else: Map.put(params, "cursor", cursor)
    page = call(ctx, pid, "thread/list", params)
    assert [row] = Map.fetch!(page, "data")
    assert Map.fetch!(row, "id") == expected
    assert Map.fetch!(row, "historyMode") == "paginated"
    assert Map.fetch!(row, "turns") == []
    assert Map.fetch!(row, "section") === section
    assert Map.fetch!(row, "sectionEnteredAt") == saved[expected].section_entered
    assert Map.fetch!(row, "path") == saved[expected].path
    assert Map.fetch!(row, "preview") == saved[expected].preview
    assert Map.fetch!(row, "cwd") == ctx.fixture.workspace
    assert Map.fetch!(row, "modelProvider") == "fixture"
    assert is_binary(cursor(page, "backwardsCursor"))
    page
  end

  defp stable_page(page) do
    %{
      ids: Enum.map(Map.fetch!(page, "data"), &Map.fetch!(&1, "id")),
      next: Map.fetch!(page, "nextCursor"),
      backwards: Map.fetch!(page, "backwardsCursor")
    }
  end

  defp cursor(page, field) do
    value = Map.fetch!(page, field)
    assert is_binary(value) and byte_size(value) in 1..256
    value
  end

  defp section(ctx, pid) do
    name = "Owned integer-rank cursor section"

    assert %{"section" => %{"id" => id} = section} =
             call(ctx, pid, "threadSection/create", %{"name" => name})

    assert is_binary(id) and byte_size(id) > 0
    assert section === %{"id" => id, "name" => name, "appearance" => nil}
    section
  end

  defp move(ctx, pid, thread, section, before \\ nil) do
    params = %{"threadId" => thread, "sectionId" => section["id"]}
    params = if before == nil, do: params, else: Map.put(params, "beforeThreadId", before)
    assert call(ctx, pid, "thread/section/move", params) == %{}
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

  defp turn(ctx, pid, thread, text) do
    before = length(ModelFixture.requests(ctx.fixture))

    result =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })

    id = result["turn"]["id"]
    assert is_binary(id) and byte_size(id) > 0
    events = complete(pid, thread, id, [], deadline(20_000))
    saved = read(ctx, pid, thread)
    assert_history(saved, {thread, id, text})
    [assistant] = Enum.filter(hd(saved["turns"])["items"], &(&1["type"] == "agentMessage"))
    assert is_binary(assistant["id"]) and byte_size(assistant["id"]) > 0

    assert Enum.any?(events, fn event ->
             event.wire["method"] == "item/completed" and
               event.wire["params"]["threadId"] == thread and
               event.wire["params"]["turnId"] == id and
               event.wire["params"]["item"]["id"] == assistant["id"] and
               event.wire["params"]["item"]["text"] == @answer
           end)

    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == before + 1
    request = List.last(requests)
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^id} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{"role" => "developer", "content" => [%{"text" => @instructions}]} =
             hd(request["input"])

    texts =
      for item <- request["input"],
          item["role"] == "user",
          part <- item["content"],
          part["type"] == "input_text",
          do: part["text"]

    assert Enum.count(texts, &(&1 == text)) == 1
    id
  end

  defp complete(pid, thread, turn, accumulated, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = accumulated ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    finished =
      Enum.find(events, fn event ->
        event.wire["method"] == "turn/completed" and
          event.wire["params"]["threadId"] == thread and
          event.wire["params"]["turn"]["id"] == turn
      end)

    if finished do
      assert finished.wire["params"]["turn"]["status"] == "completed"
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native section-rank turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected section-rank event gap")
      after
        10 -> :ok
      end

      complete(pid, thread, turn, events, until)
    end
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp save(ctx, pid, {id, _, _} = expected, section) do
    native = read(ctx, pid, id)
    assert_history(native, expected)
    assert native["section"] === section
    entered = Map.fetch!(native, "sectionEnteredAt")
    assert is_integer(entered)
    path = Map.fetch!(native, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    {id,
     %{
       path: path,
       file: snapshot(path),
       turns: native["turns"],
       preview: Map.fetch!(native, "preview"),
       section_entered: entered
     }}
  end

  defp assert_history(native, {thread, turn, text}) do
    assert Map.fetch!(native, "id") == thread
    assert Map.fetch!(native, "historyMode") == "paginated"
    assert [saved] = Map.fetch!(native, "turns")
    assert Map.fetch!(saved, "id") == turn
    assert Map.fetch!(saved, "status") == "completed"
    assert Map.fetch!(saved, "error") == nil
    item_ids = Enum.map(saved["items"], &Map.fetch!(&1, "id"))
    assert Enum.all?(item_ids, &(is_binary(&1) and byte_size(&1) > 0))
    assert length(item_ids) == length(Enum.uniq(item_ids))
    assert [user] = Enum.filter(saved["items"], &(&1["type"] == "userMessage"))

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) ==
             [%{"type" => "text", "text" => text}]

    assert [%{"text" => @answer}] = Enum.filter(saved["items"], &(&1["type"] == "agentMessage"))
  end

  defp assert_retained(ctx, pid, histories, section, saved, inputs) do
    assert_inputs(inputs)
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    for {id, _, _} = expected <- histories do
      source = Map.fetch!(saved, id)
      assert snapshot(source.path) === source.file
      native = read(ctx, pid, id)
      assert_history(native, expected)
      assert native["turns"] === source.turns
      assert native["path"] == source.path
      assert native["preview"] == source.preview
      assert native["section"] === section
      assert native["sectionEnteredAt"] == source.section_entered
      assert snapshot(source.path) === source.file
    end

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

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-section-rank-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "owned_section_rank_cursor", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
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

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
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
