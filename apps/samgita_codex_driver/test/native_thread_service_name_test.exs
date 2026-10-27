defmodule SamgitaCodexDriver.NativeThreadServiceNameTest do
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
  @client "owned_thread_service_name"
  @reader "owned_thread_service_reader"
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary service-name provenance instructions."
  @metadata_query """
  import json, pathlib, sqlite3, sys
  database = pathlib.Path(sys.argv[1]).resolve().as_uri() + "?mode=ro"
  with sqlite3.connect(database, uri=True, timeout=1) as connection:
      connection.row_factory = sqlite3.Row
      placeholders = ",".join("?" for _ in sys.argv[2:])
      query = ("SELECT id, rollout_path, created_at_ms, updated_at_ms FROM threads "
               "WHERE id IN (" + placeholders + ") ORDER BY id")
      rows = connection.execute(query, sys.argv[2:]).fetchall()
      print(json.dumps([dict(row) for row in rows], ensure_ascii=False))
  """
  @cases [
    {%{}, @client, "before"},
    {%{"serviceName" => "  CoDeX_WoRk_DeSkToP  "}, "codex_work_desktop", "desktop"},
    {%{"serviceName" => "CHATGPT_CCA"}, "chatgpt_cca", "cca"},
    {%{"serviceName" => "owned-service-λ"}, @client, "unknown"},
    {%{"serviceName" => nil}, @client, "null"},
    {%{}, @client, "after"}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      with {:ok, next} <- Stdio.send(state, encoded) do
        case record(next, :out, encoded) do
          :ok -> {:ok, next}
          {:error, error} -> {:error, error, next}
        end
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)

      if selected?(direction, wire) do
        Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
      else
        :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger
          |> Map.put(direction, entries ++ [entry])
          |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

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

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})
    Map.merge(ctx, %{inputs: inputs, capture: capture})
  end

  test "native service-name provenance stays thread-local and survives cold public reads", ctx do
    warm = start(ctx, @client)
    assert_unloaded(ctx, warm.pid)
    markers = Enum.map(@cases, fn {_extra, _originator, label} -> marker(label) end)

    rows =
      for {entry, index} <- Enum.with_index(@cases, 1) do
        materialize(ctx, warm.pid, entry, index, markers)
      end

    assert length(Enum.uniq_by(rows, & &1.id)) == 6
    assert length(Enum.uniq_by(rows, & &1.saved["path"])) == 6
    assert length(Enum.uniq_by(rows, & &1.turn)) == 6
    assert length(ModelFixture.requests(ctx.fixture)) == 6
    journal = snapshot(ctx.fixture.requests)

    for row <- rows do
      assert read(ctx, warm.pid, row.id) === row.saved
      assert snapshot(row.saved["path"]) === row.rollout
    end

    loaded = call(ctx, warm.pid, "thread/loaded/list", %{})
    assert loaded["nextCursor"] == nil
    assert Enum.sort(loaded["data"]) == Enum.sort(Enum.map(rows, & &1.id))
    assert_retained(ctx, warm.pid, rows, journal)
    close(warm)
    assert_retained_files(ctx, rows, journal)

    cold = start(ctx, @reader)
    refute cold.native == warm.native
    assert_unloaded(ctx, cold.pid)
    persisted = persisted_rows(ctx, rows)

    for row <- rows do
      expected = cold_view(row, Map.fetch!(persisted, row.id))
      restored = read(ctx, cold.pid, row.id)
      assert restored === expected
      assert Map.fetch!(restored, "originator") == row.originator
      assert_history(restored, row)
      assert read(ctx, cold.pid, row.id) === restored
      assert_unloaded(ctx, cold.pid)
    end

    assert persisted_rows(ctx, rows) === persisted
    assert_retained(ctx, cold.pid, rows, journal)
    close(cold)
    assert_retained_files(ctx, rows, journal)
    assert_inventory(ctx)
  end

  defp materialize(ctx, pid, {extra, originator, label}, index, markers) do
    params =
      Map.merge(
        %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.fixture.workspace,
          "ephemeral" => false,
          "historyMode" => "legacy"
        },
        extra
      )

    assert length(ModelFixture.requests(ctx.fixture)) == index - 1
    created = call(ctx, pid, "thread/start", params)["thread"]
    id = Map.fetch!(created, "id")
    assert is_binary(id) and id != ""
    events = collect(pid, &started?(&1, id), deadline(5_000))
    assert_creation(ctx, events, created, originator)
    assert length(ModelFixture.requests(ctx.fixture)) == index - 1
    text = marker(label)
    turn_params = %{"threadId" => id, "input" => [%{"type" => "text", "text" => text}]}
    turn = call(ctx, pid, "turn/start", turn_params)["turn"]["id"]
    assert is_binary(turn) and turn != ""
    events = collect(pid, &finished?(&1, id, turn), deadline(20_000))
    items = assert_turn(events, id, turn, text)
    assert_provider(ctx, index, id, turn, text, markers)
    row = %{id: id, originator: originator, turn: turn, text: text, items: items}
    saved = read(ctx, pid, id)
    assert Map.fetch!(saved, "originator") == originator
    assert_warm_runtime(ctx, saved)
    assert_history(saved, row)
    rollout = snapshot(saved["path"])
    rollout_mtime = File.stat!(saved["path"], time: :posix).mtime
    assert rollout_mtime >= saved["createdAt"]
    assert rollout_mtime <= System.system_time(:second)
    assert_meta(rollout.bytes, id, originator, saved["createdAt"])
    Map.merge(row, %{saved: saved, rollout: rollout, rollout_mtime: rollout_mtime})
  end

  defp assert_creation(ctx, events, created, originator) do
    id = created["id"]

    assert [event] = Enum.filter(events, &(&1.wire["method"] == "thread/started"))

    notified = event.wire["params"]["thread"]

    for thread <- [created, notified] do
      assert Map.fetch!(thread, "id") == id
      assert Map.fetch!(thread, "originator") == originator
      assert Map.fetch!(thread, "historyMode") == "legacy"
      assert Map.fetch!(thread, "preview") == ""
      assert Map.fetch!(thread, "turns") == []
      assert Map.fetch!(thread, "cwd") == ctx.fixture.workspace
      assert Map.fetch!(thread, "source") == "vscode"
      assert String.starts_with?(Map.fetch!(thread, "path"), ctx.fixture.codex_home <> "/")
    end

    refute Enum.any?(events, &String.starts_with?(&1.wire["method"], ["turn/", "item/"]))
  end

  defp assert_turn(events, thread, turn, text) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             TurnFixture.notification(events, "turn/started", &(&1["turn"]["id"] == turn))

    completed = items(events, "item/completed", thread, turn)
    assert [user, assistant] = completed
    assert Map.fetch!(user, "type") == "userMessage"

    assert Map.fetch!(user, "content") == [
             %{"type" => "text", "text" => text, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "type") == "agentMessage"
    assert Map.fetch!(assistant, "text") == @answer

    assert Enum.map(items(events, "item/started", thread, turn), &Map.take(&1, ~w(id type))) ==
             Enum.map(completed, &Map.take(&1, ~w(id type)))

    assert Enum.all?(completed, &(is_binary(&1["id"]) and &1["id"] != ""))
    refute user["id"] == assistant["id"]
    completed
  end

  defp items(events, method, thread, turn) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["threadId"] == thread,
        event.wire["params"]["turnId"] == turn,
        do: event.wire["params"]["item"]
  end

  defp assert_provider(ctx, index, thread, turn, text, markers) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == index
    request = List.last(requests)
    assert Map.fetch!(request, "model") == "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ~w(thread_id turn_id)) == %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.filter(user_texts, &(&1 in markers)) == [text]
    encoded = JSON.encode!(request["input"])
    for other <- markers -- [text], do: refute(String.contains?(encoded, other))
  end

  # Legacy readback uses its own item-1/item-2 IDs, not live item IDs.
  defp assert_history(saved, row) do
    assert Map.fetch!(saved, "id") == row.id
    assert Map.fetch!(saved, "originator") == row.originator
    assert Map.fetch!(saved, "historyMode") == "legacy"
    assert Map.fetch!(saved, "preview") == row.text
    [user, assistant] = row.items
    expected = [Map.put(user, "id", "item-1"), Map.put(assistant, "id", "item-2")]
    assert [%{"id" => turn, "status" => "completed", "items" => ^expected}] = saved["turns"]
    assert turn == row.turn
  end

  defp assert_warm_runtime(ctx, saved) do
    assert Map.fetch!(saved, "status") == %{"type" => "idle"}
    assert Map.fetch!(saved, "canAcceptDirectInput") === true
    assert Map.fetch!(saved, "updatedAt") == Map.fetch!(saved, "createdAt")

    assert Map.fetch!(saved, "environments") === [
             %{
               "cwd" => ctx.fixture.workspace,
               "environmentId" => "local",
               "runtimeWorkspaceRoots" => [ctx.fixture.workspace]
             }
           ]
  end

  # Metadata-only warm legacy reads derive updatedAt from SessionMeta creation;
  # cold full reads retain the independently observed native SQLite timestamp.
  defp cold_view(row, metadata) do
    assert metadata["id"] == row.id
    assert metadata["rollout_path"] == row.saved["path"]
    assert div(metadata["created_at_ms"], 1000) == row.saved["createdAt"]
    assert metadata["updated_at_ms"] >= metadata["created_at_ms"]

    Map.merge(row.saved, %{
      "status" => %{"type" => "notLoaded"},
      "canAcceptDirectInput" => nil,
      "environments" => nil,
      "updatedAt" => div(metadata["updated_at_ms"], 1000)
    })
  end

  defp persisted_rows(ctx, rows) do
    database = Path.join(ctx.fixture.codex_home, "state_5.sqlite")
    assert File.regular?(database)
    ids = Enum.map(rows, & &1.id)

    assert {encoded, 0} =
             System.cmd("python3", ["-c", @metadata_query, database | ids],
               stderr_to_stdout: true
             )

    assert byte_size(encoded) <= 8192
    metadata = JSON.decode!(encoded)
    assert length(metadata) == length(ids)
    assert MapSet.new(Enum.map(metadata, & &1["id"])) == MapSet.new(ids)
    Map.new(metadata, &{&1["id"], &1})
  end

  defp assert_meta(bytes, id, originator, created_at) do
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 256

    assert [meta] =
             for(
               line <- lines,
               entry = JSON.decode!(line),
               entry["type"] == "session_meta" and entry["payload"]["id"] == id,
               do: entry["payload"]
             )

    assert Map.fetch!(meta, "originator") == originator
    assert {:ok, timestamp, _offset} = DateTime.from_iso8601(Map.fetch!(meta, "timestamp"))
    assert DateTime.to_unix(timestamp) == created_at
  end

  defp assert_retained(ctx, pid, rows, journal) do
    assert_retained_files(ctx, rows, journal)
    assert length(ModelFixture.requests(ctx.fixture)) == 6
    assert {:ok, events} = Session.drain(pid, 256)
    assert_bounded(events)
    assert {:ok, []} = Session.drain(pid, 256)

    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil, buffered_events: 0} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp assert_retained_files(ctx, rows, journal) do
    for {file, original} <- ctx.inputs, do: assert(snapshot(file) === original)

    for row <- rows do
      assert snapshot(row.saved["path"]) === row.rollout
      assert File.stat!(row.saved["path"], time: :posix).mtime == row.rollout_mtime
    end

    assert snapshot(ctx.fixture.requests) === journal
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp collect(pid, predicate, until, events \\ []) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_bounded(events)
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      remaining = until - System.monotonic_time(:millisecond)
      assert remaining > 0, "native service-name event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, until, events)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native service-name event gap")
      after
        remaining -> flunk("native service-name event deadline")
      end
    end
  end

  defp assert_bounded(events) do
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert Enum.all?(events, &(&1.kind == :notification))
    refute Enum.any?(events, &(&1.wire["method"] == "error"))
  end

  defp started?(events, id),
    do: TurnFixture.notification(events, "thread/started", &(&1["thread"]["id"] == id))

  defp finished?(events, thread, turn),
    do:
      TurnFixture.notification(events, "turn/completed", fn item ->
        item["threadId"] == thread and item["turn"]["id"] == turn
      end)

  defp marker(label), do: "Owned service-name " <> label <> " λ marker"

  defp assert_unloaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp read(ctx, pid, id),
    do: call(ctx, pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp call(ctx, pid, method, params) do
    id = "owned-service-name-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] == wire["id"]))
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
  end

  defp start(ctx, name) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
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
    info = %{"name" => name, "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, timeout_ms: 5_000)

    sent =
      Agent.get(ctx.capture, fn ledger ->
        Enum.filter(ledger.out, &(&1.wire["method"] == "initialize"))
      end)

    wire = List.last(sent).wire
    assert wire["params"] === %{"clientInfo" => info, "capabilities" => capabilities}
    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    warm =
      ["initialize", "server/diagnostics", "thread/loaded/list"] ++
        List.flatten(List.duplicate(["thread/start", "turn/start", "thread/read"], 6)) ++
        List.duplicate("thread/read", 6) ++ ["thread/loaded/list"]

    cold =
      ["initialize", "server/diagnostics", "thread/loaded/list"] ++
        List.flatten(List.duplicate(["thread/read", "thread/read", "thread/loaded/list"], 6))

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(ids) == 49
    assert length(Enum.uniq(ids)) == 49
    assert length(ledger.in) == 49
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp snapshot(path) do
    assert is_binary(path)
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
