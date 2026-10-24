defmodule SamgitaCodexDriver.NativeApprovalLifetimeTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @lifetime Path.expand("../../../scripts/codex/approval_lifetime_fixture.py", __DIR__)
  @interactions Path.expand("../../../scripts/codex/server_interaction_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-approval-lifetime-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    script = if tags[:interaction], do: @interactions, else: @lifetime
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", script)

    fixture =
      try do
        ModelFixture.start(root, tags.scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  @tag scenario: "patch_lifetime"
  test "session file approval suppresses a same-path update but does not approve another path",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, "fileChange", "lifetime-call-1", 1)
    assert_patch(ctx, approval, events, "approved.txt")
    respond(pid, approval, "acceptForSession")
    finish(pid, thread, first, events)
    assert File.read!(target(ctx, "approved.txt")) == "owned first\n"
    assert_stale(pid, approval)

    second = start_turn(pid, thread)
    events = finish(pid, thread, second, [])
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert File.read!(target(ctx, "approved.txt")) == "owned second\n"
    assert length(ModelFixture.requests(ctx.fixture)) == 4

    {third, current, events} = pending(ctx, pid, thread, "fileChange", "lifetime-call-5", 5)
    assert_patch(ctx, current, events, "other.txt")
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    respond(pid, current, "decline")
    events = finish(pid, thread, third, events)
    assert item(events, "fileChange")["status"] == "declined"
    refute File.exists?(target(ctx, "other.txt"))
    assert File.read!(target(ctx, "approved.txt")) == "owned second\n"
    assert length(ModelFixture.requests(ctx.fixture)) == 6
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, current)
    assert_history(pid, thread, [first, second, third])
  end

  @tag scenario: "patch_repeat"
  test "one-shot file acceptance requires a new approval for a matching path", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, "fileChange", "lifetime-call-1", 1)
    assert_patch(ctx, approval, events, "approved.txt")
    respond(pid, approval, "accept")
    finish(pid, thread, first, events)
    assert File.read!(target(ctx, "approved.txt")) == "owned first\n"

    {second, current, events} = pending(ctx, pid, thread, "fileChange", "lifetime-call-3", 3)
    assert_patch(ctx, current, events, "approved.txt", false)
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    respond(pid, current, "decline")
    events = finish(pid, thread, second, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert File.read!(target(ctx, "approved.txt")) == "owned first\n"
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, current)
    assert_history(pid, thread, [first, second])
  end

  @tag scenario: "patch_repeat"
  test "cold resume after owned native restart does not restore the file approval cache", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, "fileChange", "lifetime-call-1", 1)
    assert_patch(ctx, approval, events, "approved.txt")
    respond(pid, approval, "acceptForSession")
    finish(pid, thread, first, events)
    assert File.read!(target(ctx, "approved.txt")) == "owned first\n"
    assert_history(pid, thread, [first])
    original_instance = Session.status(pid).instance_id
    %{connection: original_connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = Session.close(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    assert Port.info(original_connection.port) == nil
    assert :atomics.get(original_connection.owner.completion, 1) == 1

    restarted = start(ctx)
    assert Session.status(restarted).instance_id != original_instance
    %{connection: next_connection} = :sys.get_state(restarted)
    assert next_connection.port != original_connection.port
    resumed = call(restarted, "thread/resume", %{"threadId" => thread})
    assert resumed["thread"]["id"] == thread
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_history(restarted, thread, [first])

    {second, current, events} =
      pending(ctx, restarted, thread, "fileChange", "lifetime-call-3", 3)

    assert_patch(ctx, current, events, "approved.txt", false)
    assert_stale(restarted, approval)
    assert %{interactions: 1} = Session.status(restarted)
    respond(restarted, current, "decline")
    events = finish(restarted, thread, second, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert File.read!(target(ctx, "approved.txt")) == "owned first\n"
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert_idle_without_rules(ctx, restarted)
    assert_stale(restarted, current)
    assert_history(restarted, thread, [first, second])
  end

  @tag scenario: "patch", interaction: true
  test "explicit interruption retires an unanswered native file approval without applying it",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {turn, approval, events} = pending(ctx, pid, thread, "fileChange", "interaction-call-1", 1)
    assert_patch(ctx, approval, events, "approved.txt")
    events = interrupt(pid, thread, turn, approval, events)
    refute File.exists?(target(ctx, "approved.txt"))
    refute Enum.any?(events, &successful_item?(&1, "fileChange"))
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert Session.interaction_outcomes(pid) == []
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, approval)
  end

  @tag scenario: "command_repeat", interaction: true
  test "explicit interruption retires an unanswered command approval without running it", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)

    {turn, approval, events} =
      pending(ctx, pid, thread, "commandExecution", "interaction-call-1", 1)

    params = approval.wire["params"]
    assert params["kind"] == "command"
    assert params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Synthetic fixture approval only"
    assert params["proposedExecpolicyAmendment"] == ["printf"]
    assert [shell, "-c", "printf samgita_interaction"] = OptionParser.split(params["command"])
    assert Path.type(shell) == :absolute and File.regular?(shell)
    assert Path.basename(shell) in ["sh", "bash", "zsh"]
    events = interrupt(pid, thread, turn, approval, events)
    refute Enum.any?(events, &successful_item?(&1, "commandExecution"))

    refute Enum.any?(events, fn event ->
             event.wire["method"] == "item/commandExecution/outputDelta" or
               (event.wire["method"] == "item/completed" and
                  event.wire["params"]["item"]["type"] == "commandExecution" and
                  event.wire["params"]["item"]["aggregatedOutput"] not in [nil, ""])
           end)

    assert File.ls!(ctx.fixture.workspace) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert Session.interaction_outcomes(pid) == []
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, approval)
  end

  defp pending(ctx, pid, thread, kind, item_id, count) do
    turn = start_turn(pid, thread)
    events = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/#{kind}/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread
    assert params["turnId"] == turn
    assert params["itemId"] == item_id
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    {turn, approval, events}
  end

  defp assert_patch(ctx, approval, events, name, absent \\ true) do
    params = approval.wire["params"]
    # Presence matters: omitted optional keys do not prove the explicit-null wire branch.
    assert Map.fetch(params, "reason") == {:ok, nil}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}
    path = target(ctx, name)
    assert [%{"path" => ^path}] = item(events, "fileChange", "item/started")["changes"]
    if absent, do: refute(File.exists?(path)), else: assert(File.read!(path) == "owned first\n")
  end

  defp respond(pid, approval, decision) do
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => decision}})
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp interrupt(pid, thread, turn, approval, events) do
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}
    events = finish(pid, thread, turn, events, "interrupted")
    request_id = approval.wire["id"]

    # Upstream queues resolution through the thread listener; it may follow terminal turn output.
    events =
      collect(pid, events, fn events ->
        notification(events, "serverRequest/resolved", fn params ->
          params["threadId"] == thread and params["requestId"] == request_id
        end)
      end)

    assert Enum.count(events, &(&1.kind == :server_request)) == 1

    assert %{"threadId" => ^thread, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    events
  end

  defp finish(pid, thread, turn, events, status \\ "completed") do
    count = Enum.count(events, &(&1.kind == :server_request))

    events =
      collect(pid, events, fn events ->
        assert Enum.count(events, &(&1.kind == :server_request)) == count,
               "Unexpected extra native approval instead of the required terminal transition"

        notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
      end)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => ^status}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    events
  end

  defp collect(pid, events, done, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if done.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, done, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during native approval lifetime")
      after
        remaining -> flunk("Native approval lifetime deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp successful_item?(event, type) do
    event.wire["method"] == "item/completed" and
      event.wire["params"]["item"]["type"] == type and
      event.wire["params"]["item"]["status"] == "completed"
  end

  defp item(events, type, method \\ "item/completed") do
    assert %{"item" => item} = notification(events, method, &(&1["item"]["type"] == type))
    item
  end

  defp assert_history(pid, thread, turns) do
    history =
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]["turns"]

    assert Enum.map(history, & &1["id"]) == turns
    assert Enum.all?(history, &(&1["status"] == "completed"))
  end

  defp assert_idle_without_rules(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp target(ctx, name), do: Path.join(ctx.fixture.workspace, name)

  defp start_turn(pid, thread) do
    TurnFixture.start_turn(pid, thread, [
      %{"type" => "text", "text" => "Owned approval lifetime fixture only"}
    ])
  end
end
