defmodule SamgitaCodexDriver.NativeCommandCacheContextTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("support/native_command_cache_context_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-command-cache-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "command_cache_context")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    a = Path.join(fixture.workspace, "context-a")
    b = Path.join(fixture.workspace, "context-b")

    for directory <- [a, b] do
      File.mkdir!(directory)
      File.write!(Path.join(directory, "canary.txt"), "OWNED_UNCHANGED_CACHE_CANARY\n")
    end

    ctx = %{binary: binary, fixture: fixture, root: root, a: a, b: b}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "browser_use = false\ncomputer_use = false\n"
    )

    ctx
  end

  test "command session cache distinguishes cwd and disappears after cold native resume", ctx do
    pid = start(ctx)
    thread = TurnFixture.thread(ctx, pid)
    {first, approval, events} = pending(ctx, pid, thread, ctx.a, 1)
    respond(pid, approval, "acceptForSession")
    events = finish(pid, thread, first, events)
    assert_command(ctx, events, first, ctx.a, 1, "completed", 0, "samgita_interaction")
    assert_stale(pid, approval)
    assert_idle(ctx, pid, 2)

    second = start_turn(pid, thread)
    events = finish(pid, thread, second, [])
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert_command(ctx, events, second, ctx.a, 3, "completed", 0, "samgita_interaction")
    assert_idle(ctx, pid, 4)

    {third, other_cwd, events} = pending(ctx, pid, thread, ctx.b, 5)
    assert_stale(pid, approval)
    respond(pid, other_cwd, "decline")
    events = finish(pid, thread, third, events)
    assert_command(ctx, events, third, ctx.b, 5, "declined", nil, nil)
    refute_output(events)
    assert_stale(pid, other_cwd)
    assert_idle(ctx, pid, 6)
    assert_history(ctx, pid, thread, [first, second, third])
    instance = Session.status(pid).instance_id
    old_connection = close_owned(pid)

    cold = start(ctx)
    assert Session.status(cold).instance_id != instance
    %{connection: cold_connection} = :sys.get_state(cold)
    assert cold_connection.port != old_connection.port
    assert call(cold, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert_idle(ctx, cold, 6)

    {fourth, after_restart, events} = pending(ctx, cold, thread, ctx.a, 7)
    assert_stale(cold, approval)
    assert_stale(cold, other_cwd)
    respond(cold, after_restart, "decline")
    events = finish(cold, thread, fourth, events)
    assert_command(ctx, events, fourth, ctx.a, 7, "declined", nil, nil)
    refute_output(events)
    assert_stale(cold, after_restart)
    assert_idle(ctx, cold, 8)
    assert_history(ctx, cold, thread, [first, second, third, fourth])
    close_owned(cold)
  end

  defp pending(ctx, pid, thread, cwd, index) do
    turn = start_turn(pid, thread)
    events = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == "command-cache-call-#{index}"
    assert params["kind"] == "command" and params["cwd"] == cwd
    assert params["reason"] == "Synthetic fixture approval only"
    assert params["proposedExecpolicyAmendment"] == [Path.join(ctx.fixture.bin, "sh")]
    assert params["networkApprovalContext"] == nil
    assert params["proposedNetworkPolicyAmendments"] == nil
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert OptionParser.split(params["command"]) == argv(ctx)
    assert approval.handle.id == approval.wire["id"]
    assert is_reference(approval.handle.reference)
    assert length(ModelFixture.requests(ctx.fixture)) == index
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    refute_output(events)
    assert_canaries(ctx)
    {turn, approval, events}
  end

  defp finish(pid, thread, turn, events) do
    approvals = Enum.count(events, &(&1.kind == :server_request))

    events =
      collect(pid, events, fn collected ->
        assert Enum.count(collected, &(&1.kind == :server_request)) == approvals,
               "Unexpected extra native approval; no implicit approval is permitted"

        notification(collected, "turn/completed", &(&1["turn"]["id"] == turn))
      end)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    events
  end

  defp assert_command(ctx, events, turn, cwd, index, status, exit_code, output) do
    assert [item] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["turnId"] == turn,
               event.wire["params"]["item"]["type"] == "commandExecution",
               do: event.wire["params"]["item"]
             )

    assert item["id"] == "command-cache-call-#{index}"
    assert item["cwd"] == cwd
    assert OptionParser.split(item["command"]) == argv(ctx)
    assert item["status"] == status and item["exitCode"] == exit_code
    assert item["aggregatedOutput"] == output
    refute Enum.any?(events, &(&1.wire["method"] in ["warning", "error"]))
  end

  defp assert_history(ctx, pid, thread, turns) do
    history =
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]["turns"]

    assert Enum.map(history, & &1["id"]) == turns
    assert Enum.all?(history, &(&1["status"] == "completed"))

    expected =
      Enum.take(
        [
          {ctx.a, "completed", 0, "samgita_interaction"},
          {ctx.a, "completed", 0, "samgita_interaction"},
          {ctx.b, "declined", nil, nil},
          {ctx.a, "declined", nil, nil}
        ],
        length(turns)
      )

    for {turn, {cwd, status, code, output}} <- Enum.zip(history, expected) do
      commands = Enum.filter(turn["items"], &(&1["type"] == "commandExecution"))

      if status == "declined" do
        # The app-server synthesizes a live decline before the core execution
        # emitter starts; the pinned store has no command item for that turn.
        assert commands == []
      else
        assert [item] = commands
        assert item["cwd"] == cwd and OptionParser.split(item["command"]) == argv(ctx)
        assert item["status"] == status and item["exitCode"] == code
        assert item["aggregatedOutput"] == output
      end
    end
  end

  defp refute_output(events) do
    refute Enum.any?(events, fn event ->
             event.wire["method"] == "item/commandExecution/outputDelta" or
               (event.wire["method"] == "item/completed" and
                  event.wire["params"]["item"]["type"] == "commandExecution" and
                  event.wire["params"]["item"]["aggregatedOutput"] not in [nil, ""])
           end)
  end

  defp assert_idle(ctx, pid, count) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert length(ModelFixture.requests(ctx.fixture)) == count
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
    assert_canaries(ctx)
  end

  defp assert_canaries(ctx) do
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["context-a", "context-b"]

    for cwd <- [ctx.a, ctx.b] do
      assert File.ls!(cwd) == ["canary.txt"]
      assert File.read!(Path.join(cwd, "canary.txt")) == "OWNED_UNCHANGED_CACHE_CANARY\n"
    end
  end

  defp respond(pid, approval, decision),
    do: assert(:ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => decision}}))

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp close_owned(pid) do
    %{connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = Session.close(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1
    connection
  end

  defp start_turn(pid, thread),
    do:
      TurnFixture.start_turn(pid, thread, [
        %{"type" => "text", "text" => "Owned command cache fixture only"}
      ])

  defp argv(ctx), do: [Path.join(ctx.fixture.bin, "sh"), "-c", "printf samgita_interaction"]

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
        {:codex_driver, ^pid, :events_available} -> collect(pid, events, done, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native command-cache event gap")
      after
        remaining -> flunk("Native command-cache deadline: #{inspect(Session.status(pid))}")
      end
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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_command_cache_context", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
