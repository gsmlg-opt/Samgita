defmodule SamgitaCodexDriver.NativeThreadRevertProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @answer "Deterministic local fixture answer"

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
    def send(state, encoded), do: Stdio.send(state, encoded)

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &capture_notice(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    # Retain the selected original JSONL before Session decoding or projection.
    defp capture_notice({:message, encoded}, :ok, capture) do
      wire = JSON.decode!(encoded)

      if wire["method"] == "thread/reverted" do
        case Agent.get_and_update(capture, &append(&1, encoded, wire)) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      else
        {:cont, :ok}
      end
    end

    defp capture_notice(_event, :ok, _capture), do: {:cont, :ok}

    defp append(ledger, encoded, wire) do
      size = byte_size(encoded)

      if ledger.count < 128 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
        record = %{encoded: encoded, wire: wire}

        {:ok,
         %{
           count: ledger.count + 1,
           bytes: ledger.bytes + size,
           records: [record | ledger.records]
         }}
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
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    File.mkdir!(Path.join(ctx.root, "tmp"))

    File.write!(
      Path.join(ctx.fixture.workspace, "owned-sentinel.txt"),
      "Owned scratch content.\n"
    )

    TurnFixture.configure_model(ctx, %{})
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    Map.merge(ctx, %{
      workspace_before: workspace_snapshot(ctx.fixture.workspace),
      capture: capture
    })
  end

  test "native revert retains the first turn across read pagination and owned restart", ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})

    [first, second] =
      for text <- ["Owned retained first text", "Owned removed second text"] do
        turn = TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => text}])
        TurnFixture.finish_turn(pid, thread, turn)
        turn
      end

    before = history(pid, thread)
    assert Enum.map(before, & &1["id"]) == [first, second]
    assert_text_turn(hd(before), "Owned retained first text")
    assert_text_turn(List.last(before), "Owned removed second text")
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert {:ok, _prior_events} = Session.drain(pid)

    assert upstream_error(pid, "thread/revert", %{
             "threadId" => thread,
             "beforeTurnId" => "owned-missing-turn"
           }) == %{"code" => -32_600, "message" => "turn not found: owned-missing-turn"}

    assert history(pid, thread) == before
    assert {:ok, rejected_events} = Session.drain(pid)
    assert notices(rejected_events, "thread/reverted") == []
    assert captured(ctx) === []

    original_generation = Session.status(pid).generation
    reverted_lower = System.system_time(:millisecond)
    result = call(pid, "thread/revert", %{"threadId" => thread, "beforeTurnId" => second})
    assert result["thread"]["id"] == thread
    assert result["thread"]["turns"] == []
    assert is_binary(result["turnsBackwardsCursor"])
    assert is_binary(result["itemsBackwardsCursor"])

    events = await_reverted(pid, thread, [], System.monotonic_time(:millisecond) + 10_000)
    reverted_upper = System.system_time(:millisecond)
    assert notices(events, "thread/reverted") == [%{"threadId" => thread}]
    refute Enum.any?(events, &(&1.kind == :server_request))

    originals =
      assert_original_reverted(
        ctx,
        events,
        thread,
        original_generation,
        reverted_lower,
        reverted_upper
      )

    page =
      call(pid, "thread/turns/list", %{
        "threadId" => thread,
        "cursor" => result["turnsBackwardsCursor"],
        "sortDirection" => "desc",
        "itemsView" => "full"
      })

    assert Enum.map(page["data"], & &1["id"]) == [first]
    assert page["nextCursor"] == nil
    retained = [hd(before)]
    assert history(pid, thread) == retained
    assert workspace_snapshot(ctx.fixture.workspace) == ctx.workspace_before
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert Session.uncertain_operations(pid) == []
    assert Session.status(pid).generation === original_generation
    assert captured(ctx) === originals

    generation = Session.status(pid).generation
    assert :ok = Session.reconnect(pid)
    assert Session.status(pid).generation == generation + 1
    initialize(pid)

    resumed = call(pid, "thread/resume", %{"threadId" => thread, "excludeTurns" => true})
    assert resumed["thread"]["id"] == thread
    assert resumed["thread"]["turns"] == []
    assert history(pid, thread) == retained
    assert {:ok, restart_events} = Session.drain(pid)
    assert notices(restart_events, "thread/reverted") == []
    assert Session.uncertain_operations(pid) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert workspace_snapshot(ctx.fixture.workspace) == ctx.workspace_before
    assert captured(ctx) === originals
    assert :ok = Session.close(pid)
    assert captured(ctx) === originals
  end

  for {name, extra, message} <- [
        {"ephemeral", %{"ephemeral" => true}, "ephemeral threads do not support thread/revert"},
        {"legacy", %{"historyMode" => "legacy"}, "thread/revert only supports paginated threads"}
      ] do
    @extra extra
    @message message
    test "native #{name} history rejects revert without inference", ctx do
      pid = start(ctx)
      thread = TurnFixture.thread(ctx, pid, @extra)
      assert {:ok, _prior_events} = Session.drain(pid)

      assert upstream_error(pid, "thread/revert", %{
               "threadId" => thread,
               "beforeTurnId" => "owned-unused-turn"
             }) == %{"code" => -32_600, "message" => @message}

      read = call(pid, "thread/read", %{"threadId" => thread})["thread"]
      assert read["id"] == thread
      assert read["turns"] == []
      assert {:ok, events} = Session.drain(pid)
      assert notices(events, "thread/reverted") == []
      assert captured(ctx) === []
      assert ModelFixture.requests(ctx.fixture) == []
      assert Session.uncertain_operations(pid) == []
      assert workspace_snapshot(ctx.fixture.workspace) == ctx.workspace_before
      assert :ok = Session.close(pid)
      assert captured(ctx) === []
    end
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_thread_revert", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )
  end

  defp history(pid, thread) do
    metadata = call(pid, "thread/read", %{"threadId" => thread})["thread"]
    assert metadata["id"] == thread
    assert metadata["turns"] == []

    # Full hydration remains a supported, deprecated compatibility path at this pin.
    read = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert read["id"] == thread

    page =
      call(pid, "thread/turns/list", %{
        "threadId" => thread,
        "sortDirection" => "asc",
        "itemsView" => "full",
        "limit" => 10
      })

    assert page["nextCursor"] == nil
    assert Enum.map(read["turns"], &turn_content/1) == Enum.map(page["data"], &turn_content/1)
    Enum.map(page["data"], &turn_content/1)
  end

  defp turn_content(turn), do: Map.take(turn, ["id", "status", "items"])

  defp assert_text_turn(turn, text) do
    assert turn["status"] == "completed"
    assert Enum.all?(turn["items"], &(&1["type"] in ["userMessage", "agentMessage"]))
    user = Enum.find(turn["items"], &(&1["type"] == "userMessage"))
    assert Enum.any?(user["content"], &(&1["type"] == "text" and &1["text"] == text))
    assert Enum.find(turn["items"], &(&1["type"] == "agentMessage"))["text"] == @answer
  end

  defp await_reverted(pid, thread, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    cond do
      %{"threadId" => thread} in notices(acc, "thread/reverted") ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native thread/reverted deadline: #{inspect(Session.status(pid))}")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, gap}} -> flunk("Unexpected native gap: #{inspect(gap)}")
        after
          20 -> :ok
        end

        await_reverted(pid, thread, acc, deadline)
    end
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp captured(ctx), do: Agent.get(ctx.capture, &Enum.reverse(&1.records))

  defp assert_original_reverted(ctx, events, thread, generation, lower, upper) do
    assert [event] = Enum.filter(events, &(&1.wire["method"] == "thread/reverted"))
    assert [original] = originals = captured(ctx)
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === generation

    expected = %{
      "method" => "thread/reverted",
      "params" => %{"threadId" => thread},
      "emittedAtMs" => emitted
    }

    assert event.wire === expected
    assert original.wire === expected
    assert JSON.decode!(original.encoded) === expected
    assert {:ok, preserved} = Wire.decode(original.encoded, max_depth: 32)
    assert preserved === expected
    assert :ok = Schema.validate(notification_schema(), original.wire, max_depth: 32)
    originals
  end

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp workspace_snapshot(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.sort()
    |> Enum.map(fn path ->
      relative = Path.relative_to(path, root)
      if File.dir?(path), do: {relative, :directory}, else: {relative, File.read!(path)}
    end)
  end
end
