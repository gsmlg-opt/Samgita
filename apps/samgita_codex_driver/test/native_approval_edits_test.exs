defmodule SamgitaCodexDriver.NativeApprovalEditsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/server_interaction_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-approval-edits-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "command_repeat")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  test "a narrower edited prefix persists exactly and permits the matching later command", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, 1)
    assert :ok = amend(pid, approval, ["printf", "samgita_interaction"])
    events = finish(pid, thread, first, events)
    assert_executed(events, first)
    assert_no_amendment_warning(events)
    assert_stale(pid, approval)

    expected = ~s|prefix_rule(pattern=["printf", "samgita_interaction"], decision="allow")\n|
    assert File.read!(rules(ctx)) == expected

    second = start_turn(pid, thread)
    events = finish(pid, thread, second, [])
    assert_executed(events, second)
    assert_no_amendment_warning(events)
    assert File.read!(rules(ctx)) == expected
    assert_finished(ctx, pid, thread, [first, second])
  end

  test "an unrelated safe edited prefix persists but does not approve the later original command",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, 1)
    assert :ok = amend(pid, approval, ["printf", "samgita_other_owned_marker"])
    events = finish(pid, thread, first, events)
    assert_executed(events, first)
    assert_no_amendment_warning(events)
    assert_stale(pid, approval)

    expected =
      ~s|prefix_rule(pattern=["printf", "samgita_other_owned_marker"], decision="allow")\n|

    assert File.read!(rules(ctx)) == expected
    {second, current, events} = pending(ctx, pid, thread, 3)
    assert second != first
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    assert :ok = Session.respond(pid, current.handle, {:ok, %{"decision" => "decline"}})
    events = finish(pid, thread, second, events)
    assert_declined(events, second)
    assert_no_amendment_warning(events)
    assert File.read!(rules(ctx)) == expected
    assert_stale(pid, current)
    assert_finished(ctx, pid, thread, [first, second])
  end

  test "an empty prefix warns without persistence while the current approved action still runs",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, 1)
    assert :ok = amend(pid, approval, [])
    events = finish(pid, thread, first, events)
    assert_executed(events, first)
    assert_stale(pid, approval)

    # Pinned execpolicy/src/amend.rs rejects [] before opening the rule file.
    # core/session/handlers.rs warns and then notifies the approved decision.
    warning =
      "Failed to apply execpolicy amendment: failed to update rules file #{rules(ctx)}: " <>
        "prefix rule requires at least one token"

    assert notification(events, "warning", &(&1["message"] == warning)) == %{
             "threadId" => thread,
             "message" => warning
           }

    assert length(amendment_warnings(events)) == 1
    refute File.exists?(rules(ctx))
    {second, current, events} = pending(ctx, pid, thread, 3)
    assert second != first
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    assert :ok = Session.respond(pid, current.handle, {:ok, %{"decision" => "decline"}})
    events = finish(pid, thread, second, events)
    assert_declined(events, second)
    assert_no_amendment_warning(events)
    refute File.exists?(rules(ctx))
    assert_stale(pid, current)
    assert_finished(ctx, pid, thread, [first, second])
  end

  defp pending(ctx, pid, thread, request_index) do
    turn = start_turn(pid, thread)

    events =
      collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end), true)

    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == "interaction-call-#{request_index}"
    assert params["kind"] == "command" and params["cwd"] == ctx.fixture.workspace
    assert params["networkApprovalContext"] == nil
    assert params["proposedNetworkPolicyAmendments"] == nil
    assert params["proposedExecpolicyAmendment"] == ["printf"]
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0

    assert [shell, "-c", "printf samgita_interaction"] = OptionParser.split(params["command"])
    assert Path.type(shell) == :absolute and File.regular?(shell)
    assert Path.basename(shell) in ["sh", "bash", "zsh"]
    assert approval.handle.id == approval.wire["id"]
    assert is_reference(approval.handle.reference)
    assert length(ModelFixture.requests(ctx.fixture)) == request_index
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    {turn, approval, events}
  end

  defp amend(pid, approval, prefix) do
    Session.respond(
      pid,
      approval.handle,
      {:ok,
       %{
         "decision" => %{
           "acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => prefix}
         }
       }}
    )
  end

  defp start_turn(pid, thread) do
    TurnFixture.start_turn(pid, thread, [
      %{"type" => "text", "text" => "Synthetic prefix edit only"}
    ])
  end

  defp finish(pid, thread, turn, events) do
    events =
      collect(
        pid,
        events,
        fn all ->
          notification(all, "turn/completed", &(&1["turn"]["id"] == turn))
        end,
        false
      )

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    events
  end

  defp collect(pid, events, done, allow_request, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)

    unless allow_request do
      refute Enum.any?(incoming, &(&1.kind == :server_request)),
             "Unexpected native approval; never automatically accept unrelated requests"
    end

    events = events ++ incoming

    if done.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, done, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during native prefix edit")
      after
        remaining -> flunk("Native prefix edit deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp command_item(events, turn) do
    assert [%{"item" => item}] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["turnId"] == turn,
               event.wire["params"]["item"]["type"] == "commandExecution",
               do: event.wire["params"] |> Map.take(["item"])
             )

    item
  end

  defp assert_executed(events, turn) do
    assert %{
             "status" => "completed",
             "exitCode" => 0,
             "aggregatedOutput" => "samgita_interaction"
           } = command_item(events, turn)
  end

  defp assert_declined(events, turn) do
    assert %{"status" => "declined", "exitCode" => nil, "aggregatedOutput" => nil} =
             command_item(events, turn)
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp amendment_warnings(events) do
    for event <- events,
        event.wire["method"] == "warning",
        String.starts_with?(
          event.wire["params"]["message"],
          "Failed to apply execpolicy amendment:"
        ),
        do: event.wire["params"]
  end

  defp assert_no_amendment_warning(events), do: assert(amendment_warnings(events) == [])

  defp assert_finished(ctx, pid, thread, turns) do
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert File.ls!(ctx.fixture.workspace) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)

    history =
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]["turns"]

    assert Enum.map(history, & &1["id"]) == turns
    assert Enum.all?(history, &(&1["status"] == "completed"))
    assert :ok = Session.close(pid)
  end

  defp rules(ctx), do: Path.join([ctx.fixture.codex_home, "rules", "default.rules"])
end
