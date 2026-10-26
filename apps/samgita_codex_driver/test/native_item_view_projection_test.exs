defmodule SamgitaCodexDriver.NativeItemViewProjectionTest do
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
  @instructions "Owned ordinary rich item projection fixture instructions."
  @input "Owned rich item projection λ字🙂"
  @output "Owned synthetic lookup result β🙂"
  @answer "Deterministic local fixture answer"
  @content [%{"type" => "inputText", "text" => @output}]
  @views ~w(notLoaded summary full)
  @captured ~w(thread/start turn/start thread/turns/list thread/resume)
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Owned synthetic lookup for persisted item projections",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      transport_opts = Keyword.delete(opts, :capture)

      with {:ok, state} <- Stdio.open(transport_opts),
           do: {:ok, Map.put(state, :capture, capture)}
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
      if length(Agent.get(state.capture, & &1)) < 24 and byte_size(encoded) <= 4096 do
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

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-rich-item-view-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = model_fixture(root)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, root: root, fixture: fixture}

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    paths = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: Map.new(paths, &{&1, snapshot(&1)})})
  end

  test "native rich history differentiates summary full and notLoaded across warm and cold pages",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm)
    thread = thread(ctx, warm)
    turn = completed_turn(ctx, warm, thread)
    saved = saved_history(ctx, warm, thread, turn)
    retained = Map.put(ctx.inputs, ctx.fixture.requests, snapshot(ctx.fixture.requests))
    assert call(ctx, warm, "thread/loaded/list", %{})["data"] == [thread]

    warm_pages = list_matrix(ctx, warm, thread, saved)
    assert resume_matrix(ctx, warm, thread, saved) === warm_pages
    assert call(ctx, warm, "thread/loaded/list", %{})["data"] == [thread]
    assert_retained(ctx, warm, thread, saved, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(ctx, cold)
    refute cold_native == warm_native
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []

    # These three queries precede all cold hydration reads; no resume is issued.
    assert list_matrix(ctx, cold, thread, saved) === warm_pages
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, thread, saved, retained)
    assert call(ctx, cold, "thread/loaded/list", %{})["data"] == []
    close(cold, cold_native)
    assert_inputs(retained)
    assert snapshot(saved.path) === saved.snapshot

    captures = Agent.get(ctx.capture, & &1)
    assert length(captures) == 11
    assert capture_count(captures, "thread/start") == 1
    assert capture_count(captures, "turn/start") == 1
    assert capture_count(captures, "thread/turns/list") == 6
    assert capture_count(captures, "thread/resume") == 3
    assert length(ModelFixture.requests(ctx.fixture)) == 2
  end

  defp model_fixture(root) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "dynamic_tool")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    fixture
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
        "ephemeral" => false,
        "dynamicTools" => [@lookup]
      })

    id = result["thread"]["id"]
    assert is_binary(id) and byte_size(id) > 0
    assert ModelFixture.requests(ctx.fixture) == []
    id
  end

  defp completed_turn(ctx, pid, thread) do
    id =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @input}]
      })["turn"]["id"]

    assert is_binary(id) and byte_size(id) > 0
    events = await(pid, [], &tool_requested?/1)
    assert [tool] = Enum.filter(events, &(&1.kind == :server_request))
    assert tool.wire["method"] == "item/tool/call"
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => thread,
             "turnId" => id,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    refute Enum.any?(events, &(&1.wire["method"] == "turn/completed"))
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)

    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok, %{"success" => true, "contentItems" => @content}}
             )

    events = await(pid, events, &completed?(&1, thread, id))
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    assert_provider(ctx, thread, id)
    %{id: id, entries: completed_entries(events, thread, id)}
  end

  defp tool_requested?(events), do: Enum.any?(events, &(&1.kind == :server_request))

  defp completed?(events, thread, id) do
    Enum.any?(events, fn event ->
      event.wire["method"] == "turn/completed" and
        event.wire["params"]["threadId"] == thread and
        event.wire["params"]["turn"]["id"] == id and
        event.wire["params"]["turn"]["status"] == "completed"
    end)
  end

  defp assert_provider(ctx, thread, turn) do
    assert [first, continued] = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"
    assert Enum.filter(first["input"], &(&1["type"] == "function_call_output")) == []

    assert [%{"call_id" => "fixture-call-1", "output" => @output}] =
             Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))

    for request <- [first, continued] do
      assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
               JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

      assert %{
               "role" => "developer",
               "content" => [%{"type" => "input_text", "text" => @instructions}]
             } = hd(request["input"])

      texts =
        for item <- request["input"],
            item["role"] == "user",
            part <- item["content"],
            part["type"] == "input_text",
            do: part["text"]

      assert Enum.count(texts, &(&1 == @input)) == 1
    end
  end

  defp completed_entries(events, thread, turn) do
    completed = item_events(events, "item/completed")

    assert Enum.map(completed, & &1["item"]["type"]) == [
             "userMessage",
             "dynamicToolCall",
             "agentMessage"
           ]

    entries =
      for event <- completed do
        item = Map.fetch!(event, "item")
        assert event["threadId"] == thread and event["turnId"] == turn
        assert is_binary(item["id"]) and byte_size(item["id"]) > 0

        assert [began] =
                 Enum.filter(
                   item_events(events, "item/started"),
                   &(&1["item"]["id"] == item["id"])
                 )

        assert began["threadId"] == thread and began["turnId"] == turn
        started = Map.fetch!(began, "startedAtMs")
        ended = Map.fetch!(event, "completedAtMs")
        assert is_integer(started) and started > 0
        assert is_integer(ended) and ended >= started
        %{"turnId" => turn, "item" => item, "startedAtMs" => started, "completedAtMs" => ended}
      end

    assert length(Enum.uniq_by(entries, & &1["item"]["id"])) == 3
    assert_items(Enum.map(entries, & &1["item"]))
    entries
  end

  defp assert_items([user, dynamic, assistant]) do
    assert user["type"] == "userMessage"
    assert user["content"] == [%{"type" => "text", "text" => @input, "text_elements" => []}]
    assert dynamic["type"] == "dynamicToolCall"
    assert dynamic["id"] == "fixture-call-1"
    assert dynamic["namespace"] == nil
    assert dynamic["tool"] == "fixture_lookup"
    assert dynamic["arguments"] == %{"key" => "synthetic"}
    assert dynamic["status"] == "completed"
    assert Map.fetch!(dynamic, "contentItems") == @content
    assert Map.fetch!(dynamic, "success") == true
    assert is_integer(dynamic["durationMs"]) and dynamic["durationMs"] >= 0
    assert assistant["type"] == "agentMessage"
    assert assistant["text"] == @answer
  end

  defp item_events(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp await(pid, events, ready), do: await(pid, events, ready, deadline(20_000))

  defp await(pid, events, ready, until) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert Enum.all?(events, &(&1.generation == generation))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.sort(Enum.uniq(sequences))
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    assert Enum.count(events, &(&1.kind == :server_request)) <= 1

    if ready.(events) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native rich item projection deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected rich item projection gap")
      after
        10 -> :ok
      end

      await(pid, events, ready, until)
    end
  end

  defp saved_history(ctx, pid, thread, expected) do
    # A synchronous native history read observes complete rows, not an fsync barrier.
    saved = read(ctx, pid, thread)
    assert Map.fetch!(saved, "historyMode") == "paginated"
    assert [%{"id" => turn, "status" => "completed", "error" => nil} = row] = saved["turns"]
    assert turn == expected.id
    assert row["itemsView"] == "full"
    assert row["items"] === Enum.map(expected.entries, & &1["item"])
    assert_items(row["items"])
    assert is_integer(row["startedAt"]) and row["startedAt"] > 0
    assert is_integer(row["completedAt"]) and row["completedAt"] >= row["startedAt"]
    assert is_integer(row["durationMs"]) and row["durationMs"] >= 0

    entries = item_entries(ctx, pid, thread, expected.id)
    assert entries === expected.entries
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    %{
      path: path,
      snapshot: snapshot(path),
      turns: saved["turns"],
      entries: entries,
      preview: Map.fetch!(saved, "preview")
    }
  end

  defp list_matrix(ctx, pid, thread, saved) do
    for view <- @views do
      page =
        call(ctx, pid, "thread/turns/list", %{
          "threadId" => thread,
          "itemsView" => view,
          "sortDirection" => "asc",
          "limit" => 100
        })

      assert_page(page, view, saved)
      assert snapshot(saved.path) === saved.snapshot
      assert_functional_state(ctx, pid)
      {view, page}
    end
  end

  defp resume_matrix(ctx, pid, thread, saved) do
    for view <- @views do
      result =
        call(ctx, pid, "thread/resume", %{
          "threadId" => thread,
          "excludeTurns" => true,
          "initialTurnsPage" => %{"itemsView" => view, "sortDirection" => "asc", "limit" => 100}
        })

      assert result["thread"]["id"] == thread
      assert result["thread"]["historyMode"] == "paginated"
      assert result["thread"]["path"] == saved.path
      assert result["thread"]["turns"] == []
      page = Map.fetch!(result, "initialTurnsPage")
      assert_page(page, view, saved)
      assert snapshot(saved.path) === saved.snapshot
      assert_functional_state(ctx, pid)
      {view, page}
    end
  end

  defp assert_page(page, view, saved) do
    assert Enum.sort(Map.keys(page)) == ~w(backwardsCursor data nextCursor)
    assert Map.fetch!(page, "nextCursor") == nil
    backwards = Map.fetch!(page, "backwardsCursor")
    assert is_binary(backwards) and byte_size(backwards) > 0 and byte_size(backwards) <= 4096
    [original] = saved.turns
    items = projection(view, original["items"])
    expected = original |> Map.put("itemsView", view) |> Map.put("items", items)
    assert Map.fetch!(page, "data") === [expected]
    assert_selected(view, hd(page["data"])["items"], original["items"])
  end

  defp assert_selected("notLoaded", actual, _original), do: assert(actual == [])

  defp assert_selected("summary", actual, [user, _dynamic, assistant]) do
    assert actual === [user, assistant]
    refute Enum.any?(actual, &(&1["id"] == "fixture-call-1"))
  end

  defp assert_selected("full", actual, original) do
    assert actual === original
    assert Enum.find(actual, &(&1["id"] == "fixture-call-1")) === Enum.at(original, 1)
  end

  defp projection("notLoaded", _items), do: []
  defp projection("summary", [user, _dynamic, assistant]), do: [user, assistant]
  defp projection("full", items), do: items

  defp item_entries(ctx, pid, thread, turn) do
    page =
      call(ctx, pid, "thread/items/list", %{
        "threadId" => thread,
        "turnId" => turn,
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert Map.fetch!(page, "nextCursor") == nil
    Map.fetch!(page, "data")
  end

  defp assert_retained(ctx, pid, thread, saved, inputs) do
    assert_inputs(inputs)
    assert snapshot(saved.path) === saved.snapshot
    native = read(ctx, pid, thread)
    assert native["id"] == thread
    assert native["historyMode"] == "paginated"
    assert native["path"] == saved.path
    assert native["turns"] === saved.turns
    assert native["preview"] == saved.preview
    [turn] = saved.turns
    assert item_entries(ctx, pid, thread, turn["id"]) === saved.entries
    assert snapshot(saved.path) === saved.snapshot
    assert File.ls!(ctx.fixture.workspace) == []
    assert_functional_state(ctx, pid)
    assert {:ok, events} = Session.drain(pid, 256)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(inputs)
  end

  defp assert_functional_state(ctx, pid) do
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp capture_count(captures, method),
    do: Enum.count(captures, fn {_bytes, wire} -> wire["method"] == method end)

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-rich-item-view-#{System.unique_integer([:positive, :monotonic])}"
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
               %{"name" => "owned_rich_item_view_projection", "version" => "0.1.0"},
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
