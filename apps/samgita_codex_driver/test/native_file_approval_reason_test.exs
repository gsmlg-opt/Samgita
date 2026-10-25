defmodule SamgitaCodexDriver.NativeFileApprovalReasonTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [thread: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/file_approval_reason_fixture.py", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @canary "OWNED_UNCHANGED_FILE_REASON_CANARY\n"

  setup do
    assert {:unix, :linux} = :os.type()
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-file-reason-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "file_approval_reason")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    target = Path.join(fixture.workspace, "locked.txt")
    File.write!(target, "owned before\n")
    File.chmod!(target, 0o600)
    File.write!(Path.join(fixture.workspace, "canary.txt"), @canary)
    # Guardians registered in start/1 run first. Restore only this owned file.
    on_exit(fn -> if File.exists?(target), do: File.chmod!(target, 0o600) end)
    ctx = %{binary: binary, root: root, fixture: fixture, target: target}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "owned write succeeds before chmod then native retry reason is explicitly declined", ctx do
    pid = start(ctx)

    id =
      thread(ctx, pid, %{
        "sandbox" => "workspace-write",
        "approvalPolicy" => "on-request",
        "approvalsReviewer" => "user"
      })

    assert ModelFixture.requests(ctx.fixture) == []
    assert_files(ctx, "owned before\n", 0o600)

    positive_changes = [
      %{
        "path" => ctx.target,
        "kind" => %{"type" => "update", "move_path" => nil},
        "diff" => "@@ -1 +1 @@\n-owned before\n+owned ready\n"
      }
    ]

    first = start_turn(pid, id)

    events =
      collect(pid, [], fn all ->
        assert interactions(all) == [], "Positive control unexpectedly required approval"
        notification(all, "turn/completed", &(&1["turn"]["id"] == first))
      end)

    assert_turn_and_item(events, id, first, "file-reason-call-1", "completed", positive_changes)
    assert_files(ctx, "owned ready\n", 0o600)
    assert_provider(ctx, 2, "file-reason-call-1", "Success. Updated the following files:")
    assert_idle(ctx, pid)

    File.chmod!(ctx.target, 0o444)
    assert_files(ctx, "owned ready\n", 0o444)

    assert File.stat!(ctx.target).access == :read,
           "BLOCKED_ENV: owned mode-0444 file must be readable and non-writable by this uid"

    denied_changes = [
      %{
        "path" => ctx.target,
        "kind" => %{"type" => "update", "move_path" => nil},
        "diff" => "@@ -1 +1 @@\n-owned ready\n+owned blocked\n"
      }
    ]

    second = start_turn(pid, id)
    events = collect(pid, [], &(interactions(&1) != []))
    assert [approval] = interactions(events)
    assert approval.wire["method"] == "item/fileChange/requestApproval"
    # Pinned Codex allocates server request IDs from AtomicI64 initialized at zero.
    assert is_integer(approval.wire["id"]) and approval.wire["id"] >= 0
    params = approval.wire["params"]
    assert Enum.sort(Map.keys(params)) == ~w(grantRoot itemId reason startedAtMs threadId turnId)
    assert params["threadId"] == id and params["turnId"] == second
    assert params["itemId"] == "file-reason-call-3"
    assert Map.fetch(params, "reason") == {:ok, "command failed; retry without sandbox?"}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert approval.handle.id == approval.wire["id"]
    assert approval.handle.generation == Session.status(pid).generation
    assert is_reference(approval.handle.reference)
    assert_files(ctx, "owned ready\n", 0o444)
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert %{"threadId" => ^id, "turnId" => ^second, "item" => item} =
             notification(events, "item/started", &(&1["item"]["id"] == "file-reason-call-3"))

    assert item == expected_item("file-reason-call-3", "inProgress", denied_changes)
    refute notification(events, "item/completed", &(&1["item"]["id"] == "file-reason-call-3"))
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == second))

    # Never accept the request to retry without sandbox. No generic handler exists.
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "decline"}})
    request_id = approval.wire["id"]

    events =
      collect(pid, events, fn all ->
        assert [^approval] = interactions(all)

        notification(all, "turn/completed", &(&1["turn"]["id"] == second)) &&
          notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
      end)

    assert_turn_and_item(events, id, second, "file-reason-call-3", "declined", denied_changes)

    assert %{"threadId" => ^id, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    assert [outcome] =
             Enum.filter(Session.interaction_outcomes(pid), &(&1.handle == approval.handle))

    assert outcome.status == :resolution_observed

    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})

    assert_provider(ctx, 4, "file-reason-call-3", "patch rejected by user")
    assert_files(ctx, "owned ready\n", 0o444)
    assert_idle(ctx, pid)
    close_owned(pid)
    assert_files(ctx, "owned ready\n", 0o444)
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    File.chmod!(ctx.target, 0o600)
    assert_files(ctx, "owned ready\n", 0o600)
  end

  defp expected_item(id, status, changes),
    do: %{"id" => id, "type" => "fileChange", "status" => status, "changes" => changes}

  defp assert_turn_and_item(events, thread, turn, call_id, status, changes) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert [item] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["turnId"] == turn,
               event.wire["params"]["item"]["type"] == "fileChange",
               do: event.wire["params"]["item"]
             )

    assert item == expected_item(call_id, status, changes)
    refute Enum.any?(events, &(&1.wire["method"] in ["warning", "error"]))
  end

  defp assert_files(ctx, bytes, mode) do
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["canary.txt", "locked.txt"]
    assert File.lstat!(ctx.target).type == :regular
    assert File.read!(ctx.target) == bytes
    assert Bitwise.band(File.stat!(ctx.target).mode, 0o777) == mode
    canary = Path.join(ctx.fixture.workspace, "canary.txt")
    assert File.lstat!(canary).type == :regular
    assert File.read!(canary) == @canary
  end

  defp assert_provider(ctx, count, call_id, text) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))

    assert [output] =
             Enum.filter(
               List.last(requests)["input"],
               &(&1["type"] == "function_call_output" and &1["call_id"] == call_id)
             )

    assert output["output"] =~ text
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp start_turn(pid, id),
    do:
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned readonly file retry-reason fixture only"}
      ])

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
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected file retry-reason gap")
      after
        remaining -> flunk("Native file retry-reason deadline: #{inspect(Session.status(pid))}")
      end
    end
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
               %{"name" => "samgita_file_retry_reason", "version" => "0.1.0"},
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

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))
end
