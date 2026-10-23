defmodule SamgitaCodexDriver.NativeThreadRevertProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @answer "Deterministic local fixture answer"

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
    Map.put(ctx, :workspace_before, workspace_snapshot(ctx.fixture.workspace))
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

    result = call(pid, "thread/revert", %{"threadId" => thread, "beforeTurnId" => second})
    assert result["thread"]["id"] == thread
    assert result["thread"]["turns"] == []
    assert is_binary(result["turnsBackwardsCursor"])
    assert is_binary(result["itemsBackwardsCursor"])

    events = await_reverted(pid, thread, [], System.monotonic_time(:millisecond) + 10_000)
    assert notices(events, "thread/reverted") == [%{"threadId" => thread}]
    refute Enum.any?(events, &(&1.kind == :server_request))

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
    assert :ok = Session.close(pid)
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
      assert ModelFixture.requests(ctx.fixture) == []
      assert Session.uncertain_operations(pid) == []
      assert workspace_snapshot(ctx.fixture.workspace) == ctx.workspace_before
      assert :ok = Session.close(pid)
    end
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: ["app-server", "--listen", "stdio://"],
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

    StdioSessionFixture.register_cleanup(pid)
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
