defmodule SamgitaCodexDriver.NativeSearchCreatorRootsTest do
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
  @needle "Owned search creator roots λ marker"
  @instructions "Owned fixed search creator roots instructions."
  @answer "Deterministic local fixture answer"
  @creator_a "owned_search_creator_a"
  @creator_b "owned_search_creator_b"
  @reader "owned_search_reader_c"
  @captured ~w(initialize thread/start thread/resume thread/search project/import)

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

      if wire["method"] in ~w(initialize thread/start thread/resume thread/search project/import) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 24 and byte_size(encoded) <= 8192 do
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
    roots = Enum.map(["a-second", "a-first", "b-only"], &Path.join(ctx.root, &1))
    Enum.each(roots, &File.mkdir!/1)
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\n"
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

    Map.merge(ctx, %{
      roots: roots,
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end})
    })
  end

  test "native search retains each creator and projects only currently loaded explicit roots",
       ctx do
    [second, first, only] = ctx.roots
    roots_a = [second, first]
    roots_b = [only]
    warm = start(ctx, @creator_a)
    a = complete(ctx, warm.pid, @creator_a, roots_a, "a", 1)
    search_pair(ctx, warm.pid, [a], %{a.id => roots_a}, %{})
    journal_a = snapshot(ctx.fixture.requests)
    assert_retained(ctx, warm.pid, [a], 1)
    close(warm)
    assert snapshot(ctx.fixture.requests) === journal_a

    mixed = start(ctx, @creator_b)
    b = complete(ctx, mixed.pid, @creator_b, roots_b, "b", 2)
    refute b.id == a.id
    refute b.path == a.path
    saved = [a, b]
    journal = snapshot(ctx.fixture.requests)
    search_pair(ctx, mixed.pid, saved, %{b.id => roots_b}, %{})
    projects = Map.new(saved, &{&1.id, project(ctx, mixed.pid, &1)})
    assert map_size(projects) == 2 and length(Enum.uniq(Map.values(projects))) == 2
    search_pair(ctx, mixed.pid, saved, %{b.id => roots_b}, projects)
    assert_retained(ctx, mixed.pid, saved, 2)
    close(mixed)
    assert snapshot(ctx.fixture.requests) === journal

    cold = start(ctx, @reader)
    refute cold.native in [warm.native, mixed.native]
    search_pair(ctx, cold.pid, saved, %{}, projects)
    assert_retained(ctx, cold.pid, saved, 2)
    assert_loaded(ctx, cold.pid, [])

    # A cold search does not restore environments. Explicit resume supplies
    # these roots anew; it must retain A's creator rather than adopting C.
    resumed = call(ctx, cold.pid, "thread/resume", resume_params(a, roots_a))["thread"]
    assert Map.fetch!(resumed, "id") == a.id
    assert Map.fetch!(resumed, "originator") == @creator_a
    assert Map.fetch!(resumed, "projectId") == projects[a.id]
    assert Map.fetch!(resumed, "turns") === a.turns
    checkpoint = resume_checkpoint(ctx, cold.pid, a, roots_a)
    search_pair(ctx, cold.pid, saved, %{a.id => roots_a}, projects)
    assert_retained(ctx, cold.pid, [checkpoint, b], 2)
    assert snapshot(ctx.fixture.requests) === journal
    close(cold)
    assert snapshot(ctx.fixture.requests) === journal
    for source <- [checkpoint, b], do: assert(snapshot(source.path) === source.file)
    assert_inventory(ctx, a, b, roots_a, roots_b)
  end

  defp complete(ctx, pid, creator, roots, label, count) do
    thread = call(ctx, pid, "thread/start", thread_params(ctx, roots, label))["thread"]
    id = Map.fetch!(thread, "id")
    assert is_binary(id) and id != ""
    text = label <> " " <> @needle
    turn = call(ctx, pid, "turn/start", turn_params(id, text))["turn"]["id"]
    assert is_binary(turn) and turn != ""
    events = completed(pid, id, turn, [], deadline(20_000))

    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == id,
          event.wire["params"]["turnId"] == turn,
          do: event.wire["params"]["item"]

    assert [%{"type" => "userMessage"} = user, %{"type" => "agentMessage"} = assistant] = items

    assert Map.fetch!(user, "content") == [
             %{"type" => "text", "text" => text, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "text") == @answer
    assert is_binary(user["id"]) and is_binary(assistant["id"]) and user["id"] != assistant["id"]
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    assert_provider(List.last(requests), id, turn, text)
    name = "Owned creator roots " <> label
    assert call(ctx, pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}

    # Public full history observes native persistence before search; no SQL
    # seed, hand-written rollout or retrying content into existence is used.
    history = read(ctx, pid, id)
    assert [%{"id" => ^turn, "status" => "completed", "items" => ^items}] = history["turns"]
    path = Map.fetch!(history, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    file = snapshot(path)
    meta = session_meta(file.bytes, id)
    assert Map.fetch!(meta, "originator") == creator
    assert Map.fetch!(meta, "thread_source") == "owned-source-" <> label
    assert Map.fetch!(history, "name") == name

    %{
      id: id,
      path: path,
      file: file,
      creator: creator,
      label: label,
      name: name,
      text: text,
      turns: history["turns"]
    }
  end

  defp thread_params(ctx, roots, label) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "historyMode" => "paginated",
      "ephemeral" => false,
      "runtimeWorkspaceRoots" => roots,
      "threadSource" => "owned-source-" <> label
    }
  end

  defp turn_params(id, text),
    do: %{"threadId" => id, "input" => [%{"type" => "text", "text" => text}]}

  defp resume_params(a, roots), do: %{"threadId" => a.id, "runtimeWorkspaceRoots" => roots}

  defp resume_checkpoint(ctx, pid, source, roots) do
    assert Map.fetch!(read(ctx, pid, source.id), "turns") === source.turns
    current = snapshot(source.path)
    assert String.starts_with?(current.bytes, source.file.bytes)
    offset = byte_size(source.file.bytes)
    suffix = binary_part(current.bytes, offset, byte_size(current.bytes) - offset)
    assert [line] = String.split(suffix, "\n", trim: true)
    event = JSON.decode!(line)

    previous =
      source.file.bytes |> String.split("\n", trim: true) |> List.last() |> JSON.decode!()

    assert Map.fetch!(event, "ordinal") == Map.fetch!(previous, "ordinal") + 1
    assert {:ok, _time, 0} = DateTime.from_iso8601(Map.fetch!(event, "timestamp"))
    assert Map.fetch!(event, "type") == "event_msg"
    payload = Map.fetch!(event, "payload")
    assert Map.fetch!(payload, "type") == "thread_settings_applied"
    assert Map.fetch!(payload, "thread_id") == source.id

    # Explicit resume applies settings and appends one native event. Account
    # for its functional fields without asserting any permission behavior.
    assert Map.take(
             Map.fetch!(payload, "thread_settings"),
             ~w(model model_provider_id cwd runtime_workspace_roots)
           ) == %{
             "model" => "mock-model",
             "model_provider_id" => "fixture",
             "cwd" => ctx.fixture.workspace,
             "runtime_workspace_roots" => roots
           }

    assert session_meta(current.bytes, source.id) === session_meta(source.file.bytes, source.id)
    %{source | file: current}
  end

  defp project(ctx, pid, saved) do
    project = call(ctx, pid, "project/import", project_params(saved))["project"]
    assert Map.fetch!(project, "metadata") == %{"label" => saved.label}
    id = Map.fetch!(project, "id")
    assert is_binary(id) and id != ""
    id
  end

  defp project_params(saved) do
    %{
      "name" => "Owned creator project " <> saved.label,
      "roots" => [],
      "metadata" => %{"label" => saved.label},
      "threads" => [saved.id],
      "idempotencyKey" => "owned-search-creator-project-" <> saved.label
    }
  end

  defp search_pair(ctx, pid, saved, loaded, projects) do
    ids = Map.keys(loaded)
    assert_loaded(ctx, pid, ids)

    for extra <- [%{}, %{"sourceKinds" => ["vscode"]}] do
      result = call(ctx, pid, "thread/search", Map.merge(search_params(), extra))
      assert Map.fetch!(result, "nextCursor") == nil
      rows = Map.fetch!(result, "data")
      expected = Map.new(saved, &{&1.id, &1})
      assert length(rows) == map_size(expected)
      assert Enum.sort(Enum.map(rows, & &1["thread"]["id"])) == Enum.sort(Map.keys(expected))

      for row <- rows do
        thread = Map.fetch!(row, "thread")
        source = Map.fetch!(expected, Map.fetch!(thread, "id"))
        assert Map.fetch!(row, "snippet") == source.text
        assert Map.fetch!(thread, "preview") == source.text
        assert Map.fetch!(thread, "name") == source.name
        assert Map.fetch!(thread, "path") == source.path
        assert Map.fetch!(thread, "originator") == source.creator
        assert Map.fetch!(thread, "source") == "vscode"
        assert Map.fetch!(thread, "threadSource") == nil
        assert Map.fetch!(thread, "extra") == nil
        assert Map.fetch!(thread, "projectId") == projects[source.id]
        assert Map.fetch!(thread, "historyMode") == "paginated"
        assert Map.fetch!(thread, "turns") == []

        assert_runtime(ctx, thread, source.id, loaded)
      end
    end

    assert_loaded(ctx, pid, ids)
    assert_inputs(ctx)
  end

  defp search_params, do: %{"searchTerm" => @needle, "limit" => 100}

  defp assert_runtime(ctx, thread, id, loaded) do
    if Map.has_key?(loaded, id) do
      assert Map.fetch!(thread, "environments") === [
               %{
                 "cwd" => ctx.fixture.workspace,
                 "environmentId" => "local",
                 "runtimeWorkspaceRoots" => loaded[id]
               }
             ]

      assert Map.fetch!(thread, "status") == %{"type" => "idle"}
    else
      assert Map.fetch!(thread, "environments") === nil
      assert Map.fetch!(thread, "status") == %{"type" => "notLoaded"}
    end
  end

  defp assert_retained(ctx, pid, saved, count) do
    for source <- saved do
      assert snapshot(source.path) === source.file
      history = read(ctx, pid, source.id)
      assert Map.fetch!(history, "id") == source.id
      assert Map.fetch!(history, "path") == source.path
      assert Map.fetch!(history, "turns") === source.turns
      assert Map.fetch!(history, "originator") == source.creator
      assert snapshot(source.path) === source.file
    end

    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert_inputs(ctx)
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 128
    assert byte_size(:erlang.term_to_binary(events)) <= 1_048_576

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or method == "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_inputs(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert File.ls!(ctx.fixture.workspace) == []
    for path <- ctx.roots, do: assert(File.ls!(path) == [])
  end

  defp assert_loaded(ctx, pid, ids) do
    result = call(ctx, pid, "thread/loaded/list", %{})
    assert Map.fetch!(result, "nextCursor") == nil
    assert Enum.sort(Map.fetch!(result, "data")) == Enum.sort(ids)
  end

  defp assert_provider(request, thread, turn, text) do
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } =
             hd(request["input"])

    texts =
      for item <- request["input"],
          item["role"] == "user",
          part <- item["content"],
          part["type"] == "input_text",
          do: part["text"]

    assert Enum.count(texts, &(&1 == text)) == 1
  end

  defp completed(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(:erlang.term_to_binary(events)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))

    found =
      TurnFixture.notification(
        events,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

    if found do
      assert found["turn"]["status"] == "completed"
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native creator-roots turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected creator-roots event gap")
      after
        10 -> :ok
      end

      completed(pid, thread, turn, events, until)
    end
  end

  defp session_meta(bytes, id) do
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 256

    rows =
      for line <- lines,
          row = JSON.decode!(line),
          row["type"] == "session_meta" and row["payload"]["id"] == id,
          do: row["payload"]

    assert rows != []
    List.last(rows)
  end

  defp read(ctx, pid, id),
    do: call(ctx, pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-search-creator-roots-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert byte_size(JSON.encode!(response)) <= 65_536

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

  defp start(ctx, name) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    before = length(Agent.get(ctx.capture, & &1))
    info = %{"name" => name, "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, info, capabilities, timeout_ms: 5_000)

    assert [{bytes, wire}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert Map.fetch!(wire, "method") == "initialize"
    assert Map.fetch!(wire, "params") == %{"clientInfo" => info, "capabilities" => capabilities}
    assert JSON.decode!(bytes) === wire
    assert bytes === JSON.encode!(wire)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert_loaded(ctx, pid, [])
    %{pid: pid, native: native, connection: connection}
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx, a, b, roots_a, roots_b) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 18
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 18

    query =
      Enum.map(
        [%{}, %{"sourceKinds" => ["vscode"]}],
        &{"thread/search", Map.merge(search_params(), &1)}
      )

    initialize = fn name ->
      {"initialize",
       %{
         "clientInfo" => %{"name" => name, "version" => "0.1.0"},
         "capabilities" => %{"experimentalApi" => true}
       }}
    end

    expected =
      [initialize.(@creator_a), {"thread/start", thread_params(ctx, roots_a, "a")}] ++
        query ++
        [initialize.(@creator_b), {"thread/start", thread_params(ctx, roots_b, "b")}] ++
        query ++
        Enum.map([a, b], &{"project/import", project_params(&1)}) ++
        query ++
        [initialize.(@reader)] ++ query ++ [{"thread/resume", resume_params(a, roots_a)}] ++ query

    assert Enum.map(frames, fn {_bytes, wire} -> {wire["method"], wire["params"]} end) ===
             expected
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
