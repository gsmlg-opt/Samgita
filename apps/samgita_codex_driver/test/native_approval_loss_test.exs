defmodule SamgitaCodexDriver.NativeApprovalLossTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ApprovalLossTransport, ModelFixture, Session, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/approval_loss_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @command "echo 'owned recovered command' >> loss-command.txt; printf samgita_loss_command"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-approval-loss-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags.scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    assert :ok = :gen_tcp.close(listener)
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    digest = Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    {:ok, owner} =
      Stdio.open(
        executable: binary,
        args:
          SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
            "app-server",
            "--listen",
            "ws://127.0.0.1:#{port}",
            "--ws-auth",
            "capability-token",
            "--ws-token-sha256",
            digest
          ]),
        cwd: fixture.workspace,
        env: %{
          "HOME" => fixture.home,
          "CODEX_HOME" => fixture.codex_home,
          "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "NO_COLOR" => "1",
          "RUST_LOG" => "off"
        }
      )

    on_exit(fn -> assert :ok = Stdio.close(owner) end)
    await(fn -> listening?(port) end, "owned native WebSocket listener")

    control =
      start_supervised!(
        {Agent,
         fn ->
           %{opens: 0, mode: :normal, target: nil, blackhole: false, outbound: [], discarded: []}
         end}
      )

    {:ok, pid} =
      Session.start_link(
        transport:
          {ApprovalLossTransport,
           [url: "ws://127.0.0.1:#{port}/app-server", token: token, control: control]}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: assert(:ok = Session.close(pid))
    end)

    initialize(pid)

    %{
      binary: binary,
      fixture: fixture,
      root: root,
      pid: pid,
      owner: owner,
      control: control,
      kind:
        case tags.scenario do
          "file" -> "fileChange"
          "permission" -> "permissions"
          "command" -> "commandExecution"
        end,
      total: if(tags.scenario == "permission", do: 3, else: 2)
    }
  end

  for scenario <- ["file", "permission", "command"] do
    @tag scenario: scenario
    test "pending #{scenario} approval replays only after explicit warm resume with a fresh handle",
         ctx do
      {thread, turn, approval, _events} = pending(ctx)
      old_status = Session.status(ctx.pid)
      assert replies(ctx) == []
      reconnect(ctx, old_status, approval)
      assert replies(ctx) == []
      replay = resume_pending(ctx, thread, approval, old_status.generation)
      assert Session.interaction_outcomes(ctx.pid) == []
      assert_stale(ctx.pid, approval)
      assert %{interactions: 1} = Session.status(ctx.pid)
      assert_effect_absent(ctx)
      respond(ctx, replay)
      finish(ctx, thread, turn, replay.wire["id"])
      assert_effect(ctx)
      assert length(replies(ctx)) == 1
      assert_history(ctx, thread, turn)
      assert_no_execution_replay(ctx)
      assert_borrowed_owner(ctx)
    end

    @tag scenario: scenario
    test "lost outbound #{scenario} reply remains uncertain and pending replay requires a new explicit response",
         ctx do
      {thread, turn, approval, _events} = pending(ctx)
      old_status = Session.status(ctx.pid)
      arm(ctx, approval, :drop_reply_once)
      respond(ctx, approval)
      assert [%{disposition: :dropped}] = replies(ctx)

      assert [%{handle: handle, status: :sent_unconfirmed}] =
               Session.interaction_outcomes(ctx.pid)

      assert handle == approval.handle
      assert_effect_absent(ctx)
      assert length(ModelFixture.requests(ctx.fixture)) == 1
      reconnect(ctx, old_status, approval)
      assert_uncertain(ctx, approval)
      assert length(replies(ctx)) == 1
      replay = resume_pending(ctx, thread, approval, old_status.generation)
      assert_uncertain(ctx, approval)
      assert length(replies(ctx)) == 1
      assert_effect_absent(ctx)
      respond(ctx, replay)
      finish(ctx, thread, turn, replay.wire["id"])
      assert_effect(ctx)
      assert [dropped, forwarded] = replies(ctx)
      assert dropped.disposition == :dropped and forwarded.disposition == :forwarded
      assert dropped.digest == forwarded.digest
      assert_uncertain(ctx, approval)

      assert Enum.any?(
               Session.interaction_outcomes(ctx.pid),
               &(&1.handle == replay.handle and &1.status == :resolution_observed)
             )

      assert_history(ctx, thread, turn)
      assert_no_execution_replay(ctx)
      assert_borrowed_owner(ctx)
    end

    @tag scenario: scenario
    test "accepted #{scenario} reply with lost native notifications reconciles by read without replaying the response",
         ctx do
      {thread, turn, approval, _events} = pending(ctx)
      old_status = Session.status(ctx.pid)
      arm(ctx, approval, :suppress_notifications_after_reply)
      respond(ctx, approval)

      await(
        fn ->
          discarded = Agent.get(ctx.control, & &1.discarded)

          Enum.any?(
            discarded,
            &(&1.method == "serverRequest/resolved" and &1.thread_id == thread and
                &1.request_id == approval.wire["id"])
          ) and
            Enum.any?(
              discarded,
              &(&1.method == "turn/completed" and &1.thread_id == thread and &1.turn_id == turn and
                  &1.turn_status == "completed")
            )
        end,
        "actual native resolved/completed notifications discarded by transport"
      )

      assert_effect(ctx)

      assert [%{handle: handle, status: :sent_unconfirmed}] =
               Session.interaction_outcomes(ctx.pid)

      assert handle == approval.handle
      assert [%{disposition: :forwarded}] = replies(ctx)
      reconnect(ctx, old_status, approval, ctx.total)
      assert_uncertain(ctx, approval)
      resumed = call(ctx.pid, "thread/resume", %{"threadId" => thread})
      assert resumed["thread"]["id"] == thread
      assert_history(ctx, thread, turn)
      after_resume = quiet(ctx.pid)
      refute Enum.any?(after_resume, &(&1.kind == :server_request))
      assert_uncertain(ctx, approval)
      assert [%{disposition: :forwarded}] = replies(ctx)
      assert_effect(ctx)
      assert_no_execution_replay(ctx)
      # A read does not silently settle a response whose transport ACK was lost.
      # The owner must first journal the observed native result, then explicitly retire it.
      assert :ok = Session.acknowledge_interaction_outcome(ctx.pid, approval.handle)
      assert Session.interaction_outcomes(ctx.pid) == []
      assert_borrowed_owner(ctx)
    end
  end

  defp pending(ctx) do
    thread = thread(ctx, ctx.pid)

    turn =
      TurnFixture.start_turn(ctx.pid, thread, [
        %{"type" => "text", "text" => "Owned approval loss fixture only"}
      ])

    events = collect(ctx.pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/#{ctx.kind}/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == "approval-loss-1"
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0

    case ctx.kind do
      "fileChange" ->
        assert Map.fetch(params, "reason") == {:ok, nil}
        assert Map.fetch(params, "grantRoot") == {:ok, nil}

      "commandExecution" ->
        assert params["kind"] == "command"
        assert params["cwd"] == ctx.fixture.workspace
        assert params["reason"] == "Synthetic approval loss owned workspace only"
        assert OptionParser.split(params["command"]) == command_argv(ctx)
        assert params["proposedExecpolicyAmendment"] == [Path.join(ctx.fixture.bin, "sh")]
        assert params["networkApprovalContext"] == nil
        assert params["proposedNetworkPolicyAmendments"] == nil

      "permissions" ->
        assert Map.fetch(params, "environmentId") == {:ok, "local"}
        assert params["cwd"] == ctx.fixture.workspace
        assert params["reason"] == "Synthetic approval loss owned workspace only"
        assert params["permissions"]["fileSystem"]["write"] == [ctx.fixture.workspace]
    end

    assert_effect_absent(ctx)
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    {thread, turn, approval, events}
  end

  defp reconnect(ctx, old_status, approval, count \\ 1) do
    assert :ok = Session.reconnect(ctx.pid)
    assert %{phase: :new, generation: generation, instance_id: instance} = Session.status(ctx.pid)
    assert generation == old_status.generation + 1
    assert instance == old_status.instance_id
    assert Session.status(ctx.pid).gap.reason == :explicit_reconnect
    assert_stale(ctx.pid, approval)
    initialize(ctx.pid)
    assert is_list(call(ctx.pid, "thread/loaded/list", %{})["data"])
    before_resume = quiet(ctx.pid)
    refute Enum.any?(before_resume, &(&1.kind == :server_request))
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Agent.get(ctx.control, & &1.opens) == 2
    assert %{pending: 0, interactions: 0, uncertain: 0} = Session.status(ctx.pid)
  end

  defp resume_pending(ctx, thread, old, generation) do
    assert call(ctx.pid, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    events = collect(ctx.pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [replay] = Enum.filter(events, &(&1.kind == :server_request))
    assert replay.wire == old.wire
    assert replay.handle.id == old.handle.id
    assert replay.handle.generation == generation + 1
    assert replay.handle.reference != old.handle.reference
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    replay
  end

  defp respond(ctx, approval) do
    result =
      if ctx.kind != "permissions",
        do: %{"decision" => "accept"},
        else: %{
          "permissions" => %{"fileSystem" => %{"write" => [ctx.fixture.workspace]}},
          "scope" => "turn"
        }

    assert :ok = Session.respond(ctx.pid, approval.handle, {:ok, result})
  end

  defp finish(ctx, thread, turn, request_id) do
    events =
      collect(ctx.pid, [], fn events ->
        refute Enum.any?(events, &(&1.kind == :server_request)),
               "Unexpected approval or automatic work replay"

        not is_nil(notification(events, "turn/completed", &(&1["turn"]["id"] == turn))) and
          not is_nil(
            notification(events, "serverRequest/resolved", fn params ->
              params["threadId"] == thread and params["requestId"] == request_id
            end)
          )
      end)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^thread, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    if ctx.kind == "commandExecution" do
      assert [item] =
               for(
                 event <- events,
                 event.wire["method"] == "item/completed",
                 event.wire["params"]["threadId"] == thread,
                 event.wire["params"]["turnId"] == turn,
                 event.wire["params"]["item"]["type"] == "commandExecution",
                 do: event.wire["params"]["item"]
               )

      assert_command(ctx, item)
    end

    assert %{pending: 0, interactions: 0, uncertain: 0} = Session.status(ctx.pid)
  end

  defp arm(ctx, approval, mode),
    do: Agent.update(ctx.control, &%{&1 | target: approval.wire["id"], mode: mode})

  defp replies(ctx),
    do: Agent.get(ctx.control, &Enum.filter(&1.outbound, fn entry -> entry.kind == :reply end))

  defp assert_uncertain(ctx, approval) do
    assert Enum.any?(
             Session.interaction_outcomes(ctx.pid),
             &(&1.handle == approval.handle and &1.status == :uncertain)
           )
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(
               pid,
               approval.handle,
               {:error, %{"code" => -32_000, "message" => "Old connection handle"}}
             )
  end

  defp assert_effect_absent(ctx), do: assert(File.ls!(ctx.fixture.workspace) == [])

  defp assert_effect(%{kind: "commandExecution"} = ctx) do
    assert File.ls!(ctx.fixture.workspace) == ["loss-command.txt"]

    assert File.read!(Path.join(ctx.fixture.workspace, "loss-command.txt")) ==
             "owned recovered command\n"

    assert length(ModelFixture.requests(ctx.fixture)) == ctx.total
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp assert_effect(ctx) do
    assert File.ls!(ctx.fixture.workspace) == ["loss-approved.txt"]

    assert File.read!(Path.join(ctx.fixture.workspace, "loss-approved.txt")) ==
             "owned recovered approval\n"

    assert length(ModelFixture.requests(ctx.fixture)) == ctx.total
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp assert_history(ctx, thread, turn) do
    history =
      call(ctx.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"][
        "turns"
      ]

    assert [%{"id" => ^turn, "status" => "completed"}] = history

    if ctx.kind == "commandExecution" do
      assert [item] = Enum.filter(hd(history)["items"], &(&1["type"] == "commandExecution"))
      assert_command(ctx, item)
    end
  end

  defp command_argv(ctx), do: [Path.join(ctx.fixture.bin, "sh"), "-c", @command]

  defp assert_command(ctx, item) do
    assert item["id"] == "approval-loss-1"
    assert item["cwd"] == ctx.fixture.workspace
    assert OptionParser.split(item["command"]) == command_argv(ctx)
    assert item["status"] == "completed" and item["exitCode"] == 0
    assert item["aggregatedOutput"] == "samgita_loss_command"
  end

  defp assert_no_execution_replay(ctx) do
    methods = Agent.get(ctx.control, &Enum.map(&1.outbound, fn entry -> entry.method end))
    assert Enum.count(methods, &(&1 == "turn/start")) == 1
    assert Enum.count(methods, &(&1 == "thread/resume")) == 1
    assert length(ModelFixture.requests(ctx.fixture)) == ctx.total
  end

  defp assert_borrowed_owner(ctx) do
    assert Port.info(ctx.owner.port)
    assert Session.status(ctx.pid).transport["owned_process"] == false
    assert is_list(call(ctx.pid, "thread/loaded/list", %{})["data"])
  end

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_approval_loss_fixture", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )
  end

  defp listening?(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 25) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end

  defp await(predicate, label, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    if predicate.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "Deadline: #{label}"

      receive do
      after
        10 -> :ok
      end

      await(predicate, label, deadline)
    end
  end

  defp quiet(pid, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 200
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if System.monotonic_time(:millisecond) >= deadline do
      events
    else
      receive do
      after
        10 -> :ok
      end

      quiet(pid, events, deadline)
    end
  end

  defp collect(pid, events, done, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if done.(events) do
      events
    else
      assert Session.status(pid).phase == :ready
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, events, done, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> collect(pid, events, done, deadline)
      after
        remaining -> flunk("Native approval loss event deadline")
      end
    end
  end
end
