defmodule SamgitaCodexDriver.NativePermissionLifetimeTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/permission_lifetime_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-permission-lifetime-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario] || "permission_lifetime")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  test "turn permission authorizes a same-turn patch but expires before the next turn", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval} = grant_first_turn(ctx, pid, thread, "turn")

    {second, current, events} =
      pending(ctx, pid, thread, "fileChange", "permission-lifetime-4", 4)

    assert_patch(ctx, current, events)
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    decline(pid, current)
    events = finish(pid, thread, second, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert_files(ctx, false)
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, current)
    assert_history(pid, thread, [first, second])
  end

  test "session permission authorizes a later-turn patch in the same native thread", ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval} = grant_first_turn(ctx, pid, thread, "session")
    second = start_turn(pid, thread)
    events = finish(pid, thread, second, [])
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert item(events, "fileChange")["status"] == "completed"
    assert_files(ctx, true)
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, approval)
    assert_history(pid, thread, [first, second])
  end

  test "session permission is confined to its thread even within the same app-server", ctx do
    pid = start(ctx)
    first_thread = thread(ctx, pid)
    {first, approval} = grant_first_turn(ctx, pid, first_thread, "session")
    other_thread = thread(ctx, pid)
    assert other_thread != first_thread
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    {second, current, events} =
      pending(ctx, pid, other_thread, "fileChange", "permission-lifetime-4", 4)

    assert_patch(ctx, current, events)
    assert_stale(pid, approval)
    decline(pid, current)
    events = finish(pid, other_thread, second, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert_files(ctx, false)
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, current)
    assert_history(pid, first_thread, [first])
    assert_history(pid, other_thread, [second])
  end

  test "cold thread resume after owned native restart does not restore a session permission grant",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    {first, approval} = grant_first_turn(ctx, pid, thread, "session")
    assert_history(pid, thread, [first])
    old_instance = Session.status(pid).instance_id
    %{connection: old_connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = Session.close(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    assert Port.info(old_connection.port) == nil
    assert :atomics.get(old_connection.owner.completion, 1) == 1

    restarted = start(ctx)
    assert Session.status(restarted).instance_id != old_instance
    %{connection: next_connection} = :sys.get_state(restarted)
    assert next_connection.port != old_connection.port
    assert call(restarted, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_history(restarted, thread, [first])

    {second, current, events} =
      pending(ctx, restarted, thread, "fileChange", "permission-lifetime-4", 4)

    assert_patch(ctx, current, events)
    assert_stale(restarted, approval)
    decline(restarted, current)
    events = finish(restarted, thread, second, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert_files(ctx, false)
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert_idle_without_rules(ctx, restarted)
    assert_stale(restarted, current)
    assert_history(restarted, thread, [first, second])
  end

  @tag scenario: "permission_pending"
  test "interruption retires an unanswered permission request and grants no later patch authority",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)

    {turn, approval, events} =
      pending(ctx, pid, thread, "permissions", "permission-lifetime-1", 1)

    assert_permission(ctx, approval)
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}
    events = finish(pid, thread, turn, events, "interrupted")
    request_id = approval.wire["id"]

    events =
      collect(pid, events, fn events ->
        notification(events, "serverRequest/resolved", fn params ->
          params["threadId"] == thread and params["requestId"] == request_id
        end)
      end)

    assert Enum.count(events, &(&1.kind == :server_request)) == 1

    assert %{"threadId" => ^thread, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ["item/started", "item/completed"] and
               event.wire["params"]["item"]["type"] in ["fileChange", "commandExecution"]
           end)

    assert File.ls!(ctx.fixture.workspace) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert Session.interaction_outcomes(pid) == []
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, approval)

    # A fresh, explicit turn probes authority; interruption itself must not restart inference.
    {next, current, events} =
      pending(ctx, pid, thread, "fileChange", "permission-lifetime-2", 2)

    path = Path.join(ctx.fixture.workspace, "granted-now.txt")
    assert [%{"path" => ^path}] = item(events, "fileChange", "item/started")["changes"]
    assert Map.fetch(current.wire["params"], "reason") == {:ok, nil}
    assert Map.fetch(current.wire["params"], "grantRoot") == {:ok, nil}
    assert_stale(pid, approval)
    assert %{interactions: 1} = Session.status(pid)
    decline(pid, current)
    events = finish(pid, thread, next, events)
    assert item(events, "fileChange")["status"] == "declined"
    assert File.ls!(ctx.fixture.workspace) == []
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, current)
  end

  defp grant_first_turn(ctx, pid, thread, scope) do
    {turn, approval, events} =
      pending(ctx, pid, thread, "permissions", "permission-lifetime-1", 1)

    assert_permission(ctx, approval)

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{
                  "permissions" => %{"fileSystem" => %{"write" => [ctx.fixture.workspace]}},
                  "scope" => scope,
                  "strictAutoReview" => false
                }}
             )

    events = finish(pid, thread, turn, events)
    assert item(events, "fileChange")["status"] == "completed"
    assert_files(ctx, false)
    assert length(ModelFixture.requests(ctx.fixture)) == 3

    assert permission_output(ctx) == %{
             "permissions" => %{
               "network" => nil,
               "file_system" => %{"write" => [ctx.fixture.workspace]}
             },
             "scope" => scope
           }

    assert_idle_without_rules(ctx, pid)
    assert_stale(pid, approval)
    {turn, approval}
  end

  defp assert_permission(ctx, approval) do
    params = approval.wire["params"]
    assert Map.fetch(params, "environmentId") == {:ok, "local"}
    assert params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Synthetic owned workspace permission lifetime only"
    assert params["permissions"]["fileSystem"]["write"] == [ctx.fixture.workspace]
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp assert_patch(ctx, approval, events) do
    params = approval.wire["params"]
    assert Map.fetch(params, "reason") == {:ok, nil}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}
    path = Path.join(ctx.fixture.workspace, "granted-later.txt")
    assert [%{"path" => ^path}] = item(events, "fileChange", "item/started")["changes"]
    assert_files(ctx, false)
  end

  defp permission_output(ctx) do
    assert [_first, second, _third] = ModelFixture.requests(ctx.fixture)
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "permission-lifetime-1"
    JSON.decode!(output["output"])
  end

  defp assert_files(ctx, later) do
    assert File.read!(Path.join(ctx.fixture.workspace, "granted-now.txt")) == "owned turn grant\n"
    path = Path.join(ctx.fixture.workspace, "granted-later.txt")

    if later,
      do: assert(File.read!(path) == "owned session grant\n"),
      else: refute(File.exists?(path))

    assert Enum.sort(File.ls!(ctx.fixture.workspace)) ==
             if(later, do: ["granted-later.txt", "granted-now.txt"], else: ["granted-now.txt"])
  end

  defp pending(ctx, pid, thread, kind, item_id, count) do
    turn = start_turn(pid, thread)
    events = collect(pid, [], &Enum.any?(&1, fn event -> event.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/#{kind}/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == item_id
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    {turn, approval, events}
  end

  defp finish(pid, thread, turn, events, status \\ "completed") do
    count = Enum.count(events, &(&1.kind == :server_request))

    events =
      collect(pid, events, fn events ->
        assert Enum.count(events, &(&1.kind == :server_request)) == count,
               "Unexpected native approval instead of scoped grant or terminal transition"

        notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
      end)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => ^status}} =
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
          flunk("Unexpected event gap during permission lifetime")
      after
        remaining -> flunk("Native permission lifetime deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"permissions" => %{}}})
  end

  defp decline(pid, approval) do
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "decline"}})
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

  defp assert_idle_without_rules(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))
  end

  defp start_turn(pid, thread) do
    TurnFixture.start_turn(pid, thread, [
      %{"type" => "text", "text" => "Owned permission lifetime fixture only"}
    ])
  end
end
