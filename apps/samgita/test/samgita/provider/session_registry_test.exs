defmodule Samgita.Provider.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias Samgita.Provider.SessionRegistry

  @project_id "proj-1"
  @agent_id "agent-1"

  @session %{
    session_id: "sess-abc",
    provider: SamgitaProvider.Mock,
    started_at: ~U[2026-01-01 00:00:00Z],
    message_count: 3,
    total_tokens: 150
  }

  setup do
    # Clean up any entries left by previous tests before each test runs.
    for {key, _} <- SessionRegistry.list_sessions() do
      {pid, aid} = key
      SessionRegistry.unregister(pid, aid)
    end

    :ok
  end

  describe "register/3 and lookup/2" do
    test "stores session info and retrieves it" do
      :ok = SessionRegistry.register(@project_id, @agent_id, @session)
      assert SessionRegistry.lookup(@project_id, @agent_id) == @session
    end

    test "registering the same key overwrites the previous entry" do
      updated = Map.put(@session, :message_count, 99)

      :ok = SessionRegistry.register(@project_id, @agent_id, @session)
      :ok = SessionRegistry.register(@project_id, @agent_id, updated)

      assert SessionRegistry.lookup(@project_id, @agent_id) == updated
    end
  end

  describe "unregister/2" do
    test "removes the entry so lookup/2 returns nil" do
      :ok = SessionRegistry.register(@project_id, @agent_id, @session)
      :ok = SessionRegistry.unregister(@project_id, @agent_id)

      assert SessionRegistry.lookup(@project_id, @agent_id) == nil
    end

    test "is idempotent for a key that does not exist" do
      assert :ok = SessionRegistry.unregister("ghost-proj", "ghost-agent")
    end
  end

  describe "list_sessions/0" do
    test "returns all active sessions" do
      :ok = SessionRegistry.register(@project_id, @agent_id, @session)
      :ok = SessionRegistry.register("proj-2", "agent-2", @session)

      sessions = SessionRegistry.list_sessions()
      assert length(sessions) >= 2

      keys = Enum.map(sessions, &elem(&1, 0))
      assert {@project_id, @agent_id} in keys
      assert {"proj-2", "agent-2"} in keys
    end

    test "returns empty list when no sessions registered" do
      assert SessionRegistry.list_sessions() == []
    end
  end

  describe "list_sessions/1" do
    test "filters sessions by project_id" do
      :ok = SessionRegistry.register(@project_id, "agent-a", @session)
      :ok = SessionRegistry.register(@project_id, "agent-b", @session)
      :ok = SessionRegistry.register("other-proj", "agent-c", @session)

      result = SessionRegistry.list_sessions(@project_id)
      assert length(result) == 2
      keys = Enum.map(result, &elem(&1, 0))
      assert {@project_id, "agent-a"} in keys
      assert {@project_id, "agent-b"} in keys
      refute {"other-proj", "agent-c"} in keys
    end

    test "returns empty list for a project with no sessions" do
      assert SessionRegistry.list_sessions("nonexistent-proj") == []
    end
  end

  describe "cleanup_for_agent/2" do
    test "removes the entry for the given agent" do
      :ok = SessionRegistry.register(@project_id, @agent_id, @session)
      :ok = SessionRegistry.cleanup_for_agent(@project_id, @agent_id)

      assert SessionRegistry.lookup(@project_id, @agent_id) == nil
    end
  end
end
