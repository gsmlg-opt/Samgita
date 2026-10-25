defmodule SamgitaCodexDriver.NativeIndependentCommandApprovalsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Error, Wire}
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("support/native_independent_command_approvals_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    assert {:unix, :linux} = :os.type()
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-independent-approvals-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "independent_command_approvals")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "two pending native commands retain independent explicit decline and acceptance", ctx do
    pid = start(ctx)

    thread =
      TurnFixture.thread(ctx, pid, %{
        "historyMode" => "paginated",
        "approvalsReviewer" => "user"
      })

    turn =
      TurnFixture.start_turn(pid, thread, [
        %{"type" => "text", "text" => "Owned independent command approvals only"}
      ])

    # Both callbacks must coexist before either receives an answer. Accumulating
    # two callbacks across already-settled steps does not meet this barrier.
    events =
      collect(pid, [], fn all ->
        assert length(interactions(all)) <= 2
        length(interactions(all)) == 2
      end)

    approvals = Map.new(interactions(events), &{&1.wire["params"]["itemId"], &1})
    assert Enum.sort(Map.keys(approvals)) == ~w(independent-command-A independent-command-B)
    a = Map.fetch!(approvals, "independent-command-A")
    b = Map.fetch!(approvals, "independent-command-B")
    assert a.wire["id"] != b.wire["id"]
    assert a.handle.reference != b.handle.reference

    for {label, approval} <- [{"A", a}, {"B", b}] do
      assert_approval(ctx, pid, approval, thread, turn, label)
      assert [started] = command_items(events, "item/started", label)
      assert started["status"] == "inProgress"
      assert started["cwd"] == ctx.fixture.workspace
      assert started["command"] === command_display(ctx, label)
    end

    assert %{interactions: 2, interaction_outcomes: 0} = Session.status(pid)
    assert Session.interaction_outcomes(pid) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_files(ctx, false)
    assert_clean(pid, events)
    refute_output(events)
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert command_items(events, "item/completed", "A") == []
    assert command_items(events, "item/completed", "B") == []
    original_a = Map.fetch!(:sys.get_state(pid).interactions, a.handle.id)
    assert original_a.handle == a.handle
    assert is_integer(Process.read_timer(original_a.timer))

    # B is declined explicitly while A remains unanswered. No generic responder
    # runs in collect/3, and no grant/cache/policy amendment can release A.
    assert :ok = Session.respond(pid, b.handle, {:ok, %{"decision" => "decline"}})

    events =
      collect(pid, events, fn all ->
        assert length(interactions(all)) == 2
        resolved?(all, b) and command_items(all, "item/completed", "B") != []
      end)

    assert [declined] = command_items(events, "item/completed", "B")
    assert_declined(ctx, declined)
    assert_resolution(events, b, thread)
    refute resolved?(events, a)
    assert command_items(events, "item/completed", "A") == []
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert ^original_a = Map.fetch!(:sys.get_state(pid).interactions, a.handle.id)
    assert is_integer(Process.read_timer(original_a.timer))
    assert %{interactions: 1, interaction_outcomes: 1} = Session.status(pid)
    assert_outcome(pid, b, "decline")
    assert_stale(pid, b, "decline")
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_files(ctx, false)
    refute_output(events)
    assert_clean(pid, events)

    # Only this exact still-pending handle receives one explicit acceptance.
    assert :ok = Session.respond(pid, a.handle, {:ok, %{"decision" => "accept"}})

    events =
      collect(pid, events, fn all ->
        assert length(interactions(all)) == 2

        resolved?(all, a) and
          notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) != nil
      end)

    assert [accepted] = command_items(events, "item/completed", "A")
    assert_accepted(ctx, accepted)
    assert [^declined] = command_items(events, "item/completed", "B")

    for method <- ["item/started", "item/completed"] do
      command_params =
        Enum.filter(params(events, method), &(&1["item"]["type"] == "commandExecution"))

      assert Enum.sort(Enum.map(command_params, & &1["item"]["id"])) ==
               ~w(independent-command-A independent-command-B)

      assert Enum.all?(command_params, &(&1["threadId"] == thread and &1["turnId"] == turn))
    end

    assert Enum.all?(params(events, "item/commandExecution/outputDelta"), fn delta ->
             delta["threadId"] == thread and delta["turnId"] == turn and
               delta["itemId"] == "independent-command-A"
           end)

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    assert length(params(events, "serverRequest/resolved")) == 2
    assert_resolution(events, a, thread)
    assert_resolution(events, b, thread)

    for {label, approval, decision} <- [{"A", a, "accept"}, {"B", b, "decline"}] do
      assert length(command_items(events, "item/started", label)) == 1
      assert_outcome(pid, approval, decision)
      assert_stale(pid, approval, decision)
    end

    assert %{interactions: 0, interaction_outcomes: 2} = Session.status(pid)
    assert_clean(pid, events)
    assert_files(ctx, true)
    assert_provider(ctx)
    assert_history(ctx, pid, thread, turn, accepted)
    close_owned(pid)
    assert_files(ctx, true)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
  end

  defp assert_approval(ctx, pid, approval, thread, turn, label) do
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == "independent-command-#{label}"
    assert params["kind"] == "command" and params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Owned independent command #{label} only"
    assert params["command"] === command_display(ctx, label)
    assert params["networkApprovalContext"] == nil
    assert params["proposedNetworkPolicyAmendments"] == nil
    assert params["approvalId"] == nil
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert is_binary(Map.fetch!(params, "command"))

    # Command display and generated timestamp are checked above. Exact map equality
    # also rejects unexpected fields and null values for omitted options.
    assert Map.drop(params, ["command", "startedAtMs"]) == %{
             "kind" => "command",
             "threadId" => thread,
             "turnId" => turn,
             "itemId" => "independent-command-#{label}",
             "environmentId" => "local",
             "reason" => "Owned independent command #{label} only",
             "cwd" => ctx.fixture.workspace,
             "commandActions" => [%{"type" => "unknown", "command" => command(label)}],
             "proposedExecpolicyAmendment" => shell_amendment(ctx),
             "availableDecisions" => [
               "accept",
               %{
                 "acceptWithExecpolicyAmendment" => %{
                   "execpolicy_amendment" => shell_amendment(ctx)
                 }
               },
               "cancel"
             ]
           }

    assert approval.handle.id == approval.wire["id"]
    assert approval.handle.generation == Session.status(pid).generation
    assert is_reference(approval.handle.reference)
  end

  defp assert_accepted(ctx, item) do
    assert item["id"] == "independent-command-A" and item["type"] == "commandExecution"
    assert item["status"] == "completed" and item["exitCode"] == 0
    assert item["aggregatedOutput"] == "owned-A"
    assert item["cwd"] == ctx.fixture.workspace
    assert item["command"] === command_display(ctx, "A")
  end

  defp assert_declined(ctx, item) do
    assert item["id"] == "independent-command-B" and item["type"] == "commandExecution"
    assert item["status"] == "declined"
    assert item["exitCode"] == nil and item["aggregatedOutput"] == nil
    assert item["processId"] == nil and item["durationMs"] == nil
    assert item["cwd"] == ctx.fixture.workspace
    assert item["command"] === command_display(ctx, "B")
  end

  defp assert_history(ctx, pid, thread, turn, accepted) do
    history = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert history["id"] == thread
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = history["turns"]
    assert [persisted] = Enum.filter(items, &(&1["type"] == "commandExecution"))
    assert_accepted(ctx, persisted)

    assert Map.take(persisted, ~w(id type status cwd command exitCode aggregatedOutput)) ==
             Map.take(accepted, ~w(id type status cwd command exitCode aggregatedOutput))

    # Pinned pre-launch declines are synthesized live before core execution;
    # they are absent from durable command history, rather than invented here.
    refute Enum.any?(items, &(&1["id"] == "independent-command-B"))
  end

  defp assert_provider(ctx) do
    assert [first, second] = requests = ModelFixture.requests(ctx.fixture)
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
    assert Enum.filter(first["input"], &(&1["type"] == "function_call_output")) == []
    outputs = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))

    assert Enum.sort(Enum.map(outputs, & &1["call_id"])) ==
             ~w(independent-command-A independent-command-B)

    outputs = Map.new(outputs, &{&1["call_id"], &1["output"]})
    assert outputs["independent-command-A"] =~ "Process exited with code 0"
    assert String.ends_with?(outputs["independent-command-A"], "Output:\nowned-A")
    assert outputs["independent-command-B"] =~ "rejected by user"
    refute outputs["independent-command-B"] =~ "Process exited with code 0"
    refute outputs["independent-command-B"] =~ "Output:\nowned-B"
  end

  defp assert_files(ctx, accepted?) do
    if accepted? do
      assert File.ls!(ctx.fixture.workspace) == ["a.txt"]
      path = Path.join(ctx.fixture.workspace, "a.txt")
      assert File.lstat!(path).type == :regular
      assert File.read!(path) == "owned-A\n"
    else
      assert File.ls!(ctx.fixture.workspace) == []
    end

    refute File.exists?(Path.join(ctx.fixture.workspace, "b.txt"))
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp assert_clean(pid, events) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ["warning", "error", "item/autoApprovalReview/started"]
           end)
  end

  defp assert_outcome(pid, approval, decision) do
    assert [outcome] =
             Enum.filter(Session.interaction_outcomes(pid), &(&1.handle == approval.handle))

    assert outcome.method == approval.wire["method"]
    assert outcome.thread_id == approval.wire["params"]["threadId"]
    assert outcome.status == :resolution_observed

    assert {:ok, encoded} =
             Wire.encode(%{"id" => approval.wire["id"], "result" => %{"decision" => decision}})

    assert outcome.response_digest ==
             Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
  end

  defp assert_stale(pid, approval, decision) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => decision}})
  end

  defp assert_resolution(events, approval, thread) do
    request_id = approval.wire["id"]

    assert [%{"threadId" => ^thread, "requestId" => ^request_id}] =
             Enum.filter(
               params(events, "serverRequest/resolved"),
               &(&1["requestId"] == request_id)
             )
  end

  defp resolved?(events, approval),
    do:
      Enum.any?(
        params(events, "serverRequest/resolved"),
        &(&1["requestId"] == approval.wire["id"])
      )

  defp command_items(events, method, label) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["item"]["type"] == "commandExecution",
        event.wire["params"]["item"]["id"] == "independent-command-#{label}",
        do: event.wire["params"]["item"]
  end

  defp refute_output(events),
    do: refute(Enum.any?(events, &(&1.wire["method"] == "item/commandExecution/outputDelta")))

  defp shell_amendment(ctx), do: [Path.join(ctx.fixture.bin, "sh")]

  # Pinned shlex 1.3.0 double-quotes these two fixed scripts and doubles their
  # backslash. OptionParser.split/1 does not invert that native display format.
  defp command_display(ctx, "A"),
    do:
      Path.join(ctx.fixture.bin, "sh") <>
        ~S( -c "printf 'owned-A\\n' >> a.txt && printf owned-A")

  defp command_display(ctx, "B"),
    do:
      Path.join(ctx.fixture.bin, "sh") <>
        ~S( -c "printf 'owned-B\\n' >> b.txt && printf owned-B")

  defp command(label),
    do: "printf 'owned-#{label}\\n' >> #{String.downcase(label)}.txt && printf owned-#{label}"

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))

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
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected independent approvals event gap")
      after
        remaining ->
          flunk("Native independent approvals deadline: #{inspect(Session.status(pid))}")
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
               %{"name" => "samgita_independent_command_approvals", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1
  end
end
