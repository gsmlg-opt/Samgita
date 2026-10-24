defmodule SamgitaCodexDriver.NativeApprovalDuplicateRepliesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.{Error, Wire}
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @scripts Path.expand("../../../scripts/codex", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-approval-duplicates-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    script = tags[:provider_script] || "server_interaction_fixture.py"
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", Path.join(@scripts, script))

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  @tag scenario: "command_repeat"
  test "concurrent duplicate command approvals send one local response and complete one native command",
       ctx do
    {pid, id, turn, approval, events} = pending(ctx, "commandExecution", "interaction-call-1")
    params = approval.wire["params"]
    assert params["kind"] == "command" and params["cwd"] == ctx.fixture.workspace
    assert params["proposedExecpolicyAmendment"] == ["printf"]

    assert [shell, "-c", "printf samgita_interaction"] =
             OptionParser.split(params["command"])

    assert Path.type(shell) == :absolute and File.regular?(shell)
    result = %{"decision" => "accept"}
    race_replies(ctx, pid, approval, result)
    completed = finish(ctx, pid, approval, result, events, {id, turn, "commandExecution", 2})

    assert %{
             "id" => "interaction-call-1",
             "status" => "completed",
             "exitCode" => 0,
             "aggregatedOutput" => "samgita_interaction"
           } = completed

    assert File.ls!(ctx.fixture.workspace) == []
  end

  @tag scenario: "patch"
  test "concurrent duplicate file approvals complete one native patch with exact owned bytes",
       ctx do
    {pid, id, turn, approval, events} = pending(ctx, "fileChange", "interaction-call-1")
    path = Path.join(ctx.fixture.workspace, "approved.txt")
    assert [%{"path" => ^path}] = item_event(events, "item/started", "fileChange")["changes"]
    refute File.exists?(path)
    result = %{"decision" => "accept"}
    race_replies(ctx, pid, approval, result)
    completed = finish(ctx, pid, approval, result, events, {id, turn, "fileChange", 2})
    assert completed["id"] == "interaction-call-1" and completed["status"] == "completed"
    assert File.read!(path) == "synthetic patch\n"
    assert File.ls!(ctx.fixture.workspace) == ["approved.txt"]
  end

  @tag scenario: "permission_lifetime", provider_script: "permission_lifetime_fixture.py"
  test "concurrent duplicate permission grants authorize only one same-turn owned patch", ctx do
    {pid, id, turn, approval, events} = pending(ctx, "permissions", "permission-lifetime-1")
    params = approval.wire["params"]
    assert params["environmentId"] == "local" and params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Synthetic owned workspace permission lifetime only"
    assert params["permissions"]["fileSystem"]["write"] == [ctx.fixture.workspace]

    result = %{
      "permissions" => %{"fileSystem" => %{"write" => [ctx.fixture.workspace]}},
      "scope" => "turn",
      "strictAutoReview" => false
    }

    race_replies(ctx, pid, approval, result)
    completed = finish(ctx, pid, approval, result, events, {id, turn, "fileChange", 3})
    assert completed["id"] == "permission-lifetime-2" and completed["status"] == "completed"
    assert File.read!(Path.join(ctx.fixture.workspace, "granted-now.txt")) == "owned turn grant\n"
    assert File.ls!(ctx.fixture.workspace) == ["granted-now.txt"]

    assert [_first, second, _third] = ModelFixture.requests(ctx.fixture)
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "permission-lifetime-1"

    assert JSON.decode!(output["output"]) == %{
             "permissions" => %{
               "network" => nil,
               "file_system" => %{"write" => [ctx.fixture.workspace]}
             },
             "scope" => "turn"
           }
  end

  defp pending(ctx, kind, item_id) do
    # Reuse the shared isolated launcher and its owned-process guardian.
    pid = start(ctx)
    id = thread(ctx, pid)

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned concurrent duplicate approval replies only"}
      ])

    events = collect(pid, [], &(interactions(&1) != []), true)
    assert [approval] = interactions(events)
    assert approval.wire["method"] == "item/#{kind}/requestApproval"
    assert approval.wire["params"]["threadId"] == id
    assert approval.wire["params"]["turnId"] == turn
    assert approval.wire["params"]["itemId"] == item_id
    assert is_integer(approval.wire["params"]["startedAtMs"])
    assert approval.wire["params"]["startedAtMs"] > 0
    assert approval.handle.id == approval.wire["id"]
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert_pending(ctx, pid, approval)
    {pid, id, turn, approval, events}
  end

  defp race_replies(ctx, pid, approval, result) do
    original = Map.fetch!(:sys.get_state(pid).interactions, approval.handle.id)
    assert original.handle == approval.handle
    assert is_integer(Process.read_timer(original.timer))
    owner = self()
    barrier = make_ref()

    callers =
      for _ <- 1..2 do
        Task.async(fn ->
          send(owner, {:approval_caller_ready, barrier, self()})

          receive do
            {:release_approval_caller, ^barrier} ->
              Session.respond(pid, approval.handle, {:ok, result})
          after
            5_000 -> flunk("Duplicate approval caller release deadline")
          end
        end)
      end

    try do
      for caller <- callers do
        caller_pid = caller.pid
        assert_receive {:approval_caller_ready, ^barrier, ^caller_pid}, 2_000
      end

      # Both independently scheduled callers have captured the SAME fresh handle
      # and are waiting. No reply is sent before this owner-controlled release.
      assert ^original = Map.fetch!(:sys.get_state(pid).interactions, approval.handle.id)
      assert_pending(ctx, pid, approval)
      Enum.each(callers, &send(&1.pid, {:release_approval_caller, barrier}))
      replies = Enum.map(callers, &Task.await(&1, 5_000))
      assert Enum.count(replies, &(&1 == :ok)) == 1

      assert [{:error, %Error{code: :stale_interaction, uncertain: false, wire: nil}}] =
               Enum.reject(replies, &(&1 == :ok))

      # :ok is only a successful local transport write. A native resolution may
      # already be observed; neither status alone establishes execution success.
      assert [outcome] = Session.interaction_outcomes(pid)
      assert outcome.handle == approval.handle
      assert outcome.method == approval.wire["method"]
      assert outcome.thread_id == approval.wire["params"]["threadId"]
      assert outcome.status in [:sent_unconfirmed, :resolution_observed]
      assert outcome.response_digest == response_digest(approval, result)
      assert_stale(pid, approval, result)
    after
      # Own only these two Elixir tasks. Never stop/restart a native service to
      # obtain an ordering, and leave no barrier waiter behind after assertion failure.
      Enum.each(callers, fn caller ->
        if Process.alive?(caller.pid), do: Task.shutdown(caller, :brutal_kill)
      end)
    end
  end

  defp assert_pending(ctx, pid, approval) do
    generation = approval.handle.generation

    assert %{
             phase: :ready,
             generation: ^generation,
             pending: 0,
             interactions: 1,
             interaction_outcomes: 0,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert File.ls!(ctx.fixture.workspace) == []
    refute File.exists?(rules(ctx))
  end

  defp finish(ctx, pid, approval, result, events, {id, turn, kind, provider_count}) do
    request_id = approval.wire["id"]

    events =
      collect(
        pid,
        events,
        fn all ->
          notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
            notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
        end,
        false
      )

    assert [^approval] = interactions(events)

    assert [%{"threadId" => ^id, "requestId" => ^request_id}] =
             params(events, "serverRequest/resolved")

    assert [%{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    started = item_event(events, "item/started", kind)
    completed = item_event(events, "item/completed", kind)
    assert started["id"] == completed["id"]
    assert completed["status"] == "completed"

    assert [%{"threadId" => ^id, "turnId" => ^turn}, %{"threadId" => ^id, "turnId" => ^turn}] =
             for(
               event <- events,
               event.wire["method"] in ["item/started", "item/completed"],
               event.wire["params"]["item"]["type"] == kind,
               do: Map.take(event.wire["params"], ~w(threadId turnId))
             )

    refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert [persisted] = Enum.filter(items, &(&1["type"] == kind))
    assert Map.take(persisted, ~w(id type status)) == Map.take(completed, ~w(id type status))
    assert length(ModelFixture.requests(ctx.fixture)) == provider_count

    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             interaction_outcomes: 1,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle == approval.handle and outcome.status == :resolution_observed
    assert outcome.response_digest == response_digest(approval, result)
    assert_stale(pid, approval, result)
    refute File.exists?(rules(ctx))
    completed
  end

  defp collect(pid, events, predicate, allow_request, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)

    unless allow_request do
      refute Enum.any?(incoming, &(&1.kind == :server_request)),
             "Unexpected native request; only the explicitly checked synthetic approval is answered"
    end

    events = events ++ incoming

    if predicate.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during duplicate approval replies")
      after
        remaining -> flunk("Native duplicate approval deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp item_event(events, method, kind) do
    assert [item] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["type"] == kind,
               do: event.wire["params"]["item"]
             )

    item
  end

  defp params(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp response_digest(approval, result) do
    assert {:ok, encoded} = Wire.encode(%{"id" => approval.wire["id"], "result" => result})
    :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)
  end

  defp assert_stale(pid, approval, result) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, result})
  end

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))
  defp rules(ctx), do: Path.join([ctx.fixture.codex_home, "rules", "default.rules"])
end
