defmodule SamgitaCodexDriver.NativeReadStateFieldsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}

  import TurnFixture, only: [call: 3, upstream_error: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      File.read!(config) <> "\n[features]\nplugins = false\nrecommended_plugins = false\n"
    )

    ctx
  end

  for mode <- ["legacy", "paginated"] do
    @history_mode mode
    test "#{mode} empty durable thread exposes exact read-state fields and rejects stale revisions after restart",
         ctx do
      pid = TurnFixture.start(ctx)
      id = TurnFixture.thread(ctx, pid, %{"historyMode" => @history_mode})

      assert call(pid, "thread/name/set", %{
               "threadId" => id,
               "name" => "Owned empty read-state fields #{@history_mode}"
             }) == %{}

      baseline = read(pid, id)
      thread = Map.fetch!(baseline, "thread")
      assert Map.fetch!(thread, "turns") == []
      history_path = Map.fetch!(thread, "path")
      history_bytes = File.read!(history_path)
      initial = state(baseline, nil)
      initial_revision = Map.fetch!(initial, "revision")

      unread = update(pid, id, initial_revision, "unread", %{"type" => "threadStart"})
      refute unread["revision"] == initial_revision
      assert state(read(pid, id), %{"type" => "threadStart"}) == unread
      assert_stale(pid, id, initial_revision, "read", unread)
      assert Map.fetch!(read(pid, id), "thread") == thread

      marked_read = update(pid, id, unread["revision"], "read", nil)
      refute marked_read["revision"] in [initial_revision, unread["revision"]]
      assert state(read(pid, id), nil) == marked_read
      assert_stale(pid, id, unread["revision"], "unread", marked_read)
      assert Map.fetch!(read(pid, id), "thread") == thread
      assert File.read!(history_path) == history_bytes

      assert {:ok, events} = Session.drain(pid)

      assert Enum.flat_map(events, fn event ->
               if event.wire["method"] == "thread/readState/changed",
                 do: [event.wire["params"]],
                 else: []
             end) == [
               %{"threadId" => id, "readState" => unread},
               %{"threadId" => id, "readState" => marked_read}
             ]

      assert_no_execution_events(events)

      assert_idle(ctx, pid)
      original_instance = Session.status(pid).instance_id
      old_connection = :sys.get_state(pid).connection
      assert :ok = Session.close(pid)
      assert Port.info(old_connection.port) == nil
      assert :atomics.get(old_connection.owner.completion, 1) == 1
      cold = TurnFixture.start(ctx)
      refute Session.status(cold).instance_id == original_instance
      refute :sys.get_state(cold).connection.port == old_connection.port
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      # No turn persisted a model selection. These live-session projections
      # have their explicit unloaded values before a native thread resume.
      cold_thread =
        Map.merge(thread, %{
          "status" => %{"type" => "notLoaded"},
          "environments" => nil,
          "canAcceptDirectInput" => nil,
          "model" => nil
        })

      assert Map.fetch!(read(cold, id), "thread") == cold_thread
      assert state(read(cold, id), nil) == marked_read
      assert_stale(cold, id, unread["revision"], "unread", marked_read)

      # A new explicit operator action after a fresh read is a different command.
      # No stale edit or cold startup is automatically replayed.
      final = update(cold, id, marked_read["revision"], "unread", %{"type" => "threadStart"})
      refute final["revision"] in [initial_revision, unread["revision"], marked_read["revision"]]
      assert state(read(cold, id), %{"type" => "threadStart"}) == final
      assert Map.fetch!(read(cold, id), "thread") == cold_thread
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      assert File.read!(history_path) == history_bytes
      assert_idle(ctx, cold)
      assert :ok = Session.close(cold)
    end
  end

  for mode <- ["legacy", "paginated"] do
    @attention_history_mode mode
    test "#{mode} live terminal attention retains the earliest unread turn and cold CAS winner",
         ctx do
      TurnFixture.configure_model(ctx, %{})
      pid = TurnFixture.start(ctx)
      id = TurnFixture.thread(ctx, pid, %{"historyMode" => @attention_history_mode})

      assert call(pid, "thread/name/set", %{
               "threadId" => id,
               "name" => "Owned unread-turn attention #{@attention_history_mode}"
             }) == %{}

      initial_revision = read(pid, id) |> Map.fetch!("readState") |> Map.fetch!("revision")
      {first_turn, first_events} = attention_turn(pid, id, "Owned first attention result")
      first_position = %{"type" => "turn", "turnId" => first_turn}
      first = state(read(pid, id), first_position)
      refute first["revision"] == initial_revision
      assert_attention(first_events, id, first_turn, first)

      {second_turn, second_events} = attention_turn(pid, id, "Owned later attention result")
      refute second_turn == first_turn
      second = state(read(pid, id), first_position)
      refute second["revision"] in [initial_revision, first["revision"]]
      assert_attention(second_events, id, second_turn, second)
      assert_attention_list(pid, id, second)
      before_ack = read(pid, id)
      history_path = before_ack |> Map.fetch!("thread") |> Map.fetch!("path")
      history_bytes = File.read!(history_path)

      for operation <- ["read", "unread"],
          do: assert_stale(pid, id, first["revision"], operation, second)

      assert state(read(pid, id), first_position) == second
      assert File.read!(history_path) == history_bytes
      marked_read = update(pid, id, second["revision"], "read", nil)
      assert {:ok, mark_events} = Session.drain(pid)
      refute Enum.any?(mark_events, &(&1.kind == :server_request))

      {third_turn, third_events} =
        attention_turn(pid, id, "Owned new attention after acknowledgement")

      refute third_turn in [first_turn, second_turn]
      third_position = %{"type" => "turn", "turnId" => third_turn}
      third = state(read(pid, id), third_position)

      refute third["revision"] in [
               initial_revision,
               first["revision"],
               second["revision"],
               marked_read["revision"]
             ]

      assert_attention(third_events, id, third_turn, third)
      assert_attention_list(pid, id, third)
      assert state(read(pid, id), third_position) == third
      history_bytes = File.read!(history_path)
      assert_attention_idle(ctx, pid, 3)

      original_instance = Session.status(pid).instance_id
      old_connection = :sys.get_state(pid).connection
      assert :ok = Session.close(pid)
      assert Port.info(old_connection.port) == nil
      assert :atomics.get(old_connection.owner.completion, 1) == 1

      cold = TurnFixture.start(ctx)
      refute Session.status(cold).instance_id == original_instance
      refute :sys.get_state(cold).connection.port == old_connection.port
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      assert state(read(cold, id), third_position) == third
      assert_attention_list(cold, id, third)

      for operation <- ["read", "unread"],
          do: assert_stale(cold, id, second["revision"], operation, third)

      assert state(read(cold, id), third_position) == third
      assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
      assert File.read!(history_path) == history_bytes
      assert_attention_idle(ctx, cold, 3)
      assert :ok = Session.close(cold)
    end
  end

  defp attention_turn(pid, id, text) do
    turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
    {turn, TurnFixture.finish_turn(pid, id, turn)}
  end

  defp assert_attention(events, id, turn, expected) do
    assert Enum.flat_map(events, fn event ->
             if event.wire["method"] == "thread/readState/changed",
               do: [event.wire["params"]],
               else: []
           end) == [%{"threadId" => id, "readState" => expected}]

    changed = Enum.find_index(events, &(&1.wire["method"] == "thread/readState/changed"))
    completed = Enum.find_index(events, &(&1.wire["method"] == "turn/completed"))
    assert is_integer(changed) and is_integer(completed) and changed < completed

    assert %{"threadId" => ^id, "turnId" => ^turn, "item" => %{"text" => answer}} =
             TurnFixture.notification(
               events,
               "item/completed",
               &(&1["item"]["type"] == "agentMessage")
             )

    assert answer == "Deterministic local fixture answer"
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  defp assert_attention_list(pid, id, expected) do
    listed = call(pid, "thread/list", %{"limit" => 10})
    assert Enum.map(Map.fetch!(listed, "data"), & &1["id"]) == [id]
    assert Map.fetch!(listed, "readStates") == %{id => expected}
    assert Map.fetch!(listed, "nextCursor") == nil
  end

  defp assert_attention_idle(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    assert_no_execution_events(events)
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})

  defp state(response, first_unread) do
    assert %{"firstUnread" => ^first_unread, "revision" => revision} =
             state = Map.fetch!(response, "readState")

    assert MapSet.new(Map.keys(state)) == MapSet.new(["firstUnread", "revision"])
    assert is_binary(revision) and byte_size(revision) > 0
    state
  end

  defp update(pid, id, revision, operation, first_unread) do
    result = call(pid, "thread/readState/update", params(id, revision, operation))
    assert Map.keys(result) == ["readState"]
    state(result, first_unread)
  end

  defp assert_stale(pid, id, revision, operation, winner) do
    assert upstream_error(pid, "thread/readState/update", params(id, revision, operation)) == %{
             "code" => -32_600,
             "message" => "read state changed",
             "data" => %{"reason" => "readStateConflict", "readState" => winner}
           }
  end

  defp params(id, revision, operation),
    do: %{"threadId" => id, "expectedRevision" => revision, "operation" => %{"type" => operation}}

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    assert_no_execution_events(events)
  end

  defp assert_no_execution_events(events) do
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/started",
               "item/completed"
             ]
           end)
  end
end
