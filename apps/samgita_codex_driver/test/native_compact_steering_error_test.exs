defmodule SamgitaCodexDriver.NativeCompactSteeringErrorTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/compaction_control_fixture.py", __DIR__)
  @model_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "e3c10ec249849d45ff4341b2766b4629316ffb0e290134bf501fcfecc9d07b17"
  @model_script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @before "Owned compact steering source 163 λ"
  @rejected "Owned compact steering rejected input must never execute 163 λ"
  @continuation "Owned continuation after intentional compact interruption 163 λ"
  @cold "Owned cold continuation after rejected compact steering 163 λ"
  @answer "Deterministic local fixture answer"
  @late "SYNTHETIC_CANCELLED_COMPACTION_CHECKPOINT"
  @request_id "owned-nonsteerable-compact-163"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(binary) == @binary_sha
    assert hash(@script) == @script_sha
    assert hash(@model_script) == @model_script_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-compact-steering-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "hold")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    File.mkdir!(Path.join(root, "tmp"))

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    unchanged =
      Enum.map([@script, @model_script, Path.join(fixture.codex_home, "config.toml")], fn path ->
        {path, File.read!(path)}
      end)

    %{binary: binary, root: root, fixture: fixture, unchanged: unchanged}
  end

  test "native compact steering returns exact RPC data without consuming input or changing work",
       ctx do
    source = start(ctx)
    native = native_process(source)

    thread =
      call(source, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access",
        "historyMode" => "legacy",
        "ephemeral" => false
      })["thread"]["id"]

    seed_turn = start_turn(source, thread, @before)
    seed_events = finish_turn(source, thread, seed_turn)
    assert [seed_request] = requests(ctx)
    assert Enum.count(input_texts(seed_request), &(&1 == @before)) == 1
    assert_no_effects(ctx, source, seed_events)

    # Submission acknowledgement is not readiness. The provider must actually
    # hold the real native compaction request and native must report its item/turn.
    assert call(source, "thread/compact/start", %{"threadId" => thread}) === %{}
    {held, barrier_buffer} = next_notice(ctx.fixture.port, "", now() + 20_000)
    assert held === %{"event" => "compaction_held", "index" => 2, "attempt" => 1}
    started = collect(source, &compaction_started?(&1, thread), [], now() + 20_000)

    assert %{"threadId" => ^thread, "turnId" => compact_turn, "item" => %{"id" => compact_item}} =
             compaction_started?(started, thread)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^compact_turn, "status" => "inProgress"}} =
             notification(started, "turn/started", &(&1["turn"]["id"] == compact_turn))

    refute terminal(started, compact_turn)
    assert [^seed_request, compact_request] = requests(ctx)
    assert compaction_request?(compact_request)
    assert @before in input_texts(compact_request)

    # This is a real rejected state update, not an injected ErrorNotification.
    # The pin returns a TurnError value under untyped JSON-RPC error.data.
    assert {:error, %Error{code: :upstream_error, wire: wire}} =
             Session.request(
               source,
               "turn/steer",
               %{
                 "threadId" => thread,
                 "expectedTurnId" => compact_turn,
                 "input" => [%{"type" => "text", "text" => @rejected, "text_elements" => []}]
               },
               id: @request_id
             )

    assert wire === %{
             "id" => @request_id,
             "error" => %{
               "code" => -32_600,
               "message" => "cannot steer a compact turn",
               "data" => %{
                 "message" => "cannot steer a compact turn",
                 "codexErrorInfo" => %{"activeTurnNotSteerable" => %{"turnKind" => "compact"}},
                 "additionalDetails" => nil,
                 "misalignment" => nil
               }
             }
           }

    assert {:ok, after_rejection} = Session.drain(source, 256)
    started = started ++ after_rejection
    assert_events(source, started)
    refute terminal(started, compact_turn)
    assert requests(ctx) === [seed_request, compact_request]
    assert_no_effects(ctx, source, started)

    # Rejection must leave the same compaction active. Cancellation below is a
    # separate explicit operator action, never a retry/timeout side effect.
    assert call(source, "turn/interrupt", %{"threadId" => thread, "turnId" => compact_turn}) ===
             %{}

    interrupted = collect(source, &terminal(&1, compact_turn), started, now() + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^compact_turn, "status" => "interrupted"}} =
             terminal(interrupted, compact_turn)

    assert_one_terminal(interrupted, compact_turn, "interrupted")

    assert notification(
             interrupted,
             "item/started",
             &(&1["turnId"] == compact_turn and &1["item"]["id"] == compact_item)
           )

    assert requests(ctx) === [seed_request, compact_request]
    assert Port.command(ctx.fixture.port, JSON.encode!(%{"release" => true}) <> "\n")
    {released, remainder} = next_notice(ctx.fixture.port, barrier_buffer, now() + 20_000)

    assert %{"event" => "late_output_released", "index" => 2, "outcome" => outcome} = released
    assert outcome in ["written", "peer_closed"]
    assert remainder === ""
    assert requests(ctx) === [seed_request, compact_request]

    accepted_turn = start_turn(source, thread, @continuation)
    accepted_events = finish_turn(source, thread, accepted_turn)
    assert [^seed_request, ^compact_request, ordinary] = requests(ctx)
    assert @before in input_texts(ordinary) and @continuation in input_texts(ordinary)
    refute @rejected in input_texts(ordinary)
    assert checkpoints(ordinary) === []
    refute compaction_request?(ordinary)
    assert_one_terminal(interrupted ++ accepted_events, compact_turn, "interrupted")
    assert_no_effects(ctx, source, interrupted ++ accepted_events)

    source_path = read_thread(source, thread)["path"]
    assert :ok = Session.close(source)
    assert_gone(native)
    assert_history(ctx, source_path)
    assert_unchanged(ctx)

    cold = start(ctx)
    cold_native = native_process(cold)
    refute cold_native == native
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert call(cold, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert requests(ctx) === [seed_request, compact_request, ordinary]
    assert read_thread(cold, thread)["path"] == source_path

    cold_turn = start_turn(cold, thread, @cold)
    cold_events = finish_turn(cold, thread, cold_turn)
    assert [^seed_request, ^compact_request, ^ordinary, continued] = requests(ctx)
    assert @before in input_texts(continued)
    assert @continuation in input_texts(continued) and @cold in input_texts(continued)
    refute @rejected in input_texts(continued)
    assert checkpoints(continued) === []
    refute compaction_request?(continued)
    assert_no_effects(ctx, cold, cold_events)
    assert :ok = Session.close(cold)
    assert_gone(cold_native)
    assert_history(ctx, source_path)
    assert_unchanged(ctx)
  end

  defp start_turn(pid, thread, text),
    do:
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text, "text_elements" => []}]
      })["turn"]["id"]

  defp finish_turn(pid, thread, turn) do
    events = collect(pid, &terminal(&1, turn), [], now() + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             terminal(events, turn)

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"type" => "agentMessage", "text" => @answer}
           } =
             notification(events, "item/completed", &(&1["item"]["type"] == "agentMessage"))

    assert_one_terminal(events, turn, "completed")
    events
  end

  defp collect(pid, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_events(pid, events)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "Native compact-steering event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, predicate, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected native compact-steering event gap")
      after
        max(deadline - now(), 0) -> flunk("Native compact-steering event deadline")
      end
    end
  end

  defp assert_events(pid, events) do
    assert %{phase: :ready, gap: nil} = Session.status(pid)
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
  end

  defp next_notice(port, buffer, deadline) do
    assert byte_size(buffer) <= 16_384

    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        assert byte_size(line) <= 1_024
        {JSON.decode!(line), rest}

      _ ->
        assert now() < deadline, "Native compaction provider barrier deadline"

        receive do
          {^port, {:data, bytes}} -> next_notice(port, buffer <> bytes, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned compact provider exited: #{status}")
        after
          max(deadline - now(), 0) -> flunk("Native compaction provider barrier deadline")
        end
    end
  end

  defp compaction_started?(events, thread),
    do:
      notification(events, "item/started", fn params ->
        params["threadId"] == thread and params["item"]["type"] == "contextCompaction"
      end)

  defp terminal(events, turn),
    do: notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp assert_one_terminal(events, turn, status) do
    assert [event] =
             Enum.filter(events, fn event ->
               event.wire["method"] == "turn/completed" and
                 get_in(event.wire, ["params", "turn", "id"]) == turn
             end)

    assert get_in(event.wire, ["params", "turn", "status"]) == status
  end

  defp requests(ctx) do
    assert %{type: :regular, size: size} = File.stat!(ctx.fixture.requests)
    assert size <= @max_file_bytes
    rows = ModelFixture.requests(ctx.fixture)
    assert length(rows) <= 4
    refute JSON.encode!(rows) =~ @rejected
    refute JSON.encode!(rows) =~ @late
    rows
  end

  defp input_texts(request) do
    for %{"role" => "user", "content" => content} <- request["input"],
        %{"type" => "input_text", "text" => text} <- content,
        do: text
  end

  defp compaction_request?(request),
    do: Enum.any?(request["input"], &(&1["type"] == "compaction_trigger"))

  defp checkpoints(request),
    do: Enum.filter(request["input"], &(&1["type"] == "compaction"))

  defp read_thread(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp assert_history(ctx, path) do
    assert is_binary(path)
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) == size
    refute bytes =~ @rejected
    refute bytes =~ @late
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2_048

    items =
      for line <- lines,
          _ = assert(byte_size(line) <= @max_line_bytes),
          row = JSON.decode!(line),
          row["type"] == "response_item",
          do: row["payload"]

    for marker <- [@before, @continuation] do
      assert Enum.count(items, fn item ->
               item["role"] == "user" and
                 item["content"] === [%{"type" => "input_text", "text" => marker}]
             end) == 1
    end
  end

  defp assert_no_effects(ctx, pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert Enum.filter(events, &(&1.kind == :server_request)) === []
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp assert_unchanged(ctx) do
    for {path, bytes} <- ctx.unchanged, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned compact-steering native #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        max_events: 256,
        max_event_bytes: 1_048_576,
        max_message_bytes: 1_048_576,
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
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
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_compact_steering", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
