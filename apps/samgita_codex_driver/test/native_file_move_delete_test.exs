defmodule SamgitaCodexDriver.NativeFileMoveDeleteTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, thread: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/file_move_delete_fixture.py", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @canary "OWNED_UNCHANGED_MOVE_DELETE_CANARY\n"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-file-move-delete-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "file_move_delete")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Native process guardians registered later run before provider/root teardown.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    File.write!(Path.join(fixture.workspace, "origin.txt"), "owned before\n")
    File.write!(Path.join(fixture.workspace, "canary.txt"), @canary)
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "approved native move retains its populated target and delete requires explicit approval",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []
    origin = Path.join(ctx.fixture.workspace, "origin.txt")
    moved = Path.join(ctx.fixture.workspace, "moved.txt")

    move_changes = [
      %{
        "path" => origin,
        "kind" => %{"type" => "update", "move_path" => moved},
        "diff" => "@@ -1 +1 @@\n-owned before\n+owned moved\n\n\nMoved to: #{moved}"
      }
    ]

    delete_changes = [
      %{"path" => moved, "kind" => %{"type" => "delete"}, "diff" => "owned moved\n"}
    ]

    # Constants precede observation; no expected item is copied from the wire.
    stages = [
      {1, "accept", "completed", move_changes, :initial, :moved, "M moved.txt"},
      {3, "decline", "declined", delete_changes, :moved, :moved, "moved.txt"},
      {5, "accept", "completed", delete_changes, :moved, :deleted, "D moved.txt"}
    ]

    records =
      for {index, decision, status, changes, before_state, after_state, path_label} <- stages do
        assert_files(ctx, before_state)
        call_id = "file-move-delete-call-#{index}"
        {turn, approval, events} = pending(ctx, pid, id, call_id, index, changes)
        assert_files(ctx, before_state)
        assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => decision}})
        finish(pid, id, turn, approval, events, expected_item(call_id, status, changes))
        assert_files(ctx, after_state)
        assert_provider(ctx, index + 1, call_id, status, path_label)
        assert_stale(pid, approval)

        %{
          turn: turn,
          approval: approval,
          query: %{"threadId" => id, "turnId" => turn, "itemIds" => [call_id]},
          expected: expected_item(call_id, status, changes)
        }
      end

    assert length(Enum.uniq_by(records, & &1.approval.wire["id"])) == 3
    assert_files(ctx, :deleted)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 6
    assert_history(pid, id, records)

    warm =
      for record <- records do
        response = call(pid, "thread/items/read", record.query)
        assert_direct(response, record)
        assert_files(ctx, :deleted)
        assert ModelFixture.requests(ctx.fixture) == requests
        response
      end

    assert_idle(ctx, pid)
    instance = Session.status(pid).instance_id
    native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    old_connection = close_owned(pid)
    cold = start(ctx)
    assert Session.status(cold).instance_id != instance
    %{connection: cold_connection} = :sys.get_state(cold)
    assert cold_connection.port != old_connection.port
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # Direct persisted reads in a distinct native process; no resume or new turn.
    for {record, previous_response} <- Enum.zip(records, warm) do
      response = call(cold, "thread/items/read", record.query)
      assert_direct(response, record)
      assert response == previous_response
      assert_files(ctx, :deleted)
      assert ModelFixture.requests(ctx.fixture) == requests
      assert_stale(cold, record.approval)
    end

    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_history(cold, id, records)
    assert ModelFixture.requests(ctx.fixture) == requests
    assert_idle(ctx, cold)
    close_owned(cold)
    assert_files(ctx, :deleted)
    assert ModelFixture.requests(ctx.fixture) == requests
  end

  test "approved delete of an externally removed owned target fails durably without retry", ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []
    origin = Path.join(ctx.fixture.workspace, "origin.txt")
    moved = Path.join(ctx.fixture.workspace, "moved.txt")

    move_changes = [
      %{
        "path" => origin,
        "kind" => %{"type" => "update", "move_path" => moved},
        "diff" => "@@ -1 +1 @@\n-owned before\n+owned moved\n\n\nMoved to: #{moved}"
      }
    ]

    delete_changes = [
      %{"path" => moved, "kind" => %{"type" => "delete"}, "diff" => "owned moved\n"}
    ]

    stages = [
      {1, "completed", move_changes, :initial, :moved},
      {3, "failed", delete_changes, :moved, :deleted}
    ]

    records =
      for {index, status, changes, before_state, after_state} <- stages do
        assert_files(ctx, before_state)
        call_id = "file-move-delete-call-#{index}"
        {turn, approval, events} = pending(ctx, pid, id, call_id, index, changes)
        assert_files(ctx, before_state)

        if index == 3 do
          # The operator fixture changes only its exact owned target after native
          # approval captures the delete. This is not a native deletion effect.
          assert Path.dirname(moved) == ctx.fixture.workspace
          assert File.lstat!(moved).type == :regular
          assert File.read!(moved) == "owned moved\n"
          assert :ok = File.rm(moved)
          assert_files(ctx, :deleted)
        end

        assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
        finish(pid, id, turn, approval, events, expected_item(call_id, status, changes))
        assert_files(ctx, after_state)

        if index == 1 do
          assert_provider(ctx, 2, call_id, "completed", "M moved.txt")
        else
          requests = ModelFixture.requests(ctx.fixture)
          assert length(requests) == 4
          assert Enum.all?(requests, &(&1["model"] == "mock-model"))

          assert [output] =
                   Enum.filter(
                     List.last(requests)["input"],
                     &(&1["type"] == "function_call_output" and &1["call_id"] == call_id)
                   )

          assert is_binary(output["output"])
          assert output["output"] =~ "Exit code: 1\n"

          assert String.ends_with?(
                   output["output"],
                   "\nOutput:\nFailed to delete file #{moved}\n"
                 )

          refute output["output"] =~ "Success. Updated the following files:"
          refute output["output"] =~ "patch rejected by user"
          refute output["output"] =~ "retry without sandbox"
        end

        assert_stale(pid, approval)

        %{
          turn: turn,
          approval: approval,
          query: %{"threadId" => id, "turnId" => turn, "itemIds" => [call_id]},
          expected: expected_item(call_id, status, changes)
        }
      end

    assert length(Enum.uniq_by(records, & &1.approval.wire["id"])) == 2
    assert_files(ctx, :deleted)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 4
    assert_history(pid, id, records)

    warm =
      for record <- records do
        response = call(pid, "thread/items/read", record.query)
        assert_direct(response, record)
        assert_files(ctx, :deleted)
        assert ModelFixture.requests(ctx.fixture) == requests
        response
      end

    assert_idle(ctx, pid)
    instance = Session.status(pid).instance_id
    native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    old_connection = close_owned(pid)
    cold = start(ctx)
    assert Session.status(cold).instance_id != instance
    %{connection: cold_connection} = :sys.get_state(cold)
    assert cold_connection.port != old_connection.port
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # Read both exact persisted maps in a distinct process before any resume.
    for {record, previous_response} <- Enum.zip(records, warm) do
      response = call(cold, "thread/items/read", record.query)
      assert_direct(response, record)
      assert response == previous_response
      assert_files(ctx, :deleted)
      assert ModelFixture.requests(ctx.fixture) == requests
      assert_stale(cold, record.approval)
    end

    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_history(cold, id, records)
    assert ModelFixture.requests(ctx.fixture) == requests
    assert_idle(ctx, cold)
    close_owned(cold)
    assert_files(ctx, :deleted)
    assert ModelFixture.requests(ctx.fixture) == requests
  end

  defp pending(ctx, pid, id, call_id, index, changes) do
    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned file move/delete fixture only"}
      ])

    events = collect(pid, [], &(interactions(&1) != []))
    assert [approval] = interactions(events)
    assert approval.wire["method"] == "item/fileChange/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == id and params["turnId"] == turn
    assert params["itemId"] == call_id
    assert Enum.sort(Map.keys(params)) == ~w(grantRoot itemId reason startedAtMs threadId turnId)
    assert Map.fetch(params, "reason") == {:ok, nil}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert approval.handle.id == approval.wire["id"]
    assert approval.handle.generation == Session.status(pid).generation
    assert is_reference(approval.handle.reference)

    assert %{"threadId" => ^id, "turnId" => ^turn, "item" => item} =
             notification(events, "item/started", &(&1["item"]["id"] == call_id))

    assert item == expected_item(call_id, "inProgress", changes)
    refute notification(events, "item/completed", &(&1["item"]["id"] == call_id))
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert length(ModelFixture.requests(ctx.fixture)) == index

    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0, gap: nil} =
             Session.status(pid)

    {turn, approval, events}
  end

  defp finish(pid, id, turn, approval, events, expected) do
    request_id = approval.wire["id"]

    events =
      collect(pid, events, fn all ->
        assert [^approval] = interactions(all)

        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
          notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
      end)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert [item] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["turnId"] == turn,
               event.wire["params"]["item"]["type"] == "fileChange",
               do: event.wire["params"]["item"]
             )

    assert item == expected

    assert %{"threadId" => ^id, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    assert [outcome] =
             Enum.filter(Session.interaction_outcomes(pid), &(&1.handle == approval.handle))

    assert outcome.status == :resolution_observed
    refute Enum.any?(events, &(&1.wire["method"] in ["warning", "error"]))
  end

  defp assert_direct(response, record) do
    assert Map.keys(response) == ["data"]
    turn = record.turn
    assert [%{"turnId" => ^turn, "item" => item} = entry] = response["data"]
    assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
    assert item == record.expected
  end

  defp assert_history(pid, id, records) do
    history =
      call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]["turns"]

    assert Enum.map(history, & &1["id"]) == Enum.map(records, & &1.turn)

    for {turn, record} <- Enum.zip(history, records) do
      assert turn["status"] == "completed"
      assert Enum.filter(turn["items"], &(&1["type"] == "fileChange")) == [record.expected]
    end
  end

  defp assert_provider(ctx, count, call_id, status, path_label) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
    continued = List.last(requests)

    assert [output] =
             Enum.filter(
               continued["input"],
               &(&1["type"] == "function_call_output" and &1["call_id"] == call_id)
             )

    assert is_binary(output["output"])

    if status == "declined" do
      assert output["output"] =~ "patch rejected by user"
    else
      summary = "Success. Updated the following files:\n#{path_label}\n"
      assert String.ends_with?(output["output"], "\nOutput:\n" <> summary)
    end
  end

  defp expected_item(id, status, changes),
    do: %{"id" => id, "type" => "fileChange", "status" => status, "changes" => changes}

  defp assert_files(ctx, state) do
    workspace = ctx.fixture.workspace
    canary = Path.join(workspace, "canary.txt")
    assert File.lstat!(canary).type == :regular
    assert File.read!(canary) == @canary

    expected =
      case state do
        :initial -> %{"canary.txt" => @canary, "origin.txt" => "owned before\n"}
        :moved -> %{"canary.txt" => @canary, "moved.txt" => "owned moved\n"}
        :deleted -> %{"canary.txt" => @canary}
      end

    assert Enum.sort(File.ls!(workspace)) == Enum.sort(Map.keys(expected))

    for {name, bytes} <- expected do
      path = Path.join(workspace, name)
      assert File.lstat!(path).type == :regular
      assert File.read!(path) == bytes
    end
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
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
        {:codex_driver, ^pid, :events_available} -> collect(pid, events, done, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native file move/delete gap")
      after
        remaining -> flunk("Native file move/delete deadline: #{inspect(Session.status(pid))}")
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
               %{"name" => "samgita_file_move_delete", "version" => "0.1.0"},
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
    connection
  end

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))
end
