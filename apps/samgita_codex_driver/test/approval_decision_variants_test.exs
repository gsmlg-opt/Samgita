defmodule SamgitaCodexDriver.ApprovalDecisionVariantsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/server_interaction_fixture.py", __DIR__)

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-decisions-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario] || "permissions")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  @tag scenario: "command_repeat"
  test "accept applies once and a stale handle cannot decide the next matching command",
       context do
    pid = start(context)
    thread = thread(context, pid)
    {first, approval, events} = pending(context, pid, thread, "commandExecution", 1)
    assert_command(approval, context)
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
    events = finish(pid, thread, first, events)
    assert_executed(events, first)
    refute File.exists?(rules(context))

    {second, current, events} = pending(context, pid, thread, "commandExecution", 3)
    assert second != first
    assert_command(current, context)

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})

    assert %{pending: 0, interactions: 1} = Session.status(pid)
    assert length(ModelFixture.requests(context.fixture)) == 3
    assert :ok = Session.respond(pid, current.handle, {:ok, %{"decision" => "decline"}})
    events = finish(pid, thread, second, events)
    assert %{"status" => "declined"} = item(events, "commandExecution")
    assert item(events, "commandExecution")["aggregatedOutput"] == nil
    refute File.exists?(rules(context))
    assert_history(pid, thread, [first, second])
  end

  @tag scenario: "command_repeat"
  test "an approved exact execpolicy rule survives process restart and authorizes the matching command",
       context do
    pid = start(context)
    thread = thread(context, pid)
    {turn, approval, events} = pending(context, pid, thread, "commandExecution", 1)
    assert_command(approval, context)
    assert approval.wire["params"]["proposedExecpolicyAmendment"] == ["printf"]

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{
                  "decision" => %{
                    "acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => ["printf"]}
                  }
                }}
             )

    assert_executed(finish(pid, thread, turn, events), turn)
    assert File.read!(rules(context)) == ~s|prefix_rule(pattern=["printf"], decision="allow")\n|
    assert_history(pid, thread, [turn])
    assert :ok = Session.close(pid)

    restarted = start(context)
    next_thread = thread(context, restarted)
    next_turn = start_turn(restarted, next_thread)
    events = finish(restarted, next_thread, next_turn, [])
    assert_executed(events, next_turn)
    assert length(ModelFixture.requests(context.fixture)) == 4
    assert File.read!(rules(context)) == ~s|prefix_rule(pattern=["printf"], decision="allow")\n|
    assert_history(restarted, next_thread, [next_turn])
  end

  @tag scenario: "command_repeat"
  test "an explicit command approval error fails the command without executing or writing a rule",
       context do
    pid = start(context)
    thread = thread(context, pid)
    {turn, approval, events} = pending(context, pid, thread, "commandExecution", 1)
    assert_command(approval, context)
    assert :ok = Session.respond(pid, approval.handle, denied())
    events = finish(pid, thread, turn, events)
    assert %{"status" => "failed", "exitCode" => nil} = item(events, "commandExecution")
    assert item(events, "commandExecution")["aggregatedOutput"] == nil
    refute File.exists?(rules(context))
    assert length(ModelFixture.requests(context.fixture)) == 2
    assert_history(pid, thread, [turn])
  end

  @tag scenario: "patch"
  test "an explicit file approval error denies the exact patch and preserves the filesystem",
       context do
    pid = start(context)
    thread = thread(context, pid)
    {turn, approval, events} = pending(context, pid, thread, "fileChange", 1)
    target = Path.join(context.fixture.workspace, "approved.txt")
    assert [%{"path" => ^target}] = item(events, "fileChange", "item/started")["changes"]
    refute File.exists?(target)
    assert :ok = Session.respond(pid, approval.handle, denied())
    events = finish(pid, thread, turn, events)
    assert %{"status" => "declined"} = item(events, "fileChange")
    refute File.exists?(target)
    refute File.exists?(rules(context))
    assert length(ModelFixture.requests(context.fixture)) == 2
    assert_history(pid, thread, [turn])
  end

  test "permission grants default omitted scope to the current turn", context do
    {pid, thread, turn, approval, events} = permission_request(context)

    assert :ok =
             Session.respond(pid, approval.handle, {:ok, %{"permissions" => grant(context)}})

    finish(pid, thread, turn, events)
    assert permission_output(context) == granted_output(context)
    assert_no_permission_side_effects(context)
    assert_history(pid, thread, [turn])
  end

  test "excess filesystem and network grants are intersected with the exact request", context do
    {pid, thread, turn, approval, events} = permission_request(context)
    sibling = Path.join(context.root, "unrequested")
    File.mkdir!(sibling)

    permissions = %{
      "fileSystem" => %{"write" => [context.fixture.workspace, sibling]},
      "network" => %{"enabled" => true}
    }

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok, %{"permissions" => permissions, "scope" => "turn"}}
             )

    finish(pid, thread, turn, events)
    assert permission_output(context) == granted_output(context)
    assert File.ls!(sibling) == []
    assert_no_permission_side_effects(context)
    assert_history(pid, thread, [turn])
  end

  test "session scope with strict auto review fails closed to an empty turn grant", context do
    {pid, thread, turn, approval, events} = permission_request(context)

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{
                  "permissions" => grant(context),
                  "scope" => "session",
                  "strictAutoReview" => true
                }}
             )

    finish(pid, thread, turn, events)
    assert permission_output(context) == empty_output()
    assert_no_permission_side_effects(context)
    assert_history(pid, thread, [turn])
  end

  test "an explicit permissions error returns an empty turn grant to the model", context do
    {pid, thread, turn, approval, events} = permission_request(context)
    assert :ok = Session.respond(pid, approval.handle, denied())
    finish(pid, thread, turn, events)
    assert permission_output(context) == empty_output()
    assert_no_permission_side_effects(context)
    assert_history(pid, thread, [turn])
  end

  defp permission_request(context) do
    pid = start(context)
    thread = thread(context, pid)
    {turn, approval, events} = pending(context, pid, thread, "permissions", 1)
    params = approval.wire["params"]
    assert params["cwd"] == context.fixture.workspace
    assert params["reason"] == "Synthetic directory permission only"
    assert params["permissions"]["fileSystem"]["write"] == [context.fixture.workspace]
    {pid, thread, turn, approval, events}
  end

  defp pending(context, pid, thread, kind, index) do
    turn = start_turn(pid, thread)
    events = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/#{kind}/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread
    assert params["turnId"] == turn
    assert params["itemId"] == "interaction-call-#{index}"
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert length(ModelFixture.requests(context.fixture)) == index
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    {turn, approval, events}
  end

  defp start_turn(pid, thread) do
    TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => "Synthetic decision only"}])
  end

  defp finish(pid, thread, turn, events) do
    previous = Enum.count(events, &(&1.kind == :server_request))

    events =
      collect(pid, events, fn events ->
        notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
      end)

    assert Enum.count(events, &(&1.kind == :server_request)) == previous

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
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
          flunk("Unexpected gap during native approval decision")
      after
        remaining -> flunk("Native approval decision deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_command(approval, context) do
    params = approval.wire["params"]
    assert params["kind"] == "command"
    assert params["cwd"] == context.fixture.workspace

    # The fixture omits `shell`: pinned Codex selects the account's shell, not
    # the private sh used by fixtures that explicitly request that shell type.
    assert [shell, "-c", "printf samgita_interaction"] = OptionParser.split(params["command"])
    assert Path.type(shell) == :absolute
    assert File.regular?(shell)
    assert Path.basename(shell) in ["sh", "bash", "zsh"]

    assert params["proposedExecpolicyAmendment"] == ["printf"]
  end

  defp assert_executed(events, turn) do
    assert %{"id" => id, "status" => "completed", "exitCode" => 0, "aggregatedOutput" => output} =
             item(events, "commandExecution")

    assert output == "samgita_interaction"

    assert %{"turnId" => ^turn} =
             notification(events, "item/completed", &(&1["item"]["id"] == id))
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

  defp permission_output(context) do
    assert [_first, second] = ModelFixture.requests(context.fixture)
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "interaction-call-1"
    JSON.decode!(output["output"])
  end

  defp grant(context), do: %{"fileSystem" => %{"write" => [context.fixture.workspace]}}

  defp granted_output(context) do
    %{
      "permissions" => %{
        "network" => nil,
        "file_system" => %{"write" => [context.fixture.workspace]}
      },
      "scope" => "turn"
    }
  end

  defp empty_output,
    do: %{"permissions" => %{"network" => nil, "file_system" => nil}, "scope" => "turn"}

  defp assert_no_permission_side_effects(context) do
    assert File.ls!(context.fixture.workspace) == []
    refute File.exists?(rules(context))
  end

  defp rules(context), do: Path.join([context.fixture.codex_home, "rules", "default.rules"])
  defp denied, do: {:error, %{"code" => -32_001, "message" => "Synthetic explicit refusal"}}
end
