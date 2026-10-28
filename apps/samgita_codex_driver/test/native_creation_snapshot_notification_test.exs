defmodule SamgitaCodexDriver.NativeCreationSnapshotNotificationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [configure_model: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @client "owned_creation_snapshot"
  @answer "Deterministic local fixture answer"

  # Owner2432 only: actual explicit null; nonnull Thread.extra remains unqualified.
  @thread_extra_root_sha "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1"
  @thread_extra_node_sha "055911a6e5dbc43a92b9ebb1a7b96c4d552255f35696d407b710de67bbbe797e"
  @thread_extra_node_bytes """
  {
    "anyOf": [
      {
        "$ref": "#/definitions/ThreadExtra"
      },
      {
        "type": "null"
      }
    ],
    "description": "Optional implementation-specific thread data."
  }
  """

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
      if room?(state, encoded) do
        with {:ok, next} <- Stdio.send(state, encoded) do
          record(next, :outgoing, encoded, JSON.decode!(encoded))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case capture_started(events, next) do
            :ok -> {:ok, events, next}
            :overflow -> {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), next}
          end

        other ->
          other
      end
    end

    defp capture_started(events, state) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          capture_started_frame(state, encoded, JSON.decode!(encoded))

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp capture_started_frame(state, encoded, %{"method" => "thread/started"} = wire) do
      if room?(state, encoded) do
        record(state, :incoming, encoded, wire)
        {:cont, :ok}
      else
        {:halt, :overflow}
      end
    end

    defp capture_started_frame(_state, _encoded, _wire), do: {:cont, :ok}

    defp room?(state, encoded) do
      frames = Agent.get(state.capture, & &1)

      length(frames) < 32 and byte_size(encoded) <= 4096 and
        Enum.reduce(frames, byte_size(encoded), &(byte_size(&1.encoded) + &2)) <= 131_072
    end

    defp record(state, direction, encoded, wire) do
      Agent.update(
        state.capture,
        &(&1 ++ [%{direction: direction, encoded: encoded, wire: wire}])
      )
    end

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
    assert hash(File.read!(@script)) == @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-creation-snapshot-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
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

    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, fixture: fixture, root: root}
    configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")
    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native creation snapshots retain distinct project and history choices before inference",
       ctx do
    {pid, connection} = start_native(ctx)
    native = request(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha

    prescribed = [
      %{
        name: "Owned creation A λ",
        key: "owned-creation-a",
        history: "legacy",
        marker: "Owned first creation λ🙂"
      },
      %{
        name: "Owned creation B β",
        key: "owned-creation-b",
        history: "paginated",
        marker: "Owned second creation β🙂"
      }
    ]

    projects =
      for row <- prescribed do
        cwd = Path.join(ctx.fixture.workspace, row.key)
        File.mkdir!(cwd)
        params = %{"name" => row.name, "roots" => [%{"path" => cwd}], "idempotencyKey" => row.key}
        project = request(ctx, pid, "project/create", params)["project"]
        assert project["name"] == row.name
        assert project["roots"] == params["roots"]
        assert is_binary(project["id"]) and byte_size(project["id"]) > 0
        Map.merge(row, %{cwd: cwd, project: project["id"]})
      end

    assert length(Enum.uniq_by(projects, & &1.project)) == 2
    assert ModelFixture.requests(ctx.fixture) == []

    # Both configurations and expected values precede the first user turn.
    rows =
      for row <- projects do
        params = %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => row.cwd,
          "ephemeral" => false,
          "projectId" => row.project,
          "historyMode" => row.history,
          "daybreakEnabled" => false
        }

        before_ms = System.system_time(:millisecond)
        before = System.system_time(:second)
        response = request(ctx, pid, "thread/start", params)
        after_time = System.system_time(:second)
        id = response["thread"]["id"]
        assert is_binary(id) and byte_size(id) > 0

        Map.merge(row, %{
          id: id,
          response: response["thread"],
          before: before,
          after: after_time,
          before_ms: before_ms
        })
      end

    assert length(Enum.uniq_by(rows, & &1.id)) == 2
    assert ModelFixture.requests(ctx.fixture) == []

    events =
      await(pid, [], fn events ->
        Enum.all?(rows, fn row -> length(notices(events, "thread/started", row.id)) == 1 end)
      end)

    assert length(Enum.filter(events, &(&1.wire["method"] == "thread/started"))) == 2

    refute Enum.any?(
             events,
             &(&1.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ])
           )

    schema = notification_schema()
    notice_upper_ms = System.system_time(:millisecond)
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)

    rows =
      for row <- rows do
        [event] = notices(events, "thread/started", row.id)
        snapshot = event.wire["params"]["thread"]
        assert snapshot === row.response
        expected = assert_creation(ctx, row, snapshot)
        assert event.kind == :notification and event.generation == generation
        emitted_at = Map.fetch!(event.wire, "emittedAtMs")

        assert is_integer(emitted_at) and emitted_at >= row.before_ms and
                 emitted_at <= notice_upper_ms

        assert event.wire === %{
                 "method" => "thread/started",
                 "params" => %{"thread" => expected},
                 "emittedAtMs" => emitted_at
               }

        assert :ok = Schema.validate(schema, event.wire, max_depth: 32)
        assert {:ok, encoded} = Wire.encode(event.wire, max_depth: 32)
        assert {:ok, preserved} = Wire.decode(encoded, max_depth: 32)
        assert preserved === event.wire
        Map.merge(row, %{snapshot: snapshot, event: event, event_bytes: encoded})
      end

    original_started = assert_original_started(ctx, rows)
    assert length(Enum.uniq_by(rows, & &1.snapshot["path"])) == 2
    assert ModelFixture.requests(ctx.fixture) == []
    assert_ready(pid)

    # First real messages materialize native metadata; they do not manufacture
    # the creation snapshots above. The provider fixture remains unchanged.
    {finished, events} =
      Enum.reduce(Enum.with_index(rows, 1), {[], events}, fn {row, index}, {previous, events} ->
        params = %{"threadId" => row.id, "input" => [%{"type" => "text", "text" => row.marker}]}
        turn = request(ctx, pid, "turn/start", params)["turn"]["id"]
        assert is_binary(turn) and byte_size(turn) > 0

        events =
          await(pid, events, fn events ->
            Enum.any?(events, fn event ->
              event.wire["method"] == "turn/completed" and
                event.wire["params"]["threadId"] == row.id and
                get_in(event.wire, ["params", "turn", "id"]) == turn
            end)
          end)

        assert_turn(events, row, turn)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        assert_provider(List.last(requests), row, turn, Enum.map(rows, & &1.marker))
        saved = metadata(ctx, pid, row)

        for prior <- previous do
          assert metadata(ctx, pid, prior) === prior.saved

          assert request(ctx, pid, "thread/read", %{
                   "threadId" => prior.id,
                   "includeTurns" => true
                 })["thread"]["turns"] === prior.turns
        end

        turns =
          if row.history == "legacy" do
            history =
              request(ctx, pid, "thread/read", %{"threadId" => row.id, "includeTurns" => true})[
                "thread"
              ]["turns"]

            assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = history
            assert [user, %{"type" => "agentMessage", "text" => @answer}] = items
            assert user["type"] == "userMessage"

            assert user["content"] == [
                     %{"type" => "text", "text" => row.marker, "text_elements" => []}
                   ]

            history
          else
            nil
          end

        assert {:ok, bytes} = Wire.encode(row.event.wire, max_depth: 32)
        assert bytes === row.event_bytes
        assert row.event.wire["params"]["thread"]["preview"] === ""
        assert_ready(pid)
        {previous ++ [Map.merge(row, %{saved: saved, turns: turns})], events}
      end)

    assert length(finished) == 2
    for row <- finished, do: assert(metadata(ctx, pid, row) === row.saved)
    assert length(Enum.filter(events, &(&1.wire["method"] == "turn/completed"))) == 2
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    frames = captured(ctx, :outgoing)
    assert Enum.count(frames, &(&1.wire["method"] == "project/create")) == 2
    assert Enum.count(frames, &(&1.wire["method"] == "thread/start")) == 2
    assert Enum.count(frames, &(&1.wire["method"] == "turn/start")) == 2
    assert File.read!(ctx.config) === ctx.config_bytes
    assert hash(File.read!(@script)) == @script_sha
    for row <- rows, do: assert(File.ls!(row.cwd) == [])
    journal = File.read!(ctx.fixture.requests)
    assert :ok = StdioSessionFixture.close(pid, connection)
    refute File.exists?("/proc/#{native}")
    assert File.read!(ctx.fixture.requests) === journal
    assert assert_original_started(ctx, rows) === original_started
  end

  defp assert_creation(ctx, row, snapshot) do
    assert snapshot["id"] == row.id

    assert Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
             row.id
           )

    assert Map.fetch!(snapshot, "source") === "vscode"
    assert Map.fetch!(snapshot, "cliVersion") === "0.163.0"
    assert Map.fetch!(snapshot, "daybreakEnabled") === false
    assert Map.fetch!(snapshot, "historyMode") === row.history
    assert Map.fetch!(snapshot, "model") === "mock-model"
    assert Map.fetch!(snapshot, "originator") === @client
    assert Map.fetch!(snapshot, "projectId") === row.project
    assert Map.fetch!(snapshot, "preview") === ""
    assert snapshot["cwd"] == row.cwd
    assert snapshot["turns"] == []
    now = Map.fetch!(snapshot, "recencyAt")
    assert is_integer(now) and now > 0 and now >= row.before and now <= row.after
    assert snapshot["createdAt"] === now and snapshot["updatedAt"] === now
    path = Map.fetch!(snapshot, "path")
    assert is_binary(path) and Path.type(path) == :absolute
    assert String.starts_with?(path, ctx.fixture.codex_home <> "/")
    assert String.contains?(Path.basename(path), row.id)
    refute File.exists?(path)

    assert [_, year, month, day, file_date, clock, path_id] =
             Regex.run(
               ~r"\Asessions/([0-9]{4})/([0-9]{2})/([0-9]{2})/rollout-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}-[0-9]{2}-[0-9]{2})-([0-9a-f-]{36})\.jsonl\z",
               Path.relative_to(path, ctx.fixture.codex_home)
             )

    assert file_date === Enum.join([year, month, day], "-")
    assert path_id === row.id

    assert {:ok, path_at, 0} =
             DateTime.from_iso8601(file_date <> "T" <> String.replace(clock, "-", ":") <> "Z")

    path_seconds = DateTime.to_unix(path_at)
    assert path_seconds >= row.before and path_seconds <= row.after

    expected = %{
      "id" => row.id,
      "sessionId" => row.id,
      "environments" => [
        %{"environmentId" => "local", "cwd" => row.cwd, "runtimeWorkspaceRoots" => [row.cwd]}
      ],
      "extra" => nil,
      "forkedFromId" => nil,
      "parentThreadId" => nil,
      "section" => nil,
      "sectionEnteredAt" => nil,
      "reasoningEffort" => nil,
      "threadSource" => nil,
      "agentNickname" => nil,
      "agentRole" => nil,
      "gitInfo" => nil,
      "name" => nil,
      "preview" => "",
      "turns" => [],
      "ephemeral" => false,
      "daybreakEnabled" => false,
      "projectId" => row.project,
      "historyMode" => row.history,
      "cwd" => row.cwd,
      "modelProvider" => "fixture",
      "model" => "mock-model",
      "cliVersion" => "0.163.0",
      "originator" => @client,
      "source" => "vscode",
      "canAcceptDirectInput" => true,
      "status" => %{"type" => "idle"},
      "createdAt" => now,
      "updatedAt" => now,
      "recencyAt" => now,
      "path" => path
    }

    assert map_size(expected) == 32
    assert snapshot === expected
    expected
  end

  defp assert_original_started(ctx, rows) do
    frames = captured(ctx, :incoming)
    assert length(frames) == 2

    assert Enum.map(frames, & &1.wire) ===
             Enum.map(Enum.sort_by(rows, & &1.event.sequence), & &1.event.wire)

    for frame <- frames do
      assert JSON.decode!(frame.encoded) === frame.wire
      assert_thread_extra_binding(frame.wire)
    end

    frames
  end

  defp captured(ctx, direction),
    do: Agent.get(ctx.capture, &Enum.filter(&1, fn frame -> frame.direction == direction end))

  defp metadata(ctx, pid, row) do
    saved =
      request(ctx, pid, "thread/read", %{"threadId" => row.id, "includeTurns" => false})["thread"]

    for key <- [
          "projectId",
          "daybreakEnabled",
          "historyMode",
          "model",
          "originator",
          "source",
          "path"
        ] do
      assert Map.fetch!(saved, key) === Map.fetch!(row.snapshot, key)
    end

    assert Map.fetch!(saved, "preview") === row.marker
    assert File.regular?(saved["path"])
    # A real turn may change recency/updatedAt. Only the prescribed immutable
    # selection and materialized preview are compared across the other thread.
    Map.take(saved, [
      "id",
      "projectId",
      "daybreakEnabled",
      "historyMode",
      "model",
      "originator",
      "source",
      "path",
      "preview"
    ])
  end

  defp assert_provider(request, row, turn, markers) do
    assert request["model"] == "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    assert metadata["thread_id"] == row.id and metadata["turn_id"] == turn

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.filter(user_texts, &(&1 in markers)) === [row.marker]

    for marker <- markers -- [row.marker],
        do: refute(String.contains?(JSON.encode!(request["input"]), marker))

    refute Enum.any?(request["input"], &(&1["type"] in ["function_call", "function_call_output"]))
  end

  defp assert_turn(events, row, turn) do
    [event] =
      Enum.filter(
        events,
        &(&1.wire["method"] == "turn/completed" and &1.wire["params"]["threadId"] == row.id)
      )

    assert %{"id" => ^turn, "status" => "completed"} = event.wire["params"]["turn"]

    assert [assistant] =
             Enum.filter(
               events,
               &(&1.wire["method"] == "item/completed" and &1.wire["params"]["threadId"] == row.id and
                   get_in(&1.wire, ["params", "item", "type"]) == "agentMessage")
             )

    assert assistant.wire["params"]["turnId"] == turn
    assert assistant.wire["params"]["item"]["text"] === @answer
  end

  defp request(ctx, pid, method, params) do
    id = "owned-creation-#{System.unique_integer([:positive, :monotonic])}"
    before = length(captured(ctx, :outgoing))

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    frames = captured(ctx, :outgoing)
    assert length(frames) == before + 1
    frame = List.last(frames)
    assert frame.wire === %{"id" => id, "method" => method, "params" => params}
    assert JSON.decode!(frame.encoded) === frame.wire
    result
  end

  defp notices(events, method, id),
    do:
      Enum.filter(
        events,
        &(&1.wire["method"] == method and get_in(&1.wire, ["params", "thread", "id"]) == id)
      )

  defp await(pid, events, predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 20_000
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert length(Enum.uniq_by(events, & &1.wire["method"])) <= 32
    assert Enum.all?(events, &(&1.generation == generation and &1.kind == :notification))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.sort(Enum.uniq(sequences))
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))

    if predicate.(events) do
      events
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Native creation snapshot event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native event gap")
      after
        remaining -> flunk("Native creation snapshot event deadline")
      end

      await(pid, events, predicate, deadline)
    end
  end

  defp assert_thread_extra_binding(original) do
    bytes =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
      |> File.read!()

    assert hash(bytes) === @thread_extra_root_sha
    document = JSON.decode!(bytes)
    node = get_in(document, ["definitions", "Thread", "properties", "extra"])
    assert hash(@thread_extra_node_bytes) === @thread_extra_node_sha
    assert JSON.decode!(@thread_extra_node_bytes) === node

    # The full independently prescribed creation snapshot already requires null.
    # Read it from the original notification; absence cannot qualify this field.
    actual =
      original
      |> Map.fetch!("params")
      |> Map.fetch!("thread")
      |> Map.fetch!("extra")

    assert actual === nil

    assert :ok =
             Schema.validate(
               Map.put(node, "definitions", Map.fetch!(document, "definitions")),
               actual,
               max_depth: 32
             )
  end

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp assert_ready(pid),
    do:
      assert(
        %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
          Session.status(pid)
      )

  defp start_native(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             capture: ctx.capture,
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off",
               "TZ" => "UTC"
             }
           ]}
      )

    connection = :sys.get_state(pid).connection

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(connection.owner.completion, 1) == 1
      assert Port.info(connection.port) == nil
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => @client, "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "optOutNotificationMethods" => ["remoteControl/status/changed"]
               }
             )

    {pid, connection}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
