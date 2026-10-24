defmodule SamgitaCodexDriver.NativeCommandReplayCancellationTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ApprovalLossTransport,
    ModelFixture,
    NativeLaunchFixture,
    Session,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("support/native_command_replay_cancel_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-command-replay-cancel-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "command_replay_cancel")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    File.write!(Path.join(fixture.workspace, "canary.txt"), "OWNED_COMMAND_REPLAY_CANARY\n")
    ctx = %{fixture: fixture, binary: binary, root: root}
    TurnFixture.configure_model(ctx, %{})
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    assert :ok = :gen_tcp.close(listener)
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    digest = Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    {:ok, owner} =
      Stdio.open(
        executable: Path.expand(binary),
        args:
          NativeLaunchFixture.ordinary_args([
            "app-server",
            "--listen",
            "ws://127.0.0.1:#{port}",
            "--ws-auth",
            "capability-token",
            "--ws-token-sha256",
            digest
          ]),
        cwd: fixture.workspace,
        inherit_env: [],
        env: %{
          "HOME" => fixture.home,
          "CODEX_HOME" => fixture.codex_home,
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(fixture.bin, "sh"),
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
           [
             url: "ws://127.0.0.1:#{port}/app-server",
             token: token,
             control: control
           ]}
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    initialize(pid)
    Map.merge(ctx, %{pid: pid, control: control, owner: owner})
  end

  test "a replayed command callback is cancelled explicitly and cannot revive on another reconnect",
       ctx do
    pid = ctx.pid
    thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})

    turn =
      TurnFixture.start_turn(pid, thread, [
        %{"type" => "text", "text" => "Owned command replay cancellation only"}
      ])

    events = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [original] = Enum.filter(events, &(&1.kind == :server_request))
    assert original.wire["method"] == "item/commandExecution/requestApproval"
    params = original.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == "command-replay-cancel-1"
    assert params["kind"] == "command" and params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Synthetic fixture approval only"
    assert params["proposedExecpolicyAmendment"] == [Path.join(ctx.fixture.bin, "sh")]

    assert OptionParser.split(params["command"]) == [
             Path.join(ctx.fixture.bin, "sh"),
             "-c",
             "printf samgita_interaction"
           ]

    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert_no_effect(ctx, events)
    before = Session.status(pid)

    reconnect(ctx, before, 2)
    assert_stale(pid, original)
    assert call(pid, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    replayed = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [replay] = Enum.filter(replayed, &(&1.kind == :server_request))
    assert replay.wire == original.wire
    assert replay.handle.id == original.handle.id
    assert replay.handle.generation == before.generation + 1
    assert replay.handle.reference != original.handle.reference
    assert_stale(pid, original)
    assert %{interactions: 1} = Session.status(pid)
    assert_no_effect(ctx, replayed)

    # Explicit cancellation is independent of answering the approval. No reply is sent.
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}
    request_id = original.wire["id"]

    cancelled =
      collect(pid, [], fn collected ->
        refute Enum.any?(collected, &(&1.kind == :server_request))

        not is_nil(notification(collected, "turn/completed", &(&1["turn"]["id"] == turn))) and
          not is_nil(
            notification(collected, "serverRequest/resolved", &(&1["requestId"] == request_id))
          )
      end)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "interrupted"}} =
             notification(cancelled, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^thread, "requestId" => ^request_id} =
             notification(cancelled, "serverRequest/resolved", &(&1["requestId"] == request_id))

    assert_stale(pid, original)
    assert_stale(pid, replay)
    assert_idle(ctx)
    assert_no_effect(ctx, cancelled)
    assert_history(ctx, thread, turn)

    settled = Session.status(pid)
    reconnect(ctx, settled, 3)
    assert call(pid, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    after_resume = quiet(pid)
    refute Enum.any?(after_resume, &(&1.kind == :server_request))
    assert_no_effect(ctx, after_resume)
    assert_history(ctx, thread, turn)
    assert_stale(pid, original)
    assert_stale(pid, replay)
    assert_idle(ctx)

    outbound = Agent.get(ctx.control, & &1.outbound)
    assert Enum.filter(outbound, &(&1.kind == :reply)) == []
    methods = Enum.map(outbound, & &1.method)
    assert Enum.count(methods, &(&1 == "turn/start")) == 1
    assert Enum.count(methods, &(&1 == "turn/interrupt")) == 1
    assert Enum.count(methods, &(&1 == "thread/resume")) == 2

    assert Enum.all?(
             methods,
             &(&1 in [
                 "initialize",
                 "initialized",
                 "thread/start",
                 "turn/start",
                 "turn/interrupt",
                 "thread/resume",
                 "thread/read",
                 "thread/loaded/list"
               ])
           )

    assert Port.info(ctx.owner.port)
    assert Session.status(pid).transport["owned_process"] == false
    assert :ok = Session.close(pid)
    assert Port.info(ctx.owner.port)
    assert :ok = Stdio.close(ctx.owner)
    assert Port.info(ctx.owner.port) == nil
    assert :atomics.get(ctx.owner.owner.completion, 1) == 1
  end

  defp reconnect(ctx, before, opens) do
    assert :ok = Session.reconnect(ctx.pid)
    assert %{phase: :new, instance_id: instance, generation: generation} = Session.status(ctx.pid)
    assert instance == before.instance_id and generation == before.generation + 1
    assert Session.status(ctx.pid).gap.reason == :explicit_reconnect
    pid = ctx.pid

    assert_receive {:codex_driver, ^pid,
                    {:gap, %{reason: :explicit_reconnect, generation: previous_generation}}},
                   1_000

    assert previous_generation == before.generation
    initialize(ctx.pid)
    assert is_list(call(ctx.pid, "thread/loaded/list", %{})["data"])
    events = quiet(ctx.pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert_no_effect(ctx, events)
    assert_idle(ctx)
    assert Agent.get(ctx.control, & &1.opens) == opens
    assert Port.info(ctx.owner.port)
  end

  defp assert_history(ctx, thread, turn) do
    snapshot =
      call(ctx.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert snapshot["historyMode"] == "paginated"
    assert [%{"id" => ^turn, "status" => "interrupted", "items" => items}] = snapshot["turns"]
    # Pending unified exec never reaches its core execution emitter; the live
    # approval placeholder is not a durable command execution record.
    assert Enum.filter(items, &(&1["type"] == "commandExecution")) == []
    assert_no_effect(ctx, [])
  end

  defp assert_idle(ctx) do
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(ctx.pid)
    assert Session.interaction_outcomes(ctx.pid) == []
    assert Session.uncertain_operations(ctx.pid) == []
  end

  defp assert_no_effect(ctx, events) do
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert File.ls!(ctx.fixture.workspace) == ["canary.txt"]

    assert File.read!(Path.join(ctx.fixture.workspace, "canary.txt")) ==
             "OWNED_COMMAND_REPLAY_CANARY\n"

    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))

    refute Enum.any?(events, fn event ->
             event.wire["method"] == "item/commandExecution/outputDelta" or
               (event.wire["method"] == "item/completed" and
                  event.wire["params"]["item"]["type"] == "commandExecution" and
                  (event.wire["params"]["item"]["status"] == "completed" or
                     event.wire["params"]["item"]["aggregatedOutput"] not in [nil, ""]))
           end)
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_command_replay_cancel", "version" => "0.1.0"},
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
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, done, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected command replay cancellation event gap")
      after
        remaining ->
          flunk("Native command replay cancellation deadline: #{inspect(Session.status(pid))}")
      end
    end
  end
end
