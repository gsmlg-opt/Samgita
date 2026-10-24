defmodule SamgitaCodexDriver.NativeMultifileApprovalTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  import TurnFixture, only: [call: 3, thread: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/multifile_approval_fixture.py", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-multifile-approval-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "multifile_cache")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Registered native guardians run before provider close and root deletion.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "mixed cached and fresh file keys require one whole-patch approval", ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{})
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    a = Path.join(ctx.fixture.workspace, "approved.txt")
    b = Path.join(ctx.fixture.workspace, "other.txt")
    first_changes = [%{"path" => a, "kind" => %{"type" => "add"}, "diff" => "owned first\n"}]

    mixed_changes = [
      %{
        "path" => a,
        "kind" => %{"type" => "update", "move_path" => nil},
        "diff" => "@@ -1 +1 @@\n-owned first\n+owned mixed\n"
      },
      %{"path" => b, "kind" => %{"type" => "add"}, "diff" => "owned other\n"}
    ]

    reuse_changes = [
      %{
        "path" => a,
        "kind" => %{"type" => "update", "move_path" => nil},
        "diff" => "@@ -1 +1 @@\n-owned first\n+owned reused\n"
      }
    ]

    {first, granted, events} = pending(ctx, pid, id, "multifile-call-1", 1, first_changes)
    refute File.exists?(a)
    refute File.exists?(b)
    assert File.ls!(ctx.fixture.workspace) == []
    respond(pid, granted, "acceptForSession")
    finish(pid, id, first, events, granted, "multifile-call-1", "completed", first_changes)
    assert_files(ctx, a, b, "owned first\n")
    assert_provider(ctx, 2, ["multifile-call-1"])
    assert_stale(pid, granted)

    {mixed, declined, events} = pending(ctx, pid, id, "multifile-call-3", 3, mixed_changes)

    # The callback identifies the item; the correlated item carries BOTH changes.
    # No change is approved merely because A already has a cached session key.
    assert_files(ctx, a, b, "owned first\n")
    assert %{interactions: 1} = Session.status(pid)
    assert_stale(pid, granted)
    respond(pid, declined, "decline")
    finish(pid, id, mixed, events, declined, "multifile-call-3", "declined", mixed_changes)
    assert_files(ctx, a, b, "owned first\n")
    assert_provider(ctx, 4, ["multifile-call-1", "multifile-call-3"])
    assert_stale(pid, declined)

    # Declining A+B must not evict the original accepted-for-session key for A.
    third = start_turn(pid, id)
    events = finish(pid, id, third, [], nil, "multifile-call-5", "completed", reuse_changes)
    assert interactions(events) == []
    assert_files(ctx, a, b, "owned reused\n")
    assert_provider(ctx, 6, ["multifile-call-1", "multifile-call-3", "multifile-call-5"])
    assert_idle_without_rules(ctx, pid)

    # Independent exact history expectations; never copy a live item as oracle.
    assert [one, two, three] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    for {record, turn, call_id, status, changes} <- [
          {one, first, "multifile-call-1", "completed", first_changes},
          {two, mixed, "multifile-call-3", "declined", mixed_changes},
          {three, third, "multifile-call-5", "completed", reuse_changes}
        ] do
      assert record["id"] == turn and record["status"] == "completed"

      assert Enum.filter(record["items"], &(&1["type"] == "fileChange")) == [
               expected_item(call_id, status, changes)
             ]
    end

    assert_provider(ctx, 6, ["multifile-call-1", "multifile-call-3", "multifile-call-5"])
    assert_files(ctx, a, b, "owned reused\n")
    close_owned(pid)
    assert_files(ctx, a, b, "owned reused\n")
  end

  defp pending(ctx, pid, id, call_id, count, changes) do
    turn = start_turn(pid, id)
    events = collect(pid, [], &(interactions(&1) != []))
    assert [approval] = interactions(events)
    assert approval.wire["method"] == "item/fileChange/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == id and params["turnId"] == turn
    assert params["itemId"] == call_id
    assert Enum.sort(Map.keys(params)) == ~w(grantRoot itemId reason startedAtMs threadId turnId)
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert Map.fetch(params, "reason") == {:ok, nil}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}
    assert approval.handle.id == approval.wire["id"]
    assert approval.handle.generation == Session.status(pid).generation
    assert is_reference(approval.handle.reference)

    assert %{"threadId" => ^id, "turnId" => ^turn, "item" => item} =
             notification(events, "item/started", &(&1["item"]["id"] == call_id))

    assert item == expected_item(call_id, "inProgress", changes)
    refute notification(events, "item/completed", &(&1["item"]["id"] == call_id))
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    {turn, approval, events}
  end

  defp finish(pid, id, turn, events, approval, call_id, status, changes) do
    initial_count = length(interactions(events))

    events =
      collect(pid, events, fn all ->
        assert length(interactions(all)) == initial_count,
               "Unexpected extra native approval; no generic handler is installed"

        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
          (is_nil(approval) ||
             notification(
               all,
               "serverRequest/resolved",
               &(&1["requestId"] == approval.wire["id"])
             ))
      end)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^id, "turnId" => ^turn, "item" => item} =
             notification(events, "item/completed", &(&1["item"]["id"] == call_id))

    assert item == expected_item(call_id, status, changes)

    if approval do
      assert [^approval] = interactions(events)
      request_id = approval.wire["id"]

      assert %{"threadId" => ^id, "requestId" => ^request_id} =
               notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

      assert [outcome] =
               Enum.filter(Session.interaction_outcomes(pid), &(&1.handle == approval.handle))

      assert outcome.status == :resolution_observed
    end

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    events
  end

  defp expected_item(call_id, status, changes),
    do: %{"id" => call_id, "type" => "fileChange", "status" => status, "changes" => changes}

  defp assert_files(ctx, a, b, bytes) do
    assert File.lstat!(a).type == :regular
    assert File.read!(a) == bytes
    refute File.exists?(b)
    assert File.ls!(ctx.fixture.workspace) == ["approved.txt"]
  end

  defp assert_provider(ctx, count, call_ids) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count

    for {call_id, index} <- Enum.with_index(call_ids) do
      continued = Enum.at(requests, index * 2 + 1)

      assert [output] =
               Enum.filter(continued["input"], fn item ->
                 item["type"] == "function_call_output" and item["call_id"] == call_id
               end)

      assert is_binary(output["output"])

      if call_id == "multifile-call-3" do
        assert output["output"] =~ "patch rejected by user"
      else
        assert output["output"] =~ "Success. Updated the following files:"
        assert output["output"] =~ "approved.txt"
      end
    end

    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
  end

  defp respond(pid, approval, decision),
    do: assert(:ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => decision}}))

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp assert_idle_without_rules(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp start_turn(pid, id),
    do:
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned multi-file approval cache only"}
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
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, done, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during multi-file approval")
      after
        remaining -> flunk("Native multi-file approval deadline: #{inspect(Session.status(pid))}")
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
               %{"name" => "samgita_multifile_approval", "version" => "0.1.0"},
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
