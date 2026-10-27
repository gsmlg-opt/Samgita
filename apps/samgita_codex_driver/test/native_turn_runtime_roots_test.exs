defmodule SamgitaCodexDriver.NativeTurnRuntimeRootsTest do
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
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary runtime-root context metadata instructions."

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
      case JSON.decode(encoded) do
        {:ok, wire} ->
          if selected?(direction, wire),
            do: Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire)),
            else: :ok

        _ ->
          :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      frames = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(frames) < 32 and size <= limit and ledger.bytes + size <= 1_048_576 do
        next =
          ledger
          |> Map.put(direction, frames ++ [%{encoded: encoded, wire: wire}])
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
      "supports_reasoning_summary_parameter" => true,
      "default_reasoning_summary" => "auto",
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

    roots = [Path.join(ctx.root, "owned-root-a λ"), Path.join(ctx.root, "owned-root-b λ")]
    for root <- roots, do: File.mkdir!(root)

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
    Map.merge(ctx, %{capture: capture, inputs: inputs, roots: roots})
  end

  test "ordinary turn roots preserve ordered replacement omission null and explicit empty metadata",
       ctx do
    session = start(ctx)
    pid = session.pid

    initial =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]

    thread = Map.fetch!(initial, "id")
    assert is_binary(thread) and thread != ""
    assert ModelFixture.requests(ctx.fixture) == []
    [a, b] = ctx.roots

    cases = [
      {%{"runtimeWorkspaceRoots" => [b, a, b]}, [b, a], "replace"},
      {%{}, [b, a], "omitted"},
      {%{"runtimeWorkspaceRoots" => nil}, [b, a], "null"},
      {%{"runtimeWorkspaceRoots" => []}, [], "empty"}
    ]

    turns =
      Enum.reduce(Enum.with_index(cases, 1), [], fn {{extra, expected, label}, index}, prior ->
        marker = "Owned ordinary turn roots #{label} λ"

        params =
          Map.merge(
            %{"threadId" => thread, "input" => [%{"type" => "text", "text" => marker}]},
            extra
          )

        turn = call(ctx, pid, "turn/start", params)["turn"]["id"]
        assert is_binary(turn) and turn != ""
        assert_turn_request(ctx, params, extra, index)
        events = collect(pid, &completed?(&1, thread, turn), deadline(20_000))
        row = assert_turn(events, thread, turn, marker)
        assert_provider(ctx, index, thread, turn, marker)
        summary_snapshot(ctx, pid, thread, index)
        rows = prior ++ [row]
        saved = read(ctx, pid, thread)
        assert_environment(ctx, saved, expected)
        assert_history(saved, thread, rows)
        assert_inputs(ctx)
        rows
      end)

    assert length(Enum.uniq_by(turns, & &1.id)) == 4
    ids = Enum.flat_map(turns, &Enum.map(&1.items, fn item -> item["id"] end))
    assert length(ids) == 8 and length(Enum.uniq(ids)) == 8
    final = read(ctx, pid, thread)
    assert_environment(ctx, final, [])
    assert_history(final, thread, turns)
    assert read(ctx, pid, thread) === final
    assert call(ctx, pid, "thread/loaded/list", %{}) == %{"data" => [thread], "nextCursor" => nil}
    rollout = snapshot(Map.fetch!(final, "path"))
    journal = snapshot(ctx.fixture.requests)
    assert_idle(ctx, pid)
    assert_inventory(ctx)
    assert_retained(ctx, final["path"], rollout, journal)

    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
    assert_retained(ctx, final["path"], rollout, journal)
  end

  defp assert_turn_request(ctx, params, extra, index) do
    requests = captured(ctx, "turn/start")
    assert length(requests) == index
    assert List.last(requests).wire["params"] === params

    assert Map.has_key?(params, "runtimeWorkspaceRoots") ==
             Map.has_key?(extra, "runtimeWorkspaceRoots")
  end

  defp assert_turn(events, thread, turn, marker) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             TurnFixture.notification(events, "turn/started", &(&1["turn"]["id"] == turn))

    completed = items(events, "item/completed", thread, turn)
    assert [user, assistant] = completed
    assert Map.fetch!(user, "type") == "userMessage"

    assert Map.fetch!(user, "content") == [
             %{"type" => "text", "text" => marker, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "type") == "agentMessage"
    assert Map.fetch!(assistant, "text") == @answer

    assert Enum.map(items(events, "item/started", thread, turn), &Map.take(&1, ~w(id type))) ==
             Enum.map(completed, &Map.take(&1, ~w(id type)))

    assert Enum.all?(completed, &(is_binary(&1["id"]) and &1["id"] != ""))
    refute user["id"] == assistant["id"]
    %{id: turn, marker: marker, items: completed}
  end

  defp items(events, method, thread, turn) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["threadId"] == thread,
        event.wire["params"]["turnId"] == turn,
        do: event.wire["params"]["item"]
  end

  defp assert_provider(ctx, index, thread, turn, marker) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == index
    request = List.last(requests)
    assert Map.fetch!(request, "model") == "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ~w(thread_id turn_id)) == %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(texts, &(&1 == marker)) == 1
  end

  # This summary-only update supplies a matching native snapshot barrier;
  # it does not supply or rewrite the target root vector.
  defp summary_snapshot(ctx, pid, thread, index) do
    journal = snapshot(ctx.fixture.requests)
    summary = if rem(index, 2) == 1, do: "concise", else: "detailed"
    params = %{"threadId" => thread, "summary" => summary}
    assert call(ctx, pid, "thread/settings/update", params) == %{}

    events =
      collect(
        pid,
        fn events ->
          TurnFixture.notification(events, "thread/settings/updated", fn item ->
            item["threadId"] == thread and item["threadSettings"]["summary"] == summary
          end)
        end,
        deadline(5_000)
      )

    applied =
      TurnFixture.notification(events, "thread/settings/updated", fn item ->
        item["threadId"] == thread and item["threadSettings"]["summary"] == summary
      end)["threadSettings"]

    assert Map.take(applied, ~w(model modelProvider summary)) == %{
             "model" => "mock-model",
             "modelProvider" => "fixture",
             "summary" => summary
           }

    assert snapshot(ctx.fixture.requests) === journal
  end

  defp assert_environment(ctx, saved, roots) do
    assert Map.fetch!(saved, "status") == %{"type" => "idle"}
    assert Map.fetch!(saved, "cwd") == ctx.fixture.workspace

    assert Map.fetch!(saved, "environments") === [
             %{
               "environmentId" => "local",
               "cwd" => ctx.fixture.workspace,
               "runtimeWorkspaceRoots" => roots
             }
           ]
  end

  defp assert_history(saved, thread, rows) do
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"
    turns = Map.fetch!(saved, "turns")
    assert Enum.map(turns, & &1["id"]) == Enum.map(rows, & &1.id)

    for {turn, row} <- Enum.zip(turns, rows) do
      assert Map.take(turn, ~w(id status error)) == %{
               "id" => row.id,
               "status" => "completed",
               "error" => nil
             }

      assert Map.fetch!(turn, "items") === row.items
    end
  end

  defp collect(pid, predicate, until, events \\ []) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_events(events)
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if predicate.(events) do
      events
    else
      remaining = until - System.monotonic_time(:millisecond)
      assert remaining > 0, "native runtime-root metadata event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, until, events)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native runtime-root metadata gap")
      after
        remaining -> flunk("native runtime-root metadata event deadline")
      end
    end
  end

  defp completed?(events, thread, turn),
    do:
      TurnFixture.notification(
        events,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp assert_events(events) do
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert Enum.all?(events, &(&1.kind == :notification))
    refute Enum.any?(events, &(&1.wire["method"] == "error"))
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp call(ctx, pid, method, params) do
    id = "owned-turn-roots-#{System.unique_integer([:positive, :monotonic])}"
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

  defp captured(ctx, method),
    do:
      Agent.get(ctx.capture, &Enum.filter(&1.out, fn entry -> entry.wire["method"] == method end))

  defp start(ctx) do
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
    info = %{"name" => "owned_turn_runtime_roots", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, timeout_ms: 5_000)

    assert [sent] = captured(ctx, "initialize")
    assert sent.wire["params"] === %{"clientInfo" => info, "capabilities" => capabilities}
    assert_exchange(ctx, sent.wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, native: native, connection: connection}
  end

  defp assert_idle(ctx, pid) do
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert {:ok, remaining} = Session.drain(pid, 256)
    assert_events(remaining)
    assert {:ok, []} = Session.drain(pid, 256)

    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil,
             buffered_events: 0
           } =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    methods =
      ["initialize", "server/diagnostics", "thread/start"] ++
        List.flatten(List.duplicate(["turn/start", "thread/settings/update", "thread/read"], 4)) ++
        ["thread/read", "thread/read", "thread/loaded/list"]

    assert Enum.map(ledger.out, & &1.wire["method"]) === methods
    assert length(methods) == 18 and length(ledger.in) == 18
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 18
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_inputs(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    for directory <- [ctx.fixture.workspace | ctx.roots], do: assert(File.ls!(directory) == [])
  end

  defp assert_retained(ctx, path, rollout, journal) do
    assert_inputs(ctx)
    assert snapshot(path) === rollout
    assert snapshot(ctx.fixture.requests) === journal
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
