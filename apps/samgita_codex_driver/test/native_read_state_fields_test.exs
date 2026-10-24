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
