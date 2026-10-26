defmodule SamgitaCodexDriver.NativeHistoryModeUnitInputTest do
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
  @instructions "Owned history-mode instructions λ."
  @answer "Deterministic local fixture answer"

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
      frames = Agent.get(state.capture, & &1)

      if length(frames) < 32 and byte_size(encoded) <= 4096 and
           Enum.reduce(frames, byte_size(encoded), &(byte_size(&1.encoded) + &2)) <= 131_072 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: JSON.decode!(encoded)}]))
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
    assert hash(File.read!(@script)) == @script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-history-units-#{System.unique_integer([:positive, :monotonic])}"
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
    configure_model(ctx, %{"model_messages" => %{"instructions_template" => @instructions}})
    config = Path.join(fixture.codex_home, "config.toml")
    catalog = Path.join(fixture.codex_home, "turn-models.json")
    capture = start_supervised!({Agent, fn -> [] end})

    Map.merge(ctx, %{
      capture: capture,
      config: config,
      config_bytes: File.read!(config),
      catalog: catalog,
      catalog_bytes: File.read!(catalog)
    })
  end

  test "all four native history-mode objects survive creation inference and unloaded cold reads",
       ctx do
    {pid, connection} = start_native(ctx)
    original = native_id(ctx, pid)

    prescribed =
      for mode <- ["legacy", "paginated"], payload <- [nil, %{}] do
        label = if is_nil(payload), do: "null", else: "empty"
        %{mode: mode, object: %{mode => payload}, marker: "Owned #{mode}-#{label} history λ🙂"}
      end

    rows =
      for row <- prescribed do
        params = %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.fixture.workspace,
          "ephemeral" => false,
          "historyMode" => row.object
        }

        response = request(ctx, pid, "thread/start", params)
        snapshot = response["thread"]
        assert is_binary(snapshot["id"]) and byte_size(snapshot["id"]) > 0
        assert Map.fetch!(snapshot, "historyMode") === row.mode
        assert snapshot["model"] == "mock-model"
        assert response["model"] == "mock-model" and response["modelProvider"] == "fixture"
        assert snapshot["cwd"] == ctx.fixture.workspace
        assert snapshot["turns"] == []
        assert ModelFixture.requests(ctx.fixture) == []
        Map.merge(row, %{id: snapshot["id"], path: snapshot["path"]})
      end

    assert length(Enum.uniq_by(rows, & &1.id)) == 4
    assert length(Enum.uniq_by(rows, & &1.path)) == 4

    events =
      await(pid, [], fn events -> Enum.all?(rows, &(length(started(events, &1.id)) == 1)) end)

    schema = notification_schema()

    for row <- rows do
      [event] = started(events, row.id)
      snapshot = event.wire["params"]["thread"]
      assert Map.fetch!(snapshot, "historyMode") === row.mode
      assert snapshot["model"] == "mock-model" and snapshot["cwd"] == ctx.fixture.workspace
      assert snapshot["path"] === row.path
      assert is_binary(row.path) and Path.type(row.path) == :absolute
      assert String.starts_with?(row.path, ctx.fixture.codex_home <> "/")
      assert String.contains?(Path.basename(row.path), row.id)
      assert snapshot["turns"] == [] and snapshot["preview"] == ""
      assert :ok = Schema.validate(schema, event.wire, max_depth: 32)
      assert {:ok, bytes} = Wire.encode(event.wire, max_depth: 32)
      assert {:ok, preserved} = Wire.decode(bytes, max_depth: 32)
      assert preserved === event.wire
    end

    assert length(Enum.filter(events, &(&1.wire["method"] == "thread/started"))) == 4

    refute Enum.any?(
             events,
             &(&1.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ])
           )

    assert ModelFixture.requests(ctx.fixture) == []

    {rows, events} =
      Enum.reduce(Enum.with_index(rows, 1), {[], events}, fn {row, index}, {previous, events} ->
        turn =
          request(ctx, pid, "turn/start", %{
            "threadId" => row.id,
            "input" => [%{"type" => "text", "text" => row.marker}]
          })["turn"]["id"]

        assert is_binary(turn) and byte_size(turn) > 0
        events = await(pid, events, &completed?(&1, row.id, turn))
        assert_turn(events, row, turn)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        assert_provider(List.last(requests), row, turn, Enum.map(prescribed, & &1.marker))
        row = Map.put(row, :turn, turn)
        assert_metadata(ctx, pid, row)
        history = history(ctx, pid, row)
        assert_history(history, row)
        assert_ready(pid)
        {previous ++ [Map.put(row, :history, history)], events}
      end)

    assert length(Enum.filter(events, &(&1.wire["method"] == "turn/completed"))) == 4
    journal = File.read!(ctx.fixture.requests)
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert :ok = StdioSessionFixture.close(pid, connection)
    refute File.exists?("/proc/#{original}")

    {cold, cold_connection} = start_native(ctx)
    replacement = native_id(ctx, cold)
    assert replacement != original
    assert request(ctx, cold, "thread/loaded/list", %{})["data"] == []

    for row <- rows do
      assert_metadata(ctx, cold, row)
      assert history(ctx, cold, row) === row.history
      assert File.read!(ctx.fixture.requests) === journal
    end

    assert request(ctx, cold, "thread/loaded/list", %{})["data"] == []
    assert_ready(cold)
    frames = Agent.get(ctx.capture, & &1)
    assert Enum.count(frames, &(&1.wire["method"] == "thread/start")) == 4
    assert Enum.count(frames, &(&1.wire["method"] == "turn/start")) == 4
    assert File.read!(ctx.config) === ctx.config_bytes
    assert File.read!(ctx.catalog) === ctx.catalog_bytes
    assert hash(File.read!(@script)) == @script_sha
    assert File.ls!(ctx.fixture.workspace) == []
    assert :ok = StdioSessionFixture.close(cold, cold_connection)
    refute File.exists?("/proc/#{replacement}")
    assert File.read!(ctx.fixture.requests) === journal
  end

  defp assert_metadata(ctx, pid, row) do
    saved =
      request(ctx, pid, "thread/read", %{"threadId" => row.id, "includeTurns" => false})["thread"]

    assert saved["id"] == row.id
    assert Map.fetch!(saved, "historyMode") === row.mode
    assert Map.fetch!(saved, "path") === row.path
    assert Map.fetch!(saved, "preview") === row.marker
    assert saved["ephemeral"] === false
    assert File.regular?(row.path)
  end

  defp history(ctx, pid, row) do
    page =
      request(ctx, pid, "thread/turns/list", %{
        "threadId" => row.id,
        "limit" => 1,
        "itemsView" => "full"
      })

    assert Map.fetch!(page, "nextCursor") === nil
    assert [turn] = Map.fetch!(page, "data")
    assert turn["id"] == row.turn
    [turn]
  end

  defp assert_history(history, row) do
    assert [%{"id" => id, "status" => "completed", "items" => items}] = history
    assert id == row.turn
    assert [user, %{"type" => "agentMessage", "text" => @answer}] = items
    assert user["type"] == "userMessage"
    assert user["content"] == [%{"type" => "text", "text" => row.marker, "text_elements" => []}]
  end

  defp assert_provider(request, row, turn, markers) do
    assert request["model"] == "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    assert metadata["thread_id"] == row.id and metadata["turn_id"] == turn

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.filter(user_texts, &(&1 in markers)) === [row.marker]

    for marker <- markers -- [row.marker],
        do: refute(Enum.any?(user_texts, &String.contains?(&1, marker)))

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
    id = "owned-history-unit-#{System.unique_integer([:positive, :monotonic])}"
    before = length(Agent.get(ctx.capture, & &1))

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == before + 1
    frame = List.last(frames)
    assert frame.wire === %{"id" => id, "method" => method, "params" => params}
    assert JSON.decode!(frame.encoded) === frame.wire
    assert {:ok, encoded} = Wire.encode(frame.wire)
    assert encoded === frame.encoded
    result
  end

  defp started(events, id),
    do:
      Enum.filter(
        events,
        &(&1.wire["method"] == "thread/started" and
            get_in(&1.wire, ["params", "thread", "id"]) == id)
      )

  defp completed?(events, id, turn),
    do:
      Enum.any?(
        events,
        &(&1.wire["method"] == "turn/completed" and &1.wire["params"]["threadId"] == id and
            get_in(&1.wire, ["params", "turn", "id"]) == turn)
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
      assert remaining > 0, "Native history-mode input event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native event gap")
      after
        remaining -> flunk("Native history-mode input event deadline")
      end

      await(pid, events, predicate, deadline)
    end
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

  defp native_id(ctx, pid) do
    id = request(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(id) and id > 0
    assert hash(File.read!("/proc/#{id}/exe")) == @binary_sha
    id
  end

  defp start_native(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             executable: ctx.binary,
             capture: ctx.capture,
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
               %{"name" => "owned_history_mode_units", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true,
                 "optOutNotificationMethods" => ["remoteControl/status/changed"]
               }
             )

    {pid, connection}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
