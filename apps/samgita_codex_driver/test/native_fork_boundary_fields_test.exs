defmodule SamgitaCodexDriver.NativeForkBoundaryFieldsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3, upstream_error: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @texts [
    "Owned boundary P1 λ",
    "Owned boundary P2 🙂",
    "Owned boundary P3 excluded",
    "Owned boundary P4 excluded"
  ]
  @answer "Deterministic local fixture answer"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    sentinel = Path.join(ctx.fixture.workspace, "owned-boundary-sentinel.txt")
    File.write!(sentinel, "Owned workspace content survives history-only changes.\n")
    Map.put(ctx, :sentinel, sentinel)
  end

  for mode <- ["legacy", "paginated"] do
    @mode mode
    test "#{mode} non-latest exclusive fork preserves native content and independent cold histories",
         ctx do
      pid = start(ctx)
      parent = TurnFixture.thread(ctx, pid, %{"historyMode" => @mode})
      [first, second, third, _fourth] = original = complete_many(ctx, pid, parent, @texts)

      exclusive = fork(pid, parent, %{"beforeTurnId" => third.id, "excludeTurns" => true})
      child = exclusive["id"]
      assert exclusive["turns"] == []
      assert_fork_identity(ctx, exclusive, parent)
      assert_history(pid, child, [first, second])
      assert_history(pid, parent, original)
      assert_no_replay(ctx, pid, 4)

      # Same non-latest prefix, now inclusive of the second turn. Both later
      # parent turns already exist when these calls run; this is not a latest-only cutoff.
      inclusive = fork(pid, parent, %{"lastTurnId" => second.id, "excludeTurns" => false})
      sibling = inclusive["id"]
      refute sibling == child
      assert_fork_identity(ctx, inclusive, parent)
      assert_turns(inclusive["turns"], [first, second])
      assert_history(pid, sibling, [first, second])
      assert_history(pid, child, [first, second])
      assert_history(pid, parent, original)
      assert_no_replay(ctx, pid, 4)

      empty = fork(pid, parent, %{"beforeTurnId" => first.id, "excludeTurns" => false})
      assert_fork_identity(ctx, empty, parent)
      assert empty["turns"] == []
      assert_history(pid, empty["id"], [])

      for extra <- [%{"excludeTurns" => false}, %{"beforeTurnId" => nil, "excludeTurns" => false}] do
        latest = fork(pid, parent, extra)
        assert_fork_identity(ctx, latest, parent)
        assert_turns(latest["turns"], original)
        assert_history(pid, latest["id"], original)
      end

      assert_no_replay(ctx, pid, 4)
      parent_new = complete(ctx, pid, parent, "Owned parent divergence P5")
      child_new = complete(ctx, pid, child, "Owned child divergence C1")

      assert_provider_prefix(
        ctx,
        @texts |> Enum.take(2) |> Kernel.++([child_new.text]),
        Enum.drop(@texts, 2) ++ [parent_new.text]
      )

      assert_history(pid, parent, original ++ [parent_new])
      assert_history(pid, child, [first, second, child_new])
      assert_history(pid, sibling, [first, second])
      assert_no_replay(ctx, pid, 6)
      process = call(pid, "server/diagnostics", %{})["process"]["id"]
      assert :ok = Session.close(pid)

      cold = start(ctx)
      refute call(cold, "server/diagnostics", %{})["process"]["id"] == process
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_history(cold, parent, original ++ [parent_new])
      assert_history(cold, child, [first, second, child_new])
      assert_history(cold, sibling, [first, second])
      assert_history(cold, empty["id"], [])
      assert_no_replay(ctx, cold, 6)

      resumed = call(cold, "thread/resume", %{"threadId" => child, "excludeTurns" => true})
      assert resumed["thread"]["id"] == child
      assert_history(cold, child, [first, second, child_new])
      assert_history(cold, parent, original ++ [parent_new])
      assert_no_replay(ctx, cold, 6)
    end

    test "#{mode} invalid unrelated and mutually exclusive fork boundaries preserve both sources",
         ctx do
      pid = start(ctx)
      parent = TurnFixture.thread(ctx, pid, %{"historyMode" => @mode})
      original = complete_many(ctx, pid, parent, @texts)
      unrelated = TurnFixture.thread(ctx, pid, %{"historyMode" => @mode})
      other = complete(ctx, pid, unrelated, "Owned unrelated turn U1")
      loaded = call(pid, "thread/loaded/list", %{})["data"]

      for boundary <- ["owned-missing-boundary", "not-a-turn-id", other.id] do
        message =
          if @mode == "paginated",
            do: "turn not found: #{boundary}",
            else: "beforeTurnId '#{boundary}' was not found in the source thread"

        assert upstream_error(pid, "thread/fork", %{
                 "threadId" => parent,
                 "beforeTurnId" => boundary
               }) ==
                 invalid(message)

        assert_history(pid, parent, original)
        assert_history(pid, unrelated, [other])
        assert call(pid, "thread/loaded/list", %{})["data"] == loaded
        assert_no_replay(ctx, pid, 5)
      end

      assert upstream_error(pid, "thread/fork", %{
               "threadId" => parent,
               "beforeTurnId" => Enum.at(original, 2).id,
               "lastTurnId" => Enum.at(original, 1).id
             }) == invalid("`beforeTurnId` cannot be combined with `lastTurnId`")

      error =
        upstream_error(pid, "thread/fork", %{"threadId" => parent, "beforeTurnId" => 17},
          validation: :wire
        )

      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert_history(pid, parent, original)
      assert_history(pid, unrelated, [other])
      assert call(pid, "thread/loaded/list", %{})["data"] == loaded
      assert_no_replay(ctx, pid, 5)
    end
  end

  test "ephemeral true keeps a legacy prefix live and pathless while cold child lookup fails",
       ctx do
    pid = start(ctx)
    parent = TurnFixture.thread(ctx, pid, %{"historyMode" => "legacy"})
    [first, second, third] = original = complete_many(ctx, pid, parent, Enum.take(@texts, 3))

    child_thread =
      fork(pid, parent, %{
        "beforeTurnId" => third.id,
        "excludeTurns" => false,
        "ephemeral" => true
      })

    child = child_thread["id"]
    assert is_binary(child)
    refute child == parent
    assert child_thread["forkedFromId"] == parent
    assert Map.fetch!(child_thread, "ephemeral") == true
    assert Map.fetch!(child_thread, "path") == nil
    assert_turns(child_thread["turns"], [first, second])
    assert_history(pid, parent, original)
    assert_no_child_rollout(ctx, child)
    assert_no_replay(ctx, pid, 3)

    # Ephemeral history is available to the native runtime, but the API rejects
    # includeTurns instead of reading or manufacturing a durable rollout.
    assert upstream_error(pid, "thread/read", %{"threadId" => child, "includeTurns" => true}) ==
             invalid("ephemeral threads do not support includeTurns")

    metadata = call(pid, "thread/read", %{"threadId" => child, "includeTurns" => false})["thread"]
    assert metadata["id"] == child
    assert Map.fetch!(metadata, "ephemeral") == true
    assert Map.fetch!(metadata, "path") == nil
    assert metadata["turns"] == []

    child_first = complete_live_only(pid, child, "Owned ephemeral continuation E1 λ")
    assert_provider_prefix(ctx, [first.text, second.text, child_first.text], [third.text])
    assert_history(pid, parent, original)
    assert_no_child_rollout(ctx, child)
    assert_no_replay(ctx, pid, 4)

    parent_new = complete(ctx, pid, parent, "Owned persistent parent divergence P4")
    child_second = complete_live_only(pid, child, "Owned ephemeral continuation E2 🙂")

    assert_provider_prefix(
      ctx,
      [first.text, second.text, child_first.text, child_second.text],
      [third.text, parent_new.text]
    )

    assert_history(pid, parent, original ++ [parent_new])

    assert upstream_error(pid, "thread/read", %{"threadId" => child, "includeTurns" => true}) ==
             invalid("ephemeral threads do not support includeTurns")

    metadata = call(pid, "thread/read", %{"threadId" => child, "includeTurns" => false})["thread"]
    assert metadata["id"] == child
    assert Map.fetch!(metadata, "ephemeral") == true
    assert Map.fetch!(metadata, "path") == nil
    assert_no_child_rollout(ctx, child)
    assert_no_replay(ctx, pid, 6)
    process = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)

    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    for include_turns <- [false, true] do
      assert upstream_error(cold, "thread/read", %{
               "threadId" => child,
               "includeTurns" => include_turns
             }) ==
               invalid("thread not loaded: #{child}")
    end

    assert upstream_error(cold, "thread/resume", %{"threadId" => child, "excludeTurns" => true}) ==
             invalid("no rollout found for thread id #{child}")

    assert_history(cold, parent, original ++ [parent_new])
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_no_child_rollout(ctx, child)
    assert_no_replay(ctx, cold, 6)
  end

  test "non-latest paginated revert changes the parent while its existing child retains independent history",
       ctx do
    pid = start(ctx)
    parent = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    [first, second, third, fourth] = original = complete_many(ctx, pid, parent, @texts)
    child_thread = fork(pid, parent, %{"beforeTurnId" => fourth.id, "excludeTurns" => false})
    child = child_thread["id"]
    assert_fork_identity(ctx, child_thread, parent)
    assert_turns(child_thread["turns"], [first, second, third])
    child_own = complete(ctx, pid, child, "Owned preexisting child C1 retained")
    child_expected = [first, second, third, child_own]
    assert_history(pid, parent, original)
    assert_history(pid, child, child_expected)
    assert_no_replay(ctx, pid, 5)

    # The unrelated ID exists in the same storage and in the child's own segment,
    # but cannot select a parent boundary. Errors may reload the parent's runtime.
    for boundary <- ["owned-missing-revert", child_own.id] do
      assert upstream_error(pid, "thread/revert", %{
               "threadId" => parent,
               "beforeTurnId" => boundary
             }) ==
               invalid("turn not found: #{boundary}")

      assert_history(pid, parent, original)
      assert_history(pid, child, child_expected)
      assert_no_replay(ctx, pid, 5)
    end

    reverted = call(pid, "thread/revert", %{"threadId" => parent, "beforeTurnId" => third.id})
    assert reverted["thread"]["id"] == parent
    assert reverted["thread"]["turns"] == []
    assert is_binary(Map.fetch!(reverted, "turnsBackwardsCursor"))
    assert is_binary(Map.fetch!(reverted, "itemsBackwardsCursor"))
    assert_history(pid, parent, [first, second])
    assert_history(pid, child, child_expected)

    hydration =
      call(pid, "thread/turns/list", %{
        "threadId" => parent,
        "cursor" => reverted["turnsBackwardsCursor"],
        "sortDirection" => "desc",
        "itemsView" => "full",
        "limit" => 100
      })

    assert_turns(hydration["data"], [second, first])
    assert Map.fetch!(hydration, "nextCursor") == nil

    assert upstream_error(pid, "thread/revert", %{
             "threadId" => parent,
             "beforeTurnId" => third.id
           }) ==
             invalid("turn not found: #{third.id}")

    assert_history(pid, parent, [first, second])
    assert_history(pid, child, child_expected)
    assert_no_replay(ctx, pid, 5)

    after_revert = complete(ctx, pid, parent, "Owned explicit continuation after revert P-new")

    assert_provider_prefix(ctx, [first.text, second.text, after_revert.text], [
      third.text,
      fourth.text,
      child_own.text
    ])

    parent_expected = [first, second, after_revert]
    assert_history(pid, parent, parent_expected)
    assert_history(pid, child, child_expected)
    assert_no_replay(ctx, pid, 6)
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_history(cold, parent, parent_expected)
    assert_history(cold, child, child_expected)
    assert_no_replay(ctx, cold, 6)

    assert call(cold, "thread/resume", %{"threadId" => parent, "excludeTurns" => true})["thread"][
             "id"
           ] == parent

    assert call(cold, "thread/resume", %{"threadId" => child, "excludeTurns" => true})["thread"][
             "id"
           ] == child

    assert_history(cold, parent, parent_expected)
    assert_history(cold, child, child_expected)
    assert_no_replay(ctx, cold, 6)
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
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
               %{"name" => "samgita_fork_boundaries", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp fork(pid, parent, extra) do
    call(pid, "thread/fork", Map.merge(%{"threadId" => parent, "ephemeral" => false}, extra))[
      "thread"
    ]
  end

  defp assert_fork_identity(ctx, thread, parent) do
    assert is_binary(thread["id"])
    refute thread["id"] == parent
    assert thread["forkedFromId"] == parent
    assert Map.fetch!(thread, "ephemeral") == false
    assert is_binary(thread["path"])
    assert Path.type(thread["path"]) == :absolute

    assert String.starts_with?(
             Path.expand(thread["path"]),
             Path.expand(ctx.fixture.codex_home) <> "/"
           )

    assert File.regular?(thread["path"])
  end

  defp complete_many(ctx, pid, id, texts), do: Enum.map(texts, &complete(ctx, pid, id, &1))

  defp complete(_ctx, pid, id, text) do
    turn_id = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    TurnFixture.finish_turn(pid, id, turn_id)

    turns =
      call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]["turns"]

    native = Enum.find(turns, &(&1["id"] == turn_id))
    assert native
    user = Enum.find(native["items"], &(&1["type"] == "userMessage"))
    agent = Enum.find(native["items"], &(&1["type"] == "agentMessage"))
    assert user && agent
    assert is_binary(user["id"]) and byte_size(user["id"]) > 0
    assert is_binary(agent["id"]) and byte_size(agent["id"]) > 0
    expected = %{id: turn_id, text: text, user: user["id"], assistant: agent["id"]}
    assert_turns([native], [expected])
    expected
  end

  defp assert_history(pid, id, expected) do
    native = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert native["id"] == id
    assert_turns(native["turns"], expected)
  end

  defp complete_live_only(pid, id, text) do
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    events = TurnFixture.finish_turn(pid, id, turn)

    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == id,
          event.wire["params"]["turnId"] == turn,
          do: event.wire["params"]["item"]

    assert Enum.map(items, & &1["type"]) == ["userMessage", "agentMessage"]
    [user, agent] = items
    assert is_binary(user["id"]) and byte_size(user["id"]) > 0
    assert is_binary(agent["id"]) and byte_size(agent["id"]) > 0

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) == [
             %{"type" => "text", "text" => text}
           ]

    assert agent["text"] == @answer
    %{id: turn, text: text, user: user["id"], assistant: agent["id"]}
  end

  defp assert_no_child_rollout(ctx, child) do
    paths = Path.wildcard(Path.join(ctx.fixture.codex_home, "**/rollout-*"), match_dot: true)
    refute Enum.any?(paths, &(File.regular?(&1) and String.contains?(Path.basename(&1), child)))
  end

  defp assert_turns(turns, expected) do
    assert Enum.map(turns, & &1["id"]) == Enum.map(expected, & &1.id)

    for {turn, row} <- Enum.zip(turns, expected) do
      assert turn["status"] == "completed"
      assert Enum.map(turn["items"], & &1["type"]) == ["userMessage", "agentMessage"]
      [user, agent] = turn["items"]
      assert user["id"] == row.user

      assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) == [
               %{"type" => "text", "text" => row.text}
             ]

      assert agent["id"] == row.assistant
      assert agent["text"] == @answer
    end
  end

  defp assert_provider_prefix(ctx, retained, excluded) do
    request = List.last(ModelFixture.requests(ctx.fixture))
    content = for item <- request["input"], part <- Map.get(item, "content", []), do: part
    for text <- retained, do: assert(%{"type" => "input_text", "text" => text} in content)
    for text <- excluded, do: refute(%{"type" => "input_text", "text" => text} in content)
  end

  defp assert_no_replay(ctx, pid, expected) do
    assert length(ModelFixture.requests(ctx.fixture)) == expected
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
    assert File.read!(ctx.sentinel) == "Owned workspace content survives history-only changes.\n"
  end

  defp invalid(message), do: %{"code" => -32_600, "message" => message}
end
