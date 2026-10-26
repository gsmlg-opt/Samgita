defmodule SamgitaCodexDriver.NativeTurnItemsViewUnitInputTest do
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
  @instructions "Owned ordinary turn-items-view unit fixture instructions."
  @answer "Deterministic local fixture answer"
  @captured ~w(thread/start turn/start thread/turns/list thread/resume)

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

      if wire["method"] in ~w(thread/start turn/start thread/turns/list thread/resume) do
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
    Map.merge(ctx, %{capture: capture, inputs: inputs, capture_limit: 24})
  end

  test "six view unit objects select native item projections on warm lists resume pages and cold lists",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    thread = thread(ctx, warm)
    first = turn(ctx, warm, thread, "Owned items-view first λ🙂", 1)
    second = turn(ctx, warm, thread, "Owned items-view second 字🙂", 2)
    expected = [first, second]
    refute first.id == second.id
    entries = first.entries ++ second.entries
    assert length(entries) == 4
    assert length(Enum.uniq(Enum.map(entries, & &1["item"]["id"]))) == 4

    # A synchronous native read observes full history. It is not an fsync or
    # disk-flush guarantee. The original full rows and rollout remain our oracle.
    saved = saved_history(ctx, warm, thread, expected)
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))
    assert call(ctx, warm, "thread/loaded/list", %{})["data"] == [thread]
    warm_pages = list_matrix(ctx, warm, thread, saved)

    # The thread stays loaded for all six bootstrap-page requests. These are
    # genuine warm resume consumers; object-specific cold resume is out of scope.
    resume_pages = resume_matrix(ctx, warm, thread, saved)
    assert resume_pages === warm_pages
    assert call(ctx, warm, "thread/loaded/list", %{})["data"] == [thread]
    assert_retained(ctx, warm, thread, expected, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []

    # All six cold list calls precede any full history read. No explicit resume
    # is issued on this new process and no execution runtime should be loaded.
    assert list_matrix(ctx, cold, thread, saved) === warm_pages
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert snapshot(saved.path) === saved.snapshot
    assert_inputs(retained)
    assert_functional_state(ctx, cold)
    assert_retained(ctx, cold, thread, expected, saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 21
    assert capture_count(captures, "thread/start") == 1
    assert capture_count(captures, "turn/start") == 2
    assert capture_count(captures, "thread/turns/list") == 12
    assert capture_count(captures, "thread/resume") == 6
    assert length(ModelFixture.requests(ctx.fixture)) == 2
  end

  defp view_forms do
    for view <- ["notLoaded", "summary", "full"],
        payload <- [nil, %{}],
        do: {view, %{view => payload}}
  end

  defp list_matrix(ctx, pid, thread, saved) do
    for {view, object} <- view_forms() do
      page =
        call(ctx, pid, "thread/turns/list", %{
          "threadId" => thread,
          "itemsView" => object,
          "sortDirection" => "asc",
          "limit" => 100
        })

      assert_page(page, view, saved)
      assert snapshot(saved.path) === saved.snapshot
      assert_functional_state(ctx, pid)
      {object, page}
    end
  end

  defp resume_matrix(ctx, pid, thread, saved) do
    for {view, object} <- view_forms() do
      result =
        call(ctx, pid, "thread/resume", %{
          "threadId" => thread,
          "excludeTurns" => true,
          "initialTurnsPage" => %{
            "itemsView" => object,
            "sortDirection" => "asc",
            "limit" => 100
          }
        })

      assert result["thread"]["id"] == thread
      assert result["thread"]["historyMode"] == "paginated"
      assert result["thread"]["path"] == saved.path
      assert result["thread"]["turns"] == []
      page = Map.fetch!(result, "initialTurnsPage")

      # Independently assert the original turn IDs/status/timing and prescribed
      # item projection before comparing this page with the warm list result.
      assert_page(page, view, saved)
      assert snapshot(saved.path) === saved.snapshot
      assert_functional_state(ctx, pid)
      {object, page}
    end
  end

  defp assert_page(page, view, saved) do
    assert Map.fetch!(page, "nextCursor") == nil
    backwards = Map.fetch!(page, "backwardsCursor")
    assert is_binary(backwards) and byte_size(backwards) > 0

    # The unchanged assistant-only producer yields exactly userMessage plus
    # final agentMessage. Summary and Full therefore have identical two-item
    # content here; this does not prove filtering of richer intermediate items.
    expected =
      for turn <- saved.turns do
        items = if view == "notLoaded", do: [], else: Map.fetch!(turn, "items")
        turn |> Map.put("itemsView", view) |> Map.put("items", items)
      end

    assert Map.fetch!(page, "data") === expected
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

    # Completion delivery is not a disk barrier. Observe native full history
    # without claiming that this read forces durable filesystem persistence.
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
             "native turn-items-view unit turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected turn-items-view unit event gap")
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

  defp assert_retained(ctx, pid, thread, expected, saved, inputs) do
    assert_inputs(inputs)
    assert snapshot(saved.path) === saved.snapshot
    native = read(ctx, pid, thread)
    assert_history(native, thread, expected)
    assert native["path"] == saved.path
    assert native["turns"] === saved.turns
    assert native["preview"] == saved.preview
    assert snapshot(saved.path) === saved.snapshot
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

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-turn-items-view-unit-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
      assert_view_object(bytes, method, params)
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

  defp assert_view_object(bytes, method, params)
       when method in ["thread/turns/list", "thread/resume"] do
    object =
      if method == "thread/resume",
        do: Map.fetch!(Map.fetch!(params, "initialTurnsPage"), "itemsView"),
        else: Map.fetch!(params, "itemsView")

    assert is_map(object) and map_size(object) == 1
    assert :binary.match(bytes, JSON.encode!(object)) != :nomatch
  end

  defp assert_view_object(_bytes, _method, _params), do: :ok

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
               %{"name" => "owned_turn_items_view_unit_input", "version" => "0.1.0"},
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
